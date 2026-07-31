// ThermalBench - Results, History, Compare, Diagnostics Views
import SwiftUI
import SwiftData
import Charts

// MARK: - Results View

struct ResultsView: View {
    let run: RunRecord
    @Environment(AppModel.self) private var app
    @State private var selectedSection: ResultSection = .summary

    enum ResultSection: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case thermal = "Thermal"
        case power = "Power"
        case frequency = "Frequency"
        case cores = "Cores"
        case timeline = "Timeline"
        case quality = "Quality"
        var id: Self { self }
    }

    private var storedSamples: [TelemetrySample] {
        guard let json = run.dataDirectory.data(using: .utf8),
              let samples = try? JSONDecoder().decode([TelemetrySample].self, from: json) else {
            return []
        }
        return samples
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and notice
            VStack(alignment: .leading, spacing: 2) {
                Text(run.name.isEmpty ? "Test" : run.name)
                    .font(.title).bold()
                HStack(spacing: 8) {
                    Text("Started \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.tertiary)
                    Text(durationStr(run.duration))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if run.sampleCount < 50 && run.sampleCount > 0 {
                    Text("Short test · steady state not established · peaks remain valid")
                        .font(.caption2).foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)

            // Section picker — responsive: segmented if room, menu if not
            ViewThatFits {
                Picker("Section", selection: $selectedSection) {
                    ForEach(ResultSection.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 6)

                Picker("Section: \(selectedSection.rawValue)", selection: $selectedSection) {
                    ForEach(ResultSection.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
            }

            // Section content
            ScrollView {
                switch selectedSection {
                case .summary: summarySection
                case .thermal: thermalSection
                case .power: powerSection
                case .frequency: frequencySection
                case .cores: coresSection
                case .timeline: timelineSection
                case .quality: qualitySection
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    app.route = .home
                    app.resetForNewRun()
                }
                .keyboardShortcut(.escape)
            }
        }
    }

    // MARK: - Summary

    var summarySection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            summaryTile("CPU Hottest", value: run.cpuPeakTemp > 0 ? String(format: "%.1f °C", run.cpuPeakTemp) : "N/A", color: .red)
            summaryTile("GPU Hottest", value: run.gpuPeakTemp > 0 ? String(format: "%.1f °C", run.gpuPeakTemp) : "N/A", color: .purple)
            summaryTile("CPU Peak Power", value: run.cpuPeakPower > 0 ? String(format: "%.1f W", run.cpuPeakPower) : "N/A", color: .blue)
            summaryTile("P-Cluster Peak", value: run.pClusterMinFreq > 0 ? String(format: "%.2f GHz", run.pClusterMinFreq / 1000) : "N/A", color: .green)
            summaryTile("Samples", value: "\(run.sampleCount)", color: .secondary)
            summaryTile("Duration", value: durationStr(run.duration), color: .secondary)
            summaryTile("Coverage", value: String(format: "%.0f%%", run.dataCoverage * 100), color: run.dataCoverage > 0.8 ? .green : .orange)
            summaryTile("Type", value: run.testModeRaw, color: .secondary)
            if run.wasInterrupted {
                summaryTile("Status", value: "Interrupted", color: .orange)
            }
        }
        .padding(16)
    }

    // MARK: - Thermal

    var thermalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                summaryTile("CPU Hottest Peak", value: run.cpuPeakTemp > 0 ? String(format: "%.1f °C", run.cpuPeakTemp) : "N/A", color: .red)
                summaryTile("GPU Hottest Peak", value: run.gpuPeakTemp > 0 ? String(format: "%.1f °C", run.gpuPeakTemp) : "N/A", color: .purple)
                summaryTile("Sensor Count", value: storedSamples.last.map { "\($0.cpuTempSensorCount) CPU" } ?? "N/A", color: .secondary)
            }
            .padding(.horizontal)

            // Chart
            if !storedSamples.isEmpty {
                GroupBox("Temperature") {
                    Chart {
                        ForEach(storedSamples, id: \.id) { s in
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
                    }
                    .chartXAxisLabel("Time (s)").chartYAxisLabel("°C")
                    .chartForegroundStyleScale(["CPU Hottest": .red, "CPU Avg": .orange, "GPU Hottest": .purple])
                    .frame(minHeight: 220)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Power

    var powerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                summaryTile("CPU Peak", value: run.cpuPeakPower > 0 ? String(format: "%.1f W", run.cpuPeakPower) : "N/A", color: .blue)
            }.padding(.horizontal)

            if !storedSamples.isEmpty {
                GroupBox("Power") {
                    Chart {
                        ForEach(storedSamples, id: \.id) { s in
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
                    }
                    .chartXAxisLabel("Time (s)").chartYAxisLabel("W")
                    .chartForegroundStyleScale(["CPU": .blue, "GPU": .purple, "Package": .green])
                    .frame(minHeight: 220)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Frequency

    var frequencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !storedSamples.isEmpty {
                GroupBox("Frequency") {
                    Chart {
                        ForEach(storedSamples, id: \.id) { s in
                            if let f = s.pClusterFreqMHz {
                                LineMark(x: .value("s", s.elapsedSeconds), y: .value("P-Core", f / 1000), series: .value("Series", "P-Core"))
                                    .foregroundStyle(.green)
                            }
                            if let f = s.eClusterFreqMHz {
                                LineMark(x: .value("s", s.elapsedSeconds), y: .value("E-Core", f / 1000), series: .value("Series", "E-Core"))
                                    .foregroundStyle(.teal)
                            }
                        }
                    }
                    .chartXAxisLabel("Time (s)").chartYAxisLabel("GHz")
                    .chartForegroundStyleScale(["P-Core": .green, "E-Core": .teal])
                    .frame(minHeight: 220)
                }
                .padding(.horizontal)

                GroupBox("Utilization") {
                    Chart {
                        ForEach(storedSamples, id: \.id) { s in
                            if let u = s.cpuUtilization {
                                LineMark(x: .value("s", s.elapsedSeconds), y: .value("CPU", u), series: .value("Series", "CPU"))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .chartXAxisLabel("Time (s)").chartYAxisLabel("Ratio")
                    .chartForegroundStyleScale(["CPU": .blue])
                    .frame(minHeight: 180)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Cores

    var coresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let latest = storedSamples.last, !latest.perCoreUtilization.isEmpty {
                GroupBox("Per-Core Utilization (last sample)") {
                    LazyVStack(spacing: 6) {
                        Text("Efficiency Cores").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(latest.perCoreUtilization.filter { $0.kind == .efficiency }) { core in
                            coreResultBar(core: core)
                        }
                        Divider().padding(.vertical, 4)
                        Text("Performance Cores").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(latest.perCoreUtilization.filter { $0.kind == .performance }) { core in
                            coreResultBar(core: core)
                        }
                    }
                }
                .padding(.horizontal)
            } else {
                Text("Per-core data not available for this run.")
                    .foregroundStyle(.secondary).padding()
            }
        }
        .padding(.vertical, 12)
    }

    func coreResultBar(core: PerCoreUtilization) -> some View {
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
            Text(label).font(.caption.monospaced()).frame(width: 24)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary).frame(height: 14)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.8))
                            .frame(width: geo.size.width * CGFloat(pct / 100))
                    }
            }.frame(height: 14)
            Text(String(format: "%.0f%%", pct))
                .font(.caption.monospaced()).frame(width: 42, alignment: .trailing)
        }
    }

    // MARK: - Timeline

    var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Test Structure") {
                LabeledContent("Duration", value: durationStr(run.duration))
                LabeledContent("Samples", value: "\(run.sampleCount)")
                if run.wasInterrupted {
                    LabeledContent("Status", value: "Interrupted")
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Quality

    var qualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Data Quality") {
                LabeledContent("Samples", value: "\(run.sampleCount)")
                LabeledContent("Duration", value: durationStr(run.duration))
                LabeledContent("Coverage", value: String(format: "%.0f%%", run.dataCoverage * 100))
                LabeledContent("Completion", value: run.wasInterrupted ? "Interrupted" : "Completed")
                LabeledContent("Samples stored", value: storedSamples.isEmpty ? "No" : "Yes (\(storedSamples.count))")
                if !storedSamples.isEmpty {
                    LabeledContent("CPU Temp valid", value: String(format: "%d/%d", storedSamples.filter { $0.tempValid }.count, storedSamples.count))
                }
            }.padding(.horizontal)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    func summaryTile(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3).bold().foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    func durationStr(_ d: TimeInterval) -> String {
        guard d > 0 else { return "0s" }
        let m = Int(d) / 60; let s = Int(d) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}

// MARK: - History View

struct HistoryView: View {
    @Query(sort: \RunRecord.createdAt, order: .reverse) var runs: [RunRecord]
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @State private var deleteConfirmRun: RunRecord?
    @State private var renameRun: RunRecord?
    @State private var renameText: String = ""

    var body: some View {
        Group {
            if runs.isEmpty {
                ContentUnavailableView("No Tests Yet", systemImage: "chart.xyaxis.line",
                                       description: Text("Run a test to see results here."))
            } else {
                List(runs) { run in
                    HStack {
                        Button {
                            app.route = .result(run.uuid)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(run.name).font(.headline)
                                    Text(run.createdAt.formatted()).font(.caption).foregroundStyle(.secondary)
                                    Text(run.deviceSummary).font(.caption2).foregroundStyle(.tertiary)
                                    if run.sampleCount == 0 || run.duration <= 0 {
                                        HStack {
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption2)
                                            Text("Invalid Run").font(.caption2).foregroundStyle(.orange)
                                        }
                                    }
                                }
                                Spacer()
                                if run.wasInterrupted {
                                    Text("Interrupted").font(.caption).foregroundStyle(.orange)
                                }
                                if run.phaseRaw == TestPhase.completed.rawValue && run.sampleCount > 0 {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(run.sampleCount == 0 || run.duration <= 0)
                        .contextMenu {
                            Button("Open") { app.route = .result(run.uuid) }
                            Button("Rename") { renameRun = run; renameText = run.name }
                            Divider()
                            Button("Delete", role: .destructive) { deleteConfirmRun = run }
                        }

                        Button(role: .destructive) {
                            deleteConfirmRun = run
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete this test")
                    }
                }
            }
        }
        .alert("Delete this test?", isPresented: .init(
            get: { deleteConfirmRun != nil },
            set: { if !$0 { deleteConfirmRun = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleteConfirmRun = nil }
            Button("Delete", role: .destructive) {
                if let run = deleteConfirmRun { deleteRun(run) }
                deleteConfirmRun = nil
            }
        } message: {
            if let r = deleteConfirmRun {
                Text("Delete \(r.name)? \(r.sampleCount) samples, \(Int(r.duration))s. This cannot be undone.")
            } else {
                Text("This cannot be undone.")
            }
        }
        .alert("Rename Test", isPresented: .init(
            get: { renameRun != nil },
            set: { if !$0 { renameRun = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameRun = nil }
            Button("Save") {
                renameAndSave()
            }
        } message: {
            if let r = renameRun {
                Text("Enter a new name for \(r.name)")
            }
        }
        .navigationTitle("History")
    }

    private func renameAndSave() {
        guard let run = renameRun else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renameRun = nil
            return
        }
        run.name = trimmed
        try? modelContext.save()
        renameRun = nil
    }

    private func deleteRun(_ run: RunRecord) {
        // Clear Compare selections if they reference this run
        run.dataDirectory = ""
        modelContext.delete(run)
        try? modelContext.save()

        // If currently viewing this run in Results, go home
        if case .result(let id) = app.route, id == run.uuid {
            app.route = .home
        }
    }
}

// MARK: - Compare View

struct CompareView: View {
    @Query(sort: \RunRecord.createdAt, order: .reverse) var runs: [RunRecord]
    @Environment(\.modelContext) private var modelContext
    @State private var firstID: String?
    @State private var secondID: String?
    @State private var showCompare = false

    /// Only valid runs with data
    private var validRuns: [RunRecord] {
        runs.filter { $0.sampleCount > 0 && $0.duration > 0 && $0.dataCoverage > 0 }
    }

    private var runA: RunRecord? { fetchRun(uuid: firstID) }
    private var runB: RunRecord? { fetchRun(uuid: secondID) }

    private func fetchRun(uuid: String?) -> RunRecord? {
        guard let id = uuid else { return nil }
        var d = FetchDescriptor<RunRecord>(predicate: #Predicate { $0.uuid == id })
        d.fetchLimit = 1
        return try? modelContext.fetch(d).first
    }

    var body: some View {
        if validRuns.count < 2 {
            ContentUnavailableView("Need Two Valid Tests", systemImage: "arrow.left.arrow.right",
                                   description: Text("Complete at least two tests with data to use Compare."))
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    runPicker("Test A", selection: $firstID, run: runA)
                    Button("Swap") { swapSelection() }.buttonStyle(.bordered).controlSize(.small)
                    runPicker("Test B", selection: $secondID, run: runB)
                }
                .padding()

                if showCompare, let a = runA, let b = runB, a.uuid != b.uuid {
                    Divider()
                    compareContent(a: a, b: b)
                } else if firstID != nil, secondID != nil, firstID == secondID {
                    Text("Select two different tests.").foregroundStyle(.orange).padding()
                } else if showCompare, (runA == nil || runB == nil) {
                    Text("Could not load selected test data.").foregroundStyle(.orange).padding()
                }
            }
            .onAppear {
                if validRuns.count >= 2 {
                    firstID = validRuns[0].uuid
                    secondID = validRuns[1].uuid
                    showCompare = true
                }
            }
            .onChange(of: firstID) { _, _ in showCompare = firstID != nil && secondID != nil && firstID != secondID }
            .onChange(of: secondID) { _, _ in showCompare = firstID != nil && secondID != nil && firstID != secondID }
        }
    }

    func runPicker(_ label: String, selection: Binding<String?>, run: RunRecord?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Picker(label, selection: selection) {
                Text("Select...").tag(nil as String?)
                ForEach(validRuns) { r in
                    let pct = r.cpuPeakTemp > 0 ? String(format: ", %.0f°C", r.cpuPeakTemp) : ""
                    Text("\(r.name.prefix(16)) \(r.createdAt.formatted(date: .abbreviated, time: .shortened)) \(r.sampleCount)s\(pct)")
                        .tag(r.uuid as String?)
                }
            }
            .frame(width: 280)
        }
    }

    func swapSelection() {
        let tmp = firstID; firstID = secondID; secondID = tmp
    }

    // MARK: - Compare Content

    @ViewBuilder
    func compareContent(a: RunRecord, b: RunRecord) -> some View {
        let result = CompareAnalyzer.analyze(a: a, b: b)
        let sa = result.canCompare ? decodeSamples(run: a) : []
        let sb = result.canCompare ? decodeSamples(run: b) : []

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // ── Comparability Verdict ──
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: result.level.icon)
                                .foregroundStyle(levelColor(result.level))
                                .font(.title3)
                            Text(result.level.displayName)
                                .font(.headline)
                                .foregroundStyle(levelColor(result.level))
                        }

                        if !result.warnings.isEmpty {
                            Divider()
                            ForEach(result.warnings) { w in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: severityIcon(w.severity))
                                        .font(.caption)
                                        .foregroundStyle(severityColor(w.severity))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(w.field).font(.caption).bold()
                                        Text(w.detail).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Field-by-field comparison ──
                if !result.fields.isEmpty {
                    GroupBox("Comparison Details") {
                        Grid(horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Field").bold().gridColumnAlignment(.leading)
                                Text("Run A").bold().frame(maxWidth: .infinity, alignment: .leading)
                                Text("Run B").bold().frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption)
                            Divider()
                            ForEach(result.fields) { f in
                                GridRow {
                                    HStack(spacing: 4) {
                                        Image(systemName: f.match ? "checkmark.circle.fill" : "circle")
                                            .font(.caption2)
                                            .foregroundStyle(f.match ? .green : .secondary)
                                        Text(f.label)
                                    }
                                    Text(f.valueA).lineLimit(2)
                                    Text(f.valueB).lineLimit(2)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }

                // ── Summary Table (only if comparable) ──
                if result.canCompare {
                    GroupBox("Metrics") {
                        Grid(horizontalSpacing: 20, verticalSpacing: 8) {
                            GridRow {
                                Text("Metric").bold().gridColumnAlignment(.leading)
                                Text("Run A").bold().frame(width: 80)
                                Text("Run B").bold().frame(width: 80)
                                Text("Δ").bold().frame(width: 80)
                            }
                            .font(.caption)
                            Divider()
                            compareRow("Duration", a: durationStr(a.duration), b: durationStr(b.duration))
                            compareRow("Samples", a: "\(a.sampleCount)", b: "\(b.sampleCount)")
                            compareMetric("CPU Peak Temp", a: a.cpuPeakTemp, b: b.cpuPeakTemp, unit: "°C")
                            compareMetric("GPU Peak Temp", a: a.gpuPeakTemp, b: b.gpuPeakTemp, unit: "°C")
                            compareMetric("CPU Peak Power", a: a.cpuPeakPower, b: b.cpuPeakPower, unit: "W")
                            compareRow("P-Cluster Peak",
                                       a: pFreqStr(a.pClusterMinFreq),
                                       b: pFreqStr(b.pClusterMinFreq))
                            compareRow("Coverage",
                                       a: pctStr(a.dataCoverage),
                                       b: pctStr(b.dataCoverage))
                        }
                        .font(.caption)
                    }
                }

                // Overlay Charts — only when comparable
                if result.canCompare, !sa.isEmpty || !sb.isEmpty {
                    GroupBox("Temperature Comparison") {
                        Chart {
                            ForEach(sa, id: \.id) { s in
                                if let t = s.cpuTempHottest {
                                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("A", t), series: .value("Series", "A Hottest"))
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                            }
                            ForEach(sb, id: \.id) { s in
                                if let t = s.cpuTempHottest {
                                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("B", t), series: .value("Series", "B Hottest"))
                                        .foregroundStyle(.red.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                                }
                            }
                        }
                        .chartXAxisLabel("Time (s)").chartYAxisLabel("°C")
                        .chartForegroundStyleScale(["A Hottest": .red, "B Hottest": .orange])
                        .frame(minHeight: 180)
                    }
                }
            }
            .padding(16)
        }
    }

    func compareRow(_ label: String, a: String, b: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(a)
            Text(b)
            Text("-").foregroundStyle(.tertiary)
        }
        .font(.caption)
    }

    // MARK: - Compare Helpers

    func levelColor(_ level: ComparabilityLevel) -> Color {
        switch level {
        case .highlyComparable:       .green
        case .comparableWithWarnings: .orange
        case .invalid:                .red
        }
    }

    func severityIcon(_ s: ComparabilityWarning.Severity) -> String {
        switch s {
        case .info:    "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error:   "xmark.circle.fill"
        }
    }

    func severityColor(_ s: ComparabilityWarning.Severity) -> Color {
        switch s {
        case .info:    .secondary
        case .warning: .orange
        case .error:   .red
        }
    }

    // MARK: - Legacy helpers (kept for compatibility)

    func compareMetric(_ label: String, a: Double, b: Double, unit: String) -> some View {
        let aAvail = a > 0
        let bAvail = b > 0
        let delta = aAvail && bAvail ? b - a : nil
        let deltaStr: String
        if let d = delta {
            let sign = d >= 0 ? "+" : ""
            deltaStr = String(format: "\(sign)%.1f \(unit)", d)
        } else {
            deltaStr = "N/A"
        }
        return GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(aAvail ? String(format: "%.1f \(unit)", a) : "N/A")
            Text(bAvail ? String(format: "%.1f \(unit)", b) : "N/A")
            Text(deltaStr).foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    func pFreqStr(_ f: Double) -> String {
        f > 0 ? String(format: "%.2f GHz", f / 1000) : "N/A"
    }
    func pctStr(_ v: Double) -> String {
        v > 0 ? String(format: "%.0f%%", v * 100) : "N/A"
    }
    func durationStr(_ d: TimeInterval) -> String {
        guard d > 0 else { return "0s" }
        let m = Int(d) / 60; let s = Int(d) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    func decodeSamples(run: RunRecord) -> [TelemetrySample] {
        guard let json = run.dataDirectory.data(using: .utf8),
              let samples = try? JSONDecoder().decode([TelemetrySample].self, from: json),
              !samples.isEmpty else {
            return []
        }
        return samples
    }
}

// MARK: - Diagnostics View

// MARK: - Diagnostics

private struct ProbeResult {
    var tempOK: Bool?
    var powerOK: Bool?
    var freqOK: Bool?
    var tempHottest: Double?
    var cpuPower: Double?
    var pFreq: Double?
    var battery: Int?
    var ac: Bool?
    var error: String?
}

private struct DiagnosticRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    var status: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 26, height: 26)
                .background(Circle().fill(iconColor.opacity(0.14)))
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            if let status {
                Circle().fill(status).frame(width: 8, height: 8)
            }
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

private func diagCardBackground(cornerRadius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
}

private struct DiagSection<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).textCase(.uppercase)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            Divider()
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(diagCardBackground(cornerRadius: 14))
    }
}

struct DiagnosticsView: View {
    @State private var probe: ProbeResult? = nil
    @State private var isProbing = false

    var body: some View {
        let dev = DeviceProfile.current
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                deviceHeader(dev)
                selfCheckCard()

                DiagSection(title: "App", icon: "app.badge", tint: .blue) {
                    DiagnosticRow(icon: "number", iconColor: .blue, label: "Version", value: BuildIdentity.appVersion)
                    DiagnosticRow(icon: "chevron.left.forwardslash.chevron.right", iconColor: .blue, label: "Git Commit", value: BuildIdentity.gitSHA)
                    DiagnosticRow(icon: "clock", iconColor: .blue, label: "Build Time", value: BuildIdentity.buildTimestampUTC + " UTC")
                    DiagnosticRow(icon: "macbook", iconColor: .blue, label: "Model Identifier", value: dev.modelIdentifier)
                    DiagnosticRow(icon: "cpu", iconColor: .blue, label: "Chip", value: dev.chipName)
                    DiagnosticRow(icon: "circle.grid.2x2", iconColor: .blue, label: "Cores", value: dev.coreSummary)
                    DiagnosticRow(icon: "memorychip", iconColor: .blue, label: "Memory", value: dev.formattedMemory)
                    DiagnosticRow(icon: "apple.logo", iconColor: .blue, label: "macOS", value: dev.macOSVersion)
                    DiagnosticRow(icon: "square.3.layers.3d", iconColor: .blue, label: "Metal Device",
                                 value: dev.metalDeviceName ?? "N/A",
                                 status: dev.metalDeviceName == nil ? .yellow : .green)
                    if let gpu = dev.gpuCoreCount {
                        DiagnosticRow(icon: "gpu", iconColor: .blue, label: "GPU Cores", value: "\(gpu)")
                    }
                    DiagnosticRow(icon: "leaf", iconColor: .blue, label: "Low Power Mode",
                                 value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "OFF",
                                 status: ProcessInfo.processInfo.isLowPowerModeEnabled ? .yellow : .green)
                }

                DiagSection(title: "Telemetry", icon: "waveform.path.ecg", tint: .orange) {
                    DiagnosticRow(icon: "shippingbox", iconColor: .orange, label: "Core", value: "Embedded Rust macmon (vendored)")
                    DiagnosticRow(icon: "thermometer.medium", iconColor: .orange, label: "Temperature", value: "Apple SMC sensor aggregation")
                    DiagnosticRow(icon: "bolt.fill", iconColor: .orange, label: "Power", value: "IOReport via embedded library")
                    DiagnosticRow(icon: "waveform", iconColor: .orange, label: "Frequency", value: "IOReport via embedded library")
                    DiagnosticRow(icon: "square.grid.3x3", iconColor: .orange, label: "Per-Core", value: "\(dev.coreSummary) via host_processor_info")
                    DiagnosticRow(icon: "lock.shield", iconColor: .orange, label: "Privileges", value: "No sudo")
                    DiagnosticRow(icon: "externaldrive", iconColor: .orange, label: "External Processes", value: "None")
                }

                DiagSection(title: "Battery", icon: "battery.75percent", tint: .green) {
                    DiagnosticRow(icon: "battery.75percent", iconColor: .green, label: "Source", value: "IOPowerSources (public API)")
                }
            }
            .padding(24)
        }
        .navigationTitle("Diagnostics")
    }

    // MARK: - Device summary card

    private func deviceHeader(_ dev: DeviceProfile) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.blue.opacity(0.85), .purple.opacity(0.75)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                Image(systemName: "cpu")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(dev.chipName)
                    .font(.title2.weight(.semibold))
                Text("\(dev.modelIdentifier) · \(dev.coreSummary) · \(dev.formattedMemory)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(dev.macOSVersion)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .background(diagCardBackground(cornerRadius: 18))
    }

    // MARK: - Live one-shot probe

    private func selfCheckCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "stethoscope")
                    Text("Quick Self-Check").textCase(.uppercase)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.purple)
                Spacer()
                if isProbing {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        runProbe()
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.purple)
                }
            }
            Divider()

            if let probe {
                if let err = probe.error {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                } else {
                    VStack(spacing: 10) {
                        probeRow(icon: "thermometer.medium", color: .orange, label: "Temperature",
                                 ok: probe.tempOK,
                                 value: probe.tempHottest.map { String(format: "%.1f°C", $0) } ?? "—")
                        probeRow(icon: "bolt.fill", color: .yellow, label: "Power",
                                 ok: probe.powerOK,
                                 value: probe.cpuPower.map { String(format: "%.1f W", $0) } ?? "—")
                        probeRow(icon: "waveform", color: .teal, label: "Frequency",
                                 ok: probe.freqOK,
                                 value: probe.pFreq.map { String(format: "%.0f MHz", $0) } ?? "—")
                        probeRow(icon: "battery.75percent", color: .green, label: "Power Source",
                                 ok: probe.ac != nil,
                                 value: (probe.ac == true ? "AC" : probe.ac == false ? "Battery" : "Unknown")
                                     + (probe.battery.map { " · \($0)%" } ?? ""))
                    }
                }
            } else if !isProbing {
                Text("Run a live one-shot probe to verify temperature, power, frequency and power-source channels.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(diagCardBackground(cornerRadius: 14))
    }

    private func probeRow(icon: String, color: Color, label: String, ok: Bool?, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(Circle().fill(color.opacity(0.14)))
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Circle()
                .fill(ok == true ? .green : (ok == false ? .red : .gray))
                .frame(width: 8, height: 8)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private func runProbe() {
        isProbing = true
        probe = nil
        let ts = TelemetryService.shared
        Task {
            do {
                try await ts.startTelemetry()
                let s = try await ts.readSample()
                await ts.stopTelemetry()
                probe = ProbeResult(
                    tempOK: s.tempValid,
                    powerOK: s.powerValid,
                    freqOK: s.freqValid,
                    tempHottest: s.cpuTempHottest,
                    cpuPower: s.cpuPower,
                    pFreq: s.pClusterFreqMHz,
                    battery: s.batteryPercent,
                    ac: s.acConnected
                )
                isProbing = false
            } catch {
                await ts.stopTelemetry()
                probe = ProbeResult(error: error.localizedDescription)
                isProbing = false
            }
        }
    }
}


