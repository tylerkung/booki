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
    @Query private var allBets: [Bet]
    @Query private var allLedgerEntries: [LedgerEntry]
    @Query private var allEvents: [Event]

    let player: Player

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
        // Positive balance = player owes bookie (red)
        // Negative balance = bookie owes player (green - player is winning)
        balanceSummary.balanceOwed > 0 ? .red : (balanceSummary.balanceOwed < 0 ? .green : .primary)
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
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Hero Balance Section

    private var heroBalanceSection: some View {
        VStack(spacing: 8) {
            Text("Current Balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(formatCurrency(balanceSummary.balanceOwed))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(balanceColor)

            if balanceSummary.balanceOwed > 0 {
                Text("Amount you owe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if balanceSummary.balanceOwed < 0 {
                Text("Amount owed to you")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - Credit Utilization Section

    private var creditUtilizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Credit")
                    .font(.headline)

                Spacer()

                Text(formatCurrency(balanceSummary.availableCredit))
                    .font(.headline)
                    .foregroundColor(balanceSummary.availableCredit >= 0 ? Color.primary : Color.red)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.elevatedBackground)
                        .frame(height: 12)

                    // Filled portion
                    RoundedRectangle(cornerRadius: 8)
                        .fill(creditUtilizationColor)
                        .frame(width: min(CGFloat(creditUtilization) * geometry.size.width, geometry.size.width), height: 12)
                }
            }
            .frame(height: 12)

            HStack {
                Text("Used: \(formatCurrency(player.creditLimit - balanceSummary.availableCredit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Limit: \(formatCurrency(player.creditLimit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    /// Color for credit utilization bar
    private var creditUtilizationColor: Color {
        if creditUtilization >= 1.0 {
            return .red
        } else if creditUtilization >= 0.8 {
            return .orange
        } else if creditUtilization >= 0.5 {
            return .yellow
        } else {
            return .green
        }
    }

    // MARK: - Quick Stats Section

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Stats")
                .font(.headline)

            HStack(spacing: 16) {
                // Open Bets
                statCard(
                    title: "Open Bets",
                    value: "\(openBetsCount)",
                    color: .blue
                )

                // Pending Bets
                statCard(
                    title: "Pending",
                    value: "\(pendingBetsCount)",
                    color: .orange
                )

                // Win Rate
                statCard(
                    title: "Win Rate",
                    value: settledBets.isEmpty ? "—" : String(format: "%.0f%%", winRate),
                    color: .green
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }

    // MARK: - Betting Statistics Section

    private var bettingStatisticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Betting Stats")
                .font(.headline)

            // Win/Loss/Push Record
            VStack(spacing: 12) {
                // Record display (e.g., "12-8-1")
                HStack {
                    Text("Record")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 0) {
                        Text("\(winCount)")
                            .foregroundStyle(.green)
                            .fontWeight(.semibold)
                        Text("-")
                            .foregroundStyle(.secondary)
                        Text("\(lossCount)")
                            .foregroundStyle(.red)
                            .fontWeight(.semibold)
                        Text("-")
                            .foregroundStyle(.secondary)
                        Text("\(pushCount)")
                            .foregroundStyle(.orange)
                            .fontWeight(.semibold)
                    }
                    .font(.title3)
                }

                Divider()

                // Total Bets Placed
                HStack {
                    Text("Total Bets Placed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(totalBetsPlaced)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                // Win Percentage
                HStack {
                    Text("Win Percentage")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(settledBets.isEmpty ? "—" : String(format: "%.1f%%", winRate))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(winRate >= 50 ? .green : .red)
                }

                Divider()

                // Total Profit/Loss
                HStack {
                    Text("Total Profit/Loss")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if settledBets.isEmpty {
                        Text("—")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    } else {
                        Text(formatProfitLoss(totalProfitLoss))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(totalProfitLoss >= 0 ? .green : .red)
                    }
                }

                // ROI
                HStack {
                    Text("ROI")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if settledBets.isEmpty {
                        Text("—")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    } else {
                        Text(String(format: "%+.1f%%", roiPercentage))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(roiPercentage >= 0 ? .green : .red)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
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
        VStack(alignment: .leading, spacing: 12) {
            Text("My Bets")
                .font(.headline)

            // Filter picker (Active, Settled, All)
            Picker("Filter", selection: $selectedBetFilter) {
                ForEach(BetHistoryFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            // Bets list
            if filteredPlayerBets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "ticket")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No bets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if selectedBetFilter != .all {
                        Text("Try changing the filter")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
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
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    /// Get event name for a bet
    private func eventName(for bet: Bet) -> String {
        if let event = allEvents.first(where: { $0.id.uuidString == bet.eventId }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    // MARK: - Transaction History Section

    private var transactionHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)

            // Filter picker
            Picker("Filter", selection: $selectedTransactionFilter) {
                ForEach(TransactionFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            // Transaction list
            if filteredLedgerEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No transactions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if selectedTransactionFilter != .all {
                        Text("Try changing the filter")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredLedgerEntries) { entry in
                        TransactionRowView(entry: entry)
                        if entry.id != filteredLedgerEntries.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
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
            return .blue
        case .adjustment:
            return .orange
        case .paymentLogged:
            return .green
        case .reversal:
            return .purple
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
        entry.amount >= 0 ? .green : .red
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
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: entry.createdAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 40)

            // Description and metadata
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.entryDescription)
                    .font(.subheadline)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(typeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Amount
            Text(formattedAmount)
                .font(.subheadline.bold())
                .foregroundStyle(amountColor)
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
            return .orange
        case .accepted, .readyToGrade:
            return .blue
        case .graded, .settled:
            if let result = bet.gradeResult {
                switch result {
                case .win: return .green
                case .loss: return .red
                case .push: return .orange
                }
            }
            return .green
        case .declined:
            return .red
        case .void:
            return .gray
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
        formatter.timeStyle = .short
        return formatter.string(from: bet.createdAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator circle
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .frame(width: 40)

            // Bet info
            VStack(alignment: .leading, spacing: 4) {
                // Event name
                Text(eventName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                // Side and odds
                HStack(spacing: 4) {
                    Text(bet.side)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(formattedOdds)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Status badge and stake
            VStack(alignment: .trailing, spacing: 4) {
                Text(statusText)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor)
                    .clipShape(Capsule())

                Text(formattedStake)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Chevron indicator
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
        events.first { $0.id.uuidString == bet.eventId }
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
        case .pending: return .orange
        case .accepted, .readyToGrade: return .blue
        case .declined: return .red
        case .graded, .settled:
            if let result = bet.gradeResult {
                switch result {
                case .win: return .green
                case .loss: return .red
                case .push: return .orange
                }
            }
            return .green
        case .void: return .gray
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
        guard let result = bet.gradeResult else { return .primary }
        switch result {
        case .win: return .green
        case .loss: return .red
        case .push: return .orange
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
                    Spacer()
                    Text(statusText)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(statusColor)
                        .clipShape(Capsule())
                }

                if let gradeResult = bet.gradeResult {
                    HStack {
                        Text("Result")
                        Spacer()
                        Text(gradeResult.rawValue.capitalized)
                            .fontWeight(.semibold)
                            .foregroundStyle(gradeResultColor)
                    }
                }
            }

            // Event Section
            Section("Event") {
                LabeledContent("Matchup", value: eventName)

                if let event = event {
                    LabeledContent("Sport", value: event.sport)
                    LabeledContent("League", value: event.league)

                    let eventFormatter = DateFormatter()
                    let _ = eventFormatter.dateStyle = .medium
                    let _ = eventFormatter.timeStyle = .short
                    LabeledContent("Start Time", value: eventFormatter.string(from: event.startTime))

                    LabeledContent("Event Status", value: event.status.rawValue.capitalized)

                    if let finalScore = event.finalScore {
                        LabeledContent("Final Score", value: finalScore)
                    }
                }
            }

            // Bet Details Section
            Section("Your Bet") {
                LabeledContent("Market", value: bet.market)
                LabeledContent("Selection", value: bet.side)
                LabeledContent("Odds", value: formattedOdds)
                LabeledContent("Stake", value: formattedStake)
            }

            // Payout Section
            Section("Potential Return") {
                LabeledContent("Profit if Win", value: formatCurrency(potentialPayout))
                    .foregroundStyle(.green)
                LabeledContent("Total Return", value: formatCurrency(totalReturn))
                    .fontWeight(.semibold)
            }

            // Details Section
            Section("Details") {
                LabeledContent("Placed", value: formattedDate)
                LabeledContent("Bet ID", value: String(bet.id.uuidString.prefix(8)) + "...")
                    .font(.caption)
            }
        }
        .navigationTitle("Bet Details")
        .navigationBarTitleDisplayMode(.inline)
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
