// ThermalBench - TelemetryService (Rust macmon backend)
import Foundation

enum CPUCoreKind: String, Codable, Sendable {
    case efficiency, performance, unknown
}

struct PerCoreUtilization: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(logicalCoreIndex)-\(kind.rawValue)" }
    var logicalCoreIndex: Int
    var displayIndex: Int
    var kind: CPUCoreKind
    var utilizationPercent: Double?
    var valid: Bool
}

struct TelemetrySample: Identifiable, Codable {
    var id: Date { timestamp }
    var timestamp: Date = Date()
    var elapsedSeconds: Double = 0
    var cpuTemp: Double?
    var cpuTempHottest: Double?
    var gpuTemp: Double?
    var gpuTempHottest: Double?
    var cpuTempSensorCount: Int = 0
    var gpuTempSensorCount: Int = 0
    var perCoreUtilization: [PerCoreUtilization] = []
    var cpuPower: Double?
    var gpuPower: Double?
    var packagePower: Double?
    var pClusterFreqMHz: Double?
    var eClusterFreqMHz: Double?
    var batteryPercent: Int?
    var acConnected: Bool = false
    var lowPowerMode: Bool = false
    var thermalState: ThermalStateTag = .unknown
    var cpuUtilization: Double?
    var tempValid: Bool = false
    var powerValid: Bool = false
    var freqValid: Bool = false
    var phase: TestPhase = .baseline
}

actor TelemetryService {
    static let shared = TelemetryService()
    private var handle: TBTelemetryHandle?
    private var lastSeq: UInt64 = 0
    private var isRunning = false
    private var startMonotonicNs: UInt64 = 0
    private var sampleCount = 0
    private let queue = DispatchQueue(label: "com.leecdiang.thermalbench.telemetry")

    func startTelemetry() async throws {
        isRunning = true
        startMonotonicNs = DispatchTime.now().uptimeNanoseconds
        sampleCount = 0
        lastSeq = 0

        // Create Rust sampler
        guard let h = tb_telemetry_create() else {
            isRunning = false
            throw TelemetryError.initialization("tb_telemetry_create returned null")
        }
        handle = h

        // Start background sampling at 1000ms
        let err = tb_telemetry_start(h, 1000)
        guard err == TB_OK else {
            tb_telemetry_destroy(h)
            handle = nil
            isRunning = false
            throw TelemetryError.initialization("tb_telemetry_start failed: \(err)")
        }
        core_util_reset()
    }

    func readSample() async throws -> TelemetrySample {
        guard handle != nil, isRunning else {
            throw TelemetryError.notStarted
        }

        let afterSeq = lastSeq
        // Capture immutable copy for Sendable closure
        let hCopy = handle

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let h = hCopy else {
                    continuation.resume(throwing: TelemetryError.notStarted)
                    return
                }
                var raw = TBTelemetrySample()
                let err = tb_telemetry_wait_next(h, afterSeq, 5000, &raw)
                let capturedRaw = raw
                Task { @Sendable in
                    await self.processResult(err: err, raw: capturedRaw, continuation: continuation)
                }
            }
        }
    }

    private func processResult(
        err: TBErrorCode,
        raw: TBTelemetrySample,
        continuation: CheckedContinuation<TelemetrySample, any Error>
    ) {
        switch err {
        case TB_OK:
            lastSeq = raw.sequence_id
            sampleCount += 1

            var s = TelemetrySample()
            s.timestamp = Date()
            s.elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - startMonotonicNs) / 1_000_000_000
            s.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

            // Temperature
            if (raw.available_mask & TB_AVAIL_CPU_TEMP) != 0 {
                s.cpuTemp = raw.cpu_temperature_avg_c
                s.tempValid = true
            }
            if (raw.available_mask & TB_AVAIL_CPU_TEMP_HOTTEST) != 0 {
                s.cpuTempHottest = raw.cpu_temperature_hottest_c
            }
            if (raw.available_mask & TB_AVAIL_GPU_TEMP) != 0 {
                s.gpuTemp = raw.gpu_temperature_avg_c
            }
            if (raw.available_mask & TB_AVAIL_GPU_TEMP_HOTTEST) != 0 {
                s.gpuTempHottest = raw.gpu_temperature_hottest_c
            }
            if (raw.available_mask & TB_AVAIL_CPU_SENSOR_COUNT) != 0 {
                s.cpuTempSensorCount = Int(raw.cpu_temperature_sensor_count)
            }
            if (raw.available_mask & TB_AVAIL_GPU_SENSOR_COUNT) != 0 {
                s.gpuTempSensorCount = Int(raw.gpu_temperature_sensor_count)
            }

            // Power
            if (raw.available_mask & TB_AVAIL_CPU_POWER) != 0 {
                s.cpuPower = raw.cpu_power_w
                s.powerValid = true
            }
            if (raw.available_mask & TB_AVAIL_GPU_POWER) != 0 {
                s.gpuPower = raw.gpu_power_w
            }
            if (raw.available_mask & TB_AVAIL_PACKAGE_POWER) != 0 {
                s.packagePower = raw.package_power_w
            }

            // Frequency
            if (raw.available_mask & TB_AVAIL_P_FREQ) != 0 {
                s.pClusterFreqMHz = raw.p_cluster_frequency_mhz
                s.freqValid = true
            }
            if (raw.available_mask & TB_AVAIL_E_FREQ) != 0 {
                s.eClusterFreqMHz = raw.e_cluster_frequency_mhz
            }

            // Utilization
            if (raw.available_mask & TB_AVAIL_CPU_USAGE) != 0 {
                s.cpuUtilization = raw.cpu_utilization_ratio
            }

            // Per-core utilization
            s.perCoreUtilization = collectPerCoreUtil()

            // Battery (from public IOPowerSources API, still works)
            let batt = tb_read_battery()
            if batt.battery_valid {
                s.batteryPercent = batt.battery_percent >= 0 ? Int(batt.battery_percent) : nil
                s.acConnected = batt.ac_connected
            }

            // Thermal state
            let ts = ProcessInfo.processInfo.thermalState
            switch ts {
            case .nominal: s.thermalState = .nominal
            case .fair: s.thermalState = .fair
            case .serious: s.thermalState = .serious
            case .critical: s.thermalState = .critical
            @unknown default: s.thermalState = .unknown
            }

            continuation.resume(returning: s)

        case TB_ERR_TIMEOUT:
            continuation.resume(throwing: TelemetryError.timeout)

        case TB_ERR_STOPPED, TB_ERR_NOT_STARTED:
            continuation.resume(throwing: TelemetryError.stopped)

        default:
            continuation.resume(throwing: TelemetryError.readFailed("tb_telemetry_wait_next: \(err)"))
        }
    }

    func stopTelemetry() async {
        isRunning = false
        if let h = handle {
            tb_telemetry_stop(h)
            tb_telemetry_destroy(h)
            handle = nil
        }
    }
}

// MARK: - Per-core Utilization Collector

private func collectPerCoreUtil() -> [PerCoreUtilization] {
    var snap = core_util_snapshot()
    guard snap.core_count > 0 else { return [] }

    var result: [PerCoreUtilization] = []
    for i in 0..<Int(snap.core_count) {
        let info = core_util_get_core(&snap, UInt32(i))
        let kind: CPUCoreKind = info.kind == 0 ? .efficiency : info.kind == 1 ? .performance : .unknown
        result.append(PerCoreUtilization(
            logicalCoreIndex: Int(info.logical_index),
            displayIndex: Int(info.logical_index) + 1,
            kind: kind,
            utilizationPercent: info.valid != 0 ? info.utilization_percent : nil,
            valid: info.valid != 0
        ))
    }
    return result
}

enum TelemetryError: Error, LocalizedError {
    case initialization(String)
    case notStarted
    case timeout
    case stopped
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .initialization(let msg): "Telemetry init failed: \(msg)"
        case .notStarted: "Telemetry not started"
        case .timeout: "Telemetry read timeout"
        case .stopped: "Telemetry stopped"
        case .readFailed(let msg): "Telemetry read failed: \(msg)"
        }
    }
}
