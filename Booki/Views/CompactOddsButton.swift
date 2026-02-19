import SwiftUI

/// US-005 / US-011: Compact Odds Button Component
/// A streamlined odds button with minimal styling for table-style layouts
/// Used by CompactGameRow and GameDetailView
///
/// Typography hierarchy (US-005):
/// - Primary line (spread/total value, team name): Large, white (Theme.textPrimary)
/// - Secondary line (payout odds): Smaller, gray (Theme.textMuted) - only for spread/total
struct CompactOddsButton: View {
    /// Optional top text (spread value, total value, or team name)
    /// For spread/total: This is the primary value displayed prominently
    /// For moneyline: This is the team name displayed as secondary
    let topText: String?

    /// American odds value
    let odds: Int

    /// Whether this button is currently selected
    let isSelected: Bool

    /// Whether this button is disabled (e.g., event locked)
    var isDisabled: Bool = false

    /// Whether to show odds as secondary text (used for spread/total buttons)
    /// When true: topText is primary (large, white), odds is secondary (small, gray)
    /// When false: odds is primary, topText is secondary (for moneyline with team names)
    var showOddsAsSecondary: Bool = false

    /// Action when tapped
    let action: () -> Void

    /// Formatted odds string
    private var formattedOdds: String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    var body: some View {
        Button(action: {
            guard !isDisabled else { return }
            action()
        }) {
            VStack(spacing: 2) {
                if showOddsAsSecondary {
                    // US-005: Spread/Total style - line value prominent, odds de-emphasized
                    if let text = topText {
                        Text(text)
                            .font(Theme.monoDigits(size: 13, weight: .bold))
                            .foregroundColor(isSelected ? Theme.background : Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(formattedOdds)
                        .font(Theme.monoDigits(size: 10, weight: .medium))
                        .foregroundColor(isSelected ? Theme.background.opacity(0.7) : Theme.textMuted)
                } else {
                    // Original style - used for moneyline (team name secondary, odds primary)
                    if let text = topText {
                        Text(text)
                            .font(Theme.font(size: 11, weight: .medium))
                            .foregroundColor(isSelected ? Theme.background : Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(formattedOdds)
                        .font(Theme.monoDigits(size: 13, weight: .bold))
                        .foregroundColor(isSelected ? Theme.background : Theme.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isSelected ? Theme.accent : Theme.elevatedBackground)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: 1)
            )
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isSelected)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // US-005: Spread buttons - line value prominent, odds secondary
        Text("Spread (US-005)")
            .font(Theme.caption)
            .foregroundColor(Theme.textSecondary)
        HStack(spacing: 8) {
            CompactOddsButton(
                topText: "-3.5",
                odds: -110,
                isSelected: false,
                showOddsAsSecondary: true,
                action: {}
            )
            .frame(width: 80, height: 44)

            CompactOddsButton(
                topText: "+3.5",
                odds: -118,
                isSelected: true,
                showOddsAsSecondary: true,
                action: {}
            )
            .frame(width: 80, height: 44)
        }

        // Moneyline buttons - odds prominent (no secondary needed)
        Text("Moneyline")
            .font(Theme.caption)
            .foregroundColor(Theme.textSecondary)
        HStack(spacing: 8) {
            CompactOddsButton(
                topText: "Lakers",
                odds: -170,
                isSelected: false,
                action: {}
            )
            .frame(width: 80, height: 44)

            CompactOddsButton(
                topText: "Celtics",
                odds: 150,
                isSelected: false,
                action: {}
            )
            .frame(width: 80, height: 44)
        }

        // US-005: Total buttons - line value prominent, odds secondary
        Text("Total (US-005)")
            .font(Theme.caption)
            .foregroundColor(Theme.textSecondary)
        HStack(spacing: 8) {
            CompactOddsButton(
                topText: "O 220.5",
                odds: -110,
                isSelected: false,
                showOddsAsSecondary: true,
                action: {}
            )
            .frame(width: 80, height: 44)

            CompactOddsButton(
                topText: "U 220.5",
                odds: -110,
                isSelected: true,
                showOddsAsSecondary: true,
                action: {}
            )
            .frame(width: 80, height: 44)
        }

        // Disabled button
        CompactOddsButton(
            topText: "-3.5",
            odds: -110,
            isSelected: false,
            isDisabled: true,
            showOddsAsSecondary: true,
            action: {}
        )
        .frame(width: 80, height: 44)
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
