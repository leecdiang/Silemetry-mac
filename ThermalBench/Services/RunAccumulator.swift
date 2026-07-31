// ThermalBench - Run Accumulator
// Streaming summary aggregation. Every sample is folded into the summary as
// it arrives, so peaks/averages/coverage stay complete even when the in-memory
// ring buffer (UI display only) drops old samples during long tests.
import Foundation

struct RunAccumulator {
    private(set) var sampleCount = 0
    private(set) var validSampleCount = 0
    private(set) var firstElapsed: TimeInterval?
    private(set) var lastElapsed: TimeInterval?
    private(set) var lastSample: TelemetrySample?

    // Temperature (per channel, optional-aware)
    private(set) var cpuPeakTemp: Double?
    private(set) var cpuAvgSum: Double = 0
    private(set) var cpuAvgCount = 0
    private(set) var gpuPeakTemp: Double?
    private(set) var gpuAvgSum: Double = 0
    private(set) var gpuAvgCount = 0
    private(set) var tempValidCount = 0

    // Power (per channel, never fabricate 0)
    private(set) var cpuPeakPower: Double?
    private(set) var cpuPowerSum: Double = 0
    private(set) var cpuPowerCount = 0
    private(set) var gpuPeakPower: Double?
    private(set) var packagePeakPower: Double?
    private(set) var powerValidCount = 0

    // Frequency (per channel)
    private(set) var pCorePeakFreq: Double?
    private(set) var pCoreFreqSum: Double = 0
    private(set) var pCoreFreqCount = 0
    private(set) var eCorePeakFreq: Double?
    private(set) var eCoreFreqSum: Double = 0
    private(set) var eCoreFreqCount = 0
    private(set) var freqValidCount = 0

    // Load-phase CPU power average
    private(set) var loadPowerSum: Double = 0
    private(set) var loadPowerCount = 0

    mutating func add(_ s: TelemetrySample) {
        sampleCount += 1
        if s.cpuTemp != nil || s.gpuTemp != nil || s.cpuPower != nil || s.gpuPower != nil || s.pClusterFreqMHz != nil || s.eClusterFreqMHz != nil {
            validSampleCount += 1
        }
        if firstElapsed == nil { firstElapsed = s.elapsedSeconds }
        lastElapsed = s.elapsedSeconds
        lastSample = s

        if let v = s.cpuTempHottest { cpuPeakTemp = max(cpuPeakTemp ?? 0, v) }
        if let v = s.cpuTemp { cpuAvgSum += v; cpuAvgCount += 1 }
        if let v = s.gpuTempHottest { gpuPeakTemp = max(gpuPeakTemp ?? 0, v) }
        if let v = s.gpuTemp { gpuAvgSum += v; gpuAvgCount += 1 }
        if s.cpuTemp != nil || s.gpuTemp != nil { tempValidCount += 1 }

        if let v = s.cpuPower {
            cpuPeakPower = max(cpuPeakPower ?? 0, v)
            cpuPowerSum += v; cpuPowerCount += 1
        }
        if let v = s.gpuPower { gpuPeakPower = max(gpuPeakPower ?? 0, v) }
        if let v = s.packagePower { packagePeakPower = max(packagePeakPower ?? 0, v) }
        if s.cpuPower != nil || s.gpuPower != nil { powerValidCount += 1 }

        if let v = s.pClusterFreqMHz {
            pCorePeakFreq = max(pCorePeakFreq ?? 0, v)
            pCoreFreqSum += v; pCoreFreqCount += 1
        }
        if let v = s.eClusterFreqMHz {
            eCorePeakFreq = max(eCorePeakFreq ?? 0, v)
            eCoreFreqSum += v; eCoreFreqCount += 1
        }
        if s.pClusterFreqMHz != nil || s.eClusterFreqMHz != nil { freqValidCount += 1 }

        if s.phase == .loading, let v = s.cpuPower {
            loadPowerSum += v; loadPowerCount += 1
        }
    }

    /// Fold a batch of samples into the accumulator (used by tests / legacy paths).
    mutating func add(_ samples: [TelemetrySample]) {
        for s in samples { add(s) }
    }

    /// Build a full RunAnalysis from the accumulated state. Phase spans follow
    /// the configured test phases (same layout as RunAnalyzer).
    func makeAnalysis(config: TestConfiguration) -> RunAnalysis {
        let duration = (lastElapsed ?? 0) - (firstElapsed ?? 0)

        // Phase spans from config
        var offset: TimeInterval = 0
        let phases: [(TestPhase, TimeInterval)] = [
            (.baseline, config.idleDuration),
            (.loading, config.loadDuration),
            (.transition, config.transitionDuration),
            (.cooling, config.cooldownDuration),
        ]
        var spans: [RunAnalysis.PhaseSpan] = []
        var bsln: TimeInterval?, load: TimeInterval?, trans: TimeInterval?, cool: TimeInterval?
        for (phase, dur) in phases {
            guard dur > 0 else { continue }
            spans.append(RunAnalysis.PhaseSpan(phase: phase, start: offset, end: offset + dur))
            switch phase {
            case .baseline: bsln = dur
            case .loading: load = dur
            case .transition: trans = dur
            case .cooling: cool = dur
            default: break
            }
            offset += dur
        }

        let total = sampleCount
        return RunAnalysis(
            duration: duration,
            sampleCount: sampleCount,
            validSamples: validSampleCount,
            cpuPeakTemp: cpuPeakTemp,
            gpuPeakTemp: gpuPeakTemp,
            cpuAvgTemp: cpuAvgCount > 0 ? cpuAvgSum / Double(cpuAvgCount) : nil,
            gpuAvgTemp: gpuAvgCount > 0 ? gpuAvgSum / Double(gpuAvgCount) : nil,
            cpuPeakPower: cpuPeakPower,
            gpuPeakPower: gpuPeakPower,
            packagePeakPower: packagePeakPower,
            cpuAvgPower: cpuPowerCount > 0 ? cpuPowerSum / Double(cpuPowerCount) : nil,
            loadAvgPower: loadPowerCount > 0 ? loadPowerSum / Double(loadPowerCount) : nil,
            pCorePeakFreq: pCorePeakFreq,
            eCorePeakFreq: eCorePeakFreq,
            pCoreAvgFreq: pCoreFreqCount > 0 ? pCoreFreqSum / Double(pCoreFreqCount) : nil,
            eCoreAvgFreq: eCoreFreqCount > 0 ? eCoreFreqSum / Double(eCoreFreqCount) : nil,
            tempCoverage: total > 0 ? Double(tempValidCount) / Double(total) : 0,
            powerCoverage: total > 0 ? Double(powerValidCount) / Double(total) : 0,
            freqCoverage: total > 0 ? Double(freqValidCount) / Double(total) : 0,
            overallCoverage: total > 0 ? Double(validSampleCount) / Double(total) : 0,
            baselineDuration: bsln,
            loadDuration: load,
            transitionDuration: trans,
            cooldownDuration: cool,
            phaseSpans: spans
        )
    }
}
