import SwiftUI
import SwiftData

/// Filter options for transaction history
enum TransactionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case settlements = "Graded"
    case adjustments = "Adjustments"
    case payments = "Settled"

    var id: String { rawValue }

    /// Matching EntryType for filtering (nil = all types)
    var entryType: EntryType? {
        switch self {
        case .all: return nil
        case .settlements: return .settlement
        case .adjustments: return .adjustment
        case .payments: return .paymentLogged
        }
    }
}

/// Odds format preference for displaying betting odds
enum OddsFormat: String, CaseIterable, Identifiable {
    case american = "American"
    case decimal = "Decimal"
    case fractional = "Fractional"

    var id: String { rawValue }
}

/// Enhanced account summary view for players showing balance, credit utilization, and quick stats
struct AccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allBets: [Bet]
    @Query private var allLedgerEntries: [LedgerEntry]
    let player: Player

    @State private var showingLogoutConfirmation = false
    @State private var showingLogoutError = false
    @State private var logoutErrorMessage = ""
    @State private var selectedTransactionFilter: TransactionFilter = .all
    @AppStorage("playerOddsFormat") private var oddsFormat: String = OddsFormat.american.rawValue
    @AppStorage("playerNotificationsEnabled") private var notificationsEnabled: Bool = true

    // MARK: - Computed Properties

    private var playerBets: [Bet] {
        allBets.filter { $0.player?.id == player.id }
    }

    private var playerLedgerEntries: [LedgerEntry] {
        allLedgerEntries.filter { $0.player?.id == player.id }
    }

    private var filteredLedgerEntries: [LedgerEntry] {
        let sorted = playerLedgerEntries.sorted { $0.createdAt > $1.createdAt }
        guard let entryType = selectedTransactionFilter.entryType else { return sorted }
        return sorted.filter { $0.type == entryType }
    }

    private var balanceSummary: PlayerBalanceSummary {
        BalanceService.playerSummary(for: player, bets: playerBets, ledgerEntries: playerLedgerEntries)
    }

    private var displayBalance: Decimal { -balanceSummary.balanceOwed }

    private var openBetsCount: Int {
        playerBets.filter { $0.status == .pending || $0.status == .accepted || $0.status == .readyToGrade }.count
    }

    private var settledBets: [Bet] {
        playerBets.filter { $0.status == .settled && $0.gradeResult != nil }
    }

    private var winCount: Int { settledBets.filter { $0.gradeResult == .win }.count }
    private var lossCount: Int { settledBets.filter { $0.gradeResult == .loss }.count }
    private var pushCount: Int { settledBets.filter { $0.gradeResult == .push }.count }

    private var winRate: Double {
        let total = winCount + lossCount
        guard total > 0 else { return 0 }
        return Double(winCount) / Double(total) * 100
    }

    private var totalStaked: Decimal {
        let grouped = Dictionary(grouping: settledBets) { $0.ticketId }
        return grouped.values.reduce(Decimal.zero) { total, ticketBets in
            total + (ticketBets.first?.stake ?? 0)
        }
    }

    private var totalProfitLoss: Decimal {
        settledBets.reduce(Decimal.zero) { total, bet in
            guard let result = bet.gradeResult else { return total }
            switch result {
            case .win:
                let decimalOdds: Decimal = bet.odds > 0
                    ? Decimal(bet.odds) / 100
                    : 100 / Decimal(Swift.abs(bet.odds))
                return total + (bet.stake * decimalOdds)
            case .loss:
                return total - bet.stake
            case .push:
                return total
            }
        }
    }

    private var roiPercentage: Double {
        guard totalStaked > 0 else { return 0 }
        return Double(truncating: (totalProfitLoss / totalStaked * 100) as NSDecimalNumber)
    }

    private var creditUtilization: Double {
        guard player.creditLimit > 0 else { return 0 }
        let used = player.creditLimit - balanceSummary.availableCredit
        return Double(truncating: (used / player.creditLimit) as NSDecimalNumber)
    }

    private var balanceColor: Color {
        displayBalance > 0 ? .green : (displayBalance < 0 ? .red : .primary)
    }

    private var memberSinceDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: player.createdAt)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroBalanceSection
                profileAndPreferencesCard
                performanceCard
                playerMenuSection
            }
            .padding()
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Log Out", isPresented: $showingLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) { performLogout() }
        } message: {
            Text("Are you sure you want to log out?")
        }
        .alert("Logout Error", isPresented: $showingLogoutError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(logoutErrorMessage)
        }
    }

    // MARK: - Hero Balance Section (unchanged)

    private var heroBalanceSection: some View {
        VStack(spacing: 12) {
            Text("CURRENT BALANCE")
                .font(Theme.caption)
                .fontWeight(.semibold)
                .tracking(1.5)
                .foregroundStyle(Theme.textSecondary)

            Text(formatCurrency(displayBalance))
                .font(Theme.font(size: 56, weight: .bold))
                .foregroundStyle(balanceColor)
                .shadow(color: balanceColor.opacity(0.3), radius: 8, x: 0, y: 0)

            if displayBalance > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Theme.accent)
                    Text("Amount owed to you")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if displayBalance < 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Theme.danger)
                    Text("Amount you owe")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                    Text("All settled")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .overlay(alignment: .bottom) {
            Text("Balances are informational and not processed by Booki.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
                .padding(.bottom, 8)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.cardGradient)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [Theme.border.opacity(0.8), Theme.border.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
    }

    // MARK: - Profile & Preferences (merged)

    private var profileAndPreferencesCard: some View {
        VStack(spacing: 0) {
            // Profile rows
            profileRow(icon: "person.text.rectangle", label: "Name", value: player.name)
            Divider().background(Theme.divider)
            profileRow(icon: "envelope.fill", label: "Email", value: player.email ?? "—")
            Divider().background(Theme.divider)
            profileRow(icon: "link.circle.fill", label: "Organizer", value: player.bookie?.name ?? "—")
            Divider().background(Theme.divider)
            profileRow(icon: "calendar", label: "Member Since", value: memberSinceDate)

            Divider().background(Theme.divider).padding(.vertical, 4)

            // Notifications
            HStack(spacing: 12) {
                Image(systemName: "bell.fill")
                    .font(.body)
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 24)

                Toggle(isOn: $notificationsEnabled) {
                    Text("Pick Notifications")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .tint(Theme.accent)
            }
            .padding(.vertical, 12)
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.cardBackground)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.border, lineWidth: 0.5)
            }
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private func profileRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Performance Card (merged Quick Stats + Betting Stats + Credit)

    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Record hero
            VStack(spacing: 8) {
                Text("RECORD")
                    .font(Theme.caption2)
                    .fontWeight(.medium)
                    .tracking(0.5)
                    .foregroundStyle(Theme.textMuted)

                HStack(spacing: 4) {
                    Text("\(winCount)")
                        .foregroundStyle(Theme.accent)
                    Text("-")
                        .foregroundStyle(Theme.textMuted)
                    Text("\(lossCount)")
                        .foregroundStyle(Theme.danger)
                    Text("-")
                        .foregroundStyle(Theme.textMuted)
                    Text("\(pushCount)")
                        .foregroundStyle(Theme.warning)
                }
                .font(Theme.font(size: 32, weight: .bold))

                HStack(spacing: 16) {
                    legendDot(color: Theme.accent, label: "W")
                    legendDot(color: Theme.danger, label: "L")
                    legendDot(color: Theme.warning, label: "P")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.elevatedBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
            )

            // Compact stat rows
            VStack(spacing: 12) {
                statRow(label: "Open Picks", value: "\(openBetsCount)", color: Theme.scheduled)

                Divider().background(Theme.divider)

                statRow(
                    label: "Win Rate",
                    value: settledBets.isEmpty ? "—" : String(format: "%.0f%%", winRate),
                    color: settledBets.isEmpty ? Theme.textSecondary : (winRate >= 50 ? Theme.accent : Theme.danger)
                )

                Divider().background(Theme.divider)

                statRow(
                    label: "Performance",
                    value: settledBets.isEmpty ? "—" : formatProfitLoss(totalProfitLoss),
                    color: settledBets.isEmpty ? Theme.textSecondary : (totalProfitLoss >= 0 ? Theme.accent : Theme.danger)
                )

                Divider().background(Theme.divider)

                statRow(
                    label: "ROI",
                    value: settledBets.isEmpty ? "—" : String(format: "%+.1f%%", roiPercentage),
                    color: settledBets.isEmpty ? Theme.textSecondary : (roiPercentage >= 0 ? Theme.accent : Theme.danger)
                )
            }

            // Credit utilization bar
            Divider().background(Theme.divider)

            creditBar
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.cardBackground)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.border, lineWidth: 0.5)
            }
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(Theme.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func statRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }

    private var creditBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Credit")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(formatCurrency(balanceSummary.availableCredit)) / \(formatCurrency(player.creditLimit))")
                    .font(Theme.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(balanceSummary.availableCredit >= 0 ? Theme.textPrimary : Theme.danger)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.elevatedBackground)
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(creditUtilizationColor)
                        .frame(width: max(min(CGFloat(creditUtilization) * geometry.size.width, geometry.size.width), 4), height: 10)
                }
            }
            .frame(height: 10)
        }
    }

    private var creditUtilizationColor: Color {
        if creditUtilization >= 1.0 { return Theme.danger }
        else if creditUtilization >= 0.8 { return Theme.warning }
        else if creditUtilization >= 0.5 { return Theme.gold }
        else { return Theme.accent }
    }

    // MARK: - Player Menu Section

    private var playerMenuSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                PlayerActivityView(
                    ledgerEntries: playerLedgerEntries,
                    selectedFilter: $selectedTransactionFilter
                )
            } label: {
                playerMenuRow(icon: "clock.arrow.circlepath", title: "Activity")
            }

            Divider()
                .background(Theme.border)
                .padding(.leading, 58)

            NavigationLink {
                ChangePasswordView()
            } label: {
                playerMenuRow(icon: "lock.rotation", title: "Change Password")
            }

            Divider()
                .background(Theme.border)
                .padding(.leading, 58)

            NavigationLink {
                AboutSettingsView()
            } label: {
                playerMenuRow(icon: "info.circle", title: "About")
            }

            if authManager.userRole == .player {
                Divider()
                    .background(Theme.border)
                    .padding(.leading, 58)

                Button {
                    showingLogoutConfirmation = true
                } label: {
                    playerMenuRow(icon: "rectangle.portrait.and.arrow.right", title: "Log Out", color: Theme.danger)
                }
            }
        }
        .cardStyle()
    }

    private func playerMenuRow(icon: String, title: String, color: Color = Theme.accent) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 28, alignment: .center)

            Text(title)
                .font(Theme.body)
                .fontWeight(.medium)
                .foregroundStyle(title == "Log Out" ? Theme.danger : Theme.textPrimary)

            Spacer()

            if title != "Log Out" {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Transaction History Section

    private var transactionHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Theme.textSecondary)
                Text("HISTORY")
                    .font(Theme.caption)
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
            }

            segmentedPicker(selection: $selectedTransactionFilter, items: TransactionFilter.allCases)

            if filteredLedgerEntries.isEmpty {
                emptyState(icon: "doc.text", title: "No transactions", showFilterHint: selectedTransactionFilter != .all)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredLedgerEntries) { entry in
                        TransactionRowView(entry: entry)
                        if entry.id != filteredLedgerEntries.last?.id {
                            Divider().background(Theme.divider)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.cardBackground)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.border, lineWidth: 0.5)
            }
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    // MARK: - Logout Section

    private var logoutSection: some View {
        Button {
            showingLogoutConfirmation = true
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Log Out")
            }
            .font(Theme.headline)
            .textCase(.uppercase)
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(DestructiveButtonStyle())
        .padding(.top, 20)
    }

    // MARK: - Shared Components

    private func segmentedPicker<T: CaseIterable & Identifiable & RawRepresentable>(
        selection: Binding<T>,
        items: [T]
    ) -> some View where T.RawValue == String, T.ID == String {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = selection.wrappedValue.id == item.id
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection.wrappedValue = item
                    }
                } label: {
                    Text(item.rawValue)
                        .font(Theme.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Theme.background : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? AnyView(Theme.accent) : AnyView(Color.clear))
                }
            }
        }
        .background(Theme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func emptyState(icon: String, title: String, showFilterHint: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(Theme.font(size: 40))
                .foregroundStyle(Theme.textMuted)
            Text(title)
                .font(Theme.headline)
                .foregroundStyle(Theme.textSecondary)
            if showFilterHint {
                Text("Try changing the filter")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func performLogout() {
        Task {
            do {
                try await authManager.signOut()
                BetSlipManager.shared.clearAll()
                // Data clearing happens on next login via SyncService.sync()
                // (hasCompletedInitialSync resets on new session)
            } catch {
                logoutErrorMessage = error.localizedDescription
                showingLogoutError = true
            }
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    private func formatProfitLoss(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let absValue = Swift.abs(Double(truncating: value as NSDecimalNumber))
        let formatted = formatter.string(from: NSDecimalNumber(value: absValue)) ?? "$\(absValue)"
        return value >= 0 ? "+\(formatted)" : "-\(formatted)"
    }
}

// MARK: - Player Activity View

struct PlayerActivityView: View {
    let ledgerEntries: [LedgerEntry]
    @Binding var selectedFilter: TransactionFilter

    private var filteredEntries: [LedgerEntry] {
        guard let type = selectedFilter.entryType else {
            return ledgerEntries
        }
        return ledgerEntries.filter { $0.type == type }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                segmentedPicker

                if filteredEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(Theme.font(size: 40))
                            .foregroundStyle(Theme.textMuted)
                        Text("No transactions")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textSecondary)
                        if selectedFilter != .all {
                            Text("Try changing the filter")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            TransactionRowView(entry: entry)
                            if entry.id != filteredEntries.last?.id {
                                Divider().background(Theme.divider)
                            }
                        }
                    }
                    .cardStyle()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var segmentedPicker: some View {
        HStack(spacing: 0) {
            ForEach(TransactionFilter.allCases) { item in
                let isSelected = selectedFilter.id == item.id
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = item
                    }
                } label: {
                    Text(item.rawValue)
                        .font(Theme.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Theme.background : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? AnyView(Theme.accent) : AnyView(Color.clear))
                }
            }
        }
        .background(Theme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Transaction Row View

struct TransactionRowView: View {
    let entry: LedgerEntry

    private var tagColor: Color {
        switch entry.type {
        case .settlement: return Theme.scheduled
        case .adjustment: return Theme.warning
        case .paymentLogged: return Theme.accent
        case .reversal: return Color.purple
        }
    }

    private var typeLabel: String {
        switch entry.type {
        case .settlement: return "Graded"
        case .adjustment: return "Adjustment"
        case .paymentLogged: return "Settled"
        case .reversal: return "Reversal"
        }
    }

    /// Player-facing: negate internal convention so wins show positive
    private var displayAmount: Decimal { -entry.amount }

    private var amountColor: Color {
        displayAmount >= 0 ? Theme.accent : Theme.danger
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let absAmount = abs(displayAmount)
        let formatted = formatter.string(from: absAmount as NSDecimalNumber) ?? "$\(absAmount)"
        return displayAmount >= 0 ? "+\(formatted)" : "-\(formatted)"
    }

    /// Enriched description using linked bet data when available
    private var displayDescription: String {
        if let bet = entry.bet {
            let outcome: String
            switch entry.entryDescription.lowercased() {
            case let d where d.contains("won"): outcome = "Won"
            case let d where d.contains("lost"): outcome = "Lost"
            case let d where d.contains("push"): outcome = "Push"
            case let d where d.contains("void"): outcome = "Voided"
            default: return entry.entryDescription
            }
            let side = bet.side
            if let event = bet.eventDescription {
                return "\(outcome) · \(side) — \(event)"
            }
            return "\(outcome) · \(side)"
        }
        return entry.entryDescription
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: entry.createdAt)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 2, topTrailingRadius: 2)
                .fill(tagColor)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayDescription)
                    .font(Theme.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                Text(formattedDate)
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.leading, 12)

            Spacer()

            Text(formattedAmount)
                .font(Theme.body)
                .fontWeight(.bold)
                .foregroundStyle(amountColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(amountColor.opacity(0.15)))
                .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        AccountView(player: Player(
            name: "Test Player",
            email: "test@example.com",
            creditLimit: 1000
        ))
    }
    .modelContainer(for: [Player.self, Bet.self, LedgerEntry.self], inMemory: true)
}
