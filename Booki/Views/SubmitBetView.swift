import SwiftUI
import SwiftData

/// View for players to browse available events and submit bet requests
/// Uses compliant language: "Submit Request" instead of "Place Bet"
struct SubmitBetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Event.startTime) private var events: [Event]
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    let player: Player

    // MARK: - Computed Properties

    /// Available events (scheduled or live, not final)
    private var availableEvents: [Event] {
        events.filter { $0.status != .final }
    }

    /// Events grouped by sport, then by league
    private var eventsBySport: [String: [String: [Event]]] {
        var result: [String: [String: [Event]]] = [:]

        for event in availableEvents {
            if result[event.sport] == nil {
                result[event.sport] = [:]
            }
            if result[event.sport]?[event.league] == nil {
                result[event.sport]?[event.league] = []
            }
            result[event.sport]?[event.league]?.append(event)
        }

        return result
    }

    /// Sorted sports for consistent display order
    private var sortedSports: [String] {
        eventsBySport.keys.sorted()
    }

    /// Player balance summary for display
    private var balanceSummary: PlayerBalanceSummary {
        let playerBets = bets.filter { $0.player?.id == player.id }
        let playerLedgerEntries = ledgerEntries.filter { $0.player?.id == player.id }
        return BalanceService.playerSummary(
            for: player,
            bets: playerBets,
            ledgerEntries: playerLedgerEntries
        )
    }

    /// Color for available credit (computed to avoid HierarchicalShapeStyle type mismatch)
    private var availableCreditColor: Color {
        balanceSummary.availableCredit >= 0 ? Color.primary : Color.red
    }

    // MARK: - Body

    var body: some View {
        List {
            // Player info section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available Credit")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text(formatCurrency(balanceSummary.availableCredit))
                            .font(Theme.title2)
                            .foregroundStyle(availableCreditColor)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Credit Limit")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text(formatCurrency(player.creditLimit))
                            .font(Theme.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } header: {
                Text("Your Account")
            }
            .listRowBackground(Theme.cardBackground)

            // Events grouped by sport and league
            if availableEvents.isEmpty {
                ContentUnavailableView(
                    "No Available Events",
                    systemImage: "sportscourt",
                    description: Text("There are no upcoming events to submit requests for.")
                )
            } else {
                ForEach(sortedSports, id: \.self) { sport in
                    sportSection(sport: sport)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Submit Request")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Event.self) { event in
            MarketSelectionView(player: player, event: event)
        }
    }

    // MARK: - Section Views

    @ViewBuilder
    private func sportSection(sport: String) -> some View {
        let leaguesByEvent = eventsBySport[sport] ?? [:]
        let sortedLeagues = leaguesByEvent.keys.sorted()

        ForEach(sortedLeagues, id: \.self) { league in
            Section {
                ForEach(leaguesByEvent[league] ?? [], id: \.id) { event in
                    NavigationLink(value: event) {
                        EventRowView(event: event)
                    }
                }
            } header: {
                HStack {
                    Text(sport)
                        .fontWeight(.semibold)
                    Text("•")
                    Text(league)
                }
            }
            .listRowBackground(Theme.cardBackground)
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Event Row View

struct EventRowView: View {
    let event: Event

    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.startTime)
    }

    private var statusColor: Color {
        switch event.status {
        case .scheduled: return .blue
        case .live: return .green
        case .final: return .gray
        case .postponed: return .orange
        case .canceled: return .red
        }
    }

    private var statusText: String {
        switch event.status {
        case .scheduled: return "Upcoming"
        case .live: return "Live"
        case .final: return "Final"
        case .postponed: return "Postponed"
        case .canceled: return "Canceled"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Teams matchup
            HStack {
                Text("\(event.awayTeam) @ \(event.homeTeam)")
                    .font(Theme.headline)

                Spacer()

                if event.status == .live {
                    Text(statusText)
                        .font(Theme.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(statusColor)
                        .clipShape(Capsule())
                }
            }

            // Start time
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(Theme.textSecondary)
                    .font(Theme.caption)

                Text(formattedStartTime)
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Market Selection View

/// View for selecting a market and side for bet submission
struct MarketSelectionView: View {
    let player: Player
    let event: Event

    /// Selected market and side for the bet
    @State private var selectedMarket: Market?
    @State private var selectedSide: SelectedSide?

    /// Which side is selected (A or B)
    enum SelectedSide: Hashable {
        case sideA
        case sideB
    }

    // MARK: - Computed Properties

    /// Markets for this event grouped by type
    private var marketsByType: [MarketType: [Market]] {
        guard let markets = event.markets else { return [:] }
        return Dictionary(grouping: markets, by: { $0.type })
    }

    /// Ordered market types for display
    private var orderedMarketTypes: [MarketType] {
        [.spread, .total, .moneyline].filter { marketsByType[$0] != nil }
    }

    /// Display name for market type
    private func marketTypeName(_ type: MarketType) -> String {
        switch type {
        case .spread: return "Spread"
        case .total: return "Total"
        case .moneyline: return "Moneyline"
        }
    }

    /// Check if a selection has been made
    private var hasSelection: Bool {
        selectedMarket != nil && selectedSide != nil
    }

    /// Get the selected side label for display
    private var selectedSideLabel: String? {
        guard let market = selectedMarket, let side = selectedSide else { return nil }
        switch side {
        case .sideA: return market.sideA
        case .sideB: return market.sideB
        }
    }

    /// Get the selected odds for display
    private var selectedOdds: Int? {
        guard let market = selectedMarket, let side = selectedSide else { return nil }
        switch side {
        case .sideA: return market.oddsA
        case .sideB: return market.oddsB
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            // Event info section
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(event.awayTeam) @ \(event.homeTeam)")
                        .font(Theme.headline)
                    HStack {
                        Text(event.sport)
                        Text("•")
                        Text(event.league)
                    }
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text("Event")
            }
            .listRowBackground(Theme.cardBackground)

            // Markets section
            if event.markets?.isEmpty ?? true {
                ContentUnavailableView(
                    "No Markets Available",
                    systemImage: "exclamationmark.triangle",
                    description: Text("No markets are available for this event.")
                )
            } else {
                ForEach(orderedMarketTypes, id: \.self) { marketType in
                    marketTypeSection(type: marketType)
                }
            }

            // Selection summary (shown when something is selected)
            if hasSelection {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Selection")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Text(selectedSideLabel ?? "")
                                .font(Theme.headline)
                        }
                        Spacer()
                        Text(formatOdds(selectedOdds ?? 0))
                            .font(Theme.title2)
                            .foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("Selected")
                }
                .listRowBackground(Theme.cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Select Market")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if hasSelection {
                continueButton
            }
        }
        .navigationDestination(for: BetSelection.self) { selection in
            StakeEntryView(player: player, event: event, selection: selection)
        }
    }

    // MARK: - Section Views

    @ViewBuilder
    private func marketTypeSection(type: MarketType) -> some View {
        let markets = marketsByType[type] ?? []

        Section {
            ForEach(markets, id: \.id) { market in
                MarketRowView(
                    market: market,
                    selectedSide: selectedMarket?.id == market.id ? selectedSide : nil,
                    onSelectSideA: {
                        selectedMarket = market
                        selectedSide = .sideA
                    },
                    onSelectSideB: {
                        selectedMarket = market
                        selectedSide = .sideB
                    }
                )
            }
        } header: {
            Text(marketTypeName(type))
        }
        .listRowBackground(Theme.cardBackground)
    }

    // MARK: - Continue Button

    @ViewBuilder
    private var continueButton: some View {
        NavigationLink(value: BetSelection(
            market: selectedMarket!,
            side: selectedSide == .sideA ? selectedMarket!.sideA : selectedMarket!.sideB,
            odds: selectedSide == .sideA ? selectedMarket!.oddsA : selectedMarket!.oddsB,
            sideIndicator: selectedSide == .sideA ? "a" : "b"
        )) {
            Text("Continue")
                .font(Theme.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func formatOdds(_ odds: Int) -> String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }
}

// MARK: - Market Row View

/// Row view for displaying a single market with tappable sides
struct MarketRowView: View {
    let market: Market
    let selectedSide: MarketSelectionView.SelectedSide?
    let onSelectSideA: () -> Void
    let onSelectSideB: () -> Void

    private func formatOdds(_ odds: Int) -> String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    private var sideASelected: Bool {
        selectedSide == .sideA
    }

    private var sideBSelected: Bool {
        selectedSide == .sideB
    }

    var body: some View {
        HStack(spacing: 12) {
            // Side A button
            Button(action: onSelectSideA) {
                VStack(spacing: 4) {
                    Text(market.sideA)
                        .font(Theme.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(formatOdds(market.oddsA))
                        .font(Theme.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(sideASelected ? Color.blue : Color(.systemGray5))
                .foregroundStyle(sideASelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Side B button
            Button(action: onSelectSideB) {
                VStack(spacing: 4) {
                    Text(market.sideB)
                        .font(Theme.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(formatOdds(market.oddsB))
                        .font(Theme.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(sideBSelected ? Color.blue : Color(.systemGray5))
                .foregroundStyle(sideBSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Bet Selection Model

/// Model to pass selected bet details to stake entry view
struct BetSelection: Hashable {
    let market: Market
    let side: String
    let odds: Int
    /// Indicates which side of the market was selected: "a" for sideA/oddsA, "b" for sideB/oddsB
    /// Used by Edge Functions which expect side as 'a' or 'b'
    let sideIndicator: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(market.id)
        hasher.combine(side)
        hasher.combine(odds)
    }

    static func == (lhs: BetSelection, rhs: BetSelection) -> Bool {
        lhs.market.id == rhs.market.id && lhs.side == rhs.side && lhs.odds == rhs.odds
    }
}

// MARK: - Stake Entry View

/// View for entering stake amount and reviewing bet submission details
struct StakeEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    let player: Player
    let event: Event
    let selection: BetSelection

    /// Stake input as string for TextField binding
    @State private var stakeInput: String = ""
    /// Whether the submission was successful (shows confirmation)
    @State private var showingSuccess: Bool = false
    /// Error message if submission fails
    @State private var submissionError: String?

    // MARK: - Computed Properties

    /// Parse stake from input string
    private var stake: Decimal? {
        guard !stakeInput.isEmpty else { return nil }
        guard let doubleValue = Double(stakeInput) else { return nil }
        guard doubleValue > 0 else { return nil }
        return Decimal(doubleValue)
    }

    /// Calculate potential payout based on stake and odds
    private var potentialPayout: Decimal? {
        guard let stake = stake else { return nil }
        return LiabilityService.calculatePayout(stake: stake, odds: selection.odds)
    }

    /// Total return (stake + payout)
    private var totalReturn: Decimal? {
        guard let stake = stake, let payout = potentialPayout else { return nil }
        return stake + payout
    }

    /// Player balance summary for display
    private var balanceSummary: PlayerBalanceSummary {
        let playerBets = bets.filter { $0.player?.id == player.id }
        let playerLedgerEntries = ledgerEntries.filter { $0.player?.id == player.id }
        return BalanceService.playerSummary(
            for: player,
            bets: playerBets,
            ledgerEntries: playerLedgerEntries
        )
    }

    /// Check if stake is valid (positive and within available credit)
    private var isStakeValid: Bool {
        guard let _ = stake, let payout = potentialPayout else { return false }
        // Check if potential liability (payout) is within available credit
        return payout <= balanceSummary.availableCredit
    }

    /// Color for available credit
    private var availableCreditColor: Color {
        balanceSummary.availableCredit >= 0 ? Color.primary : Color.red
    }

    /// Error message for invalid stake
    private var stakeError: String? {
        guard let _ = stake, let payout = potentialPayout else { return nil }
        if payout > balanceSummary.availableCredit {
            return "Potential return exceeds available credit"
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        List {
            // Available Credit Section
            availableCreditSection

            // Stake Input Section
            stakeInputSection

            // Payout Section (shown when stake is entered)
            if stake != nil {
                payoutSection
            }

            // Review Summary Section
            reviewSummarySection

            // Compliance Disclosure Section
            if isStakeValid {
                complianceDisclosureSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Review Request")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if isStakeValid {
                submitButton
            }
        }
        .alert("Request Submitted", isPresented: $showingSuccess) {
            Button("OK") {
                // Return to event list by dismissing twice (market selection + stake entry)
                dismiss()
            }
        } message: {
            Text("Your pick request has been recorded and is pending review.")
        }
        .alert("Submission Failed", isPresented: .init(
            get: { submissionError != nil },
            set: { if !$0 { submissionError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = submissionError {
                Text(error)
            }
        }
    }

    // MARK: - Section Views

    @ViewBuilder
    private var availableCreditSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Available Credit")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(formatCurrency(balanceSummary.availableCredit))
                        .font(Theme.title2)
                        .foregroundStyle(availableCreditColor)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Credit Limit")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(formatCurrency(player.creditLimit))
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text("Your Account")
        }
        .listRowBackground(Theme.cardBackground)
    }

    @ViewBuilder
    private var stakeInputSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("$")
                        .font(Theme.title1)
                        .foregroundStyle(Theme.textSecondary)
                    TextField("0", text: $stakeInput)
                        .font(Theme.title1)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                }

                // Validation error message
                if let error = stakeError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                        Text(error)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Stake Amount")
        }
        .listRowBackground(Theme.cardBackground)
    }

    @ViewBuilder
    private var payoutSection: some View {
        Section {
            HStack {
                Text("Potential Profit")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let payout = potentialPayout {
                    Text(formatCurrency(payout))
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                }
            }

            HStack {
                Text("Total Return")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let total = totalReturn {
                    Text(formatCurrency(total))
                        .fontWeight(.bold)
                }
            }
        } header: {
            Text("Potential Return")
        } footer: {
            Text("Returns include your original stake if pick wins.")
        }
        .listRowBackground(Theme.cardBackground)
    }

    @ViewBuilder
    private var reviewSummarySection: some View {
        Section {
            // Event
            LabeledContent("Event") {
                Text("\(event.awayTeam) @ \(event.homeTeam)")
                    .foregroundStyle(Theme.textSecondary)
            }

            // Market
            LabeledContent("Market") {
                Text(selection.market.type.rawValue.capitalized)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Side
            LabeledContent("Selection") {
                Text(selection.side)
                    .fontWeight(.semibold)
            }

            // Odds
            LabeledContent("Odds") {
                Text(formatOdds(selection.odds))
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
            }

            // Stake (if entered)
            if let stakeValue = stake {
                LabeledContent("Stake") {
                    Text(formatCurrency(stakeValue))
                        .fontWeight(.semibold)
                }
            }

            // Potential Payout (if calculated)
            if let payout = potentialPayout {
                LabeledContent("Potential Return") {
                    Text(formatCurrency(payout))
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
        } header: {
            Text("Review Summary")
        }
        .listRowBackground(Theme.cardBackground)
    }

    @ViewBuilder
    private var complianceDisclosureSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Theme.accent)
                    Text("This submission records a pick request with your group. No money is wagered or transferred in this app.")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text("Disclosure")
        }
        .listRowBackground(Theme.cardBackground)
    }

    @ViewBuilder
    private var submitButton: some View {
        Button(action: submitRequest) {
            Text("Submit Request")
                .font(Theme.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions (US-016: Edge Function)

    private func submitRequest() {
        guard let stakeValue = stake else { return }

        // Get bookieId from player
        guard let bookieId = player.bookieId else {
            submissionError = "Member is not associated with an organizer"
            return
        }

        // Submit bet via Edge Function
        // Use sideIndicator ('a' or 'b') for the server, not the display name
        Task {
            let result = await BetService.submitBetToServer(
                eventId: event.id,
                marketId: selection.market.id,
                side: selection.sideIndicator,
                odds: selection.odds,
                stake: stakeValue,
                playerId: player.id,
                bookieId: bookieId
            )

            await MainActor.run {
                switch result {
                case .success(let response):
                    // Create local Bet from server response
                    if let bet = BetService.createLocalBetFromResponse(
                        response,
                        player: player,
                        localSide: selection.side,
                        localMarket: selection.market.type.rawValue
                    ) {
                        modelContext.insert(bet)
                        showingSuccess = true
                    } else {
                        submissionError = "Failed to process server response"
                    }

                case .failure(let error):
                    // Handle different error types
                    if let edgeFunctionError = error as? EdgeFunctionError {
                        switch edgeFunctionError {
                        case .notAuthenticated:
                            submissionError = "Not authenticated - please sign in again"
                        case .serverError(_, let message):
                            submissionError = message ?? "Server error"
                        default:
                            submissionError = edgeFunctionError.localizedDescription
                        }
                    } else if let betError = error as? BetServiceError {
                        switch betError {
                        case .edgeFunctionError(let message):
                            submissionError = message
                        default:
                            submissionError = "Failed to submit request. Please try again."
                        }
                    } else {
                        submissionError = "Failed to submit request: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    private func formatOdds(_ odds: Int) -> String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }
}

#Preview {
    NavigationStack {
        SubmitBetView(player: Player(
            name: "Test Player",
            email: "test@example.com",
            creditLimit: 1000
        ))
    }
    .modelContainer(for: [Player.self, Event.self, Bet.self, LedgerEntry.self], inMemory: true)
}
