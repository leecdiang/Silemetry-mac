// ThermalBench - Home View
import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var showConfirm = false
    @State private var showCustomConfig = false

    var body: some View {
        @Bindable var b = app
        ScrollView {
            VStack(spacing: 24) {
                deviceSummary
                testPresets
                if app.coordinator.state != .idle {
                    activeRunBanner
                }
                recentRunsSection
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("ThermalBench")
        .alert("Ready to start?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Start") { startTest(mode: selectedMode) }
        } message: {
            Text(modeDescription(selectedMode))
        }
        .sheet(isPresented: $showCustomConfig) {
            CustomTestConfigView { config in
                app.coordinator = TestCoordinator()
                Task { await app.coordinator.start(config: config) }
                app.route = .activeTest
            }
        }
    }

    // MARK: - Device Summary

    var deviceSummary: some View {
        let dev = DeviceProfile.current
        return HStack(spacing: 32) {
            // Left: device info
            VStack(alignment: .leading, spacing: 4) {
                Text(dev.chipName).font(.title2).bold()
                Text(dev.coreSummary + " · " + dev.formattedMemory).foregroundStyle(.secondary)
                Text(dev.macOSVersion).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            // Right: power & thermal
            VStack(alignment: .trailing, spacing: 4) {
                powerBadge
                thermalBadge
            }
        }
        .padding(20)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    var powerBadge: some View {
        BatteryStatusIcon(
            source: app.powerSource,
            lowPowerMode: app.lowPowerMode
        )
    }

    var thermalBadge: some View {
        @Bindable var b = app
        return HStack(spacing: 6) {
            Circle().fill(thermalColor).frame(width: 8, height: 8)
            Text(thermalText).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    var thermalColor: Color {
        switch app.thermalStateTag {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        default: .gray
        }
    }

    var thermalText: String {
        switch app.thermalStateTag {
        case .nominal: "Thermal: Nominal"
        case .fair: "Thermal: Fair"
        case .serious: "Thermal: Serious"
        case .critical: "Thermal: Critical"
        default: "Thermal: Unknown"
        }
    }

    // MARK: - Test Presets

    @State private var selectedMode = TestMode.quickCheck

    var testPresets: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240))], spacing: 12) {
            ForEach(TestMode.allCases, id: \.rawValue) { mode in
                Button {
                    if mode == .custom {
                        showCustomConfig = true
                    } else {
                        selectedMode = mode
                        showConfirm = true
                    }
                } label: {
                    presetCard(mode)
                }
                .buttonStyle(.plain)
            }
        }
    }

    func presetCard(_ mode: TestMode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconFor(mode))
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName).font(.headline)
                Text(modeDescription(mode)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(mode == .standard ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1)
        )
    }

    func iconFor(_ mode: TestMode) -> String {
        switch mode {
        case .quickCheck: "gauge.with.needle"
        case .standard: "speedometer"
        case .sustained: "clock.arrow.2.circlepath"
        case .extended: "clock.badge.checkmark"
        case .custom: "slider.horizontal.3"
        case .monitorOnly: "eye"
        }
    }

    func modeDescription(_ mode: TestMode) -> String {
        switch mode {
        case .quickCheck: "~1 min • Verify sensors"
        case .standard: "~23 min • 15 min load"
        case .sustained: "~45 min • 30 min load"
        case .extended: "~80 min • 60 min load"
        case .custom: "Custom parameters"
        case .monitorOnly: "No load • external workload"
        }
    }

    // MARK: - Active Run Banner

    var activeRunBanner: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Test in progress").font(.headline)
                Text("Continue watching live data").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {
                app.route = .activeTest
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Recent Runs

    @Query(sort: \RunRecord.createdAt, order: .reverse) private var runs: [RunRecord]

    var recentRunsSection: some View {
        Group {
            if !runs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Tests").font(.headline)
                    ForEach(runs.prefix(3)) { run in
                        Button {
                            app.route = .result(run.uuid)
                        } label: {
                            HStack {
                                Text(run.name).lineLimit(1)
                                Spacer()
                                Text(run.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func startTest(mode: TestMode) {
        let config: TestConfiguration
        switch mode {
        case .quickCheck:
            config = TestConfiguration(mode: .quickCheck, idleDuration: 10, loadDuration: 25,
                                        transitionDuration: 3, cooldownDuration: 10)
        case .standard:
            config = TestConfiguration(mode: .standard, idleDuration: 180, loadDuration: 900,
                                        transitionDuration: 5, cooldownDuration: 300)
        case .sustained:
            config = TestConfiguration(mode: .sustained, idleDuration: 300, loadDuration: 1800,
                                        transitionDuration: 5, cooldownDuration: 600)
        case .extended:
            config = TestConfiguration(mode: .extended, idleDuration: 300, loadDuration: 3600,
                                        transitionDuration: 5, cooldownDuration: 900)
        case .custom:
            config = TestConfiguration(mode: .custom, idleDuration: 60, loadDuration: 300,
                                        transitionDuration: 5, cooldownDuration: 60)
        case .monitorOnly:
            config = TestConfiguration(mode: .monitorOnly, cpuThreads: 0, gpuIntensity: .off,
                                        idleDuration: 0, loadDuration: 0,
                                        transitionDuration: 0, cooldownDuration: 0)
        }
        app.coordinator = TestCoordinator()
        Task { await app.coordinator.start(config: config) }
        app.route = .activeTest
    }
}
