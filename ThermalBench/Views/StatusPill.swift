// ThermalBench - Unified Status Capsule
// Single-source pill component for phase/status badges.
// Prevents text wrapping via lineLimit(1) + fixedSize, adapts to content width,
// and falls back to short labels in tight layouts via ViewThatFits.
import SwiftUI

struct StatusPill: View {
    let label: String
    let shortLabel: String?
    let color: Color
    let dotSize: CGFloat

    var body: some View {
        ViewThatFits {
            // Primary: full label
            pillContent(text: label)
            // Fallback: short label (if available)
            if let short = shortLabel {
                pillContent(text: short)
            }
        }
        .layoutPriority(1)
    }

    private func pillContent(text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: dotSize, height: dotSize)
            Text(text)
                .font(.subheadline)
                .bold()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}

// MARK: - Phase-specific helpers

extension StatusPill {
    /// Build a pill for a test phase.
    init(phase: TestPhase?, isMonitorOnly: Bool) {
        if isMonitorOnly {
            self.init(
                label: "Monitoring",
                shortLabel: "Mon",
                color: .green,
                dotSize: 8
            )
            return
        }
        guard let p = phase else {
            self.init(label: "?", shortLabel: "?", color: .gray, dotSize: 8)
            return
        }
        self.init(
            label: p.displayLabel,
            shortLabel: p.shortLabel,
            color: p.pillColor,
            dotSize: 8
        )
    }
}

extension TestPhase {
    var displayLabel: String {
        switch self {
        case .idle:        "Idle"
        case .preflight:   "Preflight"
        case .baseline:    "Baseline"
        case .monitoringExternal: "External Load"
        case .loading:     "CPU Load"
        case .transition:  "Transition"
        case .cooling:     "Cooldown"
        case .analyzing:   "Analyzing"
        case .completed:   "Completed"
        case .cancelled:   "Cancelled"
        case .failed:      "Failed"
        }
    }

    var shortLabel: String {
        switch self {
        case .idle:        "Idle"
        case .preflight:   "Check"
        case .baseline:    "Base"
        case .monitoringExternal: "Ext"
        case .loading:     "Load"
        case .transition:  "Trans"
        case .cooling:     "Cool"
        case .analyzing:   "Analysis"
        case .completed:   "Done"
        case .cancelled:   "Cancel"
        case .failed:      "Fail"
        }
    }

    var pillColor: Color {
        switch self {
        case .baseline:   .blue
        case .monitoringExternal: .teal
        case .loading:    .red
        case .transition: .orange
        case .cooling:    .green
        case .preflight:  .indigo
        case .analyzing:  .purple
        case .completed:  .green
        case .cancelled:  .orange
        case .failed:     .red
        case .idle:       .gray
        }
    }
}
