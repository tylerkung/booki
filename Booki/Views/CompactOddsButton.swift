import SwiftUI

/// US-005 / US-011: Compact Odds Button Component
/// A streamlined odds button with minimal styling for table-style layouts
/// Used by CompactGameRow and GameDetailView
struct CompactOddsButton: View {
    /// Optional top text (spread value, total value, or team name)
    let topText: String?

    /// American odds value
    let odds: Int

    /// Whether this button is currently selected
    let isSelected: Bool

    /// Whether this button is disabled (e.g., event locked)
    var isDisabled: Bool = false

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
                if let text = topText {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isSelected ? Theme.background : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(formattedOdds)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isSelected ? Theme.background : Theme.textPrimary)
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
        HStack(spacing: 8) {
            // Unselected spread button
            CompactOddsButton(
                topText: "-3.5",
                odds: -110,
                isSelected: false,
                action: {}
            )
            .frame(width: 80, height: 44)

            // Selected spread button
            CompactOddsButton(
                topText: "+3.5",
                odds: -110,
                isSelected: true,
                action: {}
            )
            .frame(width: 80, height: 44)
        }

        HStack(spacing: 8) {
            // Moneyline buttons
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

        HStack(spacing: 8) {
            // Total buttons
            CompactOddsButton(
                topText: "O 220.5",
                odds: -110,
                isSelected: false,
                action: {}
            )
            .frame(width: 80, height: 44)

            CompactOddsButton(
                topText: "U 220.5",
                odds: -110,
                isSelected: true,
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
            action: {}
        )
        .frame(width: 80, height: 44)
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
