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
    @Query private var events: [Event]
    let player: Player

    @State private var showingLogoutConfirmation = false
    @State private var showingLogoutError = false
    @State private var logoutErrorMessage = ""
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteFinalConfirmation = false
    @State private var isBecomingOrganizer = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var selectedTransactionFilter: TransactionFilter = .all
    @AppStorage("playerOddsFormat") private var oddsFormat: String = OddsFormat.american.rawValue


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

    private func ticketForEntry(_ entry: LedgerEntry) -> Ticket? {
        guard let bet = entry.bet else { return nil }
        let ticketBets = playerBets.filter { $0.ticketId == bet.ticketId }
        guard !ticketBets.isEmpty else { return nil }
        return Ticket(id: bet.ticketId, bets: ticketBets)
    }

    private func parlayTitle(for entry: LedgerEntry) -> String? {
        guard let ticket = ticketForEntry(entry), ticket.isParlay else { return nil }
        let outcome: String
        switch entry.entryDescription.lowercased() {
        case let d where d.contains("won"): outcome = "Won"
        case let d where d.contains("lost"): outcome = "Lost"
        case let d where d.contains("push"): outcome = "Push"
        default: outcome = "Settled"
        }
        let oddsString = ticket.combinedAmericanOdds > 0 ? "+\(ticket.combinedAmericanOdds)" : "\(ticket.combinedAmericanOdds)"
        return "\(outcome) · \(ticket.bets.count)-leg Multi-Pick (\(oddsString))"
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
        .alert("Delete Account", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Continue", role: .destructive) {
                showingDeleteFinalConfirmation = true
            }
        } message: {
            Text("This will permanently delete your account and all your data. This action cannot be undone.")
        }
        .alert("Are you sure?", isPresented: $showingDeleteFinalConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete My Account", role: .destructive) {
                performAccountDeletion()
            }
        } message: {
            Text("This is your final confirmation. Your account will be permanently deleted.")
        }
        .alert("Deletion Error", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteError ?? "")
        }
        .overlay {
            if isDeletingAccount {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(Theme.accent)
                            .scaleEffect(1.5)
                        Text("Deleting account...")
                            .font(Theme.bodyFont(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(32)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
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

            Divider().background(Theme.divider)

            NavigationLink {
                PlayerProfileEditView(player: player)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.body)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)

                    Text("Edit Profile")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.accent)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.vertical, 12)
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
                    playerBets: playerBets,
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

            // "Be an Organizer" row for standalone users
            if authManager.isStandaloneUser {
                Divider()
                    .background(Theme.border)
                    .padding(.leading, 58)

                NavigationLink {
                    BecomeOrganizerView(onGetStarted: {
                        Task {
                            isBecomingOrganizer = true
                            do {
                                try await authManager.becomeOrganizer()
                            } catch {
                                print("Failed to become organizer: \(error)")
                            }
                            isBecomingOrganizer = false
                        }
                    })
                } label: {
                    playerMenuRow(icon: "crown.fill", title: "Be an Organizer", color: Theme.gold)
                }
            }

            Divider()
                .background(Theme.border)
                .padding(.leading, 58)

            NavigationLink {
                AboutSettingsView()
            } label: {
                playerMenuRow(icon: "info.circle", title: "About")
            }

            if authManager.userRole == .player || authManager.isStandaloneUser {
                Divider()
                    .background(Theme.border)
                    .padding(.leading, 58)

                Button {
                    showingLogoutConfirmation = true
                } label: {
                    playerMenuRow(icon: "rectangle.portrait.and.arrow.right", title: "Log Out", color: Theme.danger)
                }

                Divider()
                    .background(Theme.border)
                    .padding(.leading, 58)

                Button {
                    showingDeleteConfirmation = true
                } label: {
                    playerMenuRow(icon: "trash", title: "Delete Account", color: Theme.danger.opacity(0.7))
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
                .foregroundStyle(title == "Log Out" || title == "Delete Account" ? color : Theme.textPrimary)

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
                        if entry.type == .settlement, let ticket = ticketForEntry(entry) {
                            NavigationLink {
                                TicketDetailView(ticket: ticket)
                            } label: {
                                TransactionRowView(entry: entry, parlayTitle: parlayTitle(for: entry))
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                TransactionDetailView(entry: entry)
                            } label: {
                                TransactionRowView(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
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
            } catch {
                logoutErrorMessage = error.localizedDescription
                showingLogoutError = true
            }
        }
    }

    private func performAccountDeletion() {
        isDeletingAccount = true
        Task {
            do {
                let response: PlayerDeleteAccountResponse = try await EdgeFunctionService.shared.callFunction(
                    name: "delete_account",
                    body: PlayerEmptyRequest()
                )
                if response.success {
                    await MainActor.run {
                        isDeletingAccount = false
                    }
                    try await authManager.signOut()
                    BetSlipManager.shared.clearAll()
                } else {
                    await MainActor.run {
                        isDeletingAccount = false
                        deleteError = response.error ?? "Failed to delete account"
                    }
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    deleteError = error.localizedDescription
                }
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
    let playerBets: [Bet]
    @Binding var selectedFilter: TransactionFilter
    @Query private var events: [Event]
    @Query private var bookies: [Bookie]
    @State private var showingProUpgrade = false

    private var bookieIsPro: Bool {
        bookies.first?.isPro ?? false
    }

    private var isHistoryLimited: Bool {
        !bookieIsPro && filteredEntries.count > 30
    }

    private var displayedEntries: [LedgerEntry] {
        if bookieIsPro {
            return filteredEntries
        }
        return Array(filteredEntries.prefix(30))
    }

    private var filteredEntries: [LedgerEntry] {
        let sorted = ledgerEntries.sorted { $0.createdAt > $1.createdAt }
        guard let type = selectedFilter.entryType else {
            return sorted
        }
        return sorted.filter { $0.type == type }
    }

    private func ticketForEntry(_ entry: LedgerEntry) -> Ticket? {
        guard let bet = entry.bet else { return nil }
        let ticketBets = playerBets.filter { $0.ticketId == bet.ticketId }
        guard !ticketBets.isEmpty else { return nil }
        return Ticket(id: bet.ticketId, bets: ticketBets)
    }

    private func parlayTitle(for entry: LedgerEntry) -> String? {
        guard let ticket = ticketForEntry(entry), ticket.isParlay else { return nil }
        let outcome: String
        switch entry.entryDescription.lowercased() {
        case let d where d.contains("won"): outcome = "Won"
        case let d where d.contains("lost"): outcome = "Lost"
        case let d where d.contains("push"): outcome = "Push"
        default: outcome = "Settled"
        }
        let oddsString = ticket.combinedAmericanOdds > 0 ? "+\(ticket.combinedAmericanOdds)" : "\(ticket.combinedAmericanOdds)"
        return "\(outcome) · \(ticket.bets.count)-leg Multi-Pick (\(oddsString))"
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
                        ForEach(displayedEntries) { entry in
                            if entry.type == .settlement, let ticket = ticketForEntry(entry) {
                                NavigationLink {
                                    TicketDetailView(ticket: ticket)
                                } label: {
                                    TransactionRowView(entry: entry, parlayTitle: parlayTitle(for: entry))
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    TransactionDetailView(entry: entry)
                                } label: {
                                    TransactionRowView(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                            if entry.id != displayedEntries.last?.id {
                                Divider().background(Theme.divider)
                            }
                        }
                    }
                    .cardStyle()

                    if isHistoryLimited {
                        historyLimitFooter
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingProUpgrade) {
            ProUpgradeSheet(contextMessage: "See your full history")
        }
    }

    private var historyLimitFooter: some View {
        VStack(spacing: 6) {
            Text("Showing last 30 transactions")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)

            Button {
                showingProUpgrade = true
            } label: {
                Text("Upgrade to Pro for full history")
                    .font(Theme.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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
    var parlayTitle: String? = nil

    private var tagColor: Color {
        switch entry.type {
        case .settlement:
            // Color by outcome: green for wins, red for losses
            let desc = entry.entryDescription.lowercased()
            if desc.contains("won") { return Theme.accent }
            if desc.contains("lost") { return Theme.danger }
            return Theme.textMuted
        case .adjustment: return Theme.warning
        case .paymentLogged: return Color.purple
        case .reversal: return Theme.textMuted
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
        if let parlayTitle {
            return parlayTitle
        }
        if let bet = entry.bet {
            let outcome: String
            switch entry.entryDescription.lowercased() {
            case let d where d.contains("won"): outcome = "Won"
            case let d where d.contains("lost"): outcome = "Lost"
            case let d where d.contains("push"): outcome = "Push"
            case let d where d.contains("void"): outcome = "Voided"
            default: return entry.entryDescription
            }
            return "\(outcome) · \(bet.side)"
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
                    .lineLimit(1)

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

// MARK: - Transaction Detail View

struct TransactionDetailView: View {
    let entry: LedgerEntry

    /// Player-facing: negate internal convention
    private var displayAmount: Decimal { -entry.amount }

    private var amountColor: Color {
        displayAmount >= 0 ? Theme.accent : Theme.danger
    }

    private var typeLabel: String {
        switch entry.type {
        case .settlement: return "Graded"
        case .adjustment: return "Balance Adjustment"
        case .paymentLogged: return "Settled Up"
        case .reversal: return "Reversal"
        }
    }

    private var typeIcon: String {
        switch entry.type {
        case .settlement: return "checkmark.circle.fill"
        case .adjustment: return "plusminus.circle.fill"
        case .paymentLogged: return "banknote.fill"
        case .reversal: return "arrow.uturn.backward.circle.fill"
        }
    }

    private var typeColor: Color {
        switch entry.type {
        case .settlement: return Theme.scheduled
        case .adjustment: return Theme.warning
        case .paymentLogged: return Theme.accent
        case .reversal: return Color.purple
        }
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let absAmount = displayAmount < 0 ? -displayAmount : displayAmount
        let formatted = formatter.string(from: absAmount as NSDecimalNumber) ?? "$\(absAmount)"
        return displayAmount >= 0 ? "+\(formatted)" : "-\(formatted)"
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: entry.createdAt)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.border, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Amount hero
                VStack(spacing: 8) {
                    Image(systemName: typeIcon)
                        .font(.system(size: 44))
                        .foregroundStyle(typeColor)

                    Text(formattedAmount)
                        .font(Theme.font(size: 36, weight: .bold))
                        .foregroundStyle(amountColor)

                    Text(typeLabel)
                        .font(Theme.bodyFont(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(cardBackground)

                // Details card
                VStack(spacing: 0) {
                    detailsHeader

                    VStack(spacing: 10) {
                        labeledRow(label: "Date", value: formattedDate)

                        if !entry.entryDescription.isEmpty {
                            labeledRow(label: "Description", value: entry.entryDescription)
                        }

                        labeledRow(label: "Type", value: typeLabel)

                        Divider().background(Theme.divider)

                        labeledRow(
                            label: "Transaction ID",
                            value: String(entry.id.uuidString.prefix(8)) + "...",
                            valueColor: Theme.textMuted
                        )
                    }
                    .padding(12)
                }
                .background(cardBackground)
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailsHeader: some View {
        HStack {
            Text("DETAILS")
                .font(Theme.caption)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func labeledRow(label: String, value: String, valueColor: Color = Theme.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(Theme.bodyFont(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.bodyFont(size: 14, weight: .medium))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
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

private struct PlayerEmptyRequest: Encodable {}
private struct PlayerDeleteAccountResponse: Decodable {
    let success: Bool
    let error: String?
}
