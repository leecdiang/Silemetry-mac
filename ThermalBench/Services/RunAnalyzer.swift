// ThermalBench - Run Analyzer
// Operates on immutable snapshot, computes all metrics from samples
import Foundation

struct RunAnalysis {
    let duration: TimeInterval
    let sampleCount: Int
    let validSamples: Int

    // Temperature
    let cpuPeakTemp: Double?
    let gpuPeakTemp: Double?
    let cpuAvgTemp: Double?
    let gpuAvgTemp: Double?

    // Power
    let cpuPeakPower: Double?
    let gpuPeakPower: Double?
    let packagePeakPower: Double?
    let cpuAvgPower: Double?
    let loadAvgPower: Double?

    // Frequency
    let pCorePeakFreq: Double?
    let eCorePeakFreq: Double?
    let pCoreAvgFreq: Double?
    let eCoreAvgFreq: Double?

    // Coverage
    let tempCoverage: Double
    let powerCoverage: Double
    let freqCoverage: Double
    let overallCoverage: Double

    // Phase durations
    let baselineDuration: TimeInterval?
    let loadDuration: TimeInterval?
    let transitionDuration: TimeInterval?
    let cooldownDuration: TimeInterval?

    struct PhaseSpan {
        let phase: TestPhase
        let start: TimeInterval
        let end: TimeInterval
    }
    let phaseSpans: [PhaseSpan]
}

enum RunAnalyzer {
    static func analyze(samples: [TelemetrySample], config: TestConfiguration) -> RunAnalysis {
        let valid = samples.filter { $0.tempValid || $0.powerValid || $0.freqValid }

        // Duration
        let duration: TimeInterval
        if let first = valid.first?.elapsedSeconds, let last = valid.last?.elapsedSeconds {
            duration = last - first
        } else {
            duration = 0
        }

        // Temperature — per-channel availability (nil field = channel absent).
        // Peaks use hottest sensors; averages use average sensors.
        let cpuPeakTemps = samples.compactMap(\.cpuTempHottest)
        let cpuAvgTemps = samples.compactMap(\.cpuTemp)
        let gpuPeakTemps = samples.compactMap(\.gpuTempHottest)
        let gpuAvgTemps = samples.compactMap(\.gpuTemp)
        let cpuPeakTemp = cpuPeakTemps.max()
        let gpuPeakTemp = gpuPeakTemps.max()
        let cpuAvgTemp = cpuAvgTemps.isEmpty ? nil : cpuAvgTemps.reduce(0, +) / Double(cpuAvgTemps.count)
        let gpuAvgTemp = gpuAvgTemps.isEmpty ? nil : gpuAvgTemps.reduce(0, +) / Double(gpuAvgTemps.count)

        // Power — per-channel, never fabricate 0 for a missing channel.
        let cpuPowers = samples.compactMap(\.cpuPower)
        let gpuPowers = samples.compactMap(\.gpuPower)
        let pkgPowers = samples.compactMap(\.packagePower)
        let cpuPeakPower = cpuPowers.max()
        let gpuPeakPower = gpuPowers.max()
        let packagePeakPower = pkgPowers.max()
        let cpuAvgPower = cpuPowers.isEmpty ? nil : cpuPowers.reduce(0, +) / Double(cpuPowers.count)

        // Load-phase CPU power average
        let loadSamples = valid.filter { $0.phase == .loading }
        let loadPowers = loadSamples.compactMap { $0.cpuPower }
        let loadAvgPower = loadPowers.isEmpty ? nil : loadPowers.reduce(0, +) / Double(loadPowers.count)

        // Frequency — per-channel
        let pFreqs = samples.compactMap(\.pClusterFreqMHz)
        let eFreqs = samples.compactMap(\.eClusterFreqMHz)
        let pCorePeakFreq = pFreqs.max()
        let eCorePeakFreq = eFreqs.max()
        let pCoreAvgFreq = pFreqs.isEmpty ? nil : pFreqs.reduce(0, +) / Double(pFreqs.count)
        let eCoreAvgFreq = eFreqs.isEmpty ? nil : eFreqs.reduce(0, +) / Double(eFreqs.count)

        // Coverage
        let total = samples.count
        let tempCov = total > 0 ? Double(samples.filter { $0.tempValid }.count) / Double(total) : 0
        let powerCov = total > 0 ? Double(samples.filter { $0.powerValid }.count) / Double(total) : 0
        let freqCov = total > 0 ? Double(samples.filter { $0.freqValid }.count) / Double(total) : 0
        let overall = total > 0 ? Double(valid.count) / Double(total) : 0

        // Phase spans
        let totalDuration = config.idleDuration + config.loadDuration + config.transitionDuration + config.cooldownDuration
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

        return RunAnalysis(
            duration: duration,
            sampleCount: total,
            validSamples: valid.count,
            cpuPeakTemp: cpuPeakTemp,
            gpuPeakTemp: gpuPeakTemp,
            cpuAvgTemp: cpuAvgTemp,
            gpuAvgTemp: gpuAvgTemp,
            cpuPeakPower: cpuPeakPower,
            gpuPeakPower: gpuPeakPower,
            packagePeakPower: packagePeakPower,
            cpuAvgPower: cpuAvgPower,
            loadAvgPower: loadAvgPower,
            pCorePeakFreq: pCorePeakFreq,
            eCorePeakFreq: eCorePeakFreq,
            pCoreAvgFreq: pCoreAvgFreq,
            eCoreAvgFreq: eCoreAvgFreq,
            tempCoverage: tempCov,
            powerCoverage: powerCov,
            freqCoverage: freqCov,
            overallCoverage: overall,
            baselineDuration: bsln,
            loadDuration: load,
            transitionDuration: trans,
            cooldownDuration: cool,
            phaseSpans: spans
        )
    }
}
