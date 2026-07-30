// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThermalBench",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ThermalBench", targets: ["ThermalBench"])
    ],
    targets: [
        .executableTarget(
            name: "ThermalBench",
            path: "ThermalBench",
            exclude: ["Resources", "Localizations", "Assets.xcassets"],
            sources: ["App", "Models", "Views", "Services", "Telemetry", "Workload", "Analysis", "Persistence", "Export", "Diagnostics"],
            linkerSettings: [
                .linkedLibrary("TelemetryCore"),
                .unsafeFlags(["-L\(Context.packageDirectory)/build"]),
            ]
        ),
    ]
)
