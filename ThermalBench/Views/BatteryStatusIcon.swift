// ThermalBench - Reusable Battery Status Icon
// Single component for Home, Active Test, and Results views.
// Reads power source and percentage from AppModel; handles charging,
// low battery, and Low Power Mode display.
import SwiftUI

enum PowerSource: Equatable {
    case unavailable
    case charging(batteryPercent: Int)
    case onBattery(batteryPercent: Int)
}

// MARK: - Battery Status Icon

struct BatteryStatusIcon: View {
    let source: PowerSource
    let lowPowerMode: Bool

    var body: some View {
        HStack(spacing: 4) {
            switch source {
            case .unavailable:
                Image(systemName: "battery.slash")
                    .foregroundStyle(.secondary)
                Text("Battery Unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

            case .charging(let pct):
                let p = Self.clampFraction(pct)
                Image(systemName: "battery.100", variableValue: p)
                    .foregroundStyle(.green)
                Text("Charging (\(pct)%)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if lowPowerMode { Self.lpmLabel }

            case .onBattery(let pct):
                let p = Self.clampFraction(pct)
                let color = Self.batteryDisplayColor(percent: pct)
                Image(systemName: "battery.100", variableValue: p)
                    .foregroundStyle(color)
                Text("Battery (\(pct)%)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if lowPowerMode { Self.lpmLabel }
            }
        }
    }

    // MARK: - Helpers

    private static func clampFraction(_ percent: Int) -> Double {
        min(max(Double(percent) / 100.0, 0.0), 1.0)
    }

    /// Color based on battery level (NOT on whether discharging).
    /// - >20%: secondary (neutral)
    /// - ≤20%: orange (warning)
    /// - ≤10%: red (critical)
    private static func batteryDisplayColor(percent: Int) -> Color {
        if percent <= 10 { return .red }
        if percent <= 20 { return .orange }
        return .secondary
    }

    private static var lpmLabel: some View {
        HStack(spacing: 2) {
            Image(systemName: "leaf.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text("Low Power")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }
}
