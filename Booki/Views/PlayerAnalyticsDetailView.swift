import SwiftUI
import SwiftData
@preconcurrency import Supabase

struct PlayerAnalyticsDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService

    let summary: PlayerAnalyticsSummary
    let playerBets: [Bet]
    let playerLedgerEntries: [LedgerEntry]

    @Query private var allLedgerEntries: [LedgerEntry]
    @Query private var allBets: [Bet]
    @Query private var allEvents: [Event]

    @State private var showingArchiveConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    // Settle Up / Adjust Balance
    @State private var showingSettleUp = false
    @State private var showingAdjustBalance = false

    // Edit name
    @State private var showingEditName = false
    @State private var editedName = ""

    // Picks filter
    @State private var picksFilter: PicksFilter = .open

    enum PicksFilter: String, CaseIterable {
        case open = "Open"
        case graded = "Graded"
    }

    private var player: Player { summary.player }

    private var playerHasHistory: Bool {
        !playerBets.isEmpty || !playerLedgerEntries.isEmpty
    }

    private var livePlayerLedgerEntries: [LedgerEntry] {
        allLedgerEntries.filter { $0.player?.id == player.id }
    }

    private var livePlayerBets: [Bet] {
        allBets.filter { $0.player?.id == player.id }
    }

    private var balanceSummary: PlayerBalanceSummary {
        BalanceService.playerSummary(for: player, bets: livePlayerBets, ledgerEntries: livePlayerLedgerEntries)
    }

    private var utilization: Double {
        guard player.creditLimit > 0 else { return 0 }
        let used = player.creditLimit - balanceSummary.availableCredit
        return (used as NSDecimalNumber).doubleValue / (player.creditLimit as NSDecimalNumber).doubleValue * 100
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                ctaButtons
                todaySection
                performanceSection
                behaviorSection
                reliabilitySection
                recentActivityRow
                playerPicksSection
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(summary.player.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showingArchiveConfirmation = true
                    } label: {
                        Label("Archive Member", systemImage: "archivebox")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Remove Member", systemImage: "person.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(Theme.bodyFont(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .confirmationDialog(
            "Archive this member?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Member") {
                archivePlayer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archived members retain their history but are hidden from the active members list.")
        }
        .confirmationDialog(
            "Remove \(player.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Member", role: .destructive) {
                deletePlayer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the member from your group. Their pick and ledger history will be preserved. They will be able to join another group.")
        }
        .alert("Delete Error", isPresented: .init(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = deleteError {
                Text(error)
            }
        }
        .alert("Edit Name", isPresented: $showingEditName) {
            TextField("Name", text: $editedName)
            Button("Save") {
                saveName()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This name is only visible to you.")
        }
    }

    // MARK: - Actions

    private func saveName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != player.name else { return }

        let newName = trimmed
        let playerId = player.id.uuidString.lowercased()

        Task {
            do {
                let supabase = SupabaseClientManager.shared.client
                try await supabase
                    .from("players")
                    .update(["name": newName])
                    .eq("id", value: playerId)
                    .execute()

                await MainActor.run {
                    player.name = newName
                }
            } catch {
                print("Failed to update player name: \(error)")
            }
        }
    }

    private func archivePlayer() {
        let result = PlayerService.archivePlayer(player)
        switch result {
        case .success:
            dismiss()
        case .failure(let error):
            print("Failed to archive player: \(error)")
        }
    }

    private func deletePlayer() {
        isDeleting = true
        Task {
            do {
                // Sever the relationship: NULL out bookie_id and auth_user_id
                // The player record stays for bet/ledger history, but the user
                // is freed to join another group via a new invite
                let supabase = SupabaseClientManager.shared.client
                let nullValue: String? = nil
                try await supabase
                    .from("players")
                    .update([
                        "bookie_id": nullValue,
                        "auth_user_id": nullValue,
                    ])
                    .eq("id", value: player.id.uuidString.lowercased())
                    .execute()

                // Remove from local SwiftData so bookie's list updates immediately
                // Bets and ledger entries stay locally for historical views
                await MainActor.run {
                    modelContext.delete(player)
                    isDeleting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = "Failed to remove member: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(summary.player.name)
                    .font(Theme.title1)
                    .foregroundStyle(Theme.textPrimary)

                Button {
                    editedName = player.name
                    showingEditName = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // Balance + PAS badge
            HStack(alignment: .center) {
                Text(formattedBalanceLabel)
                    .font(Theme.font(size: 22, weight: .bold))
                    .foregroundStyle(balanceColor)

                Spacer()

                Text(summary.pas.label)
                    .font(Theme.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(pasLabelColor == Theme.textMuted ? Theme.textPrimary : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(pasLabelColor)
                    .clipShape(Capsule())
            }

            // Credit limit utilization
            Text("Credit: \(formatCurrency(player.creditLimit - balanceSummary.availableCredit)) / \(formatCurrency(player.creditLimit)) · \(Int(utilization))%")
                .font(Theme.bodyFont(size: 13))
                .foregroundStyle(Theme.textSecondary)

            // Reason chips
            if !summary.pas.reasonChips.isEmpty {
                DetailReasonChips(chips: summary.pas.reasonChips)
            }
        }
        .padding(16)
        .cardStyle()
    }

    // MARK: - CTA Buttons

    private var ctaButtons: some View {
        HStack(spacing: 12) {
            Button {
                showingSettleUp = true
            } label: {
                Text("SETTLE UP")
                    .font(Theme.headline)
                    .textCase(.uppercase)
                    .foregroundStyle(.black.opacity(balanceSummary.balanceOwed == 0 ? 0.4 : 1))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(balanceSummary.balanceOwed == 0 ? Theme.accent.opacity(0.3) : Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
            .disabled(balanceSummary.balanceOwed == 0)

            Button {
                showingAdjustBalance = true
            } label: {
                Text("ADJUST BALANCE")
                    .font(Theme.headline)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
        }
        .sheet(isPresented: $showingSettleUp) {
            SettleUpSheet(player: player, balanceOwed: balanceSummary.balanceOwed, modelContext: modelContext, syncService: syncService)
        }
        .sheet(isPresented: $showingAdjustBalance) {
            AdjustBalanceSheet(player: player, balanceOwed: balanceSummary.balanceOwed, modelContext: modelContext, syncService: syncService)
        }
    }

    // MARK: - Today Section

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)

            todayMetricRow(label: "Open Exposure", value: formatCurrency(summary.exposure.grossExposure))
            todayMetricRow(label: "Open Bets", value: "\(summary.exposure.pendingBetCount)")
            todayMetricRow(label: "Largest Open Bet", value: formatCurrency(summary.exposure.largestPendingBet))
        }
        .padding(16)
        .cardStyle()
    }

    private func todayMetricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.bodyFont(size: 15))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.font(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PERFORMANCE")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                PerformanceMetricCard(label: "7d P/L", value: formatSignedCurrency(summary.sevenDayPL), color: plColor(summary.sevenDayPL))
                PerformanceMetricCard(label: "30d P/L", value: formatSignedCurrency(summary.thirtyDayPL), color: plColor(summary.thirtyDayPL))
                PerformanceMetricCard(label: "All-time P/L", value: formatSignedCurrency(summary.allTimePL), color: plColor(summary.allTimePL))
                PerformanceMetricCard(label: "Win Rate", value: "\(Int(summary.winRate * 100))%", color: Theme.textPrimary)
            }
        }
        .padding(16)
        .cardStyle()
    }

    // MARK: - Behavior Section

    private var recentBets: [Bet] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return playerBets.filter { $0.createdAt >= thirtyDaysAgo }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BEHAVIOR")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)

            if recentBets.isEmpty {
                Text("No recent activity")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                behaviorMetrics
                MarketMixBar(bets: recentBets)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var behaviorMetrics: some View {
        VStack(spacing: 8) {
            todayMetricRow(label: "Avg Bet Size (30d)", value: formatCurrency(summary.avgBetSize30d))
            todayMetricRow(label: "Bets Per Week (30d)", value: String(format: "%.1f", Double(recentBets.count) / 4.3))
        }
    }

    // MARK: - Reliability Section

    /// Payments and settle-ups count for reliability tracking
    private var paymentEntries: [LedgerEntry] {
        livePlayerLedgerEntries.filter {
            $0.type == .paymentLogged || $0.entryDescription == "Settled up"
        }
    }

    private var liveOverdue: (isOverdue: Bool, amount: Decimal) {
        PlayerAttentionService.isOverdue(player: player, ledgerEntries: livePlayerLedgerEntries)
    }

    private var paymentStatus: (label: String, color: Color) {
        if paymentEntries.isEmpty {
            return ("No payments", Theme.textSecondary)
        } else if liveOverdue.isOverdue {
            return ("Overdue", Theme.danger)
        } else {
            return ("Current", Theme.accent)
        }
    }

    private var daysSinceLastPayment: String {
        guard let mostRecent = paymentEntries.max(by: { $0.createdAt < $1.createdAt }) else {
            return "Never"
        }
        let days = Calendar.current.dateComponents([.day], from: mostRecent.createdAt, to: Date()).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "1 day ago" }
        return "\(days) days ago"
    }

    private var reliabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RELIABILITY")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)

            HStack {
                Text("Payment Status")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(paymentStatus.label)
                    .font(Theme.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(paymentStatus.color == Theme.textSecondary ? Theme.textPrimary : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(paymentStatus.color)
                    .clipShape(Capsule())
            }

            todayMetricRow(label: "Last Payment", value: daysSinceLastPayment)

            if liveOverdue.isOverdue && liveOverdue.amount > 0 {
                HStack {
                    Text("Overdue Amount")
                        .font(Theme.bodyFont(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(formatCurrency(liveOverdue.amount))
                        .font(Theme.font(size: 17, weight: .bold))
                        .foregroundStyle(Theme.danger)
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    // MARK: - Recent Activity Row

    private var recentActivityRow: some View {
        NavigationLink {
            PlayerPickHistoryView(player: player)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, alignment: .center)

                Text("Recent Activity")
                    .font(Theme.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Text("\(livePlayerLedgerEntries.count)")
                    .font(Theme.bodyFont(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .cardStyle()
    }

    // MARK: - Player Picks Section

    private var openBets: [Bet] {
        livePlayerBets
            .filter { [.pending, .accepted, .readyToGrade].contains($0.status) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var gradedBets: [Bet] {
        livePlayerBets
            .filter { [BetStatus.graded, .settled, .void].contains($0.status) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredBets: [Bet] {
        picksFilter == .open ? openBets : gradedBets
    }

    private func eventName(for bet: Bet) -> String {
        if let desc = bet.eventDescription { return desc }
        if let event = allEvents.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Unknown Event"
    }

    private var displayBets: [Bet] {
        Array(filteredBets.prefix(5))
    }

    private var playerPicksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PICKS")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(1.0)

                Spacer()

                if filteredBets.count > 5 {
                    NavigationLink {
                        PlayerPicksListView(player: player, initialFilter: picksFilter)
                    } label: {
                        Text("See All (\(filteredBets.count))")
                            .font(Theme.bodyFont(size: 13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            Picker("Filter", selection: $picksFilter) {
                ForEach(PicksFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            if filteredBets.isEmpty {
                Text(picksFilter == .open ? "No open picks" : "No graded picks")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(displayBets.enumerated()), id: \.element.id) { index, bet in
                    BetHistoryRow(bet: bet, eventName: eventName(for: bet))
                    if index < displayBets.count - 1 {
                        Divider().overlay(Theme.elevatedBackground)
                    }
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    // MARK: - Helpers (P/L)

    private func plColor(_ value: Decimal) -> Color {
        if value > 0 { return Theme.accent }
        if value < 0 { return Theme.danger }
        return Theme.textSecondary
    }

    private func formatSignedCurrency(_ value: Decimal) -> String {
        let formatted = formatCurrency(abs(value))
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
    }

    private func abs(_ value: Decimal) -> Decimal {
        return value < 0 ? -value : value
    }

    // MARK: - Helpers

    private var formattedBalanceLabel: String {
        let amount = balanceSummary.balanceOwed
        if amount > 0 {
            return "Owes \(formatCurrency(amount))"
        } else if amount < 0 {
            return "You owe \(formatCurrency(-amount))"
        }
        return "Settled"
    }

    private var balanceColor: Color {
        // Positive balanceOwed = player owes bookie (good for bookie, green)
        // Negative = bookie owes player (bad, red)
        if balanceSummary.balanceOwed > 0 { return Theme.accent }
        if balanceSummary.balanceOwed < 0 { return Theme.danger }
        return Theme.textSecondary
    }

    private var pasLabelColor: Color {
        switch summary.pas.label {
        case "High": return Theme.danger
        case "Medium": return Theme.warning
        default: return Theme.textMuted
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Adjust Balance Request/Response

private struct AdjustBalanceRequest: Encodable {
    let playerId: String
    let amount: String
    let reason: String
    var type: String?
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case amount
        case reason
        case type
        case idempotencyKey = "idempotency_key"
    }
}

private struct AdjustBalanceResponse: Decodable {
    let success: Bool
}

// MARK: - Settle Up Sheet

private struct SettleUpSheet: View {
    let player: Player
    let balanceOwed: Decimal
    let modelContext: ModelContext
    let syncService: SyncService
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var idempotencyKey = UUID().uuidString

    private var formattedBalanceOwed: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: balanceOwed as NSDecimalNumber) ?? "$\(balanceOwed)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    // Confirmation message
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.accent)

                        Text("Settle \(player.name)'s balance?")
                            .font(Theme.font(size: 20, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("This will zero out the outstanding balance of \(formattedBalanceOwed).")
                            .font(Theme.bodyFont(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()

                    if let error = errorMessage {
                        Text(error)
                            .font(Theme.bodyFont(size: 13))
                            .foregroundStyle(Theme.danger)
                    }

                    // CTA
                    Button {
                        Task { await submitSettlement() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("CONFIRM SETTLED")
                                .font(Theme.font(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(isLoading ? Theme.accent.opacity(0.5) : Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    .disabled(isLoading)
                }
                .padding()
            }
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func submitSettlement() async {
        isLoading = true
        errorMessage = nil

        let amount = balanceOwed
        let reason = "Settled up"

        var request = AdjustBalanceRequest(
            playerId: player.id.uuidString.lowercased(),
            amount: "\(-amount)",
            reason: reason,
            idempotencyKey: idempotencyKey
        )
        request.type = "paymentLogged"

        print("[SettleUpSheet] Submitting settlement: player=\(player.id), amount=\(-amount), idempotencyKey=\(idempotencyKey)")

        do {
            let response: AdjustBalanceResponse = try await EdgeFunctionService.shared.callFunction(
                name: "adjust_balance",
                body: request
            )

            print("[SettleUpSheet] Edge function returned: success=\(response.success)")

            // Pull down the new ledger entry from server immediately
            print("[SettleUpSheet] Triggering ledger sync...")
            await syncService.syncTable(.ledgerEntries)
            print("[SettleUpSheet] Ledger sync complete")

            await MainActor.run {
                isLoading = false
                dismiss()
            }
        } catch {
            print("[SettleUpSheet] Error: \(error)")
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Adjust Balance Sheet

private struct AdjustBalanceSheet: View {
    let player: Player
    let balanceOwed: Decimal
    let modelContext: ModelContext
    let syncService: SyncService
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var isCredit = false // false = increase debt (positive), true = credit (negative)
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var idempotencyKey = UUID().uuidString

    private var amountDecimal: Decimal? {
        guard !amountText.isEmpty else { return nil }
        return Decimal(string: amountText)
    }

    private var isValid: Bool {
        guard let amount = amountDecimal else { return false }
        return amount > 0 && !isLoading
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    private var formattedBalanceOwed: String {
        formatCurrency(balanceOwed)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Current balance
                    HStack {
                        Text("Current")
                            .font(Theme.bodyFont(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(balanceOwed > 0 ? "Owes \(formattedBalanceOwed)" : balanceOwed < 0 ? "You owe \(formatCurrency(-balanceOwed))" : "Settled")
                            .font(Theme.font(size: 17, weight: .bold))
                            .foregroundStyle(balanceOwed > 0 ? Theme.accent : balanceOwed < 0 ? Theme.danger : Theme.textSecondary)
                    }
                    .padding(14)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))

                    // Direction picker
                    Picker("Direction", selection: $isCredit) {
                        Text("Add to Balance").tag(false)
                        Text("Credit / Reduce").tag(true)
                    }
                    .pickerStyle(.segmented)

                    // Amount display
                    VStack(spacing: 4) {
                        Text("$\(amountText.isEmpty ? "0" : amountText)")
                            .font(Theme.font(size: 36, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)

                        Text(isCredit
                            ? "This will reduce what \(player.name) owes"
                            : "This will increase what \(player.name) owes")
                            .font(Theme.bodyFont(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                    if let error = errorMessage {
                        Text(error)
                            .font(Theme.bodyFont(size: 13))
                            .foregroundStyle(Theme.danger)
                    }

                    Spacer()

                    // Keypad + CTA
                    NumericKeypadView(text: $amountText)

                    Button {
                        Task { await submitAdjustment() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("CONFIRM ADJUSTMENT")
                                .font(Theme.font(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(isValid ? Theme.accent : Theme.accent.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    .disabled(!isValid)
                }
                .padding()
            }
            .navigationTitle("Adjust Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func submitAdjustment() async {
        guard let amount = amountDecimal else { return }
        isLoading = true
        errorMessage = nil

        let signedAmount = isCredit ? -amount : amount
        let description = "Balance adjustment"

        let request = AdjustBalanceRequest(
            playerId: player.id.uuidString.lowercased(),
            amount: "\(signedAmount)",
            reason: description,
            idempotencyKey: idempotencyKey
        )

        print("[AdjustBalanceSheet] Submitting adjustment: player=\(player.id), amount=\(signedAmount), isCredit=\(isCredit), idempotencyKey=\(idempotencyKey)")

        do {
            let response: AdjustBalanceResponse = try await EdgeFunctionService.shared.callFunction(
                name: "adjust_balance",
                body: request
            )

            print("[AdjustBalanceSheet] Edge function returned: success=\(response.success)")

            // Pull down the new ledger entry from server immediately
            print("[AdjustBalanceSheet] Triggering ledger sync...")
            await syncService.syncTable(.ledgerEntries)
            print("[AdjustBalanceSheet] Ledger sync complete")

            await MainActor.run {
                isLoading = false
                dismiss()
            }
        } catch {
            print("[AdjustBalanceSheet] Error: \(error)")
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Performance Metric Card

private struct PerformanceMetricCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.font(size: 17, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }
}

// MARK: - Detail Reason Chips

private struct DetailReasonChips: View {
    let chips: [String]
    @State private var showingTagExplainer = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(chips.prefix(3)), id: \.self) { chip in
                Button {
                    showingTagExplainer = true
                } label: {
                    Text(chip)
                        .font(Theme.bodyFont(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(chipColor(for: chip).opacity(0.25))
                        .clipShape(Capsule())
                }
            }
        }
        .sheet(isPresented: $showingTagExplainer) {
            TagExplainerSheet()
                .presentationDetents([.medium])
                .presentationBackground(Theme.background)
        }
    }

    private func chipColor(for chip: String) -> Color {
        switch chip {
        case "Overdue": return Theme.danger
        case "On Heater": return Theme.gold
        case "Cold Streak": return Theme.accentTertiary
        case "Whale": return Theme.accentSecondary
        case "Parlay Demon": return Theme.scheduled
        case "Degen": return Theme.warning
        case "Picks Pending": return Theme.accent
        default: return Theme.textMuted
        }
    }
}

// MARK: - Market Mix Bar

private struct MarketMixBar: View {
    let bets: [Bet]

    private struct MarketSegment: Identifiable {
        let id = UUID()
        let label: String
        let percentage: Double
        let color: Color
    }

    private var segments: [MarketSegment] {
        var counts: [String: Int] = ["Spread": 0, "Moneyline": 0, "Total": 0, "Multi-Pick": 0]
        for bet in bets {
            if bet.isParlay {
                counts["Multi-Pick", default: 0] += 1
            } else {
                let market = bet.market.lowercased()
                if market.contains("spread") {
                    counts["Spread", default: 0] += 1
                } else if market.contains("moneyline") {
                    counts["Moneyline", default: 0] += 1
                } else if market.contains("total") {
                    counts["Total", default: 0] += 1
                }
            }
        }

        let total = Double(counts.values.reduce(0, +))
        guard total > 0 else { return [] }

        let colorMap: [String: Color] = [
            "Spread": Theme.accent,
            "Moneyline": Theme.accentSecondary,
            "Total": Theme.gold,
            "Multi-Pick": Theme.accentTertiary
        ]

        let order = ["Spread", "Moneyline", "Total", "Multi-Pick"]
        return order.compactMap { key in
            let count = counts[key] ?? 0
            guard count > 0 else { return nil }
            return MarketSegment(label: key, percentage: Double(count) / total, color: colorMap[key] ?? Theme.textMuted)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Market Mix")
                .font(Theme.bodyFont(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(segments) { segment in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(segment.color)
                            .frame(width: max(geometry.size.width * segment.percentage - 2, 4))
                    }
                }
            }
            .frame(height: 12)

            // Legend
            HStack(spacing: 12) {
                ForEach(segments) { segment in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 8, height: 8)
                        Text("\(segment.label) \(Int(segment.percentage * 100))%")
                            .font(Theme.bodyFont(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Recent Activity Section

private struct RecentActivitySection: View {
    let player: Player
    let playerBets: [Bet]
    let playerLedgerEntries: [LedgerEntry]
    @Query private var events: [Event]

    private enum ActivityItem: Identifiable {
        case bet(Bet)
        case ledger(LedgerEntry)

        var id: String {
            switch self {
            case .bet(let bet): return "bet-\(bet.id)"
            case .ledger(let entry): return "ledger-\(entry.id)"
            }
        }

        var date: Date {
            switch self {
            case .bet(let bet): return bet.createdAt
            case .ledger(let entry): return entry.createdAt
            }
        }
    }

    private var activities: [ActivityItem] {
        var items: [ActivityItem] = []
        for bet in playerBets {
            items.append(.bet(bet))
        }
        for entry in playerLedgerEntries {
            items.append(.ledger(entry))
        }
        return items.sorted { $0.date > $1.date }
    }

    private var displayItems: [ActivityItem] {
        Array(activities.prefix(10))
    }

    private func eventName(for bet: Bet) -> String {
        if let desc = bet.eventDescription { return desc }
        if let event = events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Unknown Event"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT ACTIVITY")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)
                .padding(.leading, 16)

            if activities.isEmpty {
                Text("No activity yet")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .padding(.leading, 16)
            } else {
                ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                    activityRow(item)
                    if index < displayItems.count - 1 {
                        Divider().overlay(Theme.elevatedBackground)
                    }
                }

                if activities.count > 10 {
                    NavigationLink {
                        PlayerPickHistoryView(player: player)
                    } label: {
                        HStack {
                            Spacer()
                            Text("View All (\(activities.count))")
                                .font(Theme.bodyFont(size: 13, weight: .medium))
                                .foregroundStyle(Theme.accent)
                            Spacer()
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.top, 12)
        .padding(.trailing, 16)
        .padding(.bottom, 4)
        .padding(.leading, 0)
        .cardStyle()
    }

    @ViewBuilder
    private func activityRow(_ item: ActivityItem) -> some View {
        switch item {
        case .bet(let bet):
            BetHistoryRow(bet: bet, eventName: eventName(for: bet))
        case .ledger(let entry):
            LedgerHistoryRow(entry: entry)
        }
    }
}

// MARK: - Bet History Row

struct BetHistoryRow: View {
    let bet: Bet
    let eventName: String

    private var description: String {
        let side = "\(bet.side) \(formatOdds(bet.odds))"
        return "\(eventName) · \(side)"
    }

    private var amountColor: Color {
        switch bet.gradeResult {
        case .win: return Theme.danger   // Bookie lost money
        case .loss: return Theme.accent   // Bookie won money
        case .push, nil: return Theme.textSecondary
        }
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let formatted = formatter.string(from: bet.stake as NSDecimalNumber) ?? "$\(bet.stake)"
        return formatted
    }

    private var typeLabel: String {
        switch bet.gradeResult {
        case .win: return "Won"
        case .loss: return "Lost"
        case .push: return "Push"
        case nil: return "Pending"
        }
    }

    private var tagColor: Color {
        switch bet.gradeResult {
        case .win: return Theme.accent
        case .loss: return Theme.danger
        case .push: return Theme.textMuted
        case nil: return Theme.textSecondary
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 2, topTrailingRadius: 2)
                .fill(tagColor)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(description)
                    .font(Theme.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                Text(formatDate(bet.createdAt))
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
        }
        .padding(.vertical, 8)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatOdds(_ odds: Int) -> String {
        odds > 0 ? "+\(odds)" : "\(odds)"
    }
}

// MARK: - Ledger History Row

struct LedgerHistoryRow: View {
    let entry: LedgerEntry

    private var description: String {
        // Use entryDescription from server when available, with fallback
        let desc = entry.entryDescription
        if !desc.isEmpty && desc != "Balance adjustment" {
            return desc
        }
        switch entry.type {
        case .adjustment: return "Balance Adjustment"
        case .paymentLogged: return "Settled Up"
        case .reversal: return "Reversal"
        case .settlement: return "Pick Graded"
        }
    }

    private var amountColor: Color {
        // Bookie convention: positive = player owes more (good), negative = bookie owes (bad)
        entry.amount >= 0 ? Theme.accent : Theme.danger
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let absAmount = entry.amount < 0 ? -entry.amount : entry.amount
        let formatted = formatter.string(from: absAmount as NSDecimalNumber) ?? "$\(absAmount)"
        return entry.amount >= 0 ? "+\(formatted)" : "-\(formatted)"
    }

    private var typeLabel: String {
        switch entry.type {
        case .adjustment: return "Adjustment"
        case .paymentLogged: return "Settled"
        case .reversal: return "Reversal"
        case .settlement: return "Graded"
        }
    }

    private var tagColor: Color {
        switch entry.type {
        case .settlement: return Theme.scheduled
        case .adjustment: return Theme.warning
        case .paymentLogged: return Theme.accent
        case .reversal: return Color.purple
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 2, topTrailingRadius: 2)
                .fill(tagColor)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(description)
                    .font(Theme.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                Text(formatDate(entry.createdAt))
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
        }
        .padding(.vertical, 8)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Tag Explainer Sheet

struct TagExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct TagInfo: Identifiable {
        let id = UUID()
        let name: String
        let description: String
        let color: Color
    }

    private let tags: [TagInfo] = [
        TagInfo(name: "Picks Pending", description: "This member has open picks waiting to be graded.", color: Theme.accent),
        TagInfo(name: "Overdue", description: "Outstanding balance with no recent payment in the last 7 days.", color: Theme.danger),
        TagInfo(name: "On Heater", description: "On a hot streak — winning big over the last 7 days.", color: Theme.gold),
        TagInfo(name: "Cold Streak", description: "Losing consistently over the last 7 days.", color: Theme.accentTertiary),
        TagInfo(name: "Whale", description: "Average pick size exceeds $200 over the last 30 days.", color: Theme.accentSecondary),
        TagInfo(name: "Degen", description: "High day-to-day swings in pick results.", color: Theme.warning),
        TagInfo(name: "Parlay Demon", description: "More than half of recent picks are multi-picks.", color: Theme.scheduled),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tags are auto-assigned based on each member's recent activity and help you spot trends at a glance.")
                        .font(Theme.bodyFont(size: 14))
                        .foregroundStyle(Theme.textSecondary)

                    ForEach(tags) { tag in
                        HStack(alignment: .top, spacing: 12) {
                            Text(tag.name)
                                .font(Theme.bodyFont(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(tag.color.opacity(0.25))
                                .clipShape(Capsule())
                                .frame(width: 120, alignment: .leading)

                            Text(tag.description)
                                .font(Theme.bodyFont(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Member Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}
