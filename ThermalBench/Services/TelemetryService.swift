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
    // Per-channel availability (CPU/GPU/p/e independent)
    var cpuTempValid: Bool = false
    var gpuTempValid: Bool = false
    var cpuPowerValid: Bool = false
    var gpuPowerValid: Bool = false
    var pFrequencyValid: Bool = false
    var eFrequencyValid: Bool = false
    // Aggregate flags (kept for compatibility; any channel of that kind)
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

    func startTelemetry(intervalMilliseconds: Int = 1000) async throws {
        // Exclusive ownership: refuse to clobber an existing session.
        guard !isRunning else {
            throw TelemetryError.alreadyRunning
        }
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

        // Start background sampling at the requested cadence (ms)
        let err = tb_telemetry_start(h, UInt32(max(intervalMilliseconds, 100)))
        guard err == TB_OK else {
            tb_telemetry_destroy(h)
            handle = nil
            isRunning = false
            throw TelemetryError.initialization("tb_telemetry_start failed: \(err)")
        }
        core_util_reset()
    }

    func readSample() async throws -> TelemetrySample {
        // Absorb the startup race: the Rust sampler thread flips `running`
        // asynchronously after start(), so an immediate first read can hit
        // NotStarted/Stopped before the thread is actually up.
        for attempt in 0..<10 {
            do {
                return try await readSampleOnce()
            } catch TelemetryError.stopped {
                if attempt == 9 {
                    throw TelemetryError.stopped(readLastError())
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        throw TelemetryError.stopped(readLastError())
    }

    private func readSampleOnce() async throws -> TelemetrySample {
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
                    await self.processResult(err: err, raw: capturedRaw, h: h, continuation: continuation)
                }
            }
        }
    }

    private func readLastError() -> String? {
        guard let h = handle else { return nil }
        var buf = [CChar](repeating: 0, count: 512)
        let rc = tb_telemetry_last_error(h, &buf, 512)
        guard rc == TB_OK else { return nil }
        let s = String(cString: buf)
        return s.isEmpty ? nil : s
    }

    private func processResult(
        err: TBErrorCode,
        raw: TBTelemetrySample,
        h: TBTelemetryHandle,
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

            // Temperature — per-channel
            if (raw.available_mask & TB_AVAIL_CPU_TEMP) != 0 {
                s.cpuTemp = raw.cpu_temperature_avg_c
                s.cpuTempValid = true
            }
            if (raw.available_mask & TB_AVAIL_CPU_TEMP_HOTTEST) != 0 {
                s.cpuTempHottest = raw.cpu_temperature_hottest_c
            }
            if (raw.available_mask & TB_AVAIL_GPU_TEMP) != 0 {
                s.gpuTemp = raw.gpu_temperature_avg_c
                s.gpuTempValid = true
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

            // Power — per-channel
            if (raw.available_mask & TB_AVAIL_CPU_POWER) != 0 {
                s.cpuPower = raw.cpu_power_w
                s.cpuPowerValid = true
            }
            if (raw.available_mask & TB_AVAIL_GPU_POWER) != 0 {
                s.gpuPower = raw.gpu_power_w
                s.gpuPowerValid = true
            }
            if (raw.available_mask & TB_AVAIL_PACKAGE_POWER) != 0 {
                s.packagePower = raw.package_power_w
            }

            // Frequency — per-channel
            if (raw.available_mask & TB_AVAIL_P_FREQ) != 0 {
                s.pClusterFreqMHz = raw.p_cluster_frequency_mhz
                s.pFrequencyValid = true
            }
            if (raw.available_mask & TB_AVAIL_E_FREQ) != 0 {
                s.eClusterFreqMHz = raw.e_cluster_frequency_mhz
                s.eFrequencyValid = true
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

            // Aggregate availability flags (any channel of that kind)
            s.tempValid = s.cpuTempValid || s.gpuTempValid
            s.powerValid = s.cpuPowerValid || s.gpuPowerValid
            s.freqValid = s.pFrequencyValid || s.eFrequencyValid

            continuation.resume(returning: s)

        case TB_ERR_TIMEOUT:
            continuation.resume(throwing: TelemetryError.timeout)

        case TB_ERR_STOPPED, TB_ERR_NOT_STARTED:
            var buf = [CChar](repeating: 0, count: 512)
            let rc = tb_telemetry_last_error(h, &buf, 512)
            let detail = rc == TB_OK ? String(cString: buf) : ""
            continuation.resume(throwing: TelemetryError.stopped(detail.isEmpty ? nil : detail))

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
    var pIndex = 0, eIndex = 0, uIndex = 0
    for i in 0..<Int(snap.core_count) {
        let info = core_util_get_core(&snap, UInt32(i))
        let kind: CPUCoreKind = info.kind == 0 ? .efficiency : info.kind == 1 ? .performance : .unknown
        // Per-kind ordinal: P1…Pn / E1…En / Unknown 1…n — independent of any
        // hardcoded core layout. logicalCoreIndex stays available.
        let displayIndex: Int
        switch kind {
        case .performance: pIndex += 1; displayIndex = pIndex
        case .efficiency:  eIndex += 1; displayIndex = eIndex
        case .unknown:     uIndex += 1; displayIndex = uIndex
        }
        result.append(PerCoreUtilization(
            logicalCoreIndex: Int(info.logical_index),
            displayIndex: displayIndex,
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
    case alreadyRunning
    case timeout
    case stopped(String?)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .initialization(let msg): "Telemetry init failed: \(msg)"
        case .notStarted: "Telemetry not started"
        case .alreadyRunning: "Telemetry already in use — a test may be running"
        case .timeout: "Telemetry read timeout"
        case .stopped(let detail):
            (detail?.isEmpty == false ? "Telemetry stopped: \(detail ?? "")" : "Telemetry stopped")
        case .readFailed(let msg): "Telemetry read failed: \(msg)"
        }
    }
}
