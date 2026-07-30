// ThermalBench - Unified Device Profile
// Single source of truth for chip/device identification.
// All views (Home, Diagnostics, Results, History, Compare) read from this.
import Foundation
import Metal

struct DeviceProfile: Codable, Equatable {
    let modelIdentifier: String
    let chipName: String
    let cpuCoreCount: Int
    let performanceCoreCount: Int
    let efficiencyCoreCount: Int
    let memoryBytes: UInt64
    let macOSVersion: String
    let metalDeviceName: String?
    let gpuCoreCount: Int?

    // MARK: - Current device (lazy, computed once)

    private static let _current: DeviceProfile = {
        DeviceProfile(
            modelIdentifier: Self.readModelIdentifier(),
            chipName: Self.readChipName(),
            cpuCoreCount: ProcessInfo.processInfo.processorCount,
            performanceCoreCount: Self.readPerfLevelCount(level: 0),
            efficiencyCoreCount: Self.readPerfLevelCount(level: 1),
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            metalDeviceName: Self.readMetalDeviceName(),
            gpuCoreCount: nil  // No reliable API; never guess from chip name
        )
    }()

    static var current: DeviceProfile {
        _current
    }

    // MARK: - Formatted helpers

    var memoryGB: Double {
        Double(memoryBytes) / 1_073_741_824
    }

    var formattedMemory: String {
        // Apple reports physicalMemory in bytes; use GiB for display to match standard Mac labeling
        let gib = Double(memoryBytes) / 1_073_741_824
        return String(format: "%.0f GB", gib)
    }

    var coreSummary: String {
        if performanceCoreCount > 0 && efficiencyCoreCount > 0 {
            let total = performanceCoreCount + efficiencyCoreCount
            return "\(total) cores (\(performanceCoreCount)P + \(efficiencyCoreCount)E)"
        }
        return "\(cpuCoreCount) cores"
    }

    var shortSummary: String {
        "\(chipName) · \(coreSummary) · \(formattedMemory)"
    }

    // MARK: - Private readers

    private static func readModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown Mac" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func readChipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown Chip" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Read P/E core counts from sysctl hw.perflevelN.logicalcpu (dynamic, no hardcoding).
    /// - Parameter level: 0 = Performance, 1 = Efficiency
    private static func readPerfLevelCount(level: Int) -> Int {
        let name = "hw.perflevel\(level).logicalcpu"
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let ret = name.withCString { cname in
            sysctlbyname(cname, &count, &size, nil, 0)
        }
        return ret == 0 ? Int(count) : 0
    }

    private static func readMetalDeviceName() -> String? {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice()?.name
        #else
        return nil
        #endif
    }
}
