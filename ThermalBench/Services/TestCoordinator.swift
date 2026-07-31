// ThermalBench - Test Coordinator (state machine)
import Foundation
import SwiftData

@MainActor @Observable
final class TestCoordinator {
    enum State: Equatable {
        case idle
        case running(TestPhase, elapsed: TimeInterval, remaining: TimeInterval)
        case complete(RunRecord)
        /// Carries the partial run when samples were collected before cancelling,
        /// so the interrupted run is persisted with its analysis rather than rebuilt
        /// from scratch by the view. `nil` when there was nothing worth saving.
        case cancelled(RunRecord?)
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
        state = .running(.preflight, elapsed: 0, remaining: totalDuration(config))

        do { try await telemetry.startTelemetry() }
        catch { state = .failed("Telemetry start: \(error.localizedDescription)"); return }

        let startTime = DispatchTime.now().uptimeNanoseconds

        if config.mode == .monitorOnly {
            // Monitor Only: single infinite monitoring phase
            currentPhase = .baseline
            while !untilStoppedFlag && !cancelledFlag && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(config.sampleInterval * 1000)))

                do {
                    var sample = try await telemetry.readSample()
                    sample.phase = .baseline
                    samples.append(sample)
                    if samples.count > maxSamples { samples.removeFirst() }
                    latest = sample
                } catch {
                    consecutiveReadFailures += 1
                    lastTelemetryError = error.localizedDescription
                    if consecutiveReadFailures > 10 {
                        stopWorkload()
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
                // Leave the phase loop entirely on cancel. Without this the next
                // iteration would still run its phase setup — re-starting the
                // workload for `.loading` — before the inner loop noticed the flag.
                if cancelledFlag || Task.isCancelled { break }

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
                    } catch {
                        consecutiveReadFailures += 1
                        lastTelemetryError = error.localizedDescription
                        if consecutiveReadFailures > 10 {
                            stopWorkload()
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

        await telemetry.stopTelemetry()
        stopWorkload()

        // `cancel()` has already published `.cancelled` with its own record. Falling
        // through to `.complete` here would fire the view's onChange a second time and
        // save a duplicate history entry for the same run.
        if cancelledFlag || Task.isCancelled { return }

        // Build RunRecord
        let snapshot = samples
        let analysis = RunAnalyzer.analyze(samples: snapshot, config: testConfig)
        let run = buildRunRecord(snapshot: snapshot, analysis: analysis, config: config)
        state = .complete(run)
    }

    /// Manually finish Monitor Only recording
    func finishRecording() {
        untilStoppedFlag = true
    }

    func cancel() {
        guard !cancelledFlag else { return }
        cancelledFlag = true
        Task { await telemetry.stopTelemetry() }
        stopWorkload()

        guard !samples.isEmpty else {
            state = .cancelled(nil)
            return
        }

        let snapshot = samples
        let analysis = RunAnalyzer.analyze(samples: snapshot, config: testConfig)
        let run = buildRunRecord(snapshot: snapshot, analysis: analysis, config: testConfig)
        run.wasInterrupted = true
        run.phaseRaw = TestPhase.cancelled.rawValue
        // Hand the record to the view. It used to be built here and dropped, leaving
        // the view to reconstruct a bare record with no samples or analysis.
        state = .cancelled(run)
    }

    // MARK: - Run Construction

    private func buildRunRecord(snapshot: [TelemetrySample], analysis: RunAnalysis, config: TestConfiguration) -> RunRecord {
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

        if let data = try? JSONEncoder().encode(snapshot),
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
