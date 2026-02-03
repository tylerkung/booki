import SwiftUI
import SwiftData

/// Filter options for transaction history
enum TransactionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case settlements = "Settlements"
    case adjustments = "Adjustments"
    case payments = "Payments"

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

/// Filter options for bet history (player view)
enum BetHistoryFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case settled = "Settled"
    case all = "All"

    var id: String { rawValue }

    /// Returns the bet statuses that match this filter
    var matchingStatuses: [BetStatus] {
        switch self {
        case .active:
            // Active = pending + accepted (+ readyToGrade since it's still in-play)
            return [.pending, .accepted, .readyToGrade]
        case .settled:
            // Settled = won, lost, push, void (graded bets awaiting settlement also shown here)
            return [.graded, .settled, .void]
        case .all:
            return BetStatus.allCases
        }
    }
}

/// Enhanced account summary view for players showing balance, credit utilization, and quick stats
struct AccountView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: AuthManager
    @Query private var allBets: [Bet]
    @Query private var allLedgerEntries: [LedgerEntry]
    @Query private var allEvents: [Event]

    let player: Player

    // Logout state
    @State private var showingLogoutConfirmation = false
    @State private var showingLogoutError = false
    @State private var logoutErrorMessage = ""

    // Transaction history filter state
    @State private var selectedTransactionFilter: TransactionFilter = .all

    // Bet history filter state
    @State private var selectedBetFilter: BetHistoryFilter = .active

    // MARK: - Computed Properties

    /// All bets for this player
    private var playerBets: [Bet] {
        allBets.filter { $0.player?.id == player.id }
    }

    /// Ledger entries for this player
    private var playerLedgerEntries: [LedgerEntry] {
        allLedgerEntries.filter { $0.player?.id == player.id }
    }

    /// Filtered ledger entries based on selected filter, sorted by date (newest first)
    private var filteredLedgerEntries: [LedgerEntry] {
        let sorted = playerLedgerEntries.sorted { $0.createdAt > $1.createdAt }
        guard let entryType = selectedTransactionFilter.entryType else {
            return sorted
        }
        return sorted.filter { $0.type == entryType }
    }

    /// Player balance summary
    private var balanceSummary: PlayerBalanceSummary {
        BalanceService.playerSummary(
            for: player,
            bets: playerBets,
            ledgerEntries: playerLedgerEntries
        )
    }

    /// Display balance - negated for user-facing semantics
    /// Positive = player in credit (bookie owes player)
    /// Negative = player in debt (player owes bookie)
    private var displayBalance: Decimal {
        -balanceSummary.balanceOwed
    }

    /// Open bets count (pending + accepted)
    private var openBetsCount: Int {
        playerBets.filter { $0.status == .pending || $0.status == .accepted || $0.status == .readyToGrade }.count
    }

    /// Pending bets count (awaiting acceptance)
    private var pendingBetsCount: Int {
        playerBets.filter { $0.status == .pending }.count
    }

    /// Settled bets for win rate calculation
    private var settledBets: [Bet] {
        playerBets.filter { $0.status == .settled && $0.gradeResult != nil }
    }

    /// Win count
    private var winCount: Int {
        settledBets.filter { $0.gradeResult == .win }.count
    }

    /// Loss count
    private var lossCount: Int {
        settledBets.filter { $0.gradeResult == .loss }.count
    }

    /// Win rate percentage
    private var winRate: Double {
        let winsAndLosses = winCount + lossCount
        guard winsAndLosses > 0 else { return 0 }
        return Double(winCount) / Double(winsAndLosses) * 100
    }

    /// Push count
    private var pushCount: Int {
        settledBets.filter { $0.gradeResult == .push }.count
    }

    /// Total bets placed (all bets except void)
    private var totalBetsPlaced: Int {
        playerBets.filter { $0.status != .void }.count
    }

    /// Total stake across all settled bets (for ROI calculation)
    private var totalStaked: Decimal {
        settledBets.reduce(Decimal.zero) { $0 + $1.stake }
    }

    /// Total profit/loss from settled bets
    private var totalProfitLoss: Decimal {
        settledBets.reduce(Decimal.zero) { total, bet in
            guard let result = bet.gradeResult else { return total }
            switch result {
            case .win:
                // Calculate profit from win
                let decimalOdds: Decimal
                if bet.odds > 0 {
                    decimalOdds = Decimal(bet.odds) / 100
                } else {
                    decimalOdds = 100 / Decimal(abs(bet.odds))
                }
                return total + (bet.stake * decimalOdds)
            case .loss:
                // Lost stake
                return total - bet.stake
            case .push:
                // No change
                return total
            }
        }
    }

    /// ROI percentage (profit / total staked)
    private var roiPercentage: Double {
        guard totalStaked > 0 else { return 0 }
        return Double(truncating: (totalProfitLoss / totalStaked * 100) as NSDecimalNumber)
    }

    /// Credit utilization percentage (0.0 to 1.0+)
    private var creditUtilization: Double {
        guard player.creditLimit > 0 else { return 0 }
        let used = player.creditLimit - balanceSummary.availableCredit
        return Double(truncating: (used / player.creditLimit) as NSDecimalNumber)
    }

    /// Filtered bets based on selected filter, sorted by date (newest first)
    private var filteredPlayerBets: [Bet] {
        playerBets
            .filter { selectedBetFilter.matchingStatuses.contains($0.status) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Color for balance display
    private var balanceColor: Color {
        // Positive displayBalance = player is in credit (green - bookie owes player)
        // Negative displayBalance = player owes bookie (red - player is in debt)
        displayBalance > 0 ? .green : (displayBalance < 0 ? .red : .primary)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero Balance Section
                heroBalanceSection

                // Credit Utilization Section
                creditUtilizationSection

                // Quick Stats Section
                quickStatsSection

                // Betting Statistics Section
                bettingStatisticsSection

                // My Bets Section
                myBetsSection

                // Transaction History Section
                transactionHistorySection

                // Logout Section (only show for actual players, not test mode)
                if authManager.userRole == .player {
                    logoutSection
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
        .alert("Log Out", isPresented: $showingLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                performLogout()
            }
        } message: {
            Text("Are you sure you want to log out?")
        }
        .alert("Logout Error", isPresented: $showingLogoutError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(logoutErrorMessage)
        }
    }

    // MARK: - Logout Section

    private var logoutSection: some View {
        VStack(spacing: 16) {
            Button(role: .destructive) {
                showingLogoutConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Log Out")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.danger)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.top, 20)
    }

    private func performLogout() {
        Task {
            do {
                try await authManager.signOut()
            } catch {
                logoutErrorMessage = error.localizedDescription
                showingLogoutError = true
            }
        }
    }

    // MARK: - Hero Balance Section

    private var heroBalanceSection: some View {
        VStack(spacing: 12) {
            Text("CURRENT BALANCE")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1.5)
                .foregroundStyle(Theme.textSecondary)

            Text(formatCurrency(displayBalance))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(balanceColor)
                .shadow(color: balanceColor.opacity(0.3), radius: 8, x: 0, y: 0)

            if displayBalance > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Theme.accent)
                    Text("Amount owed to you")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if displayBalance < 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Theme.danger)
                    Text("Amount you owe")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                    Text("All settled up")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
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

    // MARK: - Credit Utilization Section

    private var creditUtilizationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with icon
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "creditcard.fill")
                        .foregroundStyle(Theme.accent)
                    Text("AVAILABLE CREDIT")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Text(formatCurrency(balanceSummary.availableCredit))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(balanceSummary.availableCredit >= 0 ? Theme.textPrimary : Theme.danger)
            }

            // Styled progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track with gradient
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.elevatedBackground)
                        .frame(height: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.border, lineWidth: 1)
                        )

                    // Filled portion with gradient
                    RoundedRectangle(cornerRadius: 10)
                        .fill(creditUtilizationGradient)
                        .frame(width: max(min(CGFloat(creditUtilization) * geometry.size.width, geometry.size.width), 8), height: 16)
                        .shadow(color: creditUtilizationColor.opacity(0.5), radius: 4, x: 0, y: 0)
                }
            }
            .frame(height: 16)

            // Footer stats
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("USED")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .tracking(0.5)
                        .foregroundStyle(Theme.textMuted)
                    Text(formatCurrency(player.creditLimit - balanceSummary.availableCredit))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(creditUtilizationColor)
                }

                Spacer()

                // Utilization percentage
                VStack(spacing: 2) {
                    Text("\(Int(creditUtilization * 100))%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(creditUtilizationColor)
                    Text("utilized")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("LIMIT")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .tracking(0.5)
                        .foregroundStyle(Theme.textMuted)
                    Text(formatCurrency(player.creditLimit))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
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

    /// Color for credit utilization bar
    private var creditUtilizationColor: Color {
        if creditUtilization >= 1.0 {
            return Theme.danger
        } else if creditUtilization >= 0.8 {
            return Theme.warning
        } else if creditUtilization >= 0.5 {
            return Theme.gold
        } else {
            return Theme.accent
        }
    }

    /// Gradient for credit utilization bar
    private var creditUtilizationGradient: LinearGradient {
        LinearGradient(
            colors: [creditUtilizationColor, creditUtilizationColor.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Quick Stats Section

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Theme.gold)
                Text("QUICK STATS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 12) {
                // Open Bets
                statCard(
                    title: "Open Bets",
                    value: "\(openBetsCount)",
                    icon: "ticket.fill",
                    color: Theme.scheduled
                )

                // Pending Bets
                statCard(
                    title: "Pending",
                    value: "\(pendingBetsCount)",
                    icon: "clock.fill",
                    color: Theme.warning
                )

                // Win Rate
                statCard(
                    title: "Win Rate",
                    value: settledBets.isEmpty ? "—" : String(format: "%.0f%%", winRate),
                    icon: "percent",
                    color: Theme.accent
                )
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

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            // Icon
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            // Value
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)

            // Title
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.elevatedBackground)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.05))
        )
    }

    // MARK: - Betting Statistics Section

    private var bettingStatisticsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Theme.gold)
                Text("BETTING STATS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Record display card (W-L-P)
            VStack(spacing: 12) {
                Text("RECORD")
                    .font(.caption2)
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
                .font(.system(size: 32, weight: .bold, design: .rounded))

                HStack(spacing: 20) {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.accent).frame(width: 8, height: 8)
                        Text("Wins")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Theme.danger).frame(width: 8, height: 8)
                        Text("Losses")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Theme.warning).frame(width: 8, height: 8)
                        Text("Pushes")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.elevatedBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
            )

            // Stats grid
            VStack(spacing: 16) {
                // Total Bets Placed
                statsRow(
                    label: "Total Bets Placed",
                    value: "\(totalBetsPlaced)",
                    valueColor: Theme.textPrimary
                )

                Divider()
                    .background(Theme.divider)

                // Win Percentage
                statsRow(
                    label: "Win Percentage",
                    value: settledBets.isEmpty ? "—" : String(format: "%.1f%%", winRate),
                    valueColor: settledBets.isEmpty ? Theme.textSecondary : (winRate >= 50 ? Theme.accent : Theme.danger)
                )

                Divider()
                    .background(Theme.divider)

                // Total Profit/Loss
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "dollarsign.circle")
                            .foregroundStyle(Theme.textMuted)
                        Text("Total Profit/Loss")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if settledBets.isEmpty {
                        Text("—")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(formatProfitLoss(totalProfitLoss))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(totalProfitLoss >= 0 ? Theme.accent : Theme.danger)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill((totalProfitLoss >= 0 ? Theme.accent : Theme.danger).opacity(0.15))
                            )
                    }
                }

                Divider()
                    .background(Theme.divider)

                // ROI
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(Theme.textMuted)
                        Text("ROI")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if settledBets.isEmpty {
                        Text("—")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(String(format: "%+.1f%%", roiPercentage))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(roiPercentage >= 0 ? Theme.accent : Theme.danger)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill((roiPercentage >= 0 ? Theme.accent : Theme.danger).opacity(0.15))
                            )
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

    /// Helper for stats row
    private func statsRow(label: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
        }
    }

    /// Format profit/loss with sign
    private func formatProfitLoss(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let absValue = abs(value)
        let formatted = formatter.string(from: absValue as NSDecimalNumber) ?? "$\(absValue)"
        if value >= 0 {
            return "+\(formatted)"
        } else {
            return "-\(formatted)"
        }
    }

    // MARK: - My Bets Section

    private var myBetsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(Theme.scheduled)
                Text("MY BETS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Custom segmented picker
            HStack(spacing: 0) {
                ForEach(BetHistoryFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedBetFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedBetFilter == filter ? .semibold : .regular)
                            .foregroundStyle(selectedBetFilter == filter ? Theme.background : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selectedBetFilter == filter
                                ? AnyView(Theme.accent)
                                : AnyView(Color.clear)
                            )
                    }
                }
            }
            .background(Theme.elevatedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.border, lineWidth: 0.5)
            )

            // Bets list
            if filteredPlayerBets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "ticket")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textMuted)
                    Text("No bets")
                        .font(.headline)
                        .foregroundStyle(Theme.textSecondary)
                    if selectedBetFilter != .all {
                        Text("Try changing the filter")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredPlayerBets) { bet in
                        NavigationLink {
                            AccountBetDetailView(bet: bet)
                        } label: {
                            AccountBetRowView(bet: bet, eventName: eventName(for: bet))
                        }
                        .buttonStyle(.plain)

                        if bet.id != filteredPlayerBets.last?.id {
                            Divider()
                                .background(Theme.divider)
                                .padding(.leading, 52)
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

    /// Get event name for a bet
    private func eventName(for bet: Bet) -> String {
        if let event = allEvents.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    // MARK: - Transaction History Section

    private var transactionHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Theme.textSecondary)
                Text("HISTORY")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Custom segmented picker
            HStack(spacing: 0) {
                ForEach(TransactionFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTransactionFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.caption)
                            .fontWeight(selectedTransactionFilter == filter ? .semibold : .regular)
                            .foregroundStyle(selectedTransactionFilter == filter ? Theme.background : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selectedTransactionFilter == filter
                                ? AnyView(Theme.accent)
                                : AnyView(Color.clear)
                            )
                    }
                }
            }
            .background(Theme.elevatedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.border, lineWidth: 0.5)
            )

            // Transaction list
            if filteredLedgerEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textMuted)
                    Text("No transactions")
                        .font(.headline)
                        .foregroundStyle(Theme.textSecondary)
                    if selectedTransactionFilter != .all {
                        Text("Try changing the filter")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredLedgerEntries) { entry in
                        TransactionRowView(entry: entry)
                        if entry.id != filteredLedgerEntries.last?.id {
                            Divider()
                                .background(Theme.divider)
                                .padding(.leading, 52)
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

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Transaction Row View

/// Row view for displaying a single ledger entry in the transaction history
struct TransactionRowView: View {
    let entry: LedgerEntry

    /// Icon name based on entry type
    private var iconName: String {
        switch entry.type {
        case .settlement:
            return "checkmark.circle.fill"
        case .adjustment:
            return "slider.horizontal.3"
        case .paymentLogged:
            return "dollarsign.circle.fill"
        case .reversal:
            return "arrow.uturn.backward.circle.fill"
        }
    }

    /// Icon color based on entry type
    private var iconColor: Color {
        switch entry.type {
        case .settlement:
            return Theme.scheduled
        case .adjustment:
            return Theme.warning
        case .paymentLogged:
            return Theme.accent
        case .reversal:
            return Color.purple
        }
    }

    /// Formatted type label
    private var typeLabel: String {
        switch entry.type {
        case .settlement:
            return "Settlement"
        case .adjustment:
            return "Adjustment"
        case .paymentLogged:
            return "Payment"
        case .reversal:
            return "Reversal"
        }
    }

    /// Amount color: green for positive (credits), red for negative (debits)
    private var amountColor: Color {
        entry.amount >= 0 ? Theme.accent : Theme.danger
    }

    /// Formatted amount with sign
    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let absAmount = abs(entry.amount)
        let formatted = formatter.string(from: absAmount as NSDecimalNumber) ?? "$\(absAmount)"
        return entry.amount >= 0 ? "+\(formatted)" : "-\(formatted)"
    }

    /// Formatted date
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: entry.createdAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Type icon with background
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .font(.body)
                    .foregroundStyle(iconColor)
            }

            // Description and metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.entryDescription)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(typeLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(iconColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(iconColor.opacity(0.1))
                        )

                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }

            Spacer()

            // Amount with background
            Text(formattedAmount)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(amountColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(amountColor.opacity(0.1))
                )
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Player Bet Row View

/// Row view for displaying a bet in the player's bet history
struct AccountBetRowView: View {
    let bet: Bet
    let eventName: String

    /// Status color based on bet status
    private var statusColor: Color {
        switch bet.status {
        case .pending:
            return Theme.warning
        case .accepted, .readyToGrade:
            return Theme.scheduled
        case .graded, .settled:
            if let result = bet.gradeResult {
                switch result {
                case .win: return Theme.accent
                case .loss: return Theme.danger
                case .push: return Theme.warning
                }
            }
            return Theme.accent
        case .declined:
            return Theme.danger
        case .void:
            return Theme.textMuted
        }
    }

    /// Status display text
    private var statusText: String {
        switch bet.status {
        case .pending:
            return "Pending"
        case .accepted, .readyToGrade:
            return "Open"
        case .graded, .settled:
            if let result = bet.gradeResult {
                return result.rawValue.capitalized
            }
            return "Settled"
        case .declined:
            return "Declined"
        case .void:
            return "Void"
        }
    }

    /// Formatted odds
    private var formattedOdds: String {
        bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
    }

    /// Formatted stake
    private var formattedStake: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: bet.stake as NSDecimalNumber) ?? "$\(bet.stake)"
    }

    /// Formatted date
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: bet.createdAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator with glow effect
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(statusColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: statusColor.opacity(0.5), radius: 4, x: 0, y: 0)
            }

            // Bet info
            VStack(alignment: .leading, spacing: 6) {
                // Event name
                Text(eventName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                // Side and odds
                HStack(spacing: 8) {
                    Text(bet.side)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textSecondary)

                    Text(formattedOdds)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Theme.gold.opacity(0.15))
                        )

                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }

            Spacer()

            // Status badge and stake
            VStack(alignment: .trailing, spacing: 6) {
                Text(statusText)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor)
                    .clipShape(Capsule())

                Text(formattedStake)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Chevron indicator
            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Player Bet Detail View

/// Detail view for a player to see full bet information
struct AccountBetDetailView: View {
    @Query private var events: [Event]

    let bet: Bet

    /// Event for this bet
    private var event: Event? {
        events.first { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }
    }

    /// Event name
    private var eventName: String {
        if let event = event {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    /// Formatted odds
    private var formattedOdds: String {
        bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
    }

    /// Formatted stake
    private var formattedStake: String {
        formatCurrency(bet.stake)
    }

    /// Potential payout (profit only)
    private var potentialPayout: Decimal {
        let decimalOdds: Decimal
        if bet.odds > 0 {
            decimalOdds = Decimal(bet.odds) / 100
        } else {
            decimalOdds = 100 / Decimal(abs(bet.odds))
        }
        return bet.stake * decimalOdds
    }

    /// Total return (stake + profit)
    private var totalReturn: Decimal {
        bet.stake + potentialPayout
    }

    /// Status color
    private var statusColor: Color {
        switch bet.status {
        case .pending: return Theme.warning
        case .accepted, .readyToGrade: return Theme.scheduled
        case .declined: return Theme.danger
        case .graded, .settled:
            if let result = bet.gradeResult {
                switch result {
                case .win: return Theme.accent
                case .loss: return Theme.danger
                case .push: return Theme.warning
                }
            }
            return Theme.accent
        case .void: return Theme.textMuted
        }
    }

    /// Status text
    private var statusText: String {
        switch bet.status {
        case .pending: return "Pending Approval"
        case .accepted: return "Open"
        case .readyToGrade: return "Awaiting Result"
        case .graded: return "Graded"
        case .settled:
            if let result = bet.gradeResult {
                return result.rawValue.capitalized
            }
            return "Settled"
        case .declined: return "Declined"
        case .void: return "Void"
        }
    }

    /// Grade result color
    private var gradeResultColor: Color {
        guard let result = bet.gradeResult else { return Theme.textPrimary }
        switch result {
        case .win: return Theme.accent
        case .loss: return Theme.danger
        case .push: return Theme.warning
        }
    }

    /// Formatted date
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: bet.createdAt)
    }

    var body: some View {
        List {
            // Status Section
            Section {
                HStack {
                    Text("Status")
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(statusText)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(statusColor)
                        .clipShape(Capsule())
                }

                if let gradeResult = bet.gradeResult {
                    HStack {
                        Text("Result")
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(gradeResult.rawValue.capitalized)
                            .fontWeight(.bold)
                            .foregroundStyle(gradeResultColor)
                    }
                }
            }
            .listRowBackground(Theme.cardBackground)

            // Event Section
            Section {
                detailRow(label: "Matchup", value: eventName)

                if let event = event {
                    detailRow(label: "Sport", value: event.sport)
                    detailRow(label: "League", value: event.league)

                    let eventFormatter = DateFormatter()
                    let _ = eventFormatter.dateStyle = .medium
                    let _ = eventFormatter.timeStyle = .short
                    detailRow(label: "Start Time", value: eventFormatter.string(from: event.startTime))

                    detailRow(label: "Event Status", value: event.status.rawValue.capitalized)

                    if let finalScore = event.finalScore {
                        detailRow(label: "Final Score", value: finalScore, valueColor: Theme.gold)
                    }
                }
            } header: {
                Text("EVENT")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.cardBackground)

            // Bet Details Section
            Section {
                detailRow(label: "Market", value: bet.market)
                detailRow(label: "Selection", value: bet.side, valueColor: Theme.textPrimary)
                HStack {
                    Text("Odds")
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(formattedOdds)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Theme.gold.opacity(0.15))
                        )
                }
                detailRow(label: "Stake", value: formattedStake, valueColor: Theme.textPrimary)
            } header: {
                Text("YOUR BET")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.cardBackground)

            // Payout Section
            Section {
                HStack {
                    Text("Profit if Win")
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(formatCurrency(potentialPayout))
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.accent)
                }
                HStack {
                    Text("Total Return")
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(formatCurrency(totalReturn))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.accent)
                }
            } header: {
                Text("POTENTIAL RETURN")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.cardBackground)

            // Details Section
            Section {
                detailRow(label: "Placed", value: formattedDate)
                detailRow(label: "Bet ID", value: String(bet.id.uuidString.prefix(8)) + "...")
            } header: {
                Text("DETAILS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Bet Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Helper for detail rows
    private func detailRow(label: String, value: String, valueColor: Color = Theme.textSecondary) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(valueColor)
        }
    }

    /// Format currency helper
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
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
