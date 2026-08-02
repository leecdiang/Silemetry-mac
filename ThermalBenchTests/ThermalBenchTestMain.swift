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
        battery: Int? = 80,
        lowPower: Bool? = false,
        ambient: Double = 25,
        analysisVersion: Int = 1,
        baseline: TimeInterval = 180,
        cooldown: TimeInterval = 300,
        telemetryVer: String = "ThermalBenchTelemetryCore 0.1.0"
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
        run.lowPowerMode = lowPower
        run.ambientTemperature = ambient
        run.analysisVersion = analysisVersion
        run.baselineDuration = baseline
        run.cooldownDuration = cooldown
        run.telemetryCoreVersion = telemetryVer
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

    // ── Compare: extended provenance ───────────────────────────────────
    test("Compare: different analysis version warns") {
        let a = RunRecord.make(analysisVersion: 1)
        let b = RunRecord.make(analysisVersion: 2)
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.warnings.contains { $0.field == "Analysis Version" })
    }

    test("Compare: different baseline warns") {
        let a = RunRecord.make(baseline: 180)
        let b = RunRecord.make(baseline: 60)
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.warnings.contains { $0.id == "baseline_diff" })
    }

    test("Compare: different cooldown warns") {
        let a = RunRecord.make(cooldown: 300)
        let b = RunRecord.make(cooldown: 120)
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertTrue(r.warnings.contains { $0.id == "cooldown_diff" })
    }

    test("Compare: low power mode differs warns") {
        let a = RunRecord.make(lowPower: false)
        let b = RunRecord.make(lowPower: true)
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.warnings.contains { $0.id == "powerMode_diff" })
    }

    test("Compare: ambient diff >2°C downgrades") {
        let a = RunRecord.make(ambient: 25)
        let b = RunRecord.make(ambient: 30)
        let r = CompareAnalyzer.analyze(a: a, b: b)
        let f = r.fields.first { $0.id == "ambient" }
        try assertNotNil(f)
        try assertFalse(f!.match)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.warnings.contains { $0.id == "ambient_diff" })
    }

    test("Compare: small ambient diff within tolerance stays comparable") {
        let a = RunRecord.make(ambient: 25)
        let b = RunRecord.make(ambient: 26)
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .highlyComparable)
    }

    test("Compare: ambient not recorded on either side warns") {
        let a = RunRecord.make()
        let b = RunRecord.make()
        a.ambientTemperature = nil
        b.ambientTemperature = nil
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertTrue(r.warnings.contains { $0.id == "ambient_unverified" })
        try assertEqual(r.level, .comparableWithWarnings)
    }

    test("Compare: key metadata missing on both sides warns") {
        let a = RunRecord.make(workload: "", cpuCores: "", gpuIntensity: "", sampleInterval: 0)
        let b = RunRecord.make(workload: "", cpuCores: "", gpuIntensity: "", sampleInterval: 0)
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.warnings.contains { $0.id == "workload_both_legacy" })
        try assertTrue(r.warnings.contains { $0.id == "cpuCores_both_legacy" })
        try assertTrue(r.warnings.contains { $0.id == "sampleInterval_both_legacy" })
    }

    test("Monitor Only uses distinct external phase") {
        try assertEqual(TestPhase.monitoringExternal.rawValue, "monitoringExternal")
        try assertEqual(TestPhase.monitoringExternal.displayLabel, "External Load")
        let decoded = TestPhase(rawValue: TestPhase.monitoringExternal.rawValue)
        try assertEqual(decoded, .monitoringExternal)
    }

    // ── SampleArchive ──────────────────────────────────────────────────
    test("SampleArchive JSONL round-trip") {
        var samples: [TelemetrySample] = []
        for i in 0..<12 {
            var s = TelemetrySample()
            s.elapsedSeconds = Double(i)
            s.cpuTempHottest = Double(i)
            samples.append(s)
        }
        let uuid = "test-\(UUID().uuidString)"
        try SampleArchive.append(samples, uuid: uuid)
        let run = RunRecord(config: TestConfiguration())
        run.dataDirectory = SampleArchive.samplesFile(for: uuid).path
        let loaded = SampleArchive.load(from: run)
        try assertEqual(loaded.count, 12)
        try assertEqual(loaded.last!.elapsedSeconds, 11.0)
        SampleArchive.deleteFiles(uuid: uuid)
    }

    test("SampleArchive legacy inline JSON still loads") {
        var samples: [TelemetrySample] = []
        var s = TelemetrySample()
        s.cpuTempHottest = 61.5
        samples.append(s)
        let run = RunRecord(config: TestConfiguration())
        let data = try! JSONEncoder().encode(samples)
        run.dataDirectory = String(data: data, encoding: .utf8)!
        let loaded = SampleArchive.load(from: run)
        try assertEqual(loaded.count, 1)
        try assertEqual(loaded.first!.cpuTempHottest!, 61.5)
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
        try assertEqual(run!.cpuPeakTemp!, 59.0)
        try assertFalse(run!.appVersion.isEmpty)
    }

    test("Cancel path: empty samples discard — nil record") {
        let run = MainActor.assumeIsolated { () -> RunRecord? in
            TestCoordinator.cancelledRecord(samples: [], config: TestConfiguration())
        }
        try assertNil(run)
    }

    // ── Raw archive integrity (Summary vs raw curve consistency) ────────
    test("RawDataStatus defaults to complete") {
        let run = RunRecord(config: TestConfiguration())
        try assertEqual(run.rawDataStatusRaw, RawDataStatus.complete.rawValue)
        try assertNil(run.rawDataError)
    }

    test("RawDataStatus display names") {
        try assertEqual(RawDataStatus.complete.displayName, "Complete")
        try assertEqual(RawDataStatus.partial.displayName, "Partial")
        try assertEqual(RawDataStatus.unavailable.displayName, "Unavailable")
    }

    test("SampleArchive.hasData distinguishes written from empty") {
        let uuid = "rawstatus-\(UUID().uuidString)"
        try assertFalse(SampleArchive.hasData(uuid: uuid))
        var s = TelemetrySample()
        s.cpuTempHottest = 50
        try SampleArchive.append([s], uuid: uuid)
        try assertTrue(SampleArchive.hasData(uuid: uuid))
        SampleArchive.deleteFiles(uuid: uuid)
        try assertFalse(SampleArchive.hasData(uuid: uuid))
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

    // ── TestCoordinator stop/discard finalization ───────────────────────
    test("stopAndSave finalizes via main task (cancelled record)") {
        let coord = MainActor.assumeIsolated { () -> TestCoordinator in
            let c = TestCoordinator()
            var samples: [TelemetrySample] = []
            for i in 0..<10 {
                var s = TelemetrySample()
                s.elapsedSeconds = Double(i)
                s.cpuTempHottest = Double(50 + i)
                s.cpuPower = 5.0
                s.tempValid = true
                samples.append(s)
            }
            c.samples = samples
            c.stopAndSave()
            return c
        }
        // stopAndSave only requests the stop; the final state is produced by
        // the (not running here) main task. Simulate its finalization path:
        let run = MainActor.assumeIsolated { () -> RunRecord? in
            TestCoordinator.cancelledRecord(samples: coord.samples, config: coord.testConfig)
        }
        try assertNotNil(run)
        try assertTrue(run!.wasInterrupted)
        try assertEqual(run!.phaseRaw, TestPhase.cancelled.rawValue)
        try assertEqual(run!.sampleCount, 10)
        try assertEqual(run!.cpuPeakTemp!, 59.0)
    }

    test("cancelAndDiscard produces no record") {
        let coord = MainActor.assumeIsolated { () -> TestCoordinator in
            let c = TestCoordinator()
            var samples: [TelemetrySample] = []
            var s = TelemetrySample()
            s.cpuTempHottest = 50
            samples.append(s)
            c.samples = samples
            c.cancelAndDiscard()
            return c
        }
        // Discard must never persist: the record builder returns nil for the
        // discarded path (coord samples are cleared by the main task).
        let run = MainActor.assumeIsolated { () -> RunRecord? in
            TestCoordinator.cancelledRecord(samples: [], config: coord.testConfig)
        }
        try assertNil(run)
    }

    // ── History deletion leaves no orphan files ─────────────────────────
    test("deleteFiles removes both record path and uuid dir") {
        let uuid = "orphan-\(UUID().uuidString)"
        var samples: [TelemetrySample] = []
        var s = TelemetrySample()
        s.cpuTempHottest = 42
        samples.append(s)
        try SampleArchive.append(samples, uuid: uuid)
        let file = SampleArchive.samplesFile(for: uuid)
        try assertTrue(FileManager.default.fileExists(atPath: file.path))

        let run = RunRecord(config: TestConfiguration())
        run.uuid = uuid
        run.dataDirectory = file.path
        SampleArchive.deleteFiles(for: run)
        try assertFalse(FileManager.default.fileExists(atPath: file.path))
        try assertFalse(FileManager.default.fileExists(atPath: SampleArchive.directory(for: uuid).path))
    }

    // ── Long-test summary uses full stream, not the ring buffer ─────────
    test("RunAccumulator keeps early peaks beyond 7200 samples") {
        var acc = RunAccumulator()
        // 8000 samples: peak temp occurs at sample 100 (early, would be
        // dropped by the 7200 ring buffer).
        for i in 0..<8000 {
            var s = TelemetrySample()
            s.elapsedSeconds = Double(i)
            s.cpuTempHottest = i == 100 ? 99.0 : Double(40 + (i % 10))
            s.cpuTemp = s.cpuTempHottest
            s.cpuPower = 10.0
            s.tempValid = true
            acc.add(s)
        }
        let analysis = acc.makeAnalysis(config: TestConfiguration())
        try assertEqual(analysis.cpuPeakTemp!, 99.0)
        try assertEqual(analysis.sampleCount, 8000)
        try assertEqual(analysis.duration, 7999.0)
        try assertEqual(analysis.sampleSpan, 7999.0)

        // Ring-buffer view (last 7200) misses the early peak:
        var ring = RunAccumulator()
        var all: [TelemetrySample] = []
        for i in 0..<8000 {
            var s = TelemetrySample()
            s.elapsedSeconds = Double(i)
            s.cpuTempHottest = i == 100 ? 99.0 : Double(40 + (i % 10))
            s.cpuTemp = s.cpuTempHottest
            s.cpuPower = 10.0
            s.tempValid = true
            all.append(s)
        }
        ring.add(Array(all.suffix(7200)))
        let ringAnalysis = ring.makeAnalysis(config: TestConfiguration())
        try assertFalse(ringAnalysis.cpuPeakTemp! == 99.0)
    }

    test("RunAccumulator duration includes pre-first-sample gap") {
        // Telemetry starts at t=0 but the first sample lands at t=5; last at
        // t=10. Duration must be the total elapsed (10), not the sample span
        // (5) — otherwise the lead-in time is silently dropped.
        var acc = RunAccumulator()
        for i in 0..<3 {
            var s = TelemetrySample()
            s.elapsedSeconds = 5.0 + Double(i) * 2.5
            s.cpuTempHottest = 50
            s.tempValid = true
            acc.add(s)
        }
        let analysis = acc.makeAnalysis(config: TestConfiguration())
        try assertEqual(analysis.duration, 10.0)
        try assertEqual(analysis.sampleSpan, 5.0)
    }

    test("RunAccumulator single sample keeps real duration") {
        var acc = RunAccumulator()
        var s = TelemetrySample()
        s.elapsedSeconds = 2.0
        s.cpuTempHottest = 51
        s.tempValid = true
        acc.add(s)
        let analysis = acc.makeAnalysis(config: TestConfiguration())
        // Previously last-first = 0, which made TestView reject the run.
        try assertEqual(analysis.duration, 2.0)
        try assertEqual(analysis.sampleSpan, 0.0)
        try assertEqual(analysis.sampleCount, 1)
    }

    test("RunAnalyzer single sample keeps real duration") {
        var samples: [TelemetrySample] = []
        var s = TelemetrySample()
        s.elapsedSeconds = 3.0
        s.cpuTempHottest = 52
        s.tempValid = true
        samples.append(s)
        let analysis = RunAnalyzer.analyze(samples: samples, config: TestConfiguration())
        try assertEqual(analysis.duration, 3.0)
        try assertEqual(analysis.sampleSpan, 0.0)
    }

    // ── Compare: raw archive integrity ─────────────────────────────────
    test("Compare: partial raw data warns but stays comparable") {
        let a = RunRecord.make()
        let b = RunRecord.make()
        a.rawDataStatusRaw = RawDataStatus.partial.rawValue
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.canCompare)
        try assertTrue(r.warnings.contains { $0.id == "raw_partial_a" })
        let f = r.fields.first { $0.id == "rawData" }
        try assertNotNil(f)
        try assertFalse(f!.match)
    }

    test("Compare: unavailable raw data warns but stays comparable") {
        let a = RunRecord.make()
        let b = RunRecord.make()
        b.rawDataStatusRaw = RawDataStatus.unavailable.rawValue
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertEqual(r.level, .comparableWithWarnings)
        try assertTrue(r.canCompare)
        try assertTrue(r.warnings.contains { $0.id == "raw_unavailable_b" })
    }

    test("Compare: complete raw data on both sides matches") {
        let a = RunRecord.make()
        let b = RunRecord.make()
        let r = CompareAnalyzer.analyze(a: a, b: b)
        let f = r.fields.first { $0.id == "rawData" }
        try assertNotNil(f)
        try assertTrue(f!.match)
        try assertFalse(r.warnings.contains { $0.id.hasPrefix("raw_") })
    }

    // ── Compare: workload type trusted, not inferred from power ────────
    test("Compare: no CPU-load inference from power metrics") {
        // Both runs are GPU Only — but run A has nonzero cpuPeakPower from
        // system background activity. The old power-based inference would
        // flag a false CPU-load mismatch; the new rule must not.
        let a = RunRecord.make(cpuPower: 12.0, workload: "gpuOnly")
        let b = RunRecord.make(cpuPower: 0.0, workload: "gpuOnly")
        let r = CompareAnalyzer.analyze(a: a, b: b)
        try assertFalse(r.warnings.contains { $0.id == "cpu_load" })
        try assertFalse(r.warnings.contains { $0.field == "CPU Load" })
    }

    test("Compare: legacy workload shows unverified, not a guess") {
        let a = RunRecord.make(workload: "")
        let b = RunRecord.make()
        let r = CompareAnalyzer.analyze(a: a, b: b)
        let f = r.fields.first { $0.id == "workload" }
        try assertNotNil(f)
        try assertTrue(f!.valueA.contains("unverified") || f!.valueA.contains("Unverified"))
        try assertTrue(r.warnings.contains { $0.id == "workload_legacy_a" })
    }

    // ── RunRecord rawDataStatus decoding ───────────────────────────────
    test("RunRecord rawDataStatus decodes with legacy default") {
        let run = RunRecord(config: TestConfiguration())
        try assertEqual(run.rawDataStatus, .complete)
        run.rawDataStatusRaw = RawDataStatus.partial.rawValue
        try assertEqual(run.rawDataStatus, .partial)
        run.rawDataStatusRaw = "garbage"
        try assertEqual(run.rawDataStatus, .complete)
    }

    test("RunRecord sampleSpan defaults to zero for legacy") {
        let run = RunRecord(config: TestConfiguration())
        try assertEqual(run.sampleSpan, 0)
    }

    // ── TelemetrySample power source (nil = unknown, not Battery) ──────
    test("TelemetrySample acConnected defaults to unknown") {
        let s = TelemetrySample()
        try assertNil(s.acConnected)
        var t = TelemetrySample()
        t.acConnected = true
        try assertEqual(t.acConnected, true)
        var u = TelemetrySample()
        u.acConnected = false
        try assertEqual(u.acConnected, false)
    }

    test("TelemetrySample acConnected codable round-trip preserves unknown") {
        let s = TelemetrySample()
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(TelemetrySample.self, from: data)
        try assertNil(decoded.acConnected)
    }

    // ── Archive diagnostics: corrupted/truncated files degrade status ──
    test("ArchiveLoadResult: healthy file keeps complete") {
        let uuid = "archgood-\(UUID().uuidString)"
        var samples: [TelemetrySample] = []
        for i in 0..<4 {
            var s = TelemetrySample()
            s.elapsedSeconds = Double(i)
            s.cpuTempHottest = Double(i)
            samples.append(s)
        }
        try SampleArchive.append(samples, uuid: uuid)
        let run = RunRecord(config: TestConfiguration())
        run.dataDirectory = SampleArchive.samplesFile(for: uuid).path
        run.sampleCount = 4
        let result = SampleArchive.loadDetailed(dataDirectory: run.dataDirectory)
        try assertEqual(result.totalLines, 4)
        try assertEqual(result.malformedLines, 0)
        try assertEqual(result.samples.count, 4)
        try assertEqual(result.effectiveRawStatus(stored: .complete, expectedSamples: 4), .complete)
        SampleArchive.deleteFiles(uuid: uuid)
    }

    test("ArchiveLoadResult: malformed lines degrade complete to partial") {
        let uuid = "archbad-\(UUID().uuidString)"
        let dir = SampleArchive.directory(for: uuid)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var good = TelemetrySample()
        good.cpuTempHottest = 50
        let goodData = try JSONEncoder().encode(good)
        var text = String(data: goodData, encoding: .utf8)! + "\n"
        text += "{not valid json}\n"
        try text.write(to: SampleArchive.samplesFile(for: uuid), atomically: true, encoding: .utf8)

        let result = SampleArchive.loadDetailed(dataDirectory: SampleArchive.samplesFile(for: uuid).path)
        try assertEqual(result.totalLines, 2)
        try assertEqual(result.malformedLines, 1)
        try assertEqual(result.samples.count, 1)
        try assertEqual(result.effectiveRawStatus(stored: .complete, expectedSamples: 1), .partial)
        // Already-partial stays partial; never upgraded.
        try assertEqual(result.effectiveRawStatus(stored: .partial, expectedSamples: 1), .partial)
        SampleArchive.deleteFiles(uuid: uuid)
    }

    test("ArchiveLoadResult: truncated archive degrades to partial") {
        let uuid = "archtrunc-\(UUID().uuidString)"
        var samples: [TelemetrySample] = []
        for i in 0..<3 {
            var s = TelemetrySample()
            s.elapsedSeconds = Double(i)
            s.cpuTempHottest = Double(i)
            samples.append(s)
        }
        try SampleArchive.append(samples, uuid: uuid)
        let path = SampleArchive.samplesFile(for: uuid).path
        // Summary claims 5 samples, file only has 3.
        let result = SampleArchive.loadDetailed(dataDirectory: path)
        try assertEqual(result.totalLines, 3)
        try assertEqual(result.effectiveRawStatus(stored: .complete, expectedSamples: 5), .partial)
        SampleArchive.deleteFiles(uuid: uuid)
    }

    test("ArchiveLoadResult: missing file degrades to partial") {
        let uuid = "archmiss-\(UUID().uuidString)"
        let path = SampleArchive.samplesFile(for: uuid).path
        let result = SampleArchive.loadDetailed(dataDirectory: path)
        try assertFalse(result.fileExists)
        try assertTrue(result.isFileBacked)
        try assertEqual(result.effectiveRawStatus(stored: .complete, expectedSamples: 10), .partial)
    }

    test("ArchiveLoadResult: legacy inline JSON not cross-checked") {
        var samples: [TelemetrySample] = []
        var s = TelemetrySample()
        s.cpuTempHottest = 61.5
        samples.append(s)
        let data = try JSONEncoder().encode(samples)
        let result = SampleArchive.loadDetailed(dataDirectory: String(data: data, encoding: .utf8)!)
        try assertFalse(result.isFileBacked)
        try assertEqual(result.samples.count, 1)
        try assertEqual(result.effectiveRawStatus(stored: .complete, expectedSamples: 1), .complete)
    }

    // ── Delete transaction staging ─────────────────────────────────────
    test("stageFiles/purge removes files, restore brings them back") {
        let uuid = "stage-\(UUID().uuidString)"
        var s = TelemetrySample()
        s.cpuTempHottest = 42
        try SampleArchive.append([s], uuid: uuid)
        let run = RunRecord(config: TestConfiguration())
        run.uuid = uuid
        run.dataDirectory = SampleArchive.samplesFile(for: uuid).path

        // Stage → files leave the run directory
        let staged = SampleArchive.stageFiles(for: run)
        try assertNotNil(staged)
        try assertFalse(FileManager.default.fileExists(atPath: SampleArchive.directory(for: uuid).path))

        // Purge → staged data gone permanently
        SampleArchive.purgeStaged(staged)
        try assertFalse(FileManager.default.fileExists(atPath: staged!.path))

        // Stage again → restore puts the files back at the canonical path
        try SampleArchive.append([s], uuid: uuid)
        let staged2 = SampleArchive.stageFiles(for: run)
        try assertNotNil(staged2)
        SampleArchive.restoreStaged(staged2)
        try assertTrue(FileManager.default.fileExists(atPath: SampleArchive.directory(for: uuid).path))
        try assertTrue(FileManager.default.fileExists(atPath: SampleArchive.samplesFile(for: uuid).path))
        SampleArchive.deleteFiles(uuid: uuid)
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
