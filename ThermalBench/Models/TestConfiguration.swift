// ThermalBench - Data Models
import Foundation
import SwiftData

// MARK: - Test Configuration

/// Target CPU core cluster.
/// Matches the semantics of CoreTarget in CustomTestConfigView.
enum CpuCoreType: String, Codable, CaseIterable {
    case all         // All cores, no QoS override
    case pCores      // P-cores only
    case eCores      // E-cores only
    case custom      // Custom thread count, all cores
}

/// Which stress sources to engage during the loading phase.
enum WorkloadType: String, Codable, CaseIterable {
    case cpuOnly
    case gpuOnly
    case combined

    var displayName: String {
        switch self {
        case .cpuOnly:  "CPU Only"
        case .gpuOnly:  "GPU Only"
        case .combined: "CPU + GPU"
        }
    }

    /// True when CPU workload should run.
    var usesCPU: Bool { self != .gpuOnly }
    /// True when GPU workload should run.
    var usesGPU: Bool { self != .cpuOnly }
}

struct TestConfiguration: Codable, Equatable {
    var mode: TestMode = .standard
    var workloadType: WorkloadType = .combined
    var cpuThreads: Int = 0  // 0 = all
    var cpuCoreType: CpuCoreType = .all
    var gpuIntensity: GPUIntensity = .sustained
    var idleDuration: TimeInterval = 180
    var loadDuration: TimeInterval = 900
    var transitionDuration: TimeInterval = 5
    var cooldownDuration: TimeInterval = 300
    var sampleInterval: TimeInterval = 1.0
    var ambientTemperature: Double?
    var name: String = ""
    var tags: [String] = []
    var notes: String = ""
}

enum TestMode: String, Codable, CaseIterable {
    case quickCheck, standard, sustained, extended, custom, monitorOnly

    var displayName: String {
        switch self {
        case .quickCheck: "Quick Check"
        case .standard: "Standard Test"
        case .sustained: "Sustained Test"
        case .extended: "Extended Test"
        case .custom: "Custom"
        case .monitorOnly: "Monitor Only"
        }
    }
}

enum GPUIntensity: String, Codable, CaseIterable {
    case off, light, sustained, combinedSoC
    var displayName: String {
        switch self {
        case .off: "Off"
        case .light: "Moderate"
        case .sustained: "Maximum"
        case .combinedSoC: "Combined SoC"
        }
    }
}

// MARK: - Test Phase

enum TestPhase: String, Codable, Equatable {
    case idle, preflight, baseline, loading, transition, cooling, analyzing
    case completed, cancelled, failed
}

// MARK: - Test State

enum ThermalStateTag: String, Codable {
    case nominal, fair, serious, critical, unknown
}

// MARK: - SwiftData Run Record

@Model
final class RunRecord {
    @Attribute(.unique) var uuid: String = UUID().uuidString
    var name: String = ""
    var testModeRaw: String = TestMode.standard.rawValue
    var createdAt: Date = Date()
    var completedAt: Date?

    // ── Device info (populated from DeviceProfile at test start) ──
    var deviceModelIdentifier: String = ""
    var chipName: String = ""
    var cpuCoreCount: Int = 0
    var performanceCoreCount: Int = 0
    var efficiencyCoreCount: Int = 0
    var gpuCoreCount: Int = 0
    var memoryBytes: Int64 = 0
    var macOSVersion: String = ""
    var metalDeviceName: String = ""

    // ── Legacy fields (kept for existing stores, not actively written) ──
    var deviceModel: String = ""
    var cpuCores: Int = 0
    var gpuCores: Int = 0

    // ── Test metadata ──
    var appVersion: String = ""
    var phaseRaw: String = TestPhase.completed.rawValue
    var wasInterrupted: Bool = false
    var tags: [String] = []
    var notes: String = ""
    var isFavorite: Bool = false
    var dataDirectory: String = ""
    var sampleCount: Int = 0
    var duration: TimeInterval = 0

    // ── Configuration snapshot (empty/zero = legacy run) ──
    var workloadTypeRaw: String = ""
    var cpuCoreTypeRaw: String = ""
    var gpuIntensityRaw: String = ""
    var cpuThreadCount: Int = 0
    var loadDuration: TimeInterval = 0
    var sampleInterval: TimeInterval = 0
    var acConnected: Bool?
    var batteryPercent: Int?

    // ── Extended snapshot (analysis provenance / environment) ──
    var lowPowerMode: Bool?
    var ambientTemperature: Double?
    var analysisVersion: Int = 0
    var baselineDuration: TimeInterval = 0
    var cooldownDuration: TimeInterval = 0
    var telemetryCoreVersion: String = ""

    // ── Summary metrics (nil = channel unavailable, never a fake 0) ──
    var cpuPeakPower: Double?
    var cpuPeakTemp: Double?
    var gpuPeakTemp: Double?
    var gpuPeakPower: Double?
    /// Peak P-cluster frequency (was misnamed pClusterMinFreq).
    var pClusterPeakFreq: Double?
    /// Legacy field — kept for old stores, no longer written.
    var pClusterMinFreq: Double = 0
    var steadyPower: Double = 0
    var steadyTemp: Double = 0
    var dataCoverage: Double = 0

    /// Human-readable device summary for display.
    var deviceSummary: String {
        if deviceModelIdentifier.isEmpty && chipName.isEmpty {
            return "Unknown \u{00B7} Legacy Run"
        }
        var parts: [String] = []
        if !chipName.isEmpty { parts.append(chipName) }
        if performanceCoreCount > 0 || efficiencyCoreCount > 0 {
            let total = performanceCoreCount + efficiencyCoreCount
            if total > 0 {
                parts.append("\(total) cores (\(performanceCoreCount)P + \(efficiencyCoreCount)E)")
            }
        } else if cpuCoreCount > 0 {
            parts.append("\(cpuCoreCount) cores")
        }
        if memoryBytes > 0 {
            let gib = Double(memoryBytes) / 1_073_741_824
            parts.append(String(format: "%.0f GB", gib))
        }
        if !macOSVersion.isEmpty { parts.append(macOSVersion) }
        return parts.joined(separator: " \u{00B7} ")
    }

    init(config: TestConfiguration) {
        self.name = config.name.isEmpty ? "Run \(Date().formatted(date: .abbreviated, time: .shortened))" : config.name
        self.testModeRaw = config.mode.rawValue
        self.tags = config.tags
        self.notes = config.notes

        // Configuration snapshot for comparability checks
        self.workloadTypeRaw = config.workloadType.rawValue
        self.cpuCoreTypeRaw = config.cpuCoreType.rawValue
        self.gpuIntensityRaw = config.gpuIntensity.rawValue
        self.cpuThreadCount = config.cpuThreads
        self.loadDuration = config.loadDuration
        self.sampleInterval = config.sampleInterval
        self.ambientTemperature = config.ambientTemperature
        self.baselineDuration = config.idleDuration
        self.cooldownDuration = config.cooldownDuration
    }
}


