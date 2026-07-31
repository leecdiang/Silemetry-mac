// ThermalBenchTests — minimal test runner (no XCTest dependency).
// Compiles alongside main sources; shares the same module namespace.
// Exit code 0 = pass, 1 = fail.
import Foundation

// MARK: - Test Runner

var total = 0, passed = 0, failed = 0

func test(_ name: String, _ body: () throws -> Void) {
    total += 1
    do {
        try body()
        passed += 1
        print("  ✅ \(name)")
    } catch {
        failed += 1
        print("  ❌ \(name): \(error)")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard a == b else { throw TestError.mismatch(msg.isEmpty ? "\(a) != \(b)" : msg, file: file, line: line) }
}

func assertTrue(_ condition: Bool, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard condition else { throw TestError.mismatch(msg.isEmpty ? "expected true" : msg, file: file, line: line) }
}

func assertFalse(_ condition: Bool, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard !condition else { throw TestError.mismatch(msg.isEmpty ? "expected false" : msg, file: file, line: line) }
}

func assertGreaterThan<T: Comparable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard a > b else { throw TestError.mismatch(msg.isEmpty ? "\(a) <= \(b)" : msg, file: file, line: line) }
}

func assertNil<T>(_ value: T?, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard value == nil else { throw TestError.mismatch(msg.isEmpty ? "expected nil, got \(value!)" : msg, file: file, line: line) }
}

func assertNotNil<T>(_ value: T?, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard value != nil else { throw TestError.mismatch(msg.isEmpty ? "expected non-nil" : msg, file: file, line: line) }
}

enum TestError: Error, CustomStringConvertible {
    case mismatch(String, file: String, line: Int)
    var description: String { if case .mismatch(let m, _, _) = self { return m }; return "unknown" }
}

extension RunRecord {
    static func make(
        uuid: String = UUID().uuidString,
        chip: String = "Apple M4",
        device: String = "Mac16,13",
        mode: String = "standard",
        duration: TimeInterval = 600,
        samples: Int = 300,
        coverage: Double = 0.95,
        interrupted: Bool = false,
        appVersion: String = "0.2.0 (build 1)",
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
}

// MARK: - Test Suites

func runAllTests() {

    // ── RunAnalyzer: hottest field ──────────────────────────────────────
    test("RunAnalyzer uses cpuTempHottest for peak") {
        var samples: [TelemetrySample] = []
        for i in 0..<10 {
            var s = TelemetrySample()
            s.elapsedSeconds = Double(i)
            s.cpuTempHottest = Double(50 + i)
            s.cpuTemp = Double(45 + i)
            s.gpuTempHottest = Double(40 + i * 2)
            s.cpuPower = 5.0
            s.gpuPower = 3.0
            s.pClusterFreqMHz = 3000
            s.tempValid = true
            s.powerValid = true
            s.freqValid = true
            samples.append(s)
        }
        let cfg = TestConfiguration()
        let r = RunAnalyzer.analyze(samples: samples, config: cfg)
        try assertEqual(r.cpuPeakTemp!, 59.0)
        try assertEqual(r.gpuPeakTemp!, 58.0)
    }

    // ── RunAnalyzer: missing power is nil ───────────────────────────────
    test("Missing power stays nil, not zero") {
        var samples: [TelemetrySample] = []
        for i in 0..<5 {
            var s = TelemetrySample()
            s.elapsedSeconds = Double(i)
            s.cpuTempHottest = 50
            samples.append(s)
        }
        let cfg = TestConfiguration()
        let r = RunAnalyzer.analyze(samples: samples, config: cfg)
        try assertNil(r.cpuPeakPower)
        try assertEqual(r.sampleCount, 5)
    }

    // ── Compare: same run rejected ──────────────────────────────────────
    test("Compare: same run rejected") {
        let a = RunRecord.make()
        let r = CompareAnalyzer.analyze(a: a, b: a)
        try assertEqual(r.level, .invalid)
        try assertFalse(r.canCompare)
        try assertTrue(r.warnings.contains { $0.id == "same_run" })
    }

    // ── Compare: no data rejected ──────────────────────────────────────
    test("Compare: no samples rejected") {
        let a = RunRecord.make(duration: 0, samples: 0)
        let b = RunRecord.make()
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .invalid)
    }

    test("Compare: zero coverage rejected") {
        let a = RunRecord.make(coverage: 0)
        let b = RunRecord.make()
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .invalid)
    }

    // ── Compare: different device warns ─────────────────────────────────
    test("Compare: different device warns") {
        let a = RunRecord.make(chip: "Apple M4", device: "Mac16,13")
        let b = RunRecord.make(chip: "Apple M3", device: "Mac15,6")
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.canCompare)
    }

    // ── Compare: different mode warns ───────────────────────────────────
    test("Compare: different mode warns") {
        let a = RunRecord.make(mode: "standard")
        let b = RunRecord.make(mode: "sustained")
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
    }

    // ── Compare: legacy metadata ────────────────────────────────────────
    test("Compare: legacy metadata handled safely") {
        let a = RunRecord.make(legacyDevice: true)
        let b = RunRecord.make()
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertTrue(r.fields.contains(where: { $0.valueA.contains("Legacy") }))
    }

    // ── Compare: highly comparable ──────────────────────────────────────
    test("Compare: highly comparable") {
        let a = RunRecord.make()
        let b = RunRecord.make()
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .highlyComparable)
        try assertTrue(r.canCompare)
    }

    // ── Compare: interrupted warns ──────────────────────────────────────
    test("Compare: interrupted run warns") {
        let a = RunRecord.make(interrupted: true)
        let b = RunRecord.make()
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertTrue(r.warnings.contains { $0.field == "Completion" })
    }

    // ── Compare: configuration snapshot ────────────────────────────────
    test("Compare: different workload warns") {
        let a = RunRecord.make(workload: "combined")
        let b = RunRecord.make(workload: "cpuOnly")
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.warnings.contains { $0.field == "Workload Type" })
    }

    test("Compare: different CPU core target warns") {
        let a = RunRecord.make(cpuCores: "pCores")
        let b = RunRecord.make(cpuCores: "eCores")
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.warnings.contains { $0.field == "CPU Core Target" })
    }

    test("Compare: different GPU intensity warns") {
        let a = RunRecord.make(gpuIntensity: "sustained")
        let b = RunRecord.make(gpuIntensity: "light")
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.warnings.contains { $0.field == "GPU Intensity" })
    }

    test("Compare: different thread count warns") {
        let a = RunRecord.make(threads: 8)
        let b = RunRecord.make(threads: 4)
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.warnings.contains { $0.field == "CPU Threads" })
    }

    test("Compare: load duration >10% diff warns") {
        let a = RunRecord.make(loadDuration: 900)
        let b = RunRecord.make(loadDuration: 300)
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertTrue(r.warnings.contains { $0.id == "loadDuration_diff" })
    }

    test("Compare: sample interval diff flagged") {
        let a = RunRecord.make(sampleInterval: 1.0)
        let b = RunRecord.make(sampleInterval: 0.5)
        let r = CompareAnalyzer.analyze(a: a, b: b)
        let f = r.fields.first { $0.id == "sampleInterval" }
        try assertNotNil(f)
        try assertFalse(f!.match)
    }

    test("Compare: AC vs battery warns") {
        let a = RunRecord.make(ac: true, battery: 80)
        let b = RunRecord.make(ac: false, battery: 45)
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.warnings.contains { $0.id == "power_diff" })
    }

    // ── DeviceProfile codable ───────────────────────────────────────────
    test("DeviceProfile codable round-trip") {
        let dev = DeviceProfile.current
        let data = try JSONEncoder().encode(dev)
        let decoded = try JSONDecoder().decode(DeviceProfile.self, from: data)
        try assertEqual(dev.modelIdentifier, decoded.modelIdentifier)
        try assertEqual(dev.chipName, decoded.chipName)
        try assertEqual(dev.cpuCoreCount, decoded.cpuCoreCount)
    }

    // ── TestConfiguration codable ───────────────────────────────────────
    test("TestConfiguration codable round-trip") {
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
        try assertEqual(decoded.workloadType, .combined)
        try assertEqual(decoded.cpuCoreType, .pCores)
        try assertEqual(decoded.gpuIntensity, .sustained)
        try assertEqual(decoded.loadDuration, 300)
    }

    // ── Total duration ──────────────────────────────────────────────────
    test("totalDuration: custom preset") {
        let cfg = TestConfiguration(mode: .custom, idleDuration: 60, loadDuration: 300, cooldownDuration: 60)
        let total = cfg.idleDuration + cfg.loadDuration + cfg.transitionDuration + cfg.cooldownDuration
        try assertEqual(total, 425.0)
    }

    test("totalDuration: standard preset default") {
        let cfg = TestConfiguration(mode: .standard)
        let total = cfg.idleDuration + cfg.loadDuration + cfg.transitionDuration + cfg.cooldownDuration
        try assertEqual(total, 1385.0)
    }

    // ── RunRecord cancel ────────────────────────────────────────────────
    test("Cancel produces complete RunRecord") {
        let cfg = TestConfiguration(mode: .standard)
        let run = RunRecord(config: cfg)
        run.wasInterrupted = true
        run.sampleCount = 150
        run.duration = 300
        run.completedAt = Date()
        run.phaseRaw = TestPhase.cancelled.rawValue
        try assertEqual(run.phaseRaw, TestPhase.cancelled.rawValue)
        try assertTrue(run.wasInterrupted)
        try assertEqual(run.sampleCount, 150)
        try assertFalse(run.uuid.isEmpty)
    }

    test("Cancel path: cancelledRecord builds full metrics record") {
        var samples: [TelemetrySample] = []
        for i in 0..<10 {
            var s = TelemetrySample()
            s.elapsedSeconds = Double(i)
            s.cpuTempHottest = Double(50 + i)
            s.cpuTemp = Double(45 + i)
            s.cpuPower = 5.0
            s.tempValid = true
            s.powerValid = true
            samples.append(s)
        }
        let cfg = TestConfiguration()
        let run = MainActor.assumeIsolated { () -> RunRecord? in
            TestCoordinator.cancelledRecord(samples: samples, config: cfg)
        }
        try assertNotNil(run)
        try assertTrue(run!.wasInterrupted)
        try assertEqual(run!.phaseRaw, TestPhase.cancelled.rawValue)
        try assertEqual(run!.sampleCount, 10)
        try assertGreaterThan(run!.duration, 0)
        try assertEqual(run!.cpuPeakTemp, 59.0)
        try assertFalse(run!.appVersion.isEmpty)
    }

    test("Cancel path: empty samples discard — nil record") {
        let run = MainActor.assumeIsolated { () -> RunRecord? in
            TestCoordinator.cancelledRecord(samples: [], config: TestConfiguration())
        }
        try assertNil(run)
    }

    // ── RunRecord device info ───────────────────────────────────────────
    test("RunRecord encodes device info") {
        let cfg = TestConfiguration(mode: .standard)
        let run = RunRecord(config: cfg)
        let dev = DeviceProfile.current
        run.deviceModelIdentifier = dev.modelIdentifier
        run.chipName = dev.chipName
        run.cpuCoreCount = dev.cpuCoreCount
        run.memoryBytes = Int64(dev.memoryBytes)
        try assertFalse(run.deviceModelIdentifier.isEmpty)
        try assertFalse(run.chipName.isEmpty)
        try assertGreaterThan(run.cpuCoreCount, 0)
        try assertGreaterThan(run.memoryBytes, 0)
    }

    // ── WorkloadType semantics ──────────────────────────────────────────
    test("WorkloadType: usesCPU/usesGPU") {
        try assertTrue(WorkloadType.cpuOnly.usesCPU)
        try assertFalse(WorkloadType.cpuOnly.usesGPU)
        try assertFalse(WorkloadType.gpuOnly.usesCPU)
        try assertTrue(WorkloadType.gpuOnly.usesGPU)
        try assertTrue(WorkloadType.combined.usesCPU)
        try assertTrue(WorkloadType.combined.usesGPU)
    }

    // ── DeviceProfile reads real data ───────────────────────────────────
    test("DeviceProfile reads non-empty values") {
        let dev = DeviceProfile.current
        try assertFalse(dev.modelIdentifier.isEmpty)
        try assertFalse(dev.chipName.isEmpty)
        try assertGreaterThan(dev.cpuCoreCount, 0)
        try assertGreaterThan(dev.memoryBytes, 0)
    }

    // ── Report ──────────────────────────────────────────────────────────
    print("")
    print("=== Results: \(passed)/\(total) passed, \(failed) failed ===")
}

// MARK: - Entry point
@main
struct TestMain {
    static func main() {
        print("ThermalBench Tests")
        print("==================")
        runAllTests()
        Darwin.exit(failed > 0 ? 1 : 0)
    }
}
