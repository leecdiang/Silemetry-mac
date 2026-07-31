// ThermalBench - Test Coordinator (state machine)
import Foundation
import SwiftData

@MainActor @Observable
final class TestCoordinator {
    enum State: Equatable {
        case idle
        case running(TestPhase, elapsed: TimeInterval, remaining: TimeInterval)
        case complete(RunRecord)
        /// Stopped with data — carries the final RunRecord to persist.
        case cancelled(RunRecord)
        /// Discarded — nothing to persist.
        case discarded
        case failed(String)
    }

    var state: State = .idle
    var samples: [TelemetrySample] = []
    var latest: TelemetrySample? = nil

    private let telemetry = TelemetryService.shared
    private let gpuWorkload = GPUWorkloadManager()
    private let maxSamples = 7200
    private var cancelledFlag = false
    private var untilStoppedFlag = false
    /// UUID for the run being recorded — determines the archive file path.
    private var runUUID = UUID().uuidString
    /// Samples awaiting flush to the archive file (streamed, not held forever).
    private var archiveBuffer: [TelemetrySample] = []

    var testConfig = TestConfiguration()
    var testModeRaw: String = ""

    var lastTelemetryError: String?
    var consecutiveReadFailures: Int = 0
    private var currentPhase: TestPhase = .baseline
    var isMonitorOnly: Bool { testConfig.mode == .monitorOnly }

    func start(config: TestConfiguration) async {
        testConfig = config
        currentPhase = .baseline
        cancelledFlag = false
        untilStoppedFlag = false
        runUUID = UUID().uuidString
        archiveBuffer.removeAll(keepingCapacity: true)
        samples.removeAll()
        state = .running(.preflight, elapsed: 0, remaining: totalDuration(config))

        do { try await telemetry.startTelemetry(intervalMilliseconds: Int(config.sampleInterval * 1000)) }
        catch { state = .failed("Telemetry start: \(error.localizedDescription)"); return }

        let startTime = DispatchTime.now().uptimeNanoseconds

        if config.mode == .monitorOnly {
            // Monitor Only: single infinite monitoring phase
            currentPhase = .baseline
            let phaseStart = DispatchTime.now().uptimeNanoseconds
            while !untilStoppedFlag && !cancelledFlag && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(config.sampleInterval * 1000)))

                do {
                    var sample = try await telemetry.readSample()
                    sample.phase = .baseline
                    samples.append(sample)
                    if samples.count > maxSamples { samples.removeFirst() }
                    latest = sample
                    archiveBuffer.append(sample)
                    if archiveBuffer.count >= SampleArchive.batchSize {
                        SampleArchive.append(archiveBuffer, uuid: runUUID)
                        archiveBuffer.removeAll(keepingCapacity: true)
                    }
                } catch {
                    consecutiveReadFailures += 1
                    lastTelemetryError = error.localizedDescription
                    if consecutiveReadFailures > 10 {
                        await cleanup()
                        state = .failed("Telemetry read failed \(consecutiveReadFailures) times")
                        return
                    }
                    continue
                }

                let totalElapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000_000
                state = .running(.baseline, elapsed: totalElapsed, remaining: totalElapsed)
            }
        } else {
            // Standard phased test
            let phases: [(TestPhase, TimeInterval)] = [
                (.baseline, config.idleDuration),
                (.loading, config.loadDuration),
                (.transition, config.transitionDuration),
                (.cooling, config.cooldownDuration),
            ]

            for (phase, duration) in phases {
                let phaseStart = DispatchTime.now().uptimeNanoseconds
                currentPhase = phase

                if phase == .loading { startWorkload(config: config) }
                if phase == .transition { stopWorkload() }

                while true {
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - phaseStart) / 1_000_000_000
                    if elapsed >= duration || cancelledFlag { break }
                    if Task.isCancelled { break }

                    try? await Task.sleep(for: .milliseconds(Int(config.sampleInterval * 1000)))

                    do {
                        var sample = try await telemetry.readSample()
                        consecutiveReadFailures = 0
                        lastTelemetryError = nil
                        sample.phase = currentPhase
                        samples.append(sample)
                        if samples.count > maxSamples { samples.removeFirst() }
                        latest = sample
                        archiveBuffer.append(sample)
                        if archiveBuffer.count >= SampleArchive.batchSize {
                            SampleArchive.append(archiveBuffer, uuid: runUUID)
                            archiveBuffer.removeAll(keepingCapacity: true)
                        }
                    } catch {
                        consecutiveReadFailures += 1
                        lastTelemetryError = error.localizedDescription
                        if consecutiveReadFailures > 10 {
                            await cleanup()
                            state = .failed("Telemetry read failed \(consecutiveReadFailures) times")
                            return
                        }
                        continue
                    }

                    let totalElapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000_000
                    let remaining = totalDuration(config) - totalElapsed
                    state = .running(phase, elapsed: totalElapsed, remaining: max(0, remaining))
                }
            }
        }

        await cleanup()

        // Flush any buffered samples, then build the record with the archive path.
        flushArchive()

        // Build RunRecord
        let snapshot = samples
        let analysis = RunAnalyzer.analyze(samples: snapshot, config: testConfig)
        let run = Self.buildRunRecord(snapshot: snapshot, analysis: analysis, config: config,
                                      archivePath: archivePath())
        state = .complete(run)
    }

    /// Manually finish Monitor Only recording
    func finishRecording() {
        untilStoppedFlag = true
    }



    /// Stop and keep current data (Stop button / Monitor Only finish).
    func stopAndSave() {
        cancelledFlag = true
        Task { await telemetry.stopTelemetry() }
        stopWorkload()
        flushArchive()
        state = Self.cancelledRecord(samples: samples, config: testConfig, archivePath: archivePath())
            .map { State.cancelled($0) }
            ?? .discarded
    }

    /// Discard current data without saving (Discard button).
    func cancelAndDiscard() {
        cancelledFlag = true
        Task { await telemetry.stopTelemetry() }
        stopWorkload()
        samples.removeAll()
        archiveBuffer.removeAll()
        SampleArchive.deleteFiles(uuid: runUUID)
        state = .discarded
    }

    /// Flush buffered samples to the archive file.
    private func flushArchive() {
        guard !archiveBuffer.isEmpty else { return }
        SampleArchive.append(archiveBuffer, uuid: runUUID)
        archiveBuffer.removeAll(keepingCapacity: true)
    }

    private func archivePath() -> String? {
        SampleArchive.samplesFile(for: runUUID).path
    }

    /// Build a final RunRecord for an interrupted run. Returns nil when there
    /// is nothing worth saving. Extracted so tests exercise the real path.
    static func cancelledRecord(samples: [TelemetrySample], config: TestConfiguration,
                                archivePath: String? = nil) -> RunRecord? {
        guard !samples.isEmpty else { return nil }
        let snapshot = samples
        let analysis = RunAnalyzer.analyze(samples: snapshot, config: config)
        let run = buildRunRecord(snapshot: snapshot, analysis: analysis, config: config,
                                 archivePath: archivePath)
        run.phaseRaw = TestPhase.cancelled.rawValue
        run.wasInterrupted = true
        return run
    }

    /// Unified cleanup: stops workloads, telemetry, and anything in flight.
    private func cleanup() async {
        await telemetry.stopTelemetry()
        stopWorkload()
    }

    // MARK: - Run Construction

    private static func buildRunRecord(snapshot: [TelemetrySample], analysis: RunAnalysis, config: TestConfiguration,
                                       archivePath: String?) -> RunRecord {
        let run = RunRecord(config: config)
        run.sampleCount = analysis.sampleCount
        run.duration = analysis.duration
        run.completedAt = Date()
        run.phaseRaw = TestPhase.completed.rawValue

        // Populate device info from current profile
        let dev = DeviceProfile.current
        run.deviceModelIdentifier = dev.modelIdentifier
        run.chipName = dev.chipName
        run.cpuCoreCount = dev.cpuCoreCount
        run.performanceCoreCount = dev.performanceCoreCount
        run.efficiencyCoreCount = dev.efficiencyCoreCount
        run.gpuCoreCount = dev.gpuCoreCount ?? 0
        run.memoryBytes = Int64(dev.memoryBytes)
        run.macOSVersion = dev.macOSVersion
        run.metalDeviceName = dev.metalDeviceName ?? ""

        run.cpuPeakPower = analysis.cpuPeakPower ?? 0
        run.cpuPeakTemp = analysis.cpuPeakTemp ?? 0
        run.gpuPeakTemp = analysis.gpuPeakTemp ?? 0
        run.pClusterMinFreq = analysis.pCorePeakFreq ?? 0
        run.dataCoverage = analysis.overallCoverage
        run.appVersion = BuildIdentity.appVersion

        // Analysis provenance
        run.analysisVersion = CompareAnalyzer.analysisVersion
        run.telemetryCoreVersion = String(cString: tb_telemetry_core_version())

        // Power source + low-power-mode snapshot (last sample)
        if let last = snapshot.last {
            run.acConnected = last.acConnected
            run.batteryPercent = last.batteryPercent
            run.lowPowerMode = last.lowPowerMode
        }

        // Samples: new file-backed archive, or legacy inline JSON.
        if let archivePath {
            run.dataDirectory = archivePath
        } else if let data = try? JSONEncoder().encode(snapshot),
                  let json = String(data: data, encoding: .utf8) {
            run.dataDirectory = json
        }

        if config.mode == .monitorOnly {
            run.name = "Monitor Only"
        }

        return run
    }

    // MARK: - Workload

    private func startWorkload(config: TestConfiguration) {
        if config.mode == .monitorOnly { return }

        // CPU workload — only when workload type uses CPU
        if config.workloadType.usesCPU {
            var cfg = cpu_workload_config_t(
                num_threads: config.cpuThreads > 0 ? UInt32(config.cpuThreads) : 0,
                use_fma: true,
                validate: true,
                core_type: CpuCoreTypeToC(config.cpuCoreType)
            )
            let r = cpu_workload_start(&cfg)
            print("[Workload] CPU start result=\(r) coreType=\(config.cpuCoreType)")
        }

        // GPU workload — only when workload type uses GPU
        if config.workloadType.usesGPU {
            gpuWorkload?.start(intensity: config.gpuIntensity)
        }
    }

    private func stopWorkload() {
        cpu_workload_stop()
        gpuWorkload?.stop()
    }

    /// Map Swift CpuCoreType to C cpu_core_type_t
    private func CpuCoreTypeToC(_ t: CpuCoreType) -> cpu_core_type_t {
        switch t {
        case .all:     return CPU_CORE_TYPE_ALL
        case .pCores:  return CPU_CORE_TYPE_PERFORMANCE
        case .eCores:  return CPU_CORE_TYPE_EFFICIENCY
        case .custom:  return CPU_CORE_TYPE_ALL  // custom thread count, use all
        }
    }

    private func totalDuration(_ c: TestConfiguration) -> TimeInterval {
        if c.mode == .monitorOnly { return 0 }
        return c.idleDuration + c.loadDuration + c.transitionDuration + c.cooldownDuration
    }
}
