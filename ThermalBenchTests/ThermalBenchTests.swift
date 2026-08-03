// ThermalBenchTests — Unit tests for models, analysis, and compare logic.
// Does not require sensors, Metal, or app lifecycle.
@testable import ThermalBench
import XCTest
import SwiftData

final class RunAnalyzerTests: XCTestCase {

    // MARK: - Hottest peak calculation

    func testPeakUsesHottestField() {
        var samples: [TelemetrySample] = []
        for i in 0..<10 {
            var s = TelemetrySample()
            s.elapsedSeconds = Double(i)
            s.cpuTempHottest = Double(50 + i)     // rising: 50..59
            s.cpuTemp = Double(45 + i)             // average: 45..54 (lower)
            s.gpuTempHottest = Double(40 + i * 2)   // 40..58
            s.cpuPower = 5.0
            s.gpuPower = 3.0
            s.pClusterFreqMHz = 3000
            samples.append(s)
        }

        let cfg = TestConfiguration()
        let result = RunAnalyzer.analyze(samples: samples, config: cfg)

        // Peak should be hottest (59), not average (54)
        XCTAssertEqual(result.cpuPeakTemp, 59.0, accuracy: 0.1)
        XCTAssertEqual(result.gpuPeakTemp, 58.0, accuracy: 0.1)
    }

    // MARK: - Missing power stays nil

    func testMissingPowerDoesNotBecomeZero() {
        var samples: [TelemetrySample] = []
        for i in 0..<5 {
            var s = TelemetrySample()
            s.elapsedSeconds = Double(i)
            s.cpuTempHottest = 50
            // cpuPower NOT set — should be nil
            samples.append(s)
        }

        let cfg = TestConfiguration()
        let result = RunAnalyzer.analyze(samples: samples, config: cfg)

        // CPU power should be nil (not 0)
        XCTAssertNil(result.cpuPeakPower)
        XCTAssertEqual(result.sampleCount, 5)
    }
}

// MARK: - Compare Tests

final class CompareAnalyzerTests: XCTestCase {

    // Helper to build a valid run
    func makeRun(
        uuid: String = UUID().uuidString,
        chip: String = "Apple M4",
        device: String = "Mac16,13",
        mode: String = "standard",
        duration: TimeInterval = 600,
        samples: Int = 300,
        coverage: Double = 0.95,
        interrupted: Bool = false,
        appVersion: String = "0.2.1 (build 1)",
        macOS: String = "macOS 26.5",
        cpuPeak: Double = 95.0,
        gpuPeak: Double = 75.0,
        cpuPower: Double = 15.0,
        legacyDevice: Bool = false,
        workload: String = "combined",
        cpuCores: String = "all",
        gpuIntensity: String = "sustained",
        threads: Int = 0,
        loadDuration: TimeInterval = 900,
        sampleInterval: TimeInterval = 1.0,
        ac: Bool? = true,
        battery: Int? = 80
    ) -> RunRecord {
        let cfg = TestConfiguration(mode: .standard)
        let run = RunRecord(config: cfg)
        run.uuid = uuid
        run.chipName = legacyDevice ? "" : chip
        run.deviceModelIdentifier = legacyDevice ? "" : device
        run.testModeRaw = mode
        run.duration = duration
        run.sampleCount = samples
        run.dataCoverage = coverage
        run.wasInterrupted = interrupted
        run.appVersion = appVersion
        run.macOSVersion = macOS
        run.cpuPeakTemp = cpuPeak
        run.gpuPeakTemp = gpuPeak
        run.cpuPeakPower = cpuPower
        run.completedAt = Date()
        run.phaseRaw = TestPhase.completed.rawValue
        run.workloadTypeRaw = workload
        run.cpuCoreTypeRaw = cpuCores
        run.gpuIntensityRaw = gpuIntensity
        run.cpuThreadCount = threads
        run.loadDuration = loadDuration
        run.sampleInterval = sampleInterval
        run.acConnected = ac
        run.batteryPercent = battery
        return run
    }

    // MARK: - Invalid comparison

    func testSameRunRejected() {
        let run = makeRun()
        let result = CompareAnalyzer.analyze(a: run, b: run)
        XCTAssertEqual(result.level, .invalid)
        XCTAssertFalse(result.canCompare)
        XCTAssertTrue(result.warnings.contains { $0.id == "same_run" })
    }

    func testNoSamplesRejected() {
        let a = makeRun(samples: 0, duration: 0)
        let b = makeRun()
        let result = CompareAnalyzer.analyze(a: a, b: b)
        XCTAssertEqual(result.level, .invalid)
        XCTAssertTrue(result.warnings.contains { $0.id == "no_data" })
    }

    func testZeroCoverageRejected() {
        let a = makeRun(coverage: 0)
        let b = makeRun()
        let result = CompareAnalyzer.analyze(a: a, b: b)
        XCTAssertEqual(result.level, .invalid)
    }

    // MARK: - Warning on different devices / workload

    func testDifferentDevicesWarns() {
        let a = makeRun(chip: "Apple M4", device: "Mac16,13")
        let b = makeRun(chip: "Apple M3", device: "Mac15,6")
        let result = CompareAnalyzer.analyze(a: a, b: b)
        XCTAssertEqual(result.level, .comparableWithWarnings)
        XCTAssertTrue(result.warnings.contains { $0.field == "Chip" })
        XCTAssertTrue(result.warnings.contains { $0.field == "Device" })
        XCTAssertTrue(result.canCompare)
    }

    func testDifferentModesWarns() {
        let a = makeRun(mode: "standard")
        let b = makeRun(mode: "sustained")
        let result = CompareAnalyzer.analyze(a: a, b: b)
        XCTAssertEqual(result.level, .comparableWithWarnings)
        XCTAssertTrue(result.warnings.contains { $0.field == "Test Mode" })
    }

    // MARK: - Legacy metadata safety

    func testLegacyMetadataHandled() {
        let a = makeRun(legacyDevice: true)  // empty device fields
        let b = makeRun()
        let result = CompareAnalyzer.analyze(a: a, b: b)
        // Should warn about legacy, not crash
        XCTAssertFalse(result.warnings.isEmpty)
        XCTAssertTrue(result.fields.contains(where: { $0.valueA.contains("Legacy") }))
    }

    // MARK: - Highly comparable

    func testHighlyComparable() {
        let a = makeRun()
        let b = makeRun()
        let result = CompareAnalyzer.analyze(a: a, b: b)
        // Same device, same mode, both complete — should be highly comparable
        // (Chip name "Apple M4" is same, device "Mac16,13" is same)
        XCTAssertEqual(result.level, .highlyComparable)
        XCTAssertTrue(result.canCompare)
    }

    // MARK: - Interrupted runs

    func testInterruptedRunWarns() {
        let a = makeRun(interrupted: true)
        let b = makeRun()
        let result = CompareAnalyzer.analyze(a: a, b: b)
        XCTAssertTrue(result.warnings.contains { $0.field == "Completion" })
    }

    // MARK: - Configuration snapshot checks

    func testDifferentWorkloadWarns() {
        let a = makeRun(workload: "combined")
        let b = makeRun(workload: "cpuOnly")
        let result = CompareAnalyzer.analyze(a: a, b: b)
        XCTAssertEqual(result.level, .comparableWithWarnings)
        XCTAssertTrue(result.warnings.contains { $0.field == "Workload Type" })
    }

    func testDifferentCpuCoreTargetWarns() {
        let a = makeRun(cpuCores: "pCores")
        let b = makeRun(cpuCores: "eCores")
        let result = CompareAnalyzer.analyze(a: a, b: b)
        XCTAssertEqual(result.level, .comparableWithWarnings)
        XCTAssertTrue(result.warnings.contains { $0.field == "CPU Core Target" })
    }

    func testDifferentGpuIntensityWarns() {
        let a = makeRun(gpuIntensity: "sustained")
        let b = makeRun(gpuIntensity: "light")
        let result = CompareAnalyzer.analyze(a: a, b: b)
        XCTAssertEqual(result.level, .comparableWithWarnings)
        XCTAssertTrue(result.warnings.contains { $0.field == "GPU Intensity" })
    }

    func testDifferentThreadCountWarns() {
        let a = makeRun(threads: 8)
        let b = makeRun(threads: 4)
        let result = CompareAnalyzer.analyze(a: a, b: b)
        XCTAssertEqual(result.level, .comparableWithWarnings)
        XCTAssertTrue(result.warnings.contains { $0.field == "CPU Threads" })
    }

    func testLoadDurationDiffWarns() {
        let a = makeRun(loadDuration: 900)
        let b = makeRun(loadDuration: 300)
        let result = CompareAnalyzer.analyze(a: a, b: b)
        XCTAssertTrue(result.warnings.contains { $0.id == "loadDuration_diff" })
    }

    func testSampleIntervalDiffFlagged() {
        let a = makeRun(sampleInterval: 1.0)
        let b = makeRun(sampleInterval: 0.5)
        let result = CompareAnalyzer.analyze(a: a, b: b)
        let field = result.fields.first { $0.id == "sampleInterval" }
        XCTAssertNotNil(field)
        XCTAssertFalse(field!.match)
    }

    func testAcVsBatteryWarns() {
        let a = makeRun(ac: true, battery: 80)
        let b = makeRun(ac: false, battery: 45)
        let result = CompareAnalyzer.analyze(a: a, b: b)
        XCTAssertEqual(result.level, .comparableWithWarnings)
        XCTAssertTrue(result.warnings.contains { $0.id == "power_diff" })
    }
}

// MARK: - DeviceProfile & RunRecord Tests

final class ModelTests: XCTestCase {

    func testDeviceProfileReadsCorrectly() {
        let dev = DeviceProfile.current
        // At minimum we should get a non-empty model
        XCTAssertFalse(dev.modelIdentifier.isEmpty)
        XCTAssertFalse(dev.chipName.isEmpty)
        XCTAssertGreaterThan(dev.cpuCoreCount, 0)
        XCTAssertGreaterThan(dev.performanceCoreCount + dev.efficiencyCoreCount, 0)
        XCTAssertGreaterThan(dev.memoryBytes, 0)
    }

    func testDeviceProfileCodable() throws {
        let dev = DeviceProfile.current
        let data = try JSONEncoder().encode(dev)
        let decoded = try JSONDecoder().decode(DeviceProfile.self, from: data)
        XCTAssertEqual(dev.modelIdentifier, decoded.modelIdentifier)
        XCTAssertEqual(dev.chipName, decoded.chipName)
        XCTAssertEqual(dev.cpuCoreCount, decoded.cpuCoreCount)
    }

    func testTestConfigurationCodable() throws {
        var cfg = TestConfiguration(mode: .custom)
        cfg.workloadType = .combined
        cfg.cpuThreads = 6
        cfg.cpuCoreType = .pCores
        cfg.gpuIntensity = .sustained
        cfg.loadDuration = 300
        cfg.sampleInterval = 0.5
        cfg.ambientTemperature = 22

        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(TestConfiguration.self, from: data)
        XCTAssertEqual(decoded.workloadType, .combined)
        XCTAssertEqual(decoded.cpuCoreType, .pCores)
        XCTAssertEqual(decoded.gpuIntensity, .sustained)
        XCTAssertEqual(decoded.loadDuration, 300)
        XCTAssertEqual(decoded.sampleInterval, 0.5)
    }

    func testTotalDuration() {
        let cfg = TestConfiguration(
            mode: .custom,
            idleDuration: 60,
            loadDuration: 300,
            transitionDuration: 5,
            cooldownDuration: 60
        )
        let total = cfg.idleDuration + cfg.loadDuration + cfg.transitionDuration + cfg.cooldownDuration
        XCTAssertEqual(total, 425.0)
    }

    func testTotalDurationDefaultPreset() {
        let cfg = TestConfiguration(mode: .standard)
        let total = cfg.idleDuration + cfg.loadDuration + cfg.transitionDuration + cfg.cooldownDuration
        // standard preset: 180 + 900 + 5 + 300
        XCTAssertEqual(total, 1385.0)
    }
}

// MARK: - RunRecord Cancel Tests

final class RunRecordCancelTests: XCTestCase {

    @MainActor
    func testCancelProducesCompleteRunRecord() {
        let cfg = TestConfiguration(mode: .standard)
        let run = RunRecord(config: cfg)
        run.wasInterrupted = true
        run.sampleCount = 150
        run.duration = 300
        run.completedAt = Date()
        run.phaseRaw = TestPhase.cancelled.rawValue

        // Verify structure
        XCTAssertEqual(run.phaseRaw, TestPhase.cancelled.rawValue)
        XCTAssertTrue(run.wasInterrupted)
        XCTAssertEqual(run.sampleCount, 150)
        XCTAssertEqual(run.duration, 300)
        XCTAssertNotNil(run.uuid)
        XCTAssertFalse(run.uuid.isEmpty)
        XCTAssertNotNil(run.createdAt)
    }

    @MainActor
    func testRunRecordEncodesDeviceInfo() {
        let cfg = TestConfiguration(mode: .standard)
        let run = RunRecord(config: cfg)
        let dev = DeviceProfile.current
        run.deviceModelIdentifier = dev.modelIdentifier
        run.chipName = dev.chipName
        run.cpuCoreCount = dev.cpuCoreCount
        run.performanceCoreCount = dev.performanceCoreCount
        run.efficiencyCoreCount = dev.efficiencyCoreCount
        run.memoryBytes = Int64(dev.memoryBytes)
        run.macOSVersion = dev.macOSVersion
        run.metalDeviceName = dev.metalDeviceName ?? ""

        XCTAssertFalse(run.deviceModelIdentifier.isEmpty)
        XCTAssertFalse(run.chipName.isEmpty)
        XCTAssertGreaterThan(run.cpuCoreCount, 0)
        XCTAssertGreaterThan(run.memoryBytes, 0)
    }
}

// MARK: - WorkloadType Tests

final class WorkloadTypeTests: XCTestCase {

    func testUsesCPU() {
        XCTAssertTrue(WorkloadType.cpuOnly.usesCPU)
        XCTAssertFalse(WorkloadType.gpuOnly.usesCPU)
        XCTAssertTrue(WorkloadType.combined.usesCPU)
    }

    func testUsesGPU() {
        XCTAssertFalse(WorkloadType.cpuOnly.usesGPU)
        XCTAssertTrue(WorkloadType.gpuOnly.usesGPU)
        XCTAssertTrue(WorkloadType.combined.usesGPU)
    }

    func testDisplayName() {
        XCTAssertEqual(WorkloadType.cpuOnly.displayName, "CPU Only")
        XCTAssertEqual(WorkloadType.gpuOnly.displayName, "GPU Only")
        XCTAssertEqual(WorkloadType.combined.displayName, "CPU + GPU")
    }
}
