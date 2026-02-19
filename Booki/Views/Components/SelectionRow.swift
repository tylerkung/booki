import SwiftUI

/// Reusable row view for displaying a single selection (bet leg) with consistent formatting.
struct SelectionRow: View {
    let selectionLabel: String
    let odds: Int
    let eventName: String
    var league: String? = nil
    var gradeResult: GradeResult? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let result = gradeResult {
                Circle()
                    .fill(gradeColor(result))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Line 1: selection + odds
                Text("\(selectionLabel) (\(PickPresenter.formatOdds(odds)))")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textPrimary)

                // Line 2: league · event
                Text(contextText)
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Private

    private var contextText: String {
        if let league = league, !league.isEmpty {
            return "\(league) · \(eventName)"
        }
        return eventName
    }

    private func gradeColor(_ result: GradeResult) -> Color {
        switch result {
        case .win:  return Theme.accent
        case .loss: return Theme.danger
        case .push: return Theme.textMuted
        }
    }
}
