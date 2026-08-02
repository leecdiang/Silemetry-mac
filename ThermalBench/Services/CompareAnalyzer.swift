// ThermalBench - Compare Analyzer
// Three-tier comparability check for A/B run comparison.
import Foundation

// MARK: - Comparability Levels

enum ComparabilityLevel: String, Equatable, CaseIterable {
    case highlyComparable
    case comparableWithWarnings
    case invalid

    var displayName: String {
        switch self {
        case .highlyComparable:       "Highly Comparable"
        case .comparableWithWarnings: "Comparable with Warnings"
        case .invalid:                "Invalid Comparison"
        }
    }

    var icon: String {
        switch self {
        case .highlyComparable:       "checkmark.circle.fill"
        case .comparableWithWarnings: "exclamationmark.circle.fill"
        case .invalid:                "xmark.circle.fill"
        }
    }
}

// MARK: - Warning

struct ComparabilityWarning: Equatable, Identifiable {
    let id: String
    let field: String
    let severity: Severity
    let detail: String

    enum Severity: String {
        case info    // minor difference (sample count, coverage)
        case warning // notable difference (different device, workload)
        case error   // blocks comparison entirely
    }
}

// MARK: - Checked Fields

struct ComparabilityField: Equatable, Identifiable {
    let id: String
    let label: String
    let valueA: String
    let valueB: String
    let match: Bool
}

// MARK: - Result

struct ComparabilityResult: Equatable {
    let level: ComparabilityLevel
    let warnings: [ComparabilityWarning]
    let fields: [ComparabilityField]
    let canCompare: Bool
}

// MARK: - Analyzer

enum CompareAnalyzer {

    /// Current analysis version — bump when check logic changes.
    static let analysisVersion = 3

    static func analyze(a: RunRecord, b: RunRecord,
                        effectiveRawA: RawDataStatus? = nil,
                        effectiveRawB: RawDataStatus? = nil) -> ComparabilityResult {
        var warnings: [ComparabilityWarning] = []
        var fields: [ComparabilityField] = []

        // Raw archive integrity — prefer the runtime cross-checked status
        // (file on disk) when the caller has loaded it; otherwise fall back to
        // the stored value. Keeps the verdict and the curve banner consistent.
        let rawA = effectiveRawA ?? a.rawDataStatus
        let rawB = effectiveRawB ?? b.rawDataStatus

        // ── Hard blockers (invalid comparison) ────────────────────────────

        // Same run
        if a.uuid == b.uuid {
            warnings.append(ComparabilityWarning(
                id: "same_run", field: "Identity", severity: .error,
                detail: "Cannot compare a run against itself"
            ))
            return ComparabilityResult(level: .invalid, warnings: warnings, fields: fields, canCompare: false)
        }

        // No valid samples or duration
        if a.sampleCount == 0 || b.sampleCount == 0
           || a.duration <= 0 || b.duration <= 0
           || a.dataCoverage <= 0 || b.dataCoverage <= 0 {
            var invalidReasons: [String] = []
            if a.sampleCount == 0 || a.duration <= 0 { invalidReasons.append("Run A has no valid data") }
            if b.sampleCount == 0 || b.duration <= 0 { invalidReasons.append("Run B has no valid data") }
            if a.dataCoverage <= 0 { invalidReasons.append("Run A coverage is zero") }
            if b.dataCoverage <= 0 { invalidReasons.append("Run B coverage is zero") }
            warnings.append(ComparabilityWarning(
                id: "no_data", field: "Data", severity: .error,
                detail: invalidReasons.joined(separator: "; ")
            ))
            return ComparabilityResult(level: .invalid, warnings: warnings, fields: fields, canCompare: false)
        }

        // Interrupted runs — warn heavily
        if a.wasInterrupted || b.wasInterrupted {
            let which = [a.wasInterrupted ? "A" : nil, b.wasInterrupted ? "B" : nil].compactMap { $0 }.joined(separator: ", ")
            warnings.append(ComparabilityWarning(
                id: "interrupted", field: "Completion", severity: .warning,
                detail: "Run \(which) was interrupted — results may be incomplete"
            ))
        }

        // ── Device identity ──────────────────────────────────────────────

        fields.append(checkField(id: "device", label: "Device",
                                 a: a.deviceModelIdentifier, b: b.deviceModelIdentifier,
                                 aLegacy: a.deviceModel, bLegacy: b.deviceModel,
                                 warnings: &warnings))

        fields.append(checkField(id: "chip", label: "Chip",
                                 a: a.chipName, b: b.chipName,
                                 aLegacy: nil, bLegacy: nil,
                                 warnings: &warnings))

        // ── Workload configuration ──────────────────────────────────────

        fields.append(checkField(id: "mode", label: "Test Mode",
                                 a: a.testModeRaw, b: b.testModeRaw,
                                 aLegacy: nil, bLegacy: nil,
                                 warnings: &warnings))

        // ── Configuration snapshot (empty/zero = legacy run) ───────────

        // Workload type — trust the recorded snapshot only. Legacy runs
        // without the field show "unverified" rather than a power-based guess
        // (CPU idle power is > 0 even during GPU-only tests, so peak-power
        // inference is unreliable).
        fields.append(checkWorkloadField(a: a.workloadTypeRaw, b: b.workloadTypeRaw,
                                         warnings: &warnings))

        fields.append(checkField(id: "cpuCores", label: "CPU Core Target",
                                 a: a.cpuCoreTypeRaw, b: b.cpuCoreTypeRaw,
                                 aLegacy: nil, bLegacy: nil,
                                 warnings: &warnings))

        fields.append(checkField(id: "gpuIntensity", label: "GPU Intensity",
                                 a: a.gpuIntensityRaw, b: b.gpuIntensityRaw,
                                 aLegacy: nil, bLegacy: nil,
                                 warnings: &warnings))

        fields.append(checkNumericField(id: "threads", label: "CPU Threads",
                                        a: Double(a.cpuThreadCount), b: Double(b.cpuThreadCount),
                                        tolerance: 0, severity: .warning,
                                        zeroIsLegacy: false,
                                        warnings: &warnings))

        fields.append(checkNumericField(id: "loadDuration", label: "Load Duration",
                                        a: a.loadDuration, b: b.loadDuration,
                                        tolerance: 0.10, severity: .warning,
                                        warnings: &warnings))

        fields.append(checkNumericField(id: "sampleInterval", label: "Sample Interval",
                                        a: a.sampleInterval, b: b.sampleInterval,
                                        tolerance: 0.05, severity: .warning,
                                        warnings: &warnings))

        fields.append(checkPowerSource(a: a, b: b, warnings: &warnings))

        // ── Extended environment / provenance ───────────────────────────

        fields.append(checkLowPowerMode(a: a, b: b, warnings: &warnings))

        // Ambient temperature — nil = not recorded (never a fake 25°C)
        if let ta = a.ambientTemperature, let tb = b.ambientTemperature {
            // Absolute tolerance: > 2.0°C difference is material for thermals.
            let diff = abs(ta - tb)
            let match = diff <= 2.0
            fields.append(ComparabilityField(id: "ambient", label: "Ambient Temp",
                                             valueA: String(format: "%.1f°C", ta),
                                             valueB: String(format: "%.1f°C", tb),
                                             match: match))
            if !match {
                warnings.append(ComparabilityWarning(
                    id: "ambient_diff", field: "Ambient Temp", severity: .warning,
                    detail: String(format: "Ambient temperature differs by %.1f°C (A: %.1f°C, B: %.1f°C) — thermal results may not be comparable", diff, ta, tb)
                ))
            }
        } else if a.ambientTemperature == nil && b.ambientTemperature == nil {
            // Unknown on both sides must not silently pass as "matching".
            warnings.append(ComparabilityWarning(
                id: "ambient_unverified", field: "Ambient Temp", severity: .warning,
                detail: "Ambient temperature not recorded for either run — environmental comparability unverified"
            ))
            fields.append(ComparabilityField(id: "ambient", label: "Ambient Temp",
                                             valueA: "Not recorded", valueB: "Not recorded", match: false))
        } else {
            let fa = a.ambientTemperature.map { String(format: "%.1f°C", $0) } ?? "Not recorded"
            let fb = b.ambientTemperature.map { String(format: "%.1f°C", $0) } ?? "Not recorded"
            warnings.append(ComparabilityWarning(
                id: "ambient_unknown", field: "Ambient Temp", severity: .warning,
                detail: "Ambient recorded for one run only (A: \(fa), B: \(fb)) — environmental comparability unverified"
            ))
            fields.append(ComparabilityField(id: "ambient", label: "Ambient Temp", valueA: fa, valueB: fb, match: false))
        }

        fields.append(checkNumericField(id: "analysisVer", label: "Analysis Version",
                                        a: Double(a.analysisVersion), b: Double(b.analysisVersion),
                                        tolerance: 0, severity: .warning,
                                        warnings: &warnings))

        fields.append(checkNumericField(id: "baseline", label: "Baseline Duration",
                                        a: a.baselineDuration, b: b.baselineDuration,
                                        tolerance: 0.10, severity: .warning,
                                        warnings: &warnings))

        fields.append(checkNumericField(id: "cooldown", label: "Cooldown Duration",
                                        a: a.cooldownDuration, b: b.cooldownDuration,
                                        tolerance: 0.10, severity: .warning,
                                        warnings: &warnings))

        fields.append(checkField(id: "telemetryVer", label: "Telemetry Core",
                                 a: a.telemetryCoreVersion, b: b.telemetryCoreVersion,
                                 aLegacy: nil, bLegacy: nil,
                                 warnings: &warnings))

        // ── Raw archive integrity (Summary vs raw curve consistency) ────

        let rawMatch = rawA == .complete && rawB == .complete
        fields.append(ComparabilityField(id: "rawData", label: "Raw Data",
                                         valueA: rawA.displayName,
                                         valueB: rawB.displayName,
                                         match: rawMatch))
        if rawA != .complete {
            warnings.append(ComparabilityWarning(
                id: rawA == .partial ? "raw_partial_a" : "raw_unavailable_a",
                field: "Raw Data", severity: .warning,
                detail: "Run A raw data is \(rawA.displayName.lowercased()) — its curve may be incomplete or absent (Summary remains valid)"
            ))
        }
        if rawB != .complete {
            warnings.append(ComparabilityWarning(
                id: rawB == .partial ? "raw_partial_b" : "raw_unavailable_b",
                field: "Raw Data", severity: .warning,
                detail: "Run B raw data is \(rawB.displayName.lowercased()) — its curve may be incomplete or absent (Summary remains valid)"
            ))
        }

        // ── Duration and sampling ────────────────────────────────────────

        let durDiff = abs(a.duration - b.duration) / max(max(a.duration, b.duration), 1)
        let durMatch = durDiff < 0.3  // within 30%
        fields.append(ComparabilityField(
            id: "duration", label: "Duration",
            valueA: formatDuration(a.duration),
            valueB: formatDuration(b.duration),
            match: durMatch
        ))
        if !durMatch {
            warnings.append(ComparabilityWarning(
                id: "duration_diff", field: "Duration", severity: .warning,
                detail: "Test durations differ by more than 30% (A: \(formatDuration(a.duration)), B: \(formatDuration(b.duration)))"
            ))
        }

        // ── Sample counts ────────────────────────────────────────────────

        let scA = a.sampleCount, scB = b.sampleCount
        let scDiff = Double(abs(scA - scB)) / Double(max(max(scA, scB), 1))
        let scMatch = scDiff < 0.5
        fields.append(ComparabilityField(
            id: "samples", label: "Samples",
            valueA: "\(scA)", valueB: "\(scB)",
            match: scMatch
        ))
        if !scMatch {
            warnings.append(ComparabilityWarning(
                id: "sample_diff", field: "Samples", severity: .info,
                detail: "Sample counts differ significantly (A: \(scA), B: \(scB))"
            ))
        }

        // ── Coverage ─────────────────────────────────────────────────────

        let covA = a.dataCoverage, covB = b.dataCoverage
        let covDiff = abs(covA - covB)
        let covMatch = covDiff < 0.2
        fields.append(ComparabilityField(
            id: "coverage", label: "Coverage",
            valueA: String(format: "%.0f%%", covA * 100),
            valueB: String(format: "%.0f%%", covB * 100),
            match: covMatch
        ))
        if !covMatch {
            warnings.append(ComparabilityWarning(
                id: "coverage_diff", field: "Coverage", severity: .info,
                detail: "Coverage differs by more than 20 percentage points"
            ))
        }

        // ── App version ──────────────────────────────────────────────────

        fields.append(checkField(id: "appVersion", label: "App Version",
                                 a: a.appVersion, b: b.appVersion,
                                 aLegacy: nil, bLegacy: nil,
                                 warnings: &warnings))

        // ── macOS version ─────────────────────────────────────────────────

        fields.append(checkField(id: "macOS", label: "macOS",
                                 a: a.macOSVersion, b: b.macOSVersion,
                                 aLegacy: nil, bLegacy: nil,
                                 warnings: &warnings))

        // ── Determine final level ────────────────────────────────────────

        let hasError = warnings.contains { $0.severity == .error }
        let hasWarning = warnings.contains { $0.severity == .warning }

        let level: ComparabilityLevel
        if hasError {
            level = .invalid
        } else if hasWarning {
            level = .comparableWithWarnings
        } else {
            level = .highlyComparable
        }

        return ComparabilityResult(
            level: level,
            warnings: warnings,
            fields: fields,
            canCompare: level != .invalid
        )
    }

    // MARK: - Helpers

    /// Power source comparison with mid-run change detection. Uses the
    /// start/end snapshots when available (a run that switched AC↔battery is
    /// "changed", not silently uniform); falls back to the legacy single
    /// snapshot for old records.
    private static func checkPowerSource(a: RunRecord, b: RunRecord,
                                         warnings: inout [ComparabilityWarning]) -> ComparabilityField {
        if a.powerSourceChanged {
            warnings.append(ComparabilityWarning(
                id: "power_changed_a", field: "Power Source", severity: .warning,
                detail: "Run A power source changed during the test (AC ↔ battery) — results mix both conditions"
            ))
        }
        if b.powerSourceChanged {
            warnings.append(ComparabilityWarning(
                id: "power_changed_b", field: "Power Source", severity: .warning,
                detail: "Run B power source changed during the test (AC ↔ battery) — results mix both conditions"
            ))
        }
        let aVal = a.powerSourceAtEnd ?? a.powerSourceAtStart ?? a.acConnected
        let bVal = b.powerSourceAtEnd ?? b.powerSourceAtStart ?? b.acConnected
        return checkPowerSource(a: aVal, b: bVal,
                                aBattery: a.batteryPercent, bBattery: b.batteryPercent,
                                warnings: &warnings)
    }

    /// Low Power Mode comparison with mid-run change detection.
    private static func checkLowPowerMode(a: RunRecord, b: RunRecord,
                                          warnings: inout [ComparabilityWarning]) -> ComparabilityField {
        if a.lowPowerModeChanged {
            warnings.append(ComparabilityWarning(
                id: "powerMode_changed_a", field: "Low Power Mode", severity: .warning,
                detail: "Run A low power mode changed during the test — results mix both conditions"
            ))
        }
        if b.lowPowerModeChanged {
            warnings.append(ComparabilityWarning(
                id: "powerMode_changed_b", field: "Low Power Mode", severity: .warning,
                detail: "Run B low power mode changed during the test — results mix both conditions"
            ))
        }
        let aVal = a.lowPowerModeAtEnd ?? a.lowPowerModeAtStart ?? a.lowPowerMode
        let bVal = b.lowPowerModeAtEnd ?? b.lowPowerModeAtStart ?? b.lowPowerMode
        return checkOptionalBoolField(id: "powerMode", label: "Low Power Mode",
                                      a: aVal, b: bVal, warnings: &warnings)
    }

    /// Workload-type comparison. The recorded workloadTypeRaw snapshot is the
    /// only trusted source — legacy runs without it are "unverified", never
    /// guessed from power metrics (idle CPU power is nonzero even in
    /// GPU-only tests).
    private static func checkWorkloadField(
        a: String, b: String,
        warnings: inout [ComparabilityWarning]
    ) -> ComparabilityField {
        let legacyA = a.isEmpty
        let legacyB = b.isEmpty

        if legacyA && legacyB {
            warnings.append(ComparabilityWarning(
                id: "workload_both_legacy", field: "Workload Type", severity: .warning,
                detail: "Workload type unverified for both runs — CPU/GPU load assumptions unchecked"
            ))
            return ComparabilityField(id: "workload", label: "Workload Type",
                                      valueA: "Workload type unverified",
                                      valueB: "Workload type unverified",
                                      match: false)
        }
        if legacyA {
            warnings.append(ComparabilityWarning(
                id: "workload_legacy_a", field: "Workload Type", severity: .info,
                detail: "Run A: workload type unverified"
            ))
            return ComparabilityField(id: "workload", label: "Workload Type",
                                      valueA: "Workload type unverified", valueB: b, match: false)
        }
        if legacyB {
            warnings.append(ComparabilityWarning(
                id: "workload_legacy_b", field: "Workload Type", severity: .info,
                detail: "Run B: workload type unverified"
            ))
            return ComparabilityField(id: "workload", label: "Workload Type",
                                      valueA: a, valueB: "Workload type unverified", match: false)
        }

        let same = a == b
        if !same {
            warnings.append(ComparabilityWarning(
                id: "workload_diff", field: "Workload Type", severity: .warning,
                detail: "Different workload type — A: \(a), B: \(b)"
            ))
        }
        return ComparabilityField(id: "workload", label: "Workload Type", valueA: a, valueB: b, match: same)
    }

    private static func isLegacy(_ v: String) -> Bool {
        v.isEmpty
    }

    private static func checkField(
        id: String, label: String,
        a: String, b: String,
        aLegacy: String?, bLegacy: String?,
        warnings: inout [ComparabilityWarning]
    ) -> ComparabilityField {
        let legacyA = isLegacy(a) && aLegacy.map(isLegacy) ?? true
        let legacyB = isLegacy(b) && bLegacy.map(isLegacy) ?? true

        if legacyA && legacyB {
            // Both runs lack the metadata — unverifiable, not a match.
            warnings.append(ComparabilityWarning(
                id: "\(id)_both_legacy", field: label, severity: .warning,
                detail: "Both runs lack \(label.lowercased()) metadata — match unverifiable"
            ))
            return ComparabilityField(
                id: id, label: label,
                valueA: "Legacy metadata unavailable",
                valueB: "Legacy metadata unavailable",
                match: false
            )
        }
        if legacyA {
            warnings.append(ComparabilityWarning(
                id: "\(id)_legacy_a", field: label, severity: .info,
                detail: "Run A: legacy metadata unavailable"
            ))
            return ComparabilityField(
                id: id, label: label,
                valueA: "Legacy metadata unavailable",
                valueB: b,
                match: false
            )
        }
        if legacyB {
            warnings.append(ComparabilityWarning(
                id: "\(id)_legacy_b", field: label, severity: .info,
                detail: "Run B: legacy metadata unavailable"
            ))
            return ComparabilityField(
                id: id, label: label,
                valueA: a,
                valueB: "Legacy metadata unavailable",
                match: false
            )
        }

        let same = a == b
        if !same {
            warnings.append(ComparabilityWarning(
                id: "\(id)_diff", field: label, severity: .warning,
                detail: "Different \(label.lowercased()) — A: \(a), B: \(b)"
            ))
        }
        return ComparabilityField(id: id, label: label, valueA: a, valueB: b, match: same)
    }

    private static func formatDuration(_ d: TimeInterval) -> String {
        let m = Int(d) / 60
        let s = Int(d) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    /// Numeric field comparison. Zero on both sides = legacy/unknown, except
    /// when zeroIsLegacy is false (e.g. threadCount where 0 means "all cores").
    private static func checkNumericField(
        id: String, label: String,
        a: Double, b: Double,
        tolerance: Double,          // 0 = exact match
        severity: ComparabilityWarning.Severity,
        zeroIsLegacy: Bool = true,
        warnings: inout [ComparabilityWarning]
    ) -> ComparabilityField {
        let legacyA = a == 0
        let legacyB = b == 0

        // 0 carries real meaning (all cores) — compare directly.
        if !zeroIsLegacy {
            let fmt: (Double) -> String = { $0 == 0 ? "All Cores" : formatNumber($0) }
            let match = a == b
            if !match {
                warnings.append(ComparabilityWarning(
                    id: "\(id)_diff", field: label, severity: severity,
                    detail: "Different \(label.lowercased()) — A: \(fmt(a)), B: \(fmt(b))"
                ))
            }
            return ComparabilityField(id: id, label: label, valueA: fmt(a), valueB: fmt(b), match: match)
        }

        if legacyA && legacyB {
            // Both runs lack the metadata — unverifiable, not a match.
            warnings.append(ComparabilityWarning(
                id: "\(id)_both_legacy", field: label, severity: .warning,
                detail: "Both runs lack \(label.lowercased()) metadata — match unverifiable"
            ))
            return ComparabilityField(
                id: id, label: label,
                valueA: "Legacy metadata unavailable",
                valueB: "Legacy metadata unavailable",
                match: false
            )
        }
        if legacyA {
            warnings.append(ComparabilityWarning(
                id: "\(id)_legacy_a", field: label, severity: .info,
                detail: "Run A: legacy metadata unavailable"
            ))
            return ComparabilityField(
                id: id, label: label,
                valueA: "Legacy metadata unavailable", valueB: formatNumber(b), match: false
            )
        }
        if legacyB {
            warnings.append(ComparabilityWarning(
                id: "\(id)_legacy_b", field: label, severity: .info,
                detail: "Run B: legacy metadata unavailable"
            ))
            return ComparabilityField(
                id: id, label: label,
                valueA: formatNumber(a), valueB: "Legacy metadata unavailable", match: false
            )
        }

        let diff = abs(a - b) / max(max(a, b), 1)
        let match = tolerance <= 0 ? a == b : diff <= tolerance
        if !match {
            warnings.append(ComparabilityWarning(
                id: "\(id)_diff", field: label, severity: severity,
                detail: "Different \(label.lowercased()) — A: \(formatNumber(a)), B: \(formatNumber(b))"
            ))
        }
        return ComparabilityField(id: id, label: label, valueA: formatNumber(a), valueB: formatNumber(b), match: match)
    }

    /// Power source comparison. nil on either side = unknown/legacy.
    private static func checkPowerSource(
        a: Bool?, b: Bool?,
        aBattery: Int?, bBattery: Int?,
        warnings: inout [ComparabilityWarning]
    ) -> ComparabilityField {
        let labelA = powerLabel(ac: a, battery: aBattery)
        let labelB = powerLabel(ac: b, battery: bBattery)

        if let a, let b {
            let match = a == b
            if !match {
                warnings.append(ComparabilityWarning(
                    id: "power_diff", field: "Power Source", severity: .warning,
                    detail: "Power source differs — AC vs battery materially affects thermals and power"
                ))
            }
            return ComparabilityField(id: "power", label: "Power Source", valueA: labelA, valueB: labelB, match: match)
        }

        // Unknown on at least one side
        if a == nil && b == nil {
            warnings.append(ComparabilityWarning(
                id: "power_unknown", field: "Power Source", severity: .warning,
                detail: "Power source unknown for both runs — AC/battery state unverified"
            ))
            return ComparabilityField(id: "power", label: "Power Source", valueA: "Unknown", valueB: "Unknown", match: false)
        }
        if a == nil {
            warnings.append(ComparabilityWarning(
                id: "power_legacy_a", field: "Power Source", severity: .info,
                detail: "Run A: power source unknown"
            ))
        }
        if b == nil {
            warnings.append(ComparabilityWarning(
                id: "power_legacy_b", field: "Power Source", severity: .info,
                detail: "Run B: power source unknown"
            ))
        }
        return ComparabilityField(id: "power", label: "Power Source", valueA: labelA, valueB: labelB, match: false)
    }

    /// Optional Bool comparison (nil = unknown on either side).
    private static func checkOptionalBoolField(
        id: String, label: String,
        a: Bool?, b: Bool?,
        warnings: inout [ComparabilityWarning]
    ) -> ComparabilityField {
        let fmt: (Bool?) -> String = { $0.map { $0 ? "ON" : "OFF" } ?? "Unknown" }

        if let a, let b {
            let match = a == b
            if !match {
                warnings.append(ComparabilityWarning(
                    id: "\(id)_diff", field: label, severity: .warning,
                    detail: "Different \(label.lowercased()) — A: \(fmt(a)), B: \(fmt(b))"
                ))
            }
            return ComparabilityField(id: id, label: label, valueA: fmt(a), valueB: fmt(b), match: match)
        }

        if a == nil && b == nil {
            warnings.append(ComparabilityWarning(
                id: "\(id)_unknown", field: label, severity: .warning,
                detail: "\(label) unknown for both runs — condition unverified"
            ))
            return ComparabilityField(id: id, label: label, valueA: "Unknown", valueB: "Unknown", match: false)
        }
        if a == nil {
            warnings.append(ComparabilityWarning(
                id: "\(id)_legacy_a", field: label, severity: .info,
                detail: "Run A: \(label.lowercased()) unknown"
            ))
        }
        if b == nil {
            warnings.append(ComparabilityWarning(
                id: "\(id)_legacy_b", field: label, severity: .info,
                detail: "Run B: \(label.lowercased()) unknown"
            ))
        }
        return ComparabilityField(id: id, label: label, valueA: fmt(a), valueB: fmt(b), match: false)
    }

    private static func powerLabel(ac: Bool?, battery: Int?) -> String {
        guard let ac else { return "Unknown" }
        if ac {
            return battery.map { "AC \u{00B7} \($0)%" } ?? "AC Power"
        }
        return battery.map { "Battery \u{00B7} \($0)%" } ?? "Battery"
    }

    private static func formatNumber(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1_000_000 {
            return String(Int(v))
        }
        return String(format: "%.2f", v)
    }
}
