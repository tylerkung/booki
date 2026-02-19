import SwiftUI

/// View displaying the full audit history of changes for a bet
/// Shows timeline of events in reverse chronological order (newest first)
struct BetHistoryView: View {

    // MARK: - Properties

    let betId: UUID

    // MARK: - State

    @State private var auditEvents: [AuditEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // MARK: - Private Properties

    private let auditService = AuditService()

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            if isLoading {
                loadingView
            } else if let errorMessage = errorMessage {
                errorView(errorMessage)
            } else if auditEvents.isEmpty {
                emptyStateView
            } else {
                timelineView
            }
        }
        .navigationTitle("Pick History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchAuditHistory()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                .scaleEffect(1.5)

            Text("Loading history...")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Theme.font(size: 48))
                .foregroundStyle(Theme.danger)

            Text("Failed to load history")
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)

            Text(message)
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await fetchAuditHistory()
                }
            } label: {
                Text("Try Again")
                    .font(Theme.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(Theme.font(size: 48))
                .foregroundStyle(Theme.textMuted)

            Text("No History")
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)

            Text("No changes have been recorded for this pick.")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var timelineView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(auditEvents.enumerated()), id: \.element.id) { index, event in
                    TimelineEventRow(
                        event: event,
                        isFirst: index == 0,
                        isLast: index == auditEvents.count - 1
                    )
                }
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Data Fetching

    private func fetchAuditHistory() async {
        isLoading = true
        errorMessage = nil

        do {
            let events = try await auditService.fetchAuditHistory(entityType: "bet", entityId: betId)
            await MainActor.run {
                self.auditEvents = events
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - Timeline Event Row

private struct TimelineEventRow: View {
    let event: AuditEvent
    let isFirst: Bool
    let isLast: Bool

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.createdAt)
    }

    private var humanReadableAction: String {
        switch event.actionType {
        case "create":
            return "Pick Created"
        case "accept":
            return "Pick Accepted"
        case "grade":
            return "Pick Graded"
        case "settle":
            return "Pick Reconciled"
        case "reverse":
            return "Reconciliation Reversed"
        case "override":
            return "Grade Overridden"
        case "adjust":
            return "Adjustment Made"
        default:
            return event.actionType.capitalized
        }
    }

    private var actionColor: Color {
        switch event.actionType {
        case "create":
            return Theme.accent
        case "accept":
            return Theme.scheduled
        case "grade":
            return Theme.accentSecondary
        case "settle":
            return Theme.win
        case "reverse":
            return Theme.warning
        case "override":
            return Theme.accentTertiary
        case "adjust":
            return Theme.gold
        default:
            return Theme.textSecondary
        }
    }

    private var actionIcon: String {
        switch event.actionType {
        case "create":
            return "plus.circle.fill"
        case "accept":
            return "checkmark.circle.fill"
        case "grade":
            return "star.circle.fill"
        case "settle":
            return "dollarsign.circle.fill"
        case "reverse":
            return "arrow.uturn.backward.circle.fill"
        case "override":
            return "exclamationmark.triangle.fill"
        case "adjust":
            return "slider.horizontal.3"
        default:
            return "circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline line and dot
            VStack(spacing: 0) {
                // Line above (hidden for first item)
                Rectangle()
                    .fill(isFirst ? Color.clear : Theme.border)
                    .frame(width: 2, height: 16)

                // Icon dot
                Image(systemName: actionIcon)
                    .font(Theme.title2)
                    .foregroundStyle(actionColor)

                // Line below (hidden for last item)
                Rectangle()
                    .fill(isLast ? Color.clear : Theme.border)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 32)

            // Event content
            VStack(alignment: .leading, spacing: 8) {
                // Action type badge
                Text(humanReadableAction)
                    .font(Theme.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)

                // Timestamp
                Text(formattedTimestamp)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)

                // Reason (if present)
                if let reason = event.reason, !reason.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "quote.opening")
                            .font(Theme.caption2)
                            .foregroundStyle(Theme.textMuted)

                        Text(reason)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .italic()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 12)
            .padding(.trailing, 16)

            Spacer()
        }
        .padding(.horizontal, 16)
        .background(Theme.cardBackground)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BetHistoryView(betId: UUID())
    }
}

#Preview("With Events") {
    NavigationStack {
        BetHistoryView(betId: UUID())
    }
}
