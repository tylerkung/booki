import SwiftUI
import SwiftData
@preconcurrency import Supabase

/// Filter options for collection status
enum CollectionFilter: String, CaseIterable, Identifiable {
    case all
    case reminded
    case promised
    case overdue
    case anyStatus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .reminded: return "Reminded"
        case .promised: return "Promised"
        case .overdue: return "Overdue"
        case .anyStatus: return "Any Status"
        }
    }
}

struct PlayersListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var players: [Player]
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    @State private var showArchived = false
    @State private var showingAddPlayer = false
    @State private var showingAddPlayerInterstitial = false
    @State private var collectionFilter: CollectionFilter = .all

    private var filteredPlayers: [Player] {
        var result = players

        // Filter by archived status
        if !showArchived {
            result = result.filter { $0.status != .archived }
        }

        // Filter by collection status
        switch collectionFilter {
        case .all:
            break // No additional filtering
        case .reminded:
            result = result.filter { $0.collectionStatus == .reminded }
        case .promised:
            result = result.filter { $0.collectionStatus == .promised }
        case .overdue:
            result = result.filter { $0.collectionStatus == .overdue }
        case .anyStatus:
            result = result.filter {
                $0.collectionStatus != nil && $0.collectionStatus != .noStatus
            }
        }

        return result
    }

    /// Count of players with any collection status (for badge)
    private var playersWithCollectionStatus: Int {
        players.filter {
            $0.collectionStatus != nil && $0.collectionStatus != .noStatus && balanceForPlayer($0) > 0
        }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredPlayers.isEmpty {
                    ContentUnavailableView(
                        "No Members",
                        systemImage: "person.2.slash",
                        description: Text("Add members to start managing your group.")
                    )
                } else {
                    ForEach(filteredPlayers) { player in
                        NavigationLink(value: player) {
                            PlayerRowView(
                                player: player,
                                balance: balanceForPlayer(player),
                                utilization: utilizationForPlayer(player)
                            )
                        }
                    }
                    .listRowBackground(Theme.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Members")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Toggle(isOn: $showArchived) {
                            Label("Show Archived", systemImage: "archivebox")
                        }
                        .toggleStyle(.button)
                        .tint(showArchived ? Theme.accent : Theme.textSecondary)

                        Menu {
                            ForEach(CollectionFilter.allCases) { filter in
                                Button {
                                    collectionFilter = filter
                                } label: {
                                    HStack {
                                        Text(filter.displayName)
                                        if collectionFilter == filter {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Collection Filter", systemImage: "line.3.horizontal.decrease.circle")
                                .foregroundStyle(collectionFilter != .all ? Theme.accent : Theme.textSecondary)
                        }
                        .overlay(alignment: .topTrailing) {
                            if playersWithCollectionStatus > 0 && collectionFilter == .all {
                                Text("\(playersWithCollectionStatus)")
                                    .font(Theme.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.background)
                                    .padding(4)
                                    .background(Theme.danger)
                                    .clipShape(Circle())
                                    .offset(x: 8, y: -8)
                            }
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddPlayerInterstitial = true
                    } label: {
                        Label("Add Member", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: Player.self) { player in
                PlayerDetailView(player: player)
            }
            .sheet(isPresented: $showingAddPlayer) {
                AddPlayerSheet()
            }
            .sheet(isPresented: $showingAddPlayerInterstitial) {
                AddPlayerInterstitialSheet(showingAddPlayer: $showingAddPlayer)
            }
        }
    }

    // MARK: - Helper Methods

    private func balanceForPlayer(_ player: Player) -> Decimal {
        let playerLedgerEntries = ledgerEntries.filter { $0.player?.id == player.id }
        return BalanceService.calculateBalance(from: playerLedgerEntries)
    }

    private func utilizationForPlayer(_ player: Player) -> Double {
        guard player.creditLimit > 0 else { return 0 }

        let playerBets = bets.filter { $0.player?.id == player.id }
        let playerLedgerEntries = ledgerEntries.filter { $0.player?.id == player.id }

        let summary = BalanceService.playerSummary(
            for: player,
            bets: playerBets,
            ledgerEntries: playerLedgerEntries
        )

        // Utilization = (creditLimit - availableCredit) / creditLimit * 100
        let used = player.creditLimit - summary.availableCredit
        let utilization = (used as NSDecimalNumber).doubleValue / (player.creditLimit as NSDecimalNumber).doubleValue
        return max(0, min(1, utilization)) * 100
    }
}

// MARK: - Player Row View

struct PlayerRowView: View {
    let player: Player
    let balance: Decimal
    let utilization: Double

    /// Whether to show collection status (only when player owes money)
    private var shouldShowCollectionStatus: Bool {
        balance > 0 && player.collectionStatus != nil && player.collectionStatus != .noStatus
    }

    private var collectionStatusColor: Color {
        switch player.collectionStatus {
        case .noStatus, nil: return Theme.textMuted
        case .reminded: return Theme.warning
        case .promised: return Theme.accent
        case .overdue: return Theme.danger
        }
    }

    private var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: balance as NSDecimalNumber) ?? "$\(balance)"
    }

    private var formattedCreditLimit: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: player.creditLimit as NSDecimalNumber) ?? "$\(player.creditLimit)"
    }

    private var statusColor: Color {
        switch player.status {
        case .active: return Theme.accent
        case .archived: return Theme.textMuted
        case .banned: return Theme.danger
        }
    }

    private var statusText: String {
        switch player.status {
        case .active: return "Active"
        case .archived: return "Archived"
        case .banned: return "Banned"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(player.name)
                        .font(Theme.headline)

                    Text(statusText)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor)
                        .clipShape(Capsule())

                    if shouldShowCollectionStatus, let collectionStatus = player.collectionStatus {
                        Text(collectionStatus.displayName)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(collectionStatusColor)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 12) {
                    Text("Balance: \(formattedBalance)")
                        .font(Theme.subheadline)
                        .foregroundStyle(balanceColor)

                    Text("Limit: \(formattedCreditLimit)")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            // Utilization percentage
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(utilization))%")
                    .font(Theme.title3)
                    .foregroundStyle(utilizationColor)

                Text("Utilized")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var utilizationColor: Color {
        if utilization >= 90 {
            return Theme.danger
        } else if utilization >= 70 {
            return Theme.warning
        } else {
            return Theme.textPrimary
        }
    }

    private var balanceColor: Color {
        // Positive balance = player owes bookie (secondary color)
        // Negative balance = bookie owes player (accent - player is winning)
        balance >= 0 ? Theme.textSecondary : Theme.accent
    }
}

// MARK: - Player Detail View

struct PlayerDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService
    @Query private var allBets: [Bet]
    @Query private var allLedgerEntries: [LedgerEntry]
    @Query private var events: [Event]

    let player: Player

    @State private var showingArchiveConfirmation = false
    @State private var showingBanConfirmation = false
    @State private var showingReactivateConfirmation = false
    @State private var showingAdjustmentSheet = false
    @State private var showingPaymentSheet = false
    @State private var showingPromisedDatePicker = false
    @State private var promisedDate: Date = Date()
    @State private var showingRevokeCodeConfirmation = false
    @State private var codeCopied = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    // MARK: - Computed Properties

    private var playerBets: [Bet] {
        allBets.filter { $0.player?.id == player.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var playerLedgerEntries: [LedgerEntry] {
        allLedgerEntries.filter { $0.player?.id == player.id }
    }

    private var balanceSummary: PlayerBalanceSummary {
        BalanceService.playerSummary(
            for: player,
            bets: playerBets,
            ledgerEntries: playerLedgerEntries
        )
    }

    private var formattedBalance: String {
        formatCurrency(balanceSummary.balanceOwed)
    }

    private var formattedCreditLimit: String {
        formatCurrency(player.creditLimit)
    }

    private var formattedAvailableCredit: String {
        formatCurrency(balanceSummary.availableCredit)
    }

    private var formattedOpenLiability: String {
        formatCurrency(balanceSummary.openLiability)
    }

    private var statusColor: Color {
        switch player.status {
        case .active: return Theme.accent
        case .archived: return Theme.textMuted
        case .banned: return Theme.danger
        }
    }

    private var statusText: String {
        switch player.status {
        case .active: return "Active"
        case .archived: return "Archived"
        case .banned: return "Banned"
        }
    }

    private var balanceOwedColor: Color {
        balanceSummary.balanceOwed >= 0 ? Theme.textSecondary : Theme.accent
    }

    private var availableCreditColor: Color {
        balanceSummary.availableCredit >= 0 ? Theme.textPrimary : Theme.danger
    }

    private var openLiabilityColor: Color {
        balanceSummary.openLiability > 0 ? Theme.warning : Theme.textSecondary
    }

    /// Whether to show collection status section (only when player owes money)
    private var shouldShowCollectionStatus: Bool {
        balanceSummary.balanceOwed > 0
    }

    private var collectionStatusColor: Color {
        switch player.collectionStatus {
        case .noStatus, nil: return Theme.textMuted
        case .reminded: return Theme.warning
        case .promised: return Theme.accent
        case .overdue: return Theme.danger
        }
    }

    private var collectionStatusText: String {
        player.collectionStatus?.displayName ?? "None"
    }

    /// Whether the player has any bets or ledger entries (for delete warning)
    private var playerHasHistory: Bool {
        PlayerService.playerHasHistory(player, bets: allBets, ledgerEntries: allLedgerEntries)
    }

    // MARK: - Body

    var body: some View {
        List {
            // MARK: - Status Section
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(statusText)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(statusColor)
                        .clipShape(Capsule())
                }

                if let email = player.email {
                    LabeledContent("Email", value: email)
                }
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Invite Code Section
            Section("Member Account") {
                if let claimedAt = player.claimedAt {
                    // Account has been claimed
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Account Claimed")
                                .font(Theme.headline)
                            Text(claimedAt, style: .date)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                } else if let code = player.inviteCode {
                    // Code exists but not claimed
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Invite Code")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)

                        HStack(spacing: 12) {
                            Text(code)
                                .font(.system(.title2, design: .monospaced))
                                .fontWeight(.bold)
                                .kerning(2)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = code
                                codeCopied = true
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()

                                // Reset copy state after 2 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    codeCopied = false
                                }
                            } label: {
                                Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                    .font(Theme.title3)
                                    .foregroundStyle(codeCopied ? Theme.accent : Theme.accent)
                            }
                        }

                        if let generatedAt = player.inviteCodeGeneratedAt {
                            Text("Generated \(generatedAt, style: .relative) ago")
                                .font(Theme.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        if let expiresAt = player.inviteCodeExpiresAt {
                            if Date() > expiresAt {
                                Text("Expired")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.danger)
                            } else {
                                Text("Expires \(expiresAt, style: .date)")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.warning)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        showingRevokeCodeConfirmation = true
                    } label: {
                        Label("Revoke Code", systemImage: "xmark.circle")
                    }
                } else {
                    // No code exists
                    Text("No invite code generated")
                        .foregroundStyle(Theme.textSecondary)
                        .italic()

                    Button {
                        generateInviteCode()
                    } label: {
                        Label("Generate Invite Code", systemImage: "envelope.badge.person.crop")
                    }
                }
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Balance Section
            Section("Balance") {
                LabeledContent("Balance Owed") {
                    Text(formattedBalance)
                        .foregroundStyle(balanceOwedColor)
                }

                LabeledContent("Credit Limit", value: formattedCreditLimit)

                LabeledContent("Available Credit") {
                    Text(formattedAvailableCredit)
                        .foregroundStyle(availableCreditColor)
                }

                LabeledContent("Open Liability") {
                    Text(formattedOpenLiability)
                        .foregroundStyle(openLiabilityColor)
                }
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Collection Status Section
            if shouldShowCollectionStatus {
                Section("Collection Status") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(collectionStatusText)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(collectionStatusColor)
                            .clipShape(Capsule())
                    }

                    if let statusDate = player.collectionStatusDate {
                        LabeledContent("Status Updated") {
                            Text(statusDate, style: .date)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    if player.collectionStatus == .promised, let promisedDate = player.promisedPaymentDate {
                        LabeledContent("Promised Date") {
                            Text(promisedDate, style: .date)
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    // Collection action buttons
                    collectionActionButtons
                }
                .listRowBackground(Theme.cardBackground)
            }

            // MARK: - Bet History Section
            Section("Pick History (\(playerBets.count))") {
                if playerBets.isEmpty {
                    Text("No picks yet")
                        .foregroundStyle(Theme.textSecondary)
                        .italic()
                } else {
                    ForEach(playerBets) { bet in
                        PlayerBetRowView(
                            bet: bet,
                            event: findEvent(for: bet)
                        )
                    }
                }
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Actions Section
            Section("Actions") {
                // View Player's Bet History
                NavigationLink {
                    TrackView(player: player)
                } label: {
                    Label("View My Picks", systemImage: "clock.arrow.circlepath")
                }

                // Submit Bet Request (only for active players)
                if player.status == .active {
                    NavigationLink {
                        SubmitBetView(player: player)
                    } label: {
                        Label("Submit Request", systemImage: "plus.circle")
                    }
                }

                // Balance Adjustment
                Button {
                    showingAdjustmentSheet = true
                } label: {
                    Label("Adjust Balance", systemImage: "dollarsign.circle")
                }

                // Record Payment
                Button {
                    showingPaymentSheet = true
                } label: {
                    Label("Record Payment", systemImage: "banknote")
                }

                // Status Actions (contextual)
                statusActionButtons
            }
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdjustmentSheet) {
            BalanceAdjustmentSheet(player: player)
        }
        .sheet(isPresented: $showingPaymentSheet) {
            PaymentSheet(player: player)
        }
        .sheet(isPresented: $showingPromisedDatePicker) {
            PromisedDateSheet(
                promisedDate: $promisedDate,
                onSave: { date in
                    markAsPromised(date: date)
                }
            )
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
            "Ban this member?",
            isPresented: $showingBanConfirmation,
            titleVisibility: .visible
        ) {
            Button("Ban Member", role: .destructive) {
                banPlayer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Banned members cannot submit new picks. Their existing picks and history are retained.")
        }
        .confirmationDialog(
            "Reactivate this member?",
            isPresented: $showingReactivateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reactivate Member") {
                reactivatePlayer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore the member to active status, allowing them to submit new picks.")
        }
        .confirmationDialog(
            "Revoke invite code?",
            isPresented: $showingRevokeCodeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Revoke Code", role: .destructive) {
                revokeInviteCode()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The member will no longer be able to use this code to claim their account.")
        }
        .confirmationDialog(
            "Delete \(player.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Member", role: .destructive) {
                deletePlayer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if playerHasHistory {
                Text("This member has picks or ledger entries. Deleting will permanently remove the member and all their history. This cannot be undone.")
            } else {
                Text("This will permanently delete the member. This cannot be undone.")
            }
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
    }

    // MARK: - Status Action Buttons

    @ViewBuilder
    private var statusActionButtons: some View {
        switch player.status {
        case .active:
            Button {
                showingArchiveConfirmation = true
            } label: {
                Label("Archive Member", systemImage: "archivebox")
            }

            Button(role: .destructive) {
                showingBanConfirmation = true
            } label: {
                Label("Ban Member", systemImage: "person.crop.circle.badge.xmark")
            }

        case .archived:
            Button {
                showingReactivateConfirmation = true
            } label: {
                Label("Reactivate Member", systemImage: "arrow.uturn.backward.circle")
            }
            .tint(Theme.accent)

        case .banned:
            Button {
                showingReactivateConfirmation = true
            } label: {
                Label("Reactivate Member", systemImage: "arrow.uturn.backward.circle")
            }
            .tint(Theme.accent)
        }

        // Delete button available for all statuses
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            Label("Delete Member", systemImage: "trash")
        }
        .disabled(isDeleting)
    }

    // MARK: - Collection Action Buttons

    @ViewBuilder
    private var collectionActionButtons: some View {
        if player.collectionStatus != .reminded {
            Button {
                markAsReminded()
            } label: {
                Label("Mark as Reminded", systemImage: "bell.badge")
            }
            .tint(Theme.warning)
        }

        if player.collectionStatus != .promised {
            Button {
                showingPromisedDatePicker = true
            } label: {
                Label("Mark as Promised", systemImage: "calendar.badge.clock")
            }
            .tint(Theme.accent)
        }

        if player.collectionStatus != .overdue {
            Button {
                markAsOverdue()
            } label: {
                Label("Mark as Overdue", systemImage: "exclamationmark.triangle")
            }
            .tint(Theme.danger)
        }

        if player.collectionStatus != nil && player.collectionStatus != .noStatus {
            Button {
                clearCollectionStatus()
            } label: {
                Label("Clear Status", systemImage: "xmark.circle")
            }
            .tint(Theme.textMuted)
        }
    }

    // MARK: - Actions

    private func archivePlayer() {
        let result = PlayerService.archivePlayer(player)
        switch result {
        case .success:
            break
        case .failure(let error):
            print("Failed to archive player: \(error)")
        }
    }

    private func banPlayer() {
        let result = PlayerService.banPlayer(player)
        switch result {
        case .success:
            break
        case .failure(let error):
            print("Failed to ban player: \(error)")
        }
    }

    private func reactivatePlayer() {
        let result = PlayerService.reactivatePlayer(player)
        switch result {
        case .success:
            break
        case .failure(let error):
            print("Failed to reactivate player: \(error)")
        }
    }

    private func deletePlayer() {
        isDeleting = true

        Task {
            do {
                // Delete from Supabase first for immediate removal
                let supabase = SupabaseClientManager.shared.client
                try await supabase
                    .from("players")
                    .delete()
                    .eq("id", value: player.id.uuidString)
                    .execute()

                // Delete associated bets from Supabase
                let playerBetIds = playerBets.map { $0.id.uuidString }
                if !playerBetIds.isEmpty {
                    try await supabase
                        .from("bets")
                        .delete()
                        .in("id", values: playerBetIds)
                        .execute()
                }

                // Delete associated ledger entries from Supabase
                let playerLedgerIds = playerLedgerEntries.map { $0.id.uuidString }
                if !playerLedgerIds.isEmpty {
                    try await supabase
                        .from("ledger_entries")
                        .delete()
                        .in("id", values: playerLedgerIds)
                        .execute()
                }

                // Delete from local SwiftData
                await MainActor.run {
                    // Delete associated bets locally
                    for bet in playerBets {
                        modelContext.delete(bet)
                    }

                    // Delete associated ledger entries locally
                    for entry in playerLedgerEntries {
                        modelContext.delete(entry)
                    }

                    // Delete the player
                    modelContext.delete(player)

                    isDeleting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = "Failed to delete member: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Collection Status Actions

    private func markAsReminded() {
        player.collectionStatus = .reminded
        player.collectionStatusDate = Date()
        player.promisedPaymentDate = nil
        player.updatedAt = Date()
    }

    private func markAsPromised(date: Date) {
        player.collectionStatus = .promised
        player.collectionStatusDate = Date()
        player.promisedPaymentDate = date
        player.updatedAt = Date()
    }

    private func markAsOverdue() {
        player.collectionStatus = .overdue
        player.collectionStatusDate = Date()
        player.promisedPaymentDate = nil
        player.updatedAt = Date()
    }

    private func clearCollectionStatus() {
        player.collectionStatus = nil
        player.collectionStatusDate = nil
        player.promisedPaymentDate = nil
        player.updatedAt = Date()
    }

    // MARK: - Invite Code Actions

    private func generateInviteCode() {
        let inviteCodeService = InviteCodeService(modelContext: modelContext)
        inviteCodeService.generateInviteForPlayer(player, expiresIn: nil)

        // Trigger sync to upload invite code to Supabase
        Task {
            await syncService.triggerUpload()
        }
    }

    private func revokeInviteCode() {
        let inviteCodeService = InviteCodeService(modelContext: modelContext)
        inviteCodeService.revokeCode(for: player)

        // Trigger sync to update Supabase
        Task {
            await syncService.triggerUpload()
        }
    }

    // MARK: - Helpers

    private func findEvent(for bet: Bet) -> Event? {
        events.first(where: { $0.id.uuidString.lowercased() == bet.eventId.lowercased() })
    }

    private func eventName(for bet: Bet) -> String {
        if let event = findEvent(for: bet) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Player Bet Row View

struct PlayerBetRowView: View {
    let bet: Bet
    let event: Event?

    var body: some View {
        PickCardCompact(presenter: PickPresenter(bet: bet, event: event), showChevron: false)
    }
}

// MARK: - Balance Adjustment Sheet

struct BalanceAdjustmentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let player: Player

    @State private var amount: String = ""
    @State private var description: String = ""
    @State private var isNegative: Bool = false

    private var amountDecimal: Decimal? {
        guard let doubleValue = Double(amount) else { return nil }
        let value = Decimal(doubleValue)
        return isNegative ? -value : value
    }

    private var isValidInput: Bool {
        guard let value = amountDecimal else { return false }
        return value != 0 && !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)

                    Toggle("Credit (negative)", isOn: $isNegative)

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Adjustment Details")
                } footer: {
                    if isNegative {
                        Text("A negative adjustment credits the member (reduces what they owe).")
                    } else {
                        Text("A positive adjustment debits the member (increases what they owe).")
                    }
                }
                .listRowBackground(Theme.cardBackground)

                Section {
                    if let value = amountDecimal {
                        LabeledContent("Adjustment Amount") {
                            Text(formatCurrency(value))
                                .foregroundStyle(value >= 0 ? Theme.textSecondary : Theme.accent)
                        }
                    }
                } header: {
                    Text("Preview")
                }
                .listRowBackground(Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Adjust Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAdjustment()
                    }
                    .disabled(!isValidInput)
                }
            }
        }
    }

    private func saveAdjustment() {
        guard let value = amountDecimal else { return }

        let ledgerEntry = PlayerService.adjustBalance(
            for: player,
            amount: value,
            description: description.trimmingCharacters(in: .whitespaces)
        )
        modelContext.insert(ledgerEntry)
        dismiss()
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Add Player Sheet

struct AddPlayerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService
    @Environment(AuthManager.self) private var authManager

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var creditLimitString: String = ""
    @State private var username: String = ""

    private var creditLimit: Decimal {
        guard let doubleValue = Double(creditLimitString) else { return 0 }
        return Decimal(doubleValue)
    }

    private var isValidInput: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var formattedCreditLimit: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: creditLimit as NSDecimalNumber) ?? "$\(creditLimit)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()

                    TextField("Email (Optional)", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    TextField("Credit Limit", text: $creditLimitString)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Member Details")
                } footer: {
                    Text("Name is required. Email and credit limit are optional.")
                }
                .listRowBackground(Theme.cardBackground)

                Section {
                    TextField("Username (Optional)", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Username can be used for member login in the future.")
                }
                .listRowBackground(Theme.cardBackground)

                Section {
                    LabeledContent("Name") {
                        Text(name.isEmpty ? "—" : name)
                            .foregroundStyle(name.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                    }

                    LabeledContent("Email") {
                        Text(email.isEmpty ? "Not provided" : email)
                            .foregroundStyle(email.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                    }

                    LabeledContent("Credit Limit") {
                        Text(formattedCreditLimit)
                    }

                    LabeledContent("Username") {
                        Text(username.isEmpty ? "Not provided" : username)
                            .foregroundStyle(username.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                    }
                } header: {
                    Text("Preview")
                }
                .listRowBackground(Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePlayer()
                    }
                    .disabled(!isValidInput)
                }
            }
        }
    }

    private func savePlayer() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)

        let player = PlayerService.addPlayer(
            name: trimmedName,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            creditLimit: creditLimit,
            username: trimmedUsername.isEmpty ? nil : trimmedUsername
        )

        // Set the bookie ID so the player is associated with the current bookie
        // This is required for the Edge Function to validate the player belongs to the bookie
        player.bookieId = authManager.currentBookieId

        modelContext.insert(player)

        // Trigger sync to upload the new player to Supabase
        // This ensures the player exists in the backend
        Task {
            await syncService.triggerUpload()
        }

        dismiss()
    }
}

// MARK: - Add Player Interstitial Sheet

struct AddPlayerInterstitialSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showingAddPlayer: Bool

    @State private var showingComingSoonAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(Theme.font(size: 48))
                        .foregroundStyle(Theme.accent)

                    Text("Add to Your Group")
                        .font(Theme.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.textPrimary)

                    Text("Choose how you want to add members")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 32)

                Spacer()

                // Options
                VStack(spacing: 16) {
                    // Add Player option
                    Button {
                        dismiss()
                        // Small delay to let the interstitial dismiss before showing AddPlayerSheet
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingAddPlayer = true
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "person.fill.badge.plus")
                                .font(Theme.title2)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 44, height: 44)
                                .background(Theme.accent.opacity(0.15))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Add Member")
                                    .font(Theme.headline)
                                    .foregroundStyle(Theme.textPrimary)

                                Text("Create a new member manually")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding()
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // Purchase Seats option
                    Button {
                        showingComingSoonAlert = true
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "person.3.fill")
                                .font(Theme.title2)
                                .foregroundStyle(Theme.gold)
                                .frame(width: 44, height: 44)
                                .background(Theme.gold.opacity(0.15))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Purchase Seats")
                                    .font(Theme.headline)
                                    .foregroundStyle(Theme.textPrimary)

                                Text("Buy additional member slots")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding()
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)

                Spacer()
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Coming Soon", isPresented: $showingComingSoonAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Seat purchasing will be available in a future update.")
            }
        }
    }
}

// MARK: - Promised Date Sheet

struct PromisedDateSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var promisedDate: Date
    let onSave: (Date) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Promised Payment Date",
                        selection: $promisedDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                } header: {
                    Text("When did the member promise to pay?")
                } footer: {
                    Text("Select the date the member has promised to make payment.")
                }
                .listRowBackground(Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Mark as Promised")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(promisedDate)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    PlayersListView()
        .modelContainer(for: [Player.self, Bet.self, LedgerEntry.self], inMemory: true)
}
