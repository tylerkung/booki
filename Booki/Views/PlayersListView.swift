import SwiftUI
import SwiftData
import MessageUI
@preconcurrency import Supabase

struct PlayersListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bookies: [Bookie]
    @Query(sort: \Player.name) private var players: [Player]
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var invites: [Invite]

    @Environment(SyncService.self) private var syncService

    @State private var showArchived = false
    @State private var showingInviteSheet = false
    @State private var selectedPendingInvite: Invite? = nil
    @State private var showCopiedToast = false
    @State private var showDeletedToast = false
    @State private var searchText = ""
    @State private var activeFilter = "All"
    @State private var showProUpgrade = false
    @AppStorage("deletedInviteIds") private var deletedInviteIdsString: String = ""
    @AppStorage("bookieTier") private var bookieTierRaw: String = BookieTier.free.rawValue

    private var bookieTier: BookieTier {
        BookieTier(rawValue: bookieTierRaw) ?? .free
    }

    private static let filterOptions = ["All", "Attention needed", "Overdue", "High exposure", "Big winners", "Big losers"]

    private var deletedInviteIds: Set<String> {
        Set(deletedInviteIdsString.split(separator: ",").map(String.init))
    }

    private var pendingInvites: [Invite] {
        invites.filter { $0.claimedAt == nil && !deletedInviteIds.contains($0.id.uuidString.lowercased()) }
    }

    private var playerSummaries: [PlayerAnalyticsSummary] {
        PlayerAttentionService.generateSummaries(
            players: players,
            bets: bets,
            ledgerEntries: ledgerEntries
        )
    }

    private func summaryForPlayer(_ player: Player) -> PlayerAnalyticsSummary? {
        playerSummaries.first { $0.player.id == player.id }
    }

    private var filteredSummaries: [PlayerAnalyticsSummary] {
        var result = playerSummaries

        // Filter by archived status
        if !showArchived {
            result = result.filter { $0.player.status != .archived }
        }

        // Apply search
        if !searchText.isEmpty {
            result = result.filter { $0.player.name.localizedCaseInsensitiveContains(searchText) }
        }

        // Apply filter
        switch activeFilter {
        case "Attention needed":
            result = result.filter { $0.pas.score >= 34 }
        case "Overdue":
            result = result.filter { $0.isOverdue }
        case "High exposure":
            result = result.filter { $0.exposure.grossExposure > 0 }
        case "Big winners":
            result = result.filter { $0.sevenDayPL < 0 }
        case "Big losers":
            result = result.filter { $0.sevenDayPL > 0 }
        default:
            break
        }

        return result
    }

    private var filteredPlayers: [Player] {
        filteredSummaries.map(\.player)
    }

    var body: some View {
        NavigationStack {
            scrollContent
                .background(Theme.background)
                .refreshable {
                    await withCheckedContinuation { continuation in
                        Task.detached {
                            await syncService.sync()
                            continuation.resume()
                        }
                    }
                }
                .navigationTitle("Members")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Image("BookiWordmark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 20)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        SyncStatusIndicator(syncService: syncService, bookieEmail: bookies.first?.email ?? "")
                    }
                }
                .navigationDestination(for: PlayerAnalyticsSummary.self) { summary in
                    PlayerAnalyticsDetailView(
                        summary: summary,
                        playerBets: bets.filter { $0.player?.id == summary.player.id },
                        playerLedgerEntries: ledgerEntries.filter { $0.player?.id == summary.player.id }
                    )
                }
                .sheet(isPresented: $showingInviteSheet) {
                    InviteMemberSheet()
                        .presentationBackground(Theme.background)
                }
                .sheet(item: $selectedPendingInvite) { invite in
                    InviteMemberSheet(existingInvite: invite)
                        .presentationBackground(Theme.background)
                }
                .sheet(isPresented: $showProUpgrade) {
                    ProUpgradeSheet(contextMessage: "You've reached the 3-member limit")
                        .presentationBackground(Theme.background)
                }
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                copiedToast
            } else if showDeletedToast {
                deletedToast
            }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                pendingInvitesSection
                membersSection
                inviteButton
            }
        }
    }

    private var memberSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textMuted)
                .font(.system(size: 14))

            TextField("Search members", text: $searchText)
                .font(Theme.bodyFont(size: 15))
                .foregroundStyle(Theme.textPrimary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textMuted)
                        .font(.system(size: 14))
                }
            }
        }
        .padding(10)
        .background(Theme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }

    private var memberFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.filterOptions, id: \.self) { filter in
                    Button {
                        activeFilter = filter
                    } label: {
                        Text(filter)
                            .font(Theme.bodyFont(size: 13, weight: .medium))
                            .foregroundStyle(activeFilter == filter ? .black : Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(activeFilter == filter ? Theme.accent : Theme.elevatedBackground)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var membersSection: some View {
        if players.filter({ $0.status != .archived }).isEmpty && pendingInvites.isEmpty {
            ContentUnavailableView(
                "No Members",
                systemImage: "person.2.slash",
                description: Text("Add members to start managing your group.")
            )
            .padding(.top, 60)
        } else {
            VStack(spacing: 12) {
                if bookieTier.isPro {
                    memberSearchBar
                    memberFilterChips

                    if activeFilter != "All" || !searchText.isEmpty {
                        Text("\(filteredSummaries.count) of \(playerSummaries.count) members")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, pendingInvites.isEmpty ? 8 : 12)
            .padding(.bottom, 12)

            if filteredPlayers.isEmpty && (activeFilter != "All" || !searchText.isEmpty) {
                Text("No members match filters")
                    .font(Theme.bodyFont(size: 15))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredSummaries, id: \.player.id) { summary in
                        NavigationLink(value: summary) {
                            PlayerRowView(
                                player: summary.player,
                                balance: balanceForPlayer(summary.player),
                                utilization: utilizationForPlayer(summary.player),
                                summary: summary,
                                expanded: true,
                                showTags: bookieTier.isPro
                            )
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 0)

                // Capacity banner for free tier at member limit
                if !bookieTier.isPro {
                    let activeCount = players.filter { $0.status != .archived && $0.authUserId != nil }.count
                    if activeCount >= bookieTier.memberLimit {
                        capacityBanner(activeCount: activeCount)
                    }
                }
            }
        }
    }

    private var inviteButton: some View {
        Button {
            showingInviteSheet = true
        } label: {
            Text("INVITE MEMBER")
                .font(Theme.font(size: 16, weight: .bold))
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private func capacityBanner(activeCount: Int) -> some View {
        Button {
            showProUpgrade = true
        } label: {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 14))
                Text("\(activeCount) of \(bookieTier.memberLimit) members · Upgrade for more")
                    .font(Theme.bodyFont(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding()
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var copiedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
            Text("Link copied to clipboard")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.cardBackground)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .padding(.bottom, 32)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var deletedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash.fill")
                .foregroundStyle(Theme.danger)
            Text("Invite deleted")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.cardBackground)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .padding(.bottom, 32)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Pending Invites Section

    @ViewBuilder
    private var pendingInvitesSection: some View {
        if !pendingInvites.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("PENDING INVITES")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(1.0)
                    .padding(.horizontal)

                ForEach(pendingInvites) { invite in
                    PendingInviteRow(invite: invite, onCopy: {
                        UIPasteboard.general.string = "booki://invite/\(invite.inviteCode)"
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation {
                            showCopiedToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showCopiedToast = false
                            }
                        }
                    }, onDelete: {
                        deleteInvite(invite)
                    })
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPendingInvite = invite
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private func deleteInvite(_ invite: Invite) {
        let inviteId = invite.id.uuidString.lowercased()
        // Persist deleted ID so sync can't resurrect it
        if deletedInviteIdsString.isEmpty {
            deletedInviteIdsString = inviteId
        } else {
            deletedInviteIdsString += ",\(inviteId)"
        }
        withAnimation {
            modelContext.delete(invite)
        }
        Task {
            do {
                let supabase = SupabaseClientManager.shared.client
                try await supabase
                    .from("invites")
                    .delete()
                    .eq("id", value: inviteId)
                    .execute()
            } catch {
                print("Failed to delete invite from server: \(error)")
            }
        }
        withAnimation {
            showDeletedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showDeletedToast = false
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

// MARK: - Pending Invite Row

struct PendingInviteRow: View {
    let invite: Invite
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var expirationText: String {
        if invite.isExpired {
            return "Expired"
        }
        let remaining = invite.expiresAt.timeIntervalSince(Date())
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return "Expires in \(hours)h \(minutes)m"
        } else {
            return "Expires in \(minutes)m"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(invite.email ?? "Link invite")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                Text(invite.inviteCode)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)

                Text(expirationText)
                    .font(Theme.caption)
                    .foregroundStyle(invite.isExpired ? Theme.danger : Theme.textSecondary)
            }

            Spacer()

            Button {
                onCopy()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.danger)
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }
}

// MARK: - Player Row View

struct PlayerRowView: View {
    let player: Player
    let balance: Decimal
    let utilization: Double
    var summary: PlayerAnalyticsSummary?
    var expanded: Bool = false
    var showTags: Bool = true

    @State private var showingTagExplainer = false

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
        formatter.maximumFractionDigits = 0
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
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Name + badges → Balance
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

                    Text("Credit: \(formattedBalance) / \(formattedCreditLimit) · \(Int(utilization))%")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Text(balanceLabel)
                    .font(Theme.title3)
                    .foregroundStyle(balanceColor)
            }

            // Expanded: extra metrics from summary
            if expanded, let summary = summary {
                expandedMetrics(summary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func expandedMetrics(_ summary: PlayerAnalyticsSummary) -> some View {
        // Row 2: Key metrics
        HStack(spacing: 0) {
            metricColumn(label: "Open Activity", value: formatCurrencyShort(summary.exposure.grossExposure), color: summary.exposure.grossExposure > 0 ? Theme.textPrimary : Theme.textSecondary)
            metricColumn(label: "7d P/L", value: formatSignedCurrencyShort(summary.sevenDayPL), color: summary.sevenDayPL > 0 ? Theme.accent : summary.sevenDayPL < 0 ? Theme.danger : Theme.textSecondary)
            metricColumn(label: "Win Rate", value: "\(Int(summary.winRate * 100))%", color: Theme.textPrimary)
            metricColumn(label: "Avg Pick", value: formatCurrencyShort(summary.avgBetSize30d), color: Theme.textPrimary)
        }

        // Row 3: Attention chips (Pro only)
        if showTags, !summary.pas.reasonChips.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(summary.pas.reasonChips.prefix(3)), id: \.self) { chip in
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
    }

    private func metricColumn(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.bodyFont(size: 10))
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(Theme.bodyFont(size: 13, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatCurrencyShort(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    private func formatSignedCurrencyShort(_ value: Decimal) -> String {
        let absValue = value < 0 ? -value : value
        let formatted = formatCurrencyShort(absValue)
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
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

    private var balanceLabel: String {
        if balance > 0 {
            return "Owes \(formattedBalance)"
        } else if balance < 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            formatter.maximumFractionDigits = 0
            let absFormatted = formatter.string(from: (-balance) as NSDecimalNumber) ?? "$\(-balance)"
            return "You owe \(absFormatted)"
        }
        return "Settled"
    }

    private var balanceColor: Color {
        if balance > 0 { return Theme.accent }
        if balance < 0 { return Theme.danger }
        return Theme.textSecondary
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
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Direction picker
                    Picker("Direction", selection: $isNegative) {
                        Text("Add to Balance").tag(false)
                        Text("Credit / Reduce").tag(true)
                    }
                    .pickerStyle(.segmented)

                    // Amount display
                    VStack(spacing: 4) {
                        Text("$\(amount.isEmpty ? "0" : amount)")
                            .font(Theme.font(size: 36, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)

                        Text(isNegative
                            ? "This will reduce what \(player.name) owes"
                            : "This will increase what \(player.name) owes")
                            .font(Theme.bodyFont(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                    // Description field
                    TextField("Reason (required)", text: $description)
                        .font(Theme.bodyFont(size: 15))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(12)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))

                    Spacer()

                    // Keypad + CTA
                    NumericKeypadView(text: $amount)

                    Button {
                        saveAdjustment()
                    } label: {
                        Text("CONFIRM ADJUSTMENT")
                            .font(Theme.font(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .background(isValidInput ? Theme.accent : Theme.accent.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    .disabled(!isValidInput)
                }
                .padding()
            }
            .navigationTitle("Adjust Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.accent)
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

// MARK: - Invite Member Sheet

struct InviteMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    enum InviteState {
        case idle
        case loading
        case generated(code: String, expiresAt: String)
        case emailSent
        case error(String)
    }

    /// Optional invite to show directly in generated state (from pending invite tap)
    var existingInvite: Invite? = nil

    @Query private var bookies: [Bookie]

    @State private var inviteState: InviteState = .idle
    @State private var codeCopied = false
    @State private var linkCopied = false
    @State private var emailAddress: String = ""
    @State private var emailInviteCode: String? = nil
    @State private var showingMailCompose = false
    @State private var showingMailFallbackAlert = false

    private var inviteURL: String? {
        if case .generated(let code, _) = inviteState {
            return "booki://invite/\(code)"
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Content based on state
                switch inviteState {
                case .idle:
                    idleContent
                case .loading:
                    loadingContent
                case .generated(let code, _):
                    generatedContent(code: code)
                case .emailSent:
                    emailSentContent
                case .error(let message):
                    errorContent(message: message)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let invite = existingInvite {
                    inviteState = .generated(code: invite.inviteCode, expiresAt: invite.expiresAt.ISO8601Format())
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
            .sheet(isPresented: $showingMailCompose) {
                if let code = emailInviteCode {
                    MailComposeView(
                        recipients: [emailAddress],
                        subject: "You've been invited to join Booki",
                        body: mailBody(code: code),
                        onDismiss: { _ in
                            inviteState = .emailSent
                        }
                    )
                    .ignoresSafeArea()
                }
            }
            .alert("Link Copied!", isPresented: $showingMailFallbackAlert) {
                Button("OK", role: .cancel) {
                    inviteState = .emailSent
                }
            } message: {
                Text("Mail is not configured — share the link manually.")
            }
        }
    }

    // MARK: - State Views

    @ViewBuilder
    private var idleContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)

            Text("Invite a Member")
                .font(Theme.title2)
                .foregroundStyle(Theme.textPrimary)

            Text("Generate a link to invite someone to your group")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                generateInvite()
            } label: {
                Text("GENERATE LINK")
                    .font(Theme.font(size: 16, weight: .bold))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.top, 8)

            // MARK: - Send via Email Section
            VStack(spacing: 12) {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

                Text("Send via Email")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)

                TextField("Enter email address", text: $emailAddress)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                    .padding()
                    .background(Theme.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    .padding(.horizontal, 32)

                Button {
                    generateEmailInvite()
                } label: {
                    Text("SEND INVITE")
                        .font(Theme.font(size: 16, weight: .bold))
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(emailAddress.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.accent.opacity(0.4) : Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                }
                .buttonStyle(.plain)
                .disabled(emailAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 32)
            }
        }
    }

    @ViewBuilder
    private var loadingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(1.5)

            Text("Generating invite...")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private func generatedContent(code: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)

            Text("Invite Created")
                .font(Theme.title2)
                .foregroundStyle(Theme.textPrimary)

            // Invite code display with copy button
            Button {
                copyInviteCode(code: code)
            } label: {
                HStack(spacing: 12) {
                    Text(code)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .kerning(3)
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 18))
                        .foregroundStyle(codeCopied ? Theme.accent : Theme.textSecondary)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .background(Theme.elevatedBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
            .buttonStyle(.plain)

            Text("Expires in 24 hours")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)

            // Action buttons
            VStack(spacing: 12) {
                // Copy Link button
                Button {
                    copyInviteLink(code: code)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: linkCopied ? "checkmark" : "link")
                        Text(linkCopied ? "LINK COPIED!" : "COPY LINK")
                    }
                    .font(Theme.font(size: 16, weight: .bold))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                }
                .buttonStyle(.plain)

                // Share button
                if let url = inviteURL {
                    ShareLink(item: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("SHARE")
                        }
                        .font(Theme.font(size: 16, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.elevatedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func errorContent(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.danger)

            Text("Failed to Create Invite")
                .font(Theme.title2)
                .foregroundStyle(Theme.textPrimary)

            Text(message)
                .font(Theme.subheadline)
                .foregroundStyle(Theme.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                generateInvite()
            } label: {
                Text("TRY AGAIN")
                    .font(Theme.font(size: 16, weight: .bold))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var emailSentContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)

            Text("Invite sent!")
                .font(Theme.title2)
                .foregroundStyle(Theme.textPrimary)

            Text("An invite has been sent to \(emailAddress)")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Actions

    private func generateEmailInvite() {
        let trimmedEmail = emailAddress.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty else { return }

        inviteState = .loading

        Task {
            do {
                let idempotencyKey = UUID().uuidString.lowercased()
                let body: [String: String] = [
                    "idempotency_key": idempotencyKey,
                    "email": trimmedEmail
                ]

                let response: CreateInviteResponse = try await EdgeFunctionService.shared.callFunction(
                    name: "create_invite",
                    body: body
                )

                await MainActor.run {
                    saveInviteLocally(response: response, email: trimmedEmail)
                    emailInviteCode = response.inviteCode

                    if MFMailComposeViewController.canSendMail() {
                        showingMailCompose = true
                    } else {
                        // Copy link to clipboard as fallback
                        UIPasteboard.general.string = "booki://invite/\(response.inviteCode)"
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        showingMailFallbackAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    inviteState = .error(error.localizedDescription)
                }
            }
        }
    }

    private func generateInvite() {
        inviteState = .loading

        Task {
            do {
                let idempotencyKey = UUID().uuidString.lowercased()
                let body: [String: String] = ["idempotency_key": idempotencyKey]

                let response: CreateInviteResponse = try await EdgeFunctionService.shared.callFunction(
                    name: "create_invite",
                    body: body
                )

                await MainActor.run {
                    saveInviteLocally(response: response)
                    inviteState = .generated(code: response.inviteCode, expiresAt: response.expiresAt)
                }
            } catch {
                await MainActor.run {
                    inviteState = .error(error.localizedDescription)
                }
            }
        }
    }

    private func saveInviteLocally(response: CreateInviteResponse, email: String? = nil) {
        guard let inviteId = UUID(uuidString: response.inviteId),
              let bookieId = bookies.first?.id else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expiresAt = formatter.date(from: response.expiresAt) ?? Date().addingTimeInterval(24 * 3600)

        let invite = Invite(
            id: inviteId,
            bookieId: bookieId,
            inviteCode: response.inviteCode,
            email: email,
            expiresAt: expiresAt
        )
        modelContext.insert(invite)
    }

    private func copyInviteCode(code: String) {
        UIPasteboard.general.string = code
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        codeCopied = true
        linkCopied = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            codeCopied = false
        }
    }

    private func copyInviteLink(code: String) {
        UIPasteboard.general.string = "https://bookisports.com/invite/\(code)"
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        linkCopied = true
        codeCopied = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            linkCopied = false
        }
    }

    private func mailBody(code: String) -> String {
        let bookieName = bookies.first?.name ?? "a group"
        return "You've been invited to join \(bookieName)'s group on Booki.\n\nOpen this link to get started: booki://invite/\(code)\n\nThis invite expires in 24 hours."
    }
}

// MARK: - Mail Compose View

struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let onDismiss: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onDismiss: (MFMailComposeResult) -> Void

        init(onDismiss: @escaping (MFMailComposeResult) -> Void) {
            self.onDismiss = onDismiss
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            DispatchQueue.main.async {
                controller.dismiss(animated: true)
            }
            onDismiss(result)
        }
    }
}

// MARK: - Create Invite Response

private struct CreateInviteResponse: Decodable {
    let success: Bool
    let inviteId: String
    let inviteCode: String
    let inviteUrl: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case success
        case inviteId = "invite_id"
        case inviteCode = "invite_code"
        case inviteUrl = "invite_url"
        case expiresAt = "expires_at"
    }
}

#Preview {
    PlayersListView()
        .modelContainer(for: [Player.self, Bet.self, LedgerEntry.self, Invite.self], inMemory: true)
}
