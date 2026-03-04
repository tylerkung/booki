import SwiftUI
import SwiftData

/// Persistent app header showing logo and balance
/// Used across player mode tabs (Games, Search, Track, Account)
struct AppHeaderView: View {
    let player: Player
    let balance: Decimal
    var title: String? = nil
    var showBalance: Bool = true

    /// Callback when logo is tapped (navigate to Games tab)
    var onLogoTap: (() -> Void)?

    // MARK: - Computed Properties

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
        Theme.formatCurrency(balance)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Center: Title (if provided)
            if let title {
                Text(title)
                    .font(Theme.font(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack(spacing: 12) {
                // Left side: App logo
                Button(action: { onLogoTap?() }) {
                    Image("BookiWordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 24)
                }
                .buttonStyle(.plain)

                Spacer()

                // Right side: Balance (optional)
                if showBalance {
                    balanceSection
                }
            }
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
            onLogoTap: { print("Logo tapped") }
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
            onLogoTap: { print("Logo tapped") }
        )

        Spacer()
    }
    .background(Theme.background)
}
