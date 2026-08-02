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
    /// Set when the sample archive failed to write (surfaced in the UI).
    var archiveError: String?
    /// Built when telemetry fails fatally but samples were captured. The UI
    /// can offer to save this partial run or discard it.
    var partialRun: RunRecord?

    enum FinishReason {
        case saveInterrupted
        case discarded
        /// Fatal telemetry failure — finalize what we have so the user can
        /// keep a partial record instead of losing everything to an early return.
        case failedSavePartial
    }

    private let telemetry = TelemetryService.shared
    private let gpuWorkload = GPUWorkloadManager()
    private let maxSamples = 7200
    private var cancelledFlag = false
    private var untilStoppedFlag = false
    /// UUID for the run being recorded — determines the archive file path.
    private var runUUID = UUID().uuidString
    /// When the current run actually started — RunRecord.createdAt is built
    /// only at finalization, so without this the "Started" time would be the
    /// end time.
    private var runStartedAt = Date()
    /// Device profile captured at test start — final records describe the
    /// machine as it was when the test began, not when it ended.
    private var runDeviceProfile = DeviceProfile.current
    /// Samples awaiting flush to the archive file (streamed, not held forever).
    private var archiveBuffer: [TelemetrySample] = []
    /// True once the archive write failed — stop buffering to avoid unbounded growth.
    private var archiveUnhealthy = false
    /// Single finalization owner: the main start() task decides the final state.
    private var finishReason: FinishReason?
    /// Streaming summary — complete peaks even when samples ring buffer drops old data.
    private var accumulator = RunAccumulator()

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
        finishReason = nil
        archiveError = nil
        archiveUnhealthy = false
        consecutiveReadFailures = 0
        lastTelemetryError = nil
        runStartedAt = Date()
        runDeviceProfile = DeviceProfile.current
        runUUID = UUID().uuidString
        partialRun = nil
        archiveBuffer.removeAll(keepingCapacity: true)
        samples.removeAll()
        accumulator = RunAccumulator()
        state = .running(.preflight, elapsed: 0, remaining: totalDuration(config))

        do { try await telemetry.startTelemetry(intervalMilliseconds: Int(config.sampleInterval * 1000)) }
        catch { state = .failed("Telemetry start: \(error.localizedDescription)"); return }

        let startTime = DispatchTime.now().uptimeNanoseconds

        if config.mode == .monitorOnly {
            // Monitor Only: single infinite monitoring phase. Distinct phase
            // so Timeline/JSONL can tell real Baseline from External Workload.
            currentPhase = .monitoringExternal
            while !untilStoppedFlag && !cancelledFlag && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(config.sampleInterval * 1000)))

                do {
                    var sample = try await telemetry.readSample()
                    sample.phase = .monitoringExternal
                    consecutiveReadFailures = 0
                    lastTelemetryError = nil
                    samples.append(sample)
                    if samples.count > maxSamples { samples.removeFirst() }
                    latest = sample
                    record(sample)
                } catch {
                    consecutiveReadFailures += 1
                    lastTelemetryError = error.localizedDescription
                    if consecutiveReadFailures > 10 {
                        // Do NOT return here — fall through to the unified
                        // cleanup → flushArchive → finalization flow so the
                        // buffered tail is written and a partial record can
                        // be offered.
                        finishReason = .failedSavePartial
                        break
                    }
                    continue
                }

                let totalElapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000_000
                // Monitor Only is a single infinite phase — publish the real
                // phase (not .baseline) and no remaining time.
                state = .running(.monitoringExternal, elapsed: totalElapsed, remaining: 0)
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
                // A stop/discard during any phase must not enter the next one.
                if cancelledFlag || finishReason != nil || Task.isCancelled { break }

                let phaseStart = DispatchTime.now().uptimeNanoseconds
                currentPhase = phase

                if phase == .loading, cancelledFlag == false, finishReason == nil {
                    startWorkload(config: config)
                }
                if phase == .transition { stopWorkload() }

                while true {
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - phaseStart) / 1_000_000_000
                    if elapsed >= duration || cancelledFlag || finishReason != nil { break }
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
                        record(sample)
                    } catch {
                        consecutiveReadFailures += 1
                        lastTelemetryError = error.localizedDescription
                        if consecutiveReadFailures > 10 {
                            // Same as monitor-only: no early return — the
                            // unified finalization below writes the buffered
                            // tail and offers a partial record.
                            finishReason = .failedSavePartial
                            break
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
        flushArchive()

        // Single finalization owner: the main task decides the final state.
        switch finishReason {
        case .discarded:
            samples.removeAll()
            archiveBuffer.removeAll()
            SampleArchive.deleteFiles(uuid: runUUID)
            state = .discarded
        case .saveInterrupted:
            // Build from the streaming accumulator, NOT the UI ring buffer —
            // after hours of running, `samples` only holds the last 7200 and
            // early peaks would vanish from the interrupted record's Summary,
            // History and Compare.
            let analysis = accumulator.makeAnalysis(config: testConfig)
            let run = Self.buildRunRecord(analysis: analysis, config: testConfig,
                                          archivePath: archivePath(), uuid: runUUID,
                                          lastSample: accumulator.lastSample,
                                          startedAt: runStartedAt,
                                          firstSample: accumulator.firstSample,
                                          device: runDeviceProfile)
            run.wasInterrupted = true
            run.phaseRaw = TestPhase.cancelled.rawValue
            applyRawDataStatus(run)
            state = .cancelled(run)
        case .failedSavePartial:
            // Fatal telemetry failure with captured samples: keep the partial
            // record for the UI to offer (Save Partial Run / Discard).
            if accumulator.sampleCount > 0 {
                let analysis = accumulator.makeAnalysis(config: testConfig)
                let run = Self.buildRunRecord(analysis: analysis, config: testConfig,
                                              archivePath: archivePath(), uuid: runUUID,
                                              lastSample: accumulator.lastSample,
                                              startedAt: runStartedAt,
                                              firstSample: accumulator.firstSample,
                                              device: runDeviceProfile)
                run.wasInterrupted = true
                run.phaseRaw = TestPhase.failed.rawValue
                applyRawDataStatus(run)
                partialRun = run
            }
            state = .failed(lastTelemetryError ?? "Telemetry read failed \(consecutiveReadFailures) times")
        case nil:
            let analysis = accumulator.makeAnalysis(config: testConfig)
            let run = Self.buildRunRecord(analysis: analysis, config: config,
                                          archivePath: archivePath(), uuid: runUUID,
                                          lastSample: accumulator.lastSample,
                                          startedAt: runStartedAt,
                                          firstSample: accumulator.firstSample,
                                          device: runDeviceProfile)
            applyRawDataStatus(run)
            state = .complete(run)
        }
    }

    /// Fold a sample into the streaming summary and archive buffer.
    private func record(_ sample: TelemetrySample) {
        accumulator.add(sample)
        guard !archiveUnhealthy else { return }
        archiveBuffer.append(sample)
        if archiveBuffer.count >= SampleArchive.batchSize {
            flushArchive()
        }
    }

    /// Manually finish Monitor Only recording
    func finishRecording() {
        untilStoppedFlag = true
    }



    /// Stop and keep current data (Stop button / Monitor Only finish).
    /// Only requests the stop — the main start() task performs the finalization.
    func stopAndSave() {
        cancelledFlag = true
        untilStoppedFlag = true
        finishReason = .saveInterrupted
    }

    /// Discard current data without saving (Discard button).
    /// Only requests the stop — the main start() task performs the finalization.
    func cancelAndDiscard() {
        cancelledFlag = true
        untilStoppedFlag = true
        finishReason = .discarded
    }

    /// Flush buffered samples to the archive file. On failure the buffer is
    /// kept (never silently dropped) and the error is surfaced to the UI.
    private func flushArchive() {
        guard !archiveBuffer.isEmpty else { return }
        do {
            try SampleArchive.append(archiveBuffer, uuid: runUUID)
            archiveBuffer.removeAll(keepingCapacity: true)
        } catch {
            archiveUnhealthy = true
            archiveError = "Sample archive write failed: \(error.localizedDescription)"
            print("[Coordinator] \(archiveError ?? "")")
        }
    }

    /// Record the integrity of the raw sample archive on the final RunRecord
    /// so the UI can warn when the Summary and the raw curve disagree.
    private func applyRawDataStatus(_ run: RunRecord) {
        guard archiveUnhealthy else { return }
        run.rawDataStatusRaw = (SampleArchive.hasData(uuid: runUUID)
            ? RawDataStatus.partial : RawDataStatus.unavailable).rawValue
        run.rawDataError = archiveError
    }

    private func archivePath() -> String? {
        SampleArchive.samplesFile(for: runUUID).path
    }

    /// Build a final RunRecord for an interrupted run. Returns nil when there
    /// is nothing worth saving.
    ///
    /// NOTE: production interrupted runs now finalize through the streaming
    /// accumulator in `start()`; this sample-array variant is kept for the
    /// test fixtures that exercise the legacy path.
    static func cancelledRecord(samples: [TelemetrySample], config: TestConfiguration,
                                archivePath: String? = nil,
                                uuid: String = UUID().uuidString) -> RunRecord? {
        guard !samples.isEmpty else { return nil }
        var acc = RunAccumulator()
        acc.add(samples)
        let analysis = acc.makeAnalysis(config: config)
        let run = buildRunRecord(analysis: analysis, config: config,
                                 archivePath: archivePath, uuid: uuid,
                                 lastSample: acc.lastSample,
                                 firstSample: acc.firstSample)
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

    private static func buildRunRecord(analysis: RunAnalysis, config: TestConfiguration,
                                       archivePath: String?, uuid: String,
                                       lastSample: TelemetrySample?,
                                       startedAt: Date? = nil,
                                       firstSample: TelemetrySample? = nil,
                                       device: DeviceProfile = DeviceProfile.current) -> RunRecord {
        let run = RunRecord(config: config)
        run.uuid = uuid
        run.createdAt = startedAt ?? Date()
        run.sampleCount = analysis.sampleCount
        run.duration = analysis.duration
        run.sampleSpan = analysis.sampleSpan
        run.completedAt = Date()
        run.phaseRaw = TestPhase.completed.rawValue

        // Power-source and low-power snapshots: first vs last sample, so a
        // run that switched conditions mid-test is not presented as uniform.
        if let first = firstSample, let last = lastSample {
            run.powerSourceAtStart = first.acConnected
            run.powerSourceAtEnd = last.acConnected
            if let a = first.acConnected, let b = last.acConnected {
                run.powerSourceChanged = a != b
            }
            run.lowPowerModeAtStart = first.lowPowerMode
            run.lowPowerModeAtEnd = last.lowPowerMode
            run.lowPowerModeChanged = first.lowPowerMode != last.lowPowerMode
        }

        // Device info from the profile captured at test start.
        let dev = device
        run.deviceModelIdentifier = dev.modelIdentifier
        run.chipName = dev.chipName
        run.cpuCoreCount = dev.cpuCoreCount
        run.performanceCoreCount = dev.performanceCoreCount
        run.efficiencyCoreCount = dev.efficiencyCoreCount
        run.gpuCoreCount = dev.gpuCoreCount ?? 0
        run.memoryBytes = Int64(dev.memoryBytes)
        run.macOSVersion = dev.macOSVersion
        run.metalDeviceName = dev.metalDeviceName ?? ""

        // Optional-aware metrics — unavailable stays nil, never a fake 0.
        run.cpuPeakPower = analysis.cpuPeakPower
        run.cpuPeakTemp = analysis.cpuPeakTemp
        run.gpuPeakTemp = analysis.gpuPeakTemp
        run.gpuPeakPower = analysis.gpuPeakPower
        run.pClusterPeakFreq = analysis.pCorePeakFreq
        run.dataCoverage = analysis.overallCoverage
        run.appVersion = BuildIdentity.appVersion

        // Analysis provenance
        run.analysisVersion = CompareAnalyzer.analysisVersion
        run.telemetryCoreVersion = String(cString: tb_telemetry_core_version())

        // Power source + low-power-mode snapshot (last sample)
        if let last = lastSample {
            run.acConnected = last.acConnected
            run.batteryPercent = last.batteryPercent
            run.lowPowerMode = last.lowPowerMode
        }

        // Samples: new file-backed archive (path), or legacy inline JSON.
        if let archivePath {
            run.dataDirectory = archivePath
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
