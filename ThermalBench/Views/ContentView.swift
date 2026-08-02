// ThermalBench - ContentView with proper navigation
import SwiftUI
import SwiftData

/// @MainActor: binds @MainActor AppModel state (sidebar selection, route)
/// from computed properties outside body — required on Xcode 15.x where View
/// is not yet globally @MainActor.
@MainActor
struct ContentView: View {
    @State private var appModel = AppModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .environment(appModel)
    }

    var sidebar: some View {
        List(selection: Binding(
            get: { appModel.route },
            set: { appModel.route = $0 }
        )) {
            Label("Home", systemImage: "house").tag(AppModel.Route.home)
            Label("History", systemImage: "clock.arrow.circlepath").tag(AppModel.Route.history)
            Label("Compare", systemImage: "arrow.left.arrow.right").tag(AppModel.Route.compare)
            Label("Diagnostics", systemImage: "stethoscope").tag(AppModel.Route.diagnostics)
        }
        .listStyle(.sidebar)
        .navigationTitle("Silemetry")
    }

    @ViewBuilder
    var detailView: some View {
        switch appModel.route {
        case .home:
            HomeView()
        case .activeTest:
            TestView()
        case .result(let runID):
            if let run = fetchRun(uuid: runID) {
                ResultsView(run: run)
            } else {
                Text("Run not found").padding()
            }
        case .history:
            HistoryView()
        case .compare:
            CompareView()
        case .diagnostics:
            DiagnosticsView()
        }
    }

    private func fetchRun(uuid: String) -> RunRecord? {
        var desc = FetchDescriptor<RunRecord>(
            predicate: #Predicate { $0.uuid == uuid }
        )
        desc.fetchLimit = 1
        return try? modelContext.fetch(desc).first
    }
}
