// ThermalBench - Results, History, Compare, Diagnostics Views
import SwiftUI
import SwiftData
import Charts

// MARK: - Results View

struct ResultsView: View {
    let run: RunRecord
    @Environment(AppModel.self) private var app
    @State private var selectedSection: ResultSection = .summary
    /// Samples loaded once in the background; avoids re-reading the whole
    /// JSONL file on every computed-property access (main thread).
    @State private var cachedSamples: [TelemetrySample]?

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
        cachedSamples ?? []
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
        .onAppear {
            guard cachedSamples == nil else { return }
            let r = run
            Task.detached(priority: .userInitiated) {
                let loaded = SampleArchive.load(from: r)
                await MainActor.run { cachedSamples = loaded }
            }
        }
    }

    // MARK: - Summary

    var summarySection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 12) {
            summaryTile("CPU Hottest", value: run.cpuPeakTemp.map { String(format: "%.1f °C", $0) } ?? "N/A", color: .red)
            summaryTile("GPU Hottest", value: run.gpuPeakTemp.map { String(format: "%.1f °C", $0) } ?? "N/A", color: .purple)
            summaryTile("CPU Peak Power", value: run.cpuPeakPower.map { String(format: "%.1f W", $0) } ?? "N/A", color: .blue)
            summaryTile("P-Cluster Peak", value: (run.pClusterPeakFreq ?? (run.pClusterMinFreq > 0 ? run.pClusterMinFreq : nil)).map { String(format: "%.2f GHz", $0 / 1000) } ?? "N/A", color: .green)
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                summaryTile("CPU Hottest Peak", value: run.cpuPeakTemp.map { String(format: "%.1f °C", $0) } ?? "N/A", color: .red)
                summaryTile("GPU Hottest Peak", value: run.gpuPeakTemp.map { String(format: "%.1f °C", $0) } ?? "N/A", color: .purple)
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                summaryTile("CPU Peak", value: run.cpuPeakPower.map { String(format: "%.1f W", $0) } ?? "N/A", color: .blue)
                summaryTile("GPU Peak", value: run.gpuPeakPower.map { String(format: "%.1f W", $0) } ?? "N/A", color: .purple)
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
            switch core.kind {
            case .performance: "P\(core.displayIndex)"
            case .efficiency:  "E\(core.displayIndex)"
            case .unknown:     "?\(core.displayIndex)"
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
                LabeledContent("Raw archive", value: rawDataStatus.displayName)
                if rawDataStatus != .complete {
                    Label("Raw sample data is incomplete — the Summary may include samples missing from the raw curve.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let rawErr = run.rawDataError {
                    Text(rawErr).font(.caption2).foregroundStyle(.secondary)
                }
                if !storedSamples.isEmpty {
                    LabeledContent("CPU Temp valid", value: channelCount(storedSamples, \.cpuTempValid))
                    LabeledContent("GPU Temp valid", value: channelCount(storedSamples, \.gpuTempValid))
                    LabeledContent("CPU Power valid", value: channelCount(storedSamples, \.cpuPowerValid))
                    LabeledContent("GPU Power valid", value: channelCount(storedSamples, \.gpuPowerValid))
                    LabeledContent("P-Freq valid", value: channelCount(storedSamples, \.pFrequencyValid))
                    LabeledContent("E-Freq valid", value: channelCount(storedSamples, \.eFrequencyValid))
                }
            }.padding(.horizontal)
        }
        .padding(.vertical, 12)
    }

    private var rawDataStatus: RawDataStatus {
        RawDataStatus(rawValue: run.rawDataStatusRaw) ?? .complete
    }

    /// "<valid>/<total>" per-channel sample coverage for the Quality page.
    private func channelCount(_ samples: [TelemetrySample], _ keyPath: KeyPath<TelemetrySample, Bool>) -> String {
        String(format: "%d/%d", samples.filter { $0[keyPath: keyPath] }.count, samples.count)
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
    @State private var isSelecting = false
    @State private var selectedRuns = Set<RunRecord.ID>()
    @State private var confirmDeleteSelected = false

    var body: some View {
        Group {
            if runs.isEmpty {
                ContentUnavailableView("No Tests Yet", systemImage: "chart.xyaxis.line",
                                       description: Text("Run a test to see results here."))
            } else {
                List(runs) { run in
                    HStack {
                        if isSelecting {
                            Image(systemName: selectedRuns.contains(run.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedRuns.contains(run.id) ? Color.accentColor : .secondary)
                                .font(.title3)
                        }
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
                        .disabled(run.sampleCount == 0 || run.duration <= 0 || isSelecting)
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
                        .opacity(isSelecting ? 0 : 1)
                        .disabled(isSelecting)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelecting {
                            if selectedRuns.contains(run.id) {
                                selectedRuns.remove(run.id)
                            } else {
                                selectedRuns.insert(run.id)
                            }
                        }
                    }
                }
            }
        }
        .alert("Delete \(selectedRuns.count) test(s)?", isPresented: $confirmDeleteSelected) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteSelectedRuns() }
        } message: {
            Text("This will permanently delete \(selectedRuns.count) tests and their sample files. This cannot be undone.")
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !isSelecting {
                    Button("Select") {
                        withAnimation { isSelecting = true }
                    }
                } else {
                    HStack(spacing: 12) {
                        Button(selectedRuns.count == runs.count ? "Deselect All" : "Select All") {
                            if selectedRuns.count == runs.count {
                                selectedRuns.removeAll()
                            } else {
                                selectedRuns = Set(runs.map(\.id))
                            }
                        }
                        Button("Delete (\(selectedRuns.count))") {
                            if !selectedRuns.isEmpty { confirmDeleteSelected = true }
                        }
                        .disabled(selectedRuns.isEmpty)
                        Button("Cancel") {
                            withAnimation { isSelecting = false }
                            selectedRuns.removeAll()
                        }
                    }
                }
            }
        }
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

    private func deleteSelectedRuns() {
        let targets = runs.filter { selectedRuns.contains($0.id) }
        for run in targets {
            // Remove sample files first (dataDirectory still holds the path),
            // then delete the record. Never clear dataDirectory before cleanup.
            SampleArchive.deleteFiles(for: run)
            modelContext.delete(run)
        }
        try? modelContext.save()
        withAnimation { isSelecting = false }
        selectedRuns.removeAll()
    }

    private func deleteRun(_ run: RunRecord) {
        // Remove sample files first, then delete the record.
        SampleArchive.deleteFiles(for: run)
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

    // Raw samples loaded off the main thread (full JSONL files are too big
    // to decode synchronously in body on every redraw).
    @State private var samplesA: [TelemetrySample]?
    @State private var samplesB: [TelemetrySample]?
    @State private var loadingComparison = false

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
                    loadComparisonData()
                }
            }
            .onChange(of: firstID) { _, _ in
                showCompare = firstID != nil && secondID != nil && firstID != secondID
                loadComparisonData()
            }
            .onChange(of: secondID) { _, _ in
                showCompare = firstID != nil && secondID != nil && firstID != secondID
                loadComparisonData()
            }
        }
    }

    /// Load the raw sample files for the selected runs off the main thread.
    /// Re-checks the selection before applying so a quick re-pick can't be
    /// overwritten by a stale load.
    private func loadComparisonData() {
        guard let a = runA, let b = runB, a.uuid != b.uuid else {
            samplesA = nil
            samplesB = nil
            loadingComparison = false
            return
        }
        let result = CompareAnalyzer.analyze(a: a, b: b)
        guard result.canCompare else {
            samplesA = []
            samplesB = []
            loadingComparison = false
            return
        }
        let idA = firstID
        let idB = secondID
        let pathA = a.dataDirectory
        let pathB = b.dataDirectory
        loadingComparison = true
        Task.detached(priority: .userInitiated) {
            let sa = SampleArchive.load(dataDirectory: pathA)
            let sb = SampleArchive.load(dataDirectory: pathB)
            await MainActor.run {
                guard idA == self.firstID, idB == self.secondID else { return }
                self.samplesA = sa
                self.samplesB = sb
                self.loadingComparison = false
            }
        }
    }

    func runPicker(_ label: String, selection: Binding<String?>, run: RunRecord?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Picker(label, selection: selection) {
                Text("Select...").tag(nil as String?)
                ForEach(validRuns) { r in
                    let pct = r.cpuPeakTemp.map { String(format: ", %.0f°C", $0) } ?? ""
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
        let sa = result.canCompare ? (samplesA ?? []) : []
        let sb = result.canCompare ? (samplesB ?? []) : []
        let loading = loadingComparison && result.canCompare

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
                            compareMetric("GPU Peak Power", a: a.gpuPeakPower, b: b.gpuPeakPower, unit: "W")
                            compareRow("P-Cluster Peak",
                                       a: pFreqStr(a.pClusterPeakFreq ?? (a.pClusterMinFreq > 0 ? a.pClusterMinFreq : nil)),
                                       b: pFreqStr(b.pClusterPeakFreq ?? (b.pClusterMinFreq > 0 ? b.pClusterMinFreq : nil)))
                            compareRow("Coverage",
                                       a: pctStr(a.dataCoverage),
                                       b: pctStr(b.dataCoverage))
                        }
                        .font(.caption)
                    }
                }

                // Overlay Charts — only when comparable
                if result.canCompare {
                    if loading {
                        ProgressView("Loading samples…")
                            .frame(maxWidth: .infinity, minHeight: 160)
                            .padding(.vertical, 24)
                    } else if !sa.isEmpty || !sb.isEmpty {
                        GroupBox("Temperature (°C)") {
                            compareTempChart(a: sa, b: sb)
                        }
                        GroupBox("Power (W)") {
                            comparePowerChart(a: sa, b: sb)
                        }
                        GroupBox("Frequency (GHz)") {
                            compareFreqChart(a: sa, b: sb)
                        }
                        GroupBox("CPU Utilization") {
                            compareUtilChart(a: sa, b: sb)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Compare Overlay Charts (A solid, B dashed)

    func compareTempChart(a: [TelemetrySample], b: [TelemetrySample]) -> some View {
        Chart {
            ForEach(a, id: \.id) { s in
                if let t = s.cpuTempHottest {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("A Hottest", t), series: .value("Series", "A Hottest"))
                        .foregroundStyle(.red.opacity(0.8))
                }
                if let t = s.gpuTempHottest {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("A GPU", t), series: .value("Series", "A GPU"))
                        .foregroundStyle(.purple.opacity(0.8))
                }
            }
            ForEach(b, id: \.id) { s in
                if let t = s.cpuTempHottest {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("B Hottest", t), series: .value("Series", "B Hottest"))
                        .foregroundStyle(.orange.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
                if let t = s.gpuTempHottest {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("B GPU", t), series: .value("Series", "B GPU"))
                        .foregroundStyle(.pink.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
        }
        .chartXAxisLabel("Time (s)").chartYAxisLabel("°C")
        .chartForegroundStyleScale(["A Hottest": .red, "A GPU": .purple, "B Hottest": .orange, "B GPU": .pink])
        .frame(minHeight: 180)
    }

    func comparePowerChart(a: [TelemetrySample], b: [TelemetrySample]) -> some View {
        Chart {
            ForEach(a, id: \.id) { s in
                if let p = s.cpuPower {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("A CPU", p), series: .value("Series", "A CPU"))
                        .foregroundStyle(.blue.opacity(0.8))
                }
                if let p = s.gpuPower {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("A GPU", p), series: .value("Series", "A GPU"))
                        .foregroundStyle(.purple.opacity(0.8))
                }
            }
            ForEach(b, id: \.id) { s in
                if let p = s.cpuPower {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("B CPU", p), series: .value("Series", "B CPU"))
                        .foregroundStyle(.orange.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
                if let p = s.gpuPower {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("B GPU", p), series: .value("Series", "B GPU"))
                        .foregroundStyle(.pink.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
        }
        .chartXAxisLabel("Time (s)").chartYAxisLabel("W")
        .chartForegroundStyleScale(["A CPU": .blue, "A GPU": .purple, "B CPU": .orange, "B GPU": .pink])
        .frame(minHeight: 180)
    }

    func compareFreqChart(a: [TelemetrySample], b: [TelemetrySample]) -> some View {
        Chart {
            ForEach(a, id: \.id) { s in
                if let f = s.pClusterFreqMHz {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("A P", f / 1000), series: .value("Series", "A P"))
                        .foregroundStyle(.green.opacity(0.8))
                }
                if let f = s.eClusterFreqMHz {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("A E", f / 1000), series: .value("Series", "A E"))
                        .foregroundStyle(.teal.opacity(0.8))
                }
            }
            ForEach(b, id: \.id) { s in
                if let f = s.pClusterFreqMHz {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("B P", f / 1000), series: .value("Series", "B P"))
                        .foregroundStyle(.orange.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
                if let f = s.eClusterFreqMHz {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("B E", f / 1000), series: .value("Series", "B E"))
                        .foregroundStyle(.pink.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
        }
        .chartXAxisLabel("Time (s)").chartYAxisLabel("GHz")
        .chartForegroundStyleScale(["A P": .green, "A E": .teal, "B P": .orange, "B E": .pink])
        .frame(minHeight: 180)
    }

    func compareUtilChart(a: [TelemetrySample], b: [TelemetrySample]) -> some View {
        Chart {
            ForEach(a, id: \.id) { s in
                if let u = s.cpuUtilization {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("A CPU", u), series: .value("Series", "A CPU"))
                        .foregroundStyle(.blue.opacity(0.8))
                }
            }
            ForEach(b, id: \.id) { s in
                if let u = s.cpuUtilization {
                    LineMark(x: .value("s", s.elapsedSeconds), y: .value("B CPU", u), series: .value("Series", "B CPU"))
                        .foregroundStyle(.orange.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
        }
        .chartXAxisLabel("Time (s)").chartYAxisLabel("Ratio")
        .chartForegroundStyleScale(["A CPU": .blue, "B CPU": .orange])
        .frame(minHeight: 160)
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

    func compareMetric(_ label: String, a: Double?, b: Double?, unit: String) -> some View {
        let aAvail = a != nil
        let bAvail = b != nil
        let delta = aAvail && bAvail ? b! - a! : nil
        let deltaStr: String
        if let d = delta {
            let sign = d >= 0 ? "+" : ""
            deltaStr = String(format: "\(sign)%.1f \(unit)", d)
        } else {
            deltaStr = "N/A"
        }
        return GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(aAvail ? String(format: "%.1f \(unit)", a!) : "N/A")
            Text(bAvail ? String(format: "%.1f \(unit)", b!) : "N/A")
            Text(deltaStr).foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    func pFreqStr(_ f: Double?) -> String {
        f.map { String(format: "%.2f GHz", $0 / 1000) } ?? "N/A"
    }
    func pctStr(_ v: Double) -> String {
        v > 0 ? String(format: "%.0f%%", v * 100) : "N/A"
    }
    func durationStr(_ d: TimeInterval) -> String {
        guard d > 0 else { return "0s" }
        let m = Int(d) / 60; let s = Int(d) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}

// MARK: - Diagnostics View

// Morandi (low-saturation) palette — blue family with distinct depths.
extension Color {
    static let morandiBlue      = Color(red: 0.55, green: 0.66, blue: 0.72) // mid dusty blue
    static let morandiBlueDeep  = Color(red: 0.44, green: 0.57, blue: 0.67) // deep slate blue
    static let morandiBlueLight = Color(red: 0.66, green: 0.75, blue: 0.81) // light dusty blue
    static let morandiSlate     = Color(red: 0.50, green: 0.58, blue: 0.65) // blue-grey
    static let morandiYellow    = Color(red: 0.78, green: 0.72, blue: 0.52)
}

// MARK: - Diagnostics View

// MARK: - Diagnostics

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
    /// Battery info read once on appear (IOPowerSources via telemetry core).
    @State private var batteryInfo: (ac: Bool, percent: Int)? = nil

    var body: some View {
        let dev = DeviceProfile.current
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                deviceHeader(dev)

                DiagSection(title: "Hardware", icon: "cpu", tint: .morandiBlueDeep) {
                    DiagnosticRow(icon: "cpu", iconColor: .morandiBlueDeep, label: "Chip", value: dev.chipName)
                    DiagnosticRow(icon: "macbook", iconColor: .morandiBlueDeep, label: "Model Identifier", value: dev.modelIdentifier)
                    DiagnosticRow(icon: "circle.grid.2x2", iconColor: .morandiBlueDeep, label: "CPU Cores", value: dev.coreSummary)
                    if let gpu = dev.gpuCoreCount {
                        DiagnosticRow(icon: "gpu", iconColor: .morandiBlueDeep, label: "GPU Cores", value: "\(gpu)")
                    }
                    DiagnosticRow(icon: "square.3.layers.3d", iconColor: .morandiBlueDeep, label: "Metal Device",
                                 value: dev.metalDeviceName ?? "N/A",
                                 status: dev.metalDeviceName == nil ? .morandiYellow : .morandiBlueDeep)
                    DiagnosticRow(icon: "memorychip", iconColor: .morandiBlueDeep, label: "Memory", value: dev.formattedMemory)
                    DiagnosticRow(icon: "internaldrive", iconColor: .morandiBlueDeep, label: "Storage", value: storageSummary)
                    DiagnosticRow(icon: "desktopcomputer", iconColor: .morandiBlueDeep, label: "Architecture", value: architecture)
                }

                DiagSection(title: "Battery & Power", icon: "battery.75percent", tint: .morandiBlue) {
                    DiagnosticRow(icon: "bolt.fill", iconColor: .morandiBlue, label: "Power Source",
                                 value: powerSourceLabel, status: powerSourceOK ? .morandiBlue : .morandiYellow)
                    DiagnosticRow(icon: "battery.75percent", iconColor: .morandiBlue, label: "Battery",
                                 value: batteryLevelLabel)
                    DiagnosticRow(icon: "leaf", iconColor: .morandiBlue, label: "Low Power Mode",
                                 value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "OFF",
                                 status: ProcessInfo.processInfo.isLowPowerModeEnabled ? .morandiYellow : .morandiBlue)
                }

                DiagSection(title: "Software", icon: "app.badge", tint: .morandiBlueLight) {
                    DiagnosticRow(icon: "apple.logo", iconColor: .morandiBlueLight, label: "macOS", value: dev.macOSVersion)
                    DiagnosticRow(icon: "number", iconColor: .morandiBlueLight, label: "App Version", value: BuildIdentity.appVersion)
                    DiagnosticRow(icon: "chevron.left.forwardslash.chevron.right", iconColor: .morandiBlueLight, label: "Git Commit", value: BuildIdentity.gitSHA)
                    DiagnosticRow(icon: "clock", iconColor: .morandiBlueLight, label: "Build Time", value: BuildIdentity.buildTimestampUTC + " UTC")
                }

                DiagSection(title: "Telemetry Architecture", icon: "waveform.path.ecg", tint: .morandiSlate) {
                    DiagnosticRow(icon: "shippingbox", iconColor: .morandiSlate, label: "Core", value: "Embedded Rust macmon (vendored)")
                    DiagnosticRow(icon: "number.circle", iconColor: .morandiSlate, label: "Core Version", value: telemetryCoreVersion)
                    DiagnosticRow(icon: "thermometer.medium", iconColor: .morandiSlate, label: "Temperature", value: "Apple SMC sensor aggregation")
                    DiagnosticRow(icon: "bolt.fill", iconColor: .morandiSlate, label: "Power", value: "IOReport via embedded library")
                    DiagnosticRow(icon: "waveform", iconColor: .morandiSlate, label: "Frequency", value: "IOReport via embedded library")
                    DiagnosticRow(icon: "square.grid.3x3", iconColor: .morandiSlate, label: "Per-Core", value: "\(dev.coreSummary) via host_processor_info")
                    DiagnosticRow(icon: "lock.shield", iconColor: .morandiSlate, label: "Privileges", value: "No sudo")
                }
            }

            Text("© 2026 LEEcDiang")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(24)
        }
        .onAppear {
            let batt = tb_read_battery()
            if batt.battery_valid {
                batteryInfo = (batt.ac_connected, Int(batt.battery_percent))
            } else {
                batteryInfo = nil
            }
        }
        .navigationTitle("Diagnostics")
    }

    // MARK: - Device summary card

    private func deviceHeader(_ dev: DeviceProfile) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.morandiBlueDeep, .morandiBlueLight],
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

    // MARK: - Report helpers

    private var storageSummary: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else {
            return "N/A"
        }
        return String(format: "%.0f GB free / %.0f GB", Double(free) / 1_073_741_824, Double(total) / 1_073_741_824)
    }

    private var architecture: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    private var powerSourceLabel: String {
        guard let b = batteryInfo else { return "Unknown" }
        return b.ac ? "AC Power" : "Battery"
    }

    private var powerSourceOK: Bool {
        batteryInfo != nil
    }

    private var batteryLevelLabel: String {
        guard let b = batteryInfo else { return "Unknown" }
        return "\(b.percent)%"
    }

    private var telemetryCoreVersion: String {
        String(cString: tb_telemetry_core_version())
    }
}


