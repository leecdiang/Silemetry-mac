// ThermalBench - Custom Test Configuration View
import SwiftUI

struct CustomTestConfigView: View {
    let onStart: (TestConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var config = TestConfiguration(mode: .custom,
                                                  workloadType: .combined,
                                                  idleDuration: 60,
                                                  loadDuration: 300,
                                                  cooldownDuration: 60)
    @State private var coreTarget: CoreTarget = .all
    @State private var customThreads: Int = 4
    @State private var gpuLevel: GPUIntensity = .sustained
    @State private var showAdvanced = false

    private let dev = DeviceProfile.current

    enum CoreTarget: String, CaseIterable, Identifiable {
        case all, pCores, eCores, custom
        var id: Self { self }
        var displayName: String {
            switch self {
            case .all:     "All Cores"
            case .pCores:  "P-Cores"
            case .eCores:  "E-Cores"
            case .custom:  "Custom"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Name ──
                Section {
                    TextField("Optional test name", text: $config.name)
                } header: { Text("Test Name") }

                // ── Durations ──
                Section {
                    durationRow("Baseline (idle)", value: $config.idleDuration, range: 0...600, step: 10)
                    durationRow(loadPhaseLabel, value: $config.loadDuration, range: 10...3600, step: 10)
                    durationRow("Cooldown", value: $config.cooldownDuration, range: 0...600, step: 10)
                } header: { Text("Durations") }
                  footer: { Text(totalTimeText).font(.caption).foregroundStyle(.secondary) }

                // ── Workload ──
                Section {
                    Picker("Stress Type", selection: $config.workloadType) {
                        ForEach(WorkloadType.allCases, id: \.rawValue) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    // CPU controls — only when CPU is engaged
                    if config.workloadType.usesCPU {
                        Picker("Core Target", selection: $coreTarget) {
                            ForEach(CoreTarget.allCases) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)

                        coreTargetDetail
                    }

                    // GPU controls — only when GPU is engaged
                    if config.workloadType.usesGPU {
                        Picker("GPU Level", selection: $gpuLevel) {
                            Text("Light").tag(GPUIntensity.light)
                            Text("Sustained").tag(GPUIntensity.sustained)
                        }
                        .pickerStyle(.segmented)

                        Text(gpuLevelHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: { Text("Workload") }

                // ── Advanced ──
                DisclosureGroup("Advanced Options", isExpanded: $showAdvanced) {
                    Picker("Sample Interval", selection: $config.sampleInterval) {
                        Text("0.5s").tag(0.5)
                        Text("1.0s").tag(1.0)
                        Text("2.0s").tag(2.0)
                        Text("5.0s").tag(5.0)
                    }

                    HStack {
                        Text("Ambient Temperature")
                        Spacer()
                        HStack(spacing: 4) {
                            Slider(value: $config.ambientTemperature, in: 15...40, step: 1)
                                .frame(width: 120)
                            Text("\(Int(config.ambientTemperature)) °C")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Custom Test")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Test") { submit() }
                        .bold()
                }
            }
        }
    }

    // MARK: - Duration Row

    private var loadPhaseLabel: String {
        switch config.workloadType {
        case .cpuOnly:  "CPU Load"
        case .gpuOnly:  "GPU Load"
        case .combined: "Stress Load"
        }
    }

    private func durationRow(_ label: String, value: Binding<TimeInterval>, range: ClosedRange<TimeInterval>, step: TimeInterval) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                Text(durationText(value.wrappedValue))
                    .monospacedDigit()
                    .frame(minWidth: 52, alignment: .trailing)
                Stepper("", value: value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }

    private func durationText(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    private var totalTimeText: String {
        let total = config.idleDuration + config.loadDuration + config.transitionDuration + config.cooldownDuration
        return "Total: \(durationText(total))"
    }

    // MARK: - Core Target Detail

    @ViewBuilder
    private var coreTargetDetail: some View {
        switch coreTarget {
        case .all:
            VStack(alignment: .leading, spacing: 2) {
                Text("All \(dev.cpuCoreCount) cores (auto‑detect)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("P: \(dev.performanceCoreCount) · E: \(dev.efficiencyCoreCount)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        case .pCores:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(dev.performanceCoreCount) P‑cores only")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Useful for observing P‑core thermal behaviour in isolation")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        case .eCores:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(dev.efficiencyCoreCount) E‑cores only")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Lower peak power, runs cooler")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        case .custom:
            Stepper("Threads: \(customThreads)", value: $customThreads, in: 1...dev.cpuCoreCount)
                .font(.caption)
                .padding(.vertical, 4)
        }
    }

    // MARK: - GPU Level Hint

    private var gpuLevelHint: String {
        switch gpuLevel {
        case .light:     "Moderate GPU compute, ≈30% utilisation"
        case .sustained: "Maximum sustained GPU compute, ≈100% utilisation"
        default:         ""
        }
    }

    // MARK: - Submit

    private func submit() {
        config.cpuThreads = resolveThreadCount()
        config.cpuCoreType = coreTargetToCpuCoreType(coreTarget)
        config.gpuIntensity = config.workloadType.usesGPU ? gpuLevel : .off
        config.transitionDuration = 5  // always 5s, not user-configurable
        onStart(config)
        dismiss()
    }

    private func coreTargetToCpuCoreType(_ t: CoreTarget) -> CpuCoreType {
        switch t {
        case .all:     return .all
        case .pCores:  return .pCores
        case .eCores:  return .eCores
        case .custom:  return .custom
        }
    }

    private func resolveThreadCount() -> Int {
        switch coreTarget {
        case .all:    return 0
        case .pCores: return dev.performanceCoreCount
        case .eCores: return dev.efficiencyCoreCount
        case .custom: return customThreads
        }
    }
}
