// ThermalBench - Shared App Model
import SwiftUI
import SwiftData

@Observable
@MainActor
final class AppModel {
    enum Route: Hashable {
        case home, activeTest, result(String), history, compare, diagnostics
    }
    var route: Route = .home

    var powerSource: PowerSource = .charging(batteryPercent: 100)
    var lowPowerMode: Bool = false
    var thermalStateTag: ThermalStateTag = .nominal

    var coordinator = TestCoordinator()

    init() { startPowerMonitor() }

    func resetForNewRun() { coordinator = TestCoordinator() }

    private func startPowerMonitor() {
        let _ = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let batt = tb_read_battery()
                if !batt.battery_valid {
                    powerSource = .unavailable
                } else if batt.ac_connected {
                    powerSource = .charging(batteryPercent: Int(max(0, batt.battery_percent)))
                } else {
                    powerSource = .onBattery(batteryPercent: Int(max(0, batt.battery_percent)))
                }
                lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                let ts = ProcessInfo.processInfo.thermalState
                switch ts {
                case .nominal: thermalStateTag = .nominal
                case .fair: thermalStateTag = .fair
                case .serious: thermalStateTag = .serious
                case .critical: thermalStateTag = .critical
                @unknown default: thermalStateTag = .unknown
                }
            }
        }
    }
}
