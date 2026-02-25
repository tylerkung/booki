import SwiftUI

/// Reusable status pill that renders settlement/workflow status with consistent colors.
struct StatusPill: View {
    let settlementStatus: PickPresenter.SettlementStatus
    var workflowStatus: PickPresenter.WorkflowStatus? = nil

    var body: some View {
        VStack(spacing: 2) {
            if workflowStatus == .rejected {
                pillView(label: "Rejected", color: Theme.danger)
            } else {
                pillView(label: settlementStatus.label, color: statusColor)
                if workflowStatus == .pending {
                    Text("Pending")
                        .font(Theme.bodyFont(size: 10, weight: .medium))
                        .foregroundStyle(Theme.warning)
                }
            }
        }
    }

    // MARK: - Private

    private var statusColor: Color {
        switch settlementStatus {
        case .open:      return Theme.scheduled
        case .won:       return Theme.accent
        case .lost:      return Theme.danger
        case .push:      return Theme.textMuted
        case .void:      return Theme.textMuted
        case .cancelled: return Theme.textMuted
        }
    }

    @ViewBuilder
    private func pillView(label: String, color: Color) -> some View {
        Text(label.uppercased())
            .font(Theme.font(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}
