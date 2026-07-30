// ThermalBench - Live Test View
import SwiftUI
import Charts
import SwiftData

struct TestView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @State private var showStopConfirm = false
    @State private var selectedTab: TestTab = .overview
    @State private var showCancelConfirm = false

    enum TestTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case cores = "Cores"
        var id: Self { self }
    }

    enum CoreKind { case efficiency, performance }

    var coord: TestCoordinator { app.coordinator }
    var samples: [TelemetrySample] { coord.samples }
    var phase: TestPhase? {
        if case .running(let p, _, _) = coord.state { return p }
        return nil
    }
    var elapsed: TimeInterval {
        if case .running(_, let e, _) = coord.state { return e }
        return 0
    }
    var remaining: TimeInterval {
        if case .running(_, _, let r) = coord.state { return r }
        return 0
    }

    var body: some View {
        let _ = {
            #if DEBUG
            if !samples.isEmpty && samples.count <= 3 {
                print("[TESTVIEW] body render: samples=\(samples.count) latestTemp=\(coord.latest?.cpuTemp?.description ?? "nil") latestPower=\(coord.latest?.cpuPower?.description ?? "nil") phase=\(phase?.rawValue ?? "nil")")
            }
            #endif
        }()
        return VStack(spacing: 0) {
            // Status bar
            statusBar
            Divider()
            // Tab switcher
            Picker("View", selection: $selectedTab) {
                ForEach(TestTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            // Content
            if selectedTab == .overview {
                overviewContent
            } else {
                coreActivityContent
            }
            // Bottom bar
            bottomBar
        }
        .navigationTitle("Active Test")
        .onChange(of: coord.state) { _, newState in
            if case .complete(let run) = newState {
                // Only save if there are valid samples
                guard run.sampleCount > 0, run.duration > 0 else {
                    app.route = .home
                    return
                }
                modelContext.insert(run)
                do { try modelContext.save() } catch {
                    print("[PERSIST] save error: \(error)")
                }
                app.route = .result(run.uuid)
            }
            if case .cancelled = newState {
                // Only save cancellations with data
                guard !coord.samples.isEmpty else {
                    app.route = .home
                    app.resetForNewRun()
                    return
                }
                let run = RunRecord(config: coord.testConfig)
                run.wasInterrupted = true
                run.sampleCount = coord.samples.count
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
                modelContext.insert(run)
                try? modelContext.save()
            }
        }
    }

    // MARK: - Status Bar

    var statusBar: some View {
        HStack(spacing: 16) {
            phaseBadge
            phaseProgress
            Divider().frame(height: 28)
            metricItem("CPU Hottest", value: tempStr(coord.latest?.cpuTempHottest))
            metricItem("CPU Avg", value: tempStr(coord.latest?.cpuTemp))
            metricItem("GPU Hottest", value: tempStr(coord.latest?.gpuTempHottest))
            metricItem("Power", value: powerStr(coord.latest?.cpuPower))
            metricItem("P-Core", value: freqStr(coord.latest?.pClusterFreqMHz))
            metricItem("Thermal", value: thermalStr(coord.latest?.thermalState))
            Spacer()
            if case .onBattery = app.powerSource {
                BatteryStatusIcon(source: app.powerSource, lowPowerMode: app.lowPowerMode)
            }
            Text(coord.isMonitorOnly ? timeStr(elapsed) : timeStr(remaining)).monospacedDigit().font(.subheadline)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
    }

    var phaseBadge: some View {
        StatusPill(phase: phase, isMonitorOnly: coord.isMonitorOnly)
    }

    var phaseProgress: some View {
        if coord.isMonitorOnly {
            return AnyView(ProgressView().frame(width: 120))
        } else {
            return AnyView(ProgressView(value: min(elapsed / max(totalDuration, 1), 1))
                .frame(width: 120))
        }
    }

    var totalDuration: TimeInterval {
        if coord.isMonitorOnly { return 0 }
        let c = coord.testConfig
        return c.idleDuration + c.loadDuration + c.transitionDuration + c.cooldownDuration
    }

    // MARK: - Charts

    func chartCard(_ title: String, empty: Bool, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            if empty {
                Text("Waiting for data…").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                content().frame(minHeight: 140)
            }
        }
        .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 0.5))
    }

    var tempChart: some View {
        Chart(samples) { s in
            if let t = s.cpuTempHottest {
                LineMark(x: .value("s", s.elapsedSeconds), y: .value("CPU Hottest", t), series: .value("Series", "CPU Hottest"))
                    .foregroundStyle(.red)
            }
            if let t = s.cpuTemp {
                LineMark(x: .value("s", s.elapsedSeconds), y: .value("CPU Avg", t), series: .value("Series", "CPU Avg"))
                    .foregroundStyle(.orange.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            if let t = s.gpuTempHottest {
                LineMark(x: .value("s", s.elapsedSeconds), y: .value("GPU Hottest", t), series: .value("Series", "GPU Hottest"))
                    .foregroundStyle(.purple)
            }
        }
        .chartXAxisLabel("s").chartYAxisLabel("°C")
        .chartForegroundStyleScale(["CPU Hottest": .red, "CPU Avg": .orange, "GPU Hottest": .purple])
    }

    var powerChart: some View {
        Chart(samples) { s in
            if let p = s.cpuPower {
                LineMark(x: .value("s", s.elapsedSeconds), y: .value("CPU", p), series: .value("Series", "CPU"))
                    .foregroundStyle(.blue)
            }
            if let p = s.gpuPower {
                LineMark(x: .value("s", s.elapsedSeconds), y: .value("GPU", p), series: .value("Series", "GPU"))
                    .foregroundStyle(.purple)
            }
            if let p = s.packagePower {
                LineMark(x: .value("s", s.elapsedSeconds), y: .value("Package", p), series: .value("Series", "Package"))
                    .foregroundStyle(.green)
            }
        }
        .chartXAxisLabel("s").chartYAxisLabel("W")
        .chartForegroundStyleScale(["CPU": .blue, "GPU": .purple, "Package": .green])
    }

    var freqChart: some View {
        Chart(samples) { s in
            if let f = s.pClusterFreqMHz {
                LineMark(x: .value("s", s.elapsedSeconds), y: .value("P-Core", f / 1000), series: .value("Series", "P-Core"))
                    .foregroundStyle(.green)
            }
            if let f = s.eClusterFreqMHz {
                LineMark(x: .value("s", s.elapsedSeconds), y: .value("E-Core", f / 1000), series: .value("Series", "E-Core"))
                    .foregroundStyle(.teal)
            }
        }
        .chartXAxisLabel("s").chartYAxisLabel("GHz")
        .chartForegroundStyleScale(["P-Core": .green, "E-Core": .teal])
    }

    var thermalChart: some View {
        Chart(samples) { s in
            let yv = thermalY(s.thermalState)
            if yv >= 0 {
                LineMark(x: .value("s", s.elapsedSeconds), y: .value("State", yv), series: .value("Series", "Thermal"))
                    .foregroundStyle(thermalColorForTag(s.thermalState))
                    .interpolationMethod(.stepStart)
            }
        }
        .chartXAxisLabel("s")
        .chartYAxis {
            AxisMarks(values: [0, 1, 2, 3]) { v in
                AxisValueLabel(["Critical", "Serious", "Fair", "Nominal"][max(0, min(3, v.index))])
            }
        }
    }

    // MARK: - Bottom Bar

    var bottomBar: some View {
        HStack {
            if coord.isMonitorOnly {
                Button {
                    coord.finishRecording()
                } label: {
                    Label("Finish Recording", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Button(role: .destructive) {
                    showCancelConfirm = true
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            } else {
                Button(role: .destructive) {
                    showStopConfirm = true
                } label: {
                    Label("Stop Test", systemImage: "stop.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(samples.count) samples").font(.caption).foregroundStyle(.secondary)
                if coord.isMonitorOnly {
                    ViewThatFits {
                        Text("External Workload").font(.caption2).foregroundStyle(.tertiary)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        Text("Ext").font(.caption2).foregroundStyle(.tertiary)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .alert("Stop Test?", isPresented: $showStopConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Stop", role: .destructive) { stopTest() }
        } message: {
            Text("Workload will stop. Current data will be saved.")
        }
        .alert("Cancel Recording?", isPresented: $showCancelConfirm) {
            Button("Keep Recording", role: .cancel) {}
            Button("Discard", role: .destructive) { stopTest() }
        } message: {
            Text("Data will not be saved.")
        }
    }

    // MARK: - Helpers

    // MARK: - Overview Content

    var overviewContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                chartCard("Temperature (°C)", empty: !hasValidTemp) { tempChart }
                chartCard("Power (W)", empty: !hasValidPower) { powerChart }
                chartCard("Frequency (GHz)", empty: !hasValidFreq) { freqChart }
                // Thermal as compact card instead of full chart
                GroupBox {
                    thermalCompactCard
                } label: {
                    Label("Thermal State", systemImage: "thermometer")
                }
                .frame(minHeight: 100)
            }
            .padding(16)
        }
    }

    var thermalCompactCard: some View {
        HStack(spacing: 12) {
            // State badge
            if let state = coord.latest?.thermalState {
                Circle().fill(thermalColorForTag(state)).frame(width: 12, height: 12)
                Text(stateLabel(state)).font(.subheadline).bold()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text("Current").font(.caption).foregroundStyle(.secondary)

            Divider().frame(height: 24)

            // Worst so far
            let worst = samples.compactMap(\.thermalState).min { thermalY($0) < thermalY($1) }
            if let w = worst {
                Circle().fill(thermalColorForTag(w)).frame(width: 8, height: 8)
                Text("Worst: \(stateLabel(w))").font(.caption).foregroundStyle(.secondary)
            }

            Divider().frame(height: 24)

            // Time non-Nominal
            if let nonNom = samples.last(where: { $0.thermalState != .nominal }) {
                Text("Non-Nominal at \(String(format: "%.0fs", nonNom.elapsedSeconds))").font(.caption).foregroundStyle(.orange)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    Text("Nominal throughout").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Core Activity Content

    var coreActivityContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Core utilization bars
                let cores = latestSampleCores
                if cores.isEmpty {
                    Text("Waiting for first per-core sample...")
                        .foregroundStyle(.secondary).padding()
                } else {
                    GroupBox("Per-Core Utilization") {
                        LazyVStack(spacing: 6) {
                            Text("Efficiency Cores").font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(cores.filter { $0.kind == .efficiency }) { core in
                                coreBar(core: core)
                            }
                            Divider().padding(.vertical, 4)
                            Text("Performance Cores").font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(cores.filter { $0.kind == .performance }) { core in
                                coreBar(core: core)
                            }
                        }
                    }
                }

                // Cluster summary
                if !samples.isEmpty {
                    GroupBox("Cluster Summary") {
                        LabeledContent("P-Cluster Frequency", value: latestPCluFreqStr)
                        LabeledContent("E-Cluster Frequency", value: latestECluFreqStr)
                        LabeledContent("P-Cluster Utilization", value: latestPUtilStr)
                        LabeledContent("E-Cluster Utilization", value: latestEUtilStr)
                    }
                }
            }
            .padding(16)
        }
    }

    var latestSampleCores: [PerCoreUtilization] {
        coord.latest?.perCoreUtilization ?? []
    }

    var latestPCluFreqStr: String {
        guard let f = coord.latest?.pClusterFreqMHz else { return "--" }
        return String(format: "%.0f MHz", f)
    }
    var latestECluFreqStr: String {
        guard let f = coord.latest?.eClusterFreqMHz else { return "--" }
        return String(format: "%.0f MHz", f)
    }
    var latestPUtilStr: String {
        guard let u = coord.latest?.cpuUtilization else { return "--" }
        return String(format: "%.1f%%", u * 100)
    }
    var latestEUtilStr: String {
        guard let eSamples = coord.latest?.perCoreUtilization.filter({ $0.kind == .efficiency }),
              !eSamples.isEmpty else { return "--" }
        let avg = eSamples.compactMap(\.utilizationPercent).reduce(0, +) / Double(eSamples.count)
        return String(format: "%.1f%%", avg)
    }

    func coreBar(core: PerCoreUtilization) -> some View {
        let pct = core.utilizationPercent ?? 0
        let color: Color = core.kind == .performance ? .indigo : .teal
        let label: String = {
            if core.kind == .performance {
                let idx = core.logicalCoreIndex - 6 + 1
                return "P\(idx)"
            } else {
                return "E\(core.logicalCoreIndex + 1)"
            }
        }()
        return HStack(spacing: 8) {
            Text(label).font(.caption.monospaced()).frame(width: 24, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary).frame(height: 16)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(core.valid ? 0.8 : 0.3))
                        .frame(width: geo.size.width * CGFloat(pct / 100), height: 16)
                }
            }
            .frame(height: 16)
            Text(String(format: "%.0f%%", pct))
                .font(.caption.monospaced()).frame(width: 42, alignment: .trailing)
        }
    }

    func stopTest() {
        // coord.cancel() sets state to .cancelled,
        // which triggers the onChange handler to save the RunRecord.
        // Do NOT reset coordinator here — the save depends on it.
        coord.cancel()
    }

    func metricItem(_ label: String, value: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(.body, design: .monospaced)).bold()
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    var hasValidTemp: Bool { samples.contains(where: { $0.cpuTemp != nil || $0.cpuTempHottest != nil }) }
    var hasValidPower: Bool { samples.contains(where: { $0.powerValid }) }
    var hasValidFreq: Bool { samples.contains(where: { $0.freqValid }) }

    func tempStr(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "…" }
    func powerStr(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "…" }
    func freqStr(_ v: Double?) -> String {
        v.map { String(format: "%.2f", $0 / 1000) } ?? "…"
    }
    func thermalStr(_ t: ThermalStateTag?) -> String {
        switch t {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        default: "…"
        }
    }
    func timeStr(_ s: TimeInterval) -> String {
        let m = Int(s) / 60; let sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }
    func thermalY(_ t: ThermalStateTag) -> Int {
        switch t { case .nominal: 3; case .fair: 2; case .serious: 1; case .critical: 0; default: -1 }
    }
    func thermalColorForTag(_ t: ThermalStateTag) -> Color {
        switch t { case .nominal: .green; case .fair: .yellow; case .serious: .orange; case .critical: .red; default: .gray }
    }
    func stateLabel(_ t: ThermalStateTag) -> String {
        switch t { case .nominal: "Nominal"; case .fair: "Fair"; case .serious: "Serious"; case .critical: "Critical"; default: "Unknown" }
    }
    func thermalLabel(_ t: ThermalStateTag) -> String {
        switch t { case .nominal: "N"; case .fair: "F"; case .serious: "S"; case .critical: "C"; default: "?" }
    }
}
