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

        // Temperature — peaks use hottest, averages use cpuTemp/gpuTemp
        let validTemps = samples.compactMap { s -> (hottest: Double, cpu: Double, gpuHottest: Double?, gpu: Double?)? in
            guard s.tempValid, let hottest = s.cpuTempHottest, let cpu = s.cpuTemp else { return nil }
            return (hottest, cpu, s.gpuTempHottest, s.gpuTemp)
        }
        let cpuPeakTemp = validTemps.map(\.hottest).max()
        let gpuPeakTemp = validTemps.compactMap(\.gpuHottest).max()
        let cpuAvgTemp = validTemps.isEmpty ? nil : validTemps.map(\.cpu).reduce(0, +) / Double(validTemps.count)
        let gpuAvgTemp = validTemps.compactMap(\.gpu).isEmpty ? nil :
            validTemps.compactMap(\.gpu).reduce(0, +) / Double(validTemps.compactMap(\.gpu).count)

        // Power
        let validPower = samples.compactMap { s -> (cpu: Double, gpu: Double, pkg: Double?)? in
            guard s.powerValid, let cpu = s.cpuPower else { return nil }
            return (cpu, s.gpuPower ?? 0, s.packagePower)
        }
        let cpuPeakPower = validPower.map(\.cpu).max()
        let gpuPeakPower = validPower.map(\.gpu).max()
        let packagePeakPower = validPower.compactMap(\.pkg).max()
        let cpuAvgPower = validPower.isEmpty ? nil : validPower.map(\.cpu).reduce(0, +) / Double(validPower.count)

        // Load-phase power average
        let loadSamples = valid.filter { $0.phase == .loading }
        let loadPowers = loadSamples.compactMap { $0.cpuPower }
        let loadAvgPower = loadPowers.isEmpty ? nil : loadPowers.reduce(0, +) / Double(loadPowers.count)

        // Frequency
        let validFreq = samples.compactMap { s -> (p: Double, e: Double?)? in
            guard s.freqValid, let p = s.pClusterFreqMHz else { return nil }
            return (p, s.eClusterFreqMHz)
        }
        let pCorePeakFreq = validFreq.map(\.p).max()
        let eCorePeakFreq = validFreq.compactMap(\.e).max()
        let pCoreAvgFreq = validFreq.isEmpty ? nil : validFreq.map(\.p).reduce(0, +) / Double(validFreq.count)
        let eCoreAvgFreq = validFreq.compactMap(\.e).isEmpty ? nil :
            validFreq.compactMap(\.e).reduce(0, +) / Double(validFreq.compactMap(\.e).count)

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
