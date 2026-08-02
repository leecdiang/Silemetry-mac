// ThermalBench - Live Test View
import SwiftUI
import Charts
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// @MainActor: this view reads @MainActor AppModel/TestCoordinator state from
/// computed properties outside body. The View protocol is only globally
/// @MainActor on newer SDKs, so without the annotation Xcode 15.x (SDK 14.5)
/// rejects those accesses as actor-isolation violations.
@MainActor
struct TestView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @State private var showStopConfirm = false
    @State private var showCancelConfirm = false
    @State private var failureMessage: String?
    @State private var showFailure = false
    /// Run that finished but could not be persisted — drives the save-failure sheet.
    @State private var pendingRun: RunRecord?
    @State private var showSaveFailure = false
    @State private var exportConfirmation: String?

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
            // Content (single page: charts + per-core utilization)
            overviewContent
            // Bottom bar
            bottomBar
        }
        .navigationTitle("Active Test")
        .onChange(of: coord.state) { _, newState in
            if case .complete(let run) = newState {
                // Only save if there are valid samples
                guard run.sampleCount > 0, run.duration > 0 else {
                    goHome()
                    return
                }
                persistRun(run)
            }
            if case .cancelled(let run) = newState {
                // Stopped with data — persist the coordinator-built final record.
                guard run.sampleCount > 0, run.duration > 0 else {
                    goHome()
                    return
                }
                persistRun(run)
            }
            if case .discarded = newState {
                // Explicitly discarded — nothing to persist.
                goHome()
            }
            if case .failed(let message) = newState {
                // Telemetry failure. The coordinator cleaned up and finalized
                // through the unified flow; offer Save Partial Run / Discard
                // when a partial record was captured.
                failureMessage = message
                showFailure = true
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
            powerMetric
            freqMetric
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

    /// Power metric follows the active workload: CPU Only → CPU power,
    /// GPU Only → GPU power, Combined → package power (CPU fallback).
    @ViewBuilder
    var powerMetric: some View {
        switch coord.testConfig.workloadType {
        case .cpuOnly:
            metricItem("CPU Power", value: powerStr(coord.latest?.cpuPower))
        case .gpuOnly:
            metricItem("GPU Power", value: powerStr(coord.latest?.gpuPower))
        case .combined:
            if let pkg = coord.latest?.packagePower {
                metricItem("Package Power", value: powerStr(pkg))
            } else {
                metricItem("CPU Power", value: powerStr(coord.latest?.cpuPower))
            }
        }
    }

    /// Frequency metric is load-relevant for CPU-bearing workloads only.
    @ViewBuilder
    var freqMetric: some View {
        if coord.testConfig.workloadType != .gpuOnly {
            metricItem("P-Core", value: freqStr(coord.latest?.pClusterFreqMHz))
        }
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
                if coord.archiveError != nil {
                    Label("Raw sample archive incomplete", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                        .help(coord.archiveError ?? "")
                }
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
            Button("Discard", role: .destructive) { discardTest() }
        } message: {
            Text("Data will not be saved.")
        }
        .alert("Test Failed", isPresented: $showFailure) {
            if coord.partialRun != nil {
                Button("Save Partial Run") { savePartialRun() }
                Button("Discard", role: .destructive) { discardFailedRun() }
            } else {
                Button("OK") { goHome() }
            }
        } message: {
            Text(failureMessage ?? "Unknown failure")
        }
        .sheet(isPresented: $showSaveFailure) {
            saveFailureSheet
        }
    }

    // MARK: - Save-Failure Handling

    /// The test finished, but its record could not be saved. Offer Retry,
    /// Export Raw Data, or Discard instead of silently landing on a Results
    /// page that cannot re-fetch the run.
    var saveFailureSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("The test finished, but its record could not be saved.")
                .font(.headline)
                .multilineTextAlignment(.center)
            if let exportConfirmation {
                Text(exportConfirmation)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button { exportRawData() } label: {
                    Label("Export Raw Data", systemImage: "square.and.arrow.up")
                }
                Button { retryPersist() } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) { discardPending() } label: {
                    Label("Discard", systemImage: "trash")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(28)
        .frame(width: 440)
    }

    private func goHome() {
        app.route = .home
        app.resetForNewRun()
    }

    /// Persist a finished run; only navigate to Results when the save
    /// actually succeeds. On failure the context is rolled back so the failed
    /// insert cannot be flushed by an unrelated save() later — the record
    /// stays detached for Retry / Export / Discard.
    private func persistRun(_ run: RunRecord) {
        modelContext.insert(run)
        do {
            try modelContext.save()
            app.route = .result(run.uuid)
        } catch {
            print("[PERSIST] save error: \(error)")
            modelContext.rollback()
            pendingRun = run
            showSaveFailure = true
        }
    }

    private func retryPersist() {
        guard let run = pendingRun else {
            showSaveFailure = false
            return
        }
        // Re-insert: the failed attempt was rolled back, so the record is
        // detached and safe to insert again.
        modelContext.insert(run)
        do {
            try modelContext.save()
            pendingRun = nil
            showSaveFailure = false
            app.route = .result(run.uuid)
        } catch {
            print("[PERSIST] retry save error: \(error)")
            modelContext.rollback()
            // Keep the sheet up — the record is still unsaved.
        }
    }

    private func discardPending() {
        guard let run = pendingRun else {
            showSaveFailure = false
            goHome()
            return
        }
        // The failed save was rolled back, so the record is not registered in
        // the context — nothing to delete there, just remove its sample files.
        SampleArchive.deleteFiles(for: run)
        pendingRun = nil
        showSaveFailure = false
        goHome()
    }

    /// Copy the raw JSONL out so the data survives even if the DB record
    /// cannot.
    private func exportRawData() {
        guard let run = pendingRun else { return }
        let panel = NSSavePanel()
        panel.title = "Export Raw Data"
        panel.nameFieldStringValue = "\(run.name)-samples.jsonl"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            do {
                let src = SampleArchive.samplesFile(for: run.uuid).path
                if FileManager.default.fileExists(atPath: src) {
                    try FileManager.default.copyItem(atPath: src, toPath: dest.path)
                } else if run.dataDirectory.hasPrefix("/"), FileManager.default.fileExists(atPath: run.dataDirectory) {
                    try FileManager.default.copyItem(atPath: run.dataDirectory, toPath: dest.path)
                } else {
                    throw NSError(domain: "ThermalBench", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "No raw sample file was written for this run."])
                }
                exportConfirmation = "Exported: \(dest.lastPathComponent)"
            } catch {
                exportConfirmation = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    /// Failure with captured samples — keep the partial record.
    private func savePartialRun() {
        guard let run = coord.partialRun else {
            goHome()
            return
        }
        persistRun(run)
    }

    /// Failure — user chose to discard the partial data.
    private func discardFailedRun() {
        if let run = coord.partialRun {
            SampleArchive.deleteFiles(for: run)
        }
        goHome()
    }

    // MARK: - Helpers

    // MARK: - Overview Content

    var overviewContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                chartCard("Temperature (°C)", empty: !hasValidTemp) { tempChart }
                chartCard("Power (W)", empty: !hasValidPower) { powerChart }
                chartCard("Frequency (GHz)", empty: !hasValidFreq) { freqChart }
                // Per-core utilization card (replaces the thermal state card)
                GroupBox {
                    coreUtilizationCard
                } label: {
                    Label("Per-Core Utilization", systemImage: "cpu")
                }
                .frame(minHeight: 100)
            }
            .padding(16)
        }
    }

    var coreUtilizationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            let cores = latestSampleCores
            if cores.isEmpty {
                Text("Waiting for first per-core sample...")
                    .foregroundStyle(.secondary).padding(.vertical, 4)
            } else {
                Text("Efficiency").font(.caption2).foregroundStyle(.secondary)
                ForEach(cores.filter { $0.kind == .efficiency }) { core in
                    coreBar(core: core)
                }
                Divider().padding(.vertical, 2)
                Text("Performance").font(.caption2).foregroundStyle(.secondary)
                ForEach(cores.filter { $0.kind == .performance }) { core in
                    coreBar(core: core)
                }
            }
            Divider().padding(.vertical, 2)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                clusterItem("P Freq", latestPCluFreqStr)
                clusterItem("E Freq", latestECluFreqStr)
                clusterItem("P Util", latestPUtilStr)
                clusterItem("E Util", latestEUtilStr)
            }
        }
    }

    func clusterItem(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospaced()).bold()
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
        let ps = coord.latest?.perCoreUtilization.filter { $0.kind == .performance && $0.valid }
        guard let ps, !ps.isEmpty else { return "--" }
        let vals = ps.compactMap(\.utilizationPercent)
        guard !vals.isEmpty else { return "--" }
        return String(format: "%.1f%%", vals.reduce(0, +) / Double(vals.count))
    }
    var latestEUtilStr: String {
        let es = coord.latest?.perCoreUtilization.filter { $0.kind == .efficiency && $0.valid }
        guard let es, !es.isEmpty else { return "--" }
        let vals = es.compactMap(\.utilizationPercent)
        guard !vals.isEmpty else { return "--" }
        return String(format: "%.1f%%", vals.reduce(0, +) / Double(vals.count))
    }

    func coreBar(core: PerCoreUtilization) -> some View {
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
        // Stop and keep data: coordinator builds the final RunRecord and the
        // onChange handler persists it. Do NOT reset the coordinator here.
        coord.stopAndSave()
    }

    func discardTest() {
        // Discard everything: nothing is persisted.
        coord.cancelAndDiscard()
    }

    func metricItem(_ label: String, value: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(.body, design: .monospaced)).bold()
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    var hasValidTemp: Bool {
        samples.contains(where: { $0.cpuTemp != nil || $0.cpuTempHottest != nil || $0.gpuTemp != nil || $0.gpuTempHottest != nil })
    }
    var hasValidPower: Bool {
        samples.contains(where: { $0.cpuPowerValid || $0.gpuPowerValid || $0.cpuPower != nil || $0.gpuPower != nil })
    }
    var hasValidFreq: Bool {
        samples.contains(where: { $0.pFrequencyValid || $0.eFrequencyValid || $0.pClusterFreqMHz != nil || $0.eClusterFreqMHz != nil })
    }

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
