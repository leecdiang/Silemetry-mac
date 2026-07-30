// ThermalBench - Main App Entry Point
import SwiftUI
import SwiftData

@main
struct ThermalBenchApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([RunRecord.self])
            let config = ModelConfiguration("ThermalBench", groupContainer: .none)
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("SwiftData init: \(error)")
        }
    }

    var body: some Scene {
        Window("Silemetry", id: "main") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(modelContainer)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
