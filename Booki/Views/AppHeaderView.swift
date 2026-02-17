import SwiftUI
import SwiftData

/// Persistent app header showing user profile and balance
/// Used across player mode tabs (Games, Track, Settings)
struct AppHeaderView: View {
    let player: Player
    let balance: Decimal

    /// Whether navigation to account is enabled (tappable user section)
    var navigateToAccount: (() -> Void)?

    // MARK: - Computed Properties

    /// User initials for avatar
    private var userInitials: String {
        let components = player.name.split(separator: " ")
        if components.count >= 2 {
            // First letter of first name + first letter of last name
            let first = components[0].prefix(1).uppercased()
            let last = components[1].prefix(1).uppercased()
            return first + last
        } else if let firstComponent = components.first, firstComponent.count >= 2 {
            // First 2 letters if single name
            return String(firstComponent.prefix(2)).uppercased()
        } else if let firstComponent = components.first {
            // Just first letter if name is only 1 character
            return String(firstComponent.prefix(1)).uppercased()
        }
        return "?"
    }

    /// Color for the avatar background based on name hash
    private var avatarColor: Color {
        let colors: [Color] = [
            Theme.accent,
            Theme.accentSecondary,
            Theme.accentTertiary,
            Theme.gold,
            Theme.scheduled
        ]
        let hash = abs(player.name.hashValue)
        return colors[hash % colors.count]
    }

    /// Color for balance display
    /// Positive balance = player is in credit (green - bookie owes player)
    /// Negative balance = player owes bookie (red - player is in debt)
    /// Zero = neutral
    private var balanceColor: Color {
        if balance > 0 {
            return Theme.accent
        } else if balance < 0 {
            return Theme.danger
        } else {
            return Theme.textSecondary
        }
    }

    /// Formatted balance string
    private var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: balance as NSDecimalNumber) ?? "$\(balance)"
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Left side: Tappable user section
            if let navigate = navigateToAccount {
                Button(action: navigate) {
                    userSection
                }
                .buttonStyle(.plain)
            } else {
                userSection
            }

            Spacer()

            // Right side: Balance (not tappable)
            balanceSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.cardBackground)
        .overlay(
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - User Section (Left Side)

    private var userSection: some View {
        HStack(spacing: 12) {
            // Circular avatar with initials
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(avatarColor)
                    .frame(width: 36, height: 36)
                    .opacity(0.8)
                Text(userInitials)
                    .font(Theme.font(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Player name
            Text(player.name)
                .font(Theme.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            // Chevron to indicate tappable (only if navigable)
            if navigateToAccount != nil {
                Image(systemName: "chevron.right")
                    .font(Theme.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    // MARK: - Balance Section (Right Side)

    private var balanceSection: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(formattedBalance)
                .font(Theme.font(size: 18, weight: .bold))
                .foregroundStyle(balanceColor)
        }
    }
}

// MARK: - Preview

#Preview("App Header - Positive Balance") {
    VStack(spacing: 0) {
        AppHeaderView(
            player: Player(name: "John Smith", creditLimit: 1000),
            balance: 250.00,
            navigateToAccount: { print("Navigate to account") }
        )

        Spacer()
    }
    .background(Theme.background)
}

#Preview("App Header - Negative Balance") {
    VStack(spacing: 0) {
        AppHeaderView(
            player: Player(name: "Jane Doe", creditLimit: 1000),
            balance: -150.00,
            navigateToAccount: { print("Navigate to account") }
        )

        Spacer()
    }
    .background(Theme.background)
}

#Preview("App Header - Zero Balance") {
    VStack(spacing: 0) {
        AppHeaderView(
            player: Player(name: "Mike", creditLimit: 1000),
            balance: 0,
            navigateToAccount: { print("Navigate to account") }
        )

        Spacer()
    }
    .background(Theme.background)
}
