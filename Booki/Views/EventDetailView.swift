import SwiftUI
import SwiftData

struct EventDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBets: [Bet]

    @Bindable var event: Event

    @State private var showingAddMarket = false
    @State private var marketToEdit: Market?
    @State private var showingFinalScoreSheet = false
    @State private var showingGradeEventSheet = false
    @State private var showingVoidConfirmation = false
    @State private var selectedStatus: EventStatus

    init(event: Event) {
        self.event = event
        self._selectedStatus = State(initialValue: event.status)
    }

    // MARK: - Formatters

    /// Formatter for relative time display (e.g., "2 hours ago")
    private var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }

    // MARK: - Computed Properties

    /// All bets for this event
    private var eventBets: [Bet] {
        allBets.filter { $0.eventId.lowercased() == event.id.uuidString.lowercased() }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Active bets (pending + accepted) for exposure calculation
    private var activeBets: [Bet] {
        eventBets.filter { $0.status == .pending || $0.status == .accepted }
    }

    /// Bets ready to grade (readyToGrade + accepted with final event)
    private var betsToGrade: [Bet] {
        eventBets.filter { $0.status == .readyToGrade || ($0.status == .accepted && event.status == .final) }
    }

    /// Event exposure breakdown
    private var eventExposure: EventExposure? {
        guard !activeBets.isEmpty else { return nil }
        return ExposureService.calculateEventExposure(eventId: event.id.uuidString, bets: activeBets)
    }

    /// Formatted start time
    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.startTime)
    }

    /// Event display name
    private var displayName: String {
        "\(event.awayTeam) @ \(event.homeTeam)"
    }

    // MARK: - Body

    var body: some View {
        List {
            // MARK: - Event Info Section
            Section("Event Info") {
                LabeledContent("Matchup", value: displayName)
                LabeledContent("Sport", value: event.sport)
                LabeledContent("League", value: event.league)
                LabeledContent("Start Time", value: formattedStartTime)

                Picker("Status", selection: $selectedStatus) {
                    Text("Scheduled").tag(EventStatus.scheduled)
                    Text("Live").tag(EventStatus.live)
                    Text("Final").tag(EventStatus.final)
                    Text("Postponed").tag(EventStatus.postponed)
                    Text("Canceled").tag(EventStatus.canceled)
                }
                .onChange(of: selectedStatus) { oldValue, newValue in
                    handleStatusChange(from: oldValue, to: newValue)
                }

                if let finalScore = event.finalScore {
                    LabeledContent("Final Score", value: finalScore)
                        .fontWeight(.semibold)
                }

                // Grade All Bets button when event is final and has gradable bets
                if event.status == .final && !betsToGrade.isEmpty {
                    Button {
                        showingGradeEventSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.accent)
                            Text("Grade All Picks (\(betsToGrade.count))")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .foregroundStyle(Theme.textPrimary)
                }

                // Void All Bets button when event is canceled and has active bets
                if event.status == .canceled && !activeBets.isEmpty {
                    Button {
                        showingVoidConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.danger)
                            Text("Void All Picks (\(activeBets.count))")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
            }

            // MARK: - Markets Section
            Section {
                if let markets = event.markets, !markets.isEmpty {
                    ForEach(markets.sorted(by: { $0.type.rawValue < $1.type.rawValue })) { market in
                        EventMarketRowView(market: market)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                marketToEdit = market
                            }
                    }
                    .onDelete(perform: deleteMarkets)
                } else {
                    Text("No markets added")
                        .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                HStack {
                    Text("Markets")
                    Spacer()
                    Button {
                        showingAddMarket = true
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .font(Theme.caption)
                    }
                }
            }

            // MARK: - Exposure Breakdown Section
            Section("Activity Breakdown") {
                if let exposure = eventExposure {
                    ForEach(exposure.sides.sorted(by: { $0.totalExposure > $1.totalExposure }), id: \.side) { sideExposure in
                        ExposureSideRow(sideExposure: sideExposure)
                    }

                    // Total max exposure
                    HStack {
                        Text("Max Activity")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(formatCurrency(exposure.maxExposure))
                            .font(Theme.headline)
                            .foregroundStyle(Theme.danger)
                    }
                    .padding(.top, 4)
                } else {
                    Text("No open activity")
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // MARK: - Bets for Event Section
            Section {
                if eventBets.isEmpty {
                    Text("No picks for this event")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(eventBets) { bet in
                        EventBetRow(bet: bet)
                    }
                }
            } header: {
                HStack {
                    Text("Picks")
                    Spacer()
                    Text("\(eventBets.count) total")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // MARK: - Liability by Side Section
            if !activeBets.isEmpty {
                Section("Liability by Side") {
                    let betsBySide = Dictionary(grouping: activeBets, by: { $0.side })
                    ForEach(betsBySide.keys.sorted(), id: \.self) { side in
                        if let sideBets = betsBySide[side] {
                            LiabilitySideRow(side: side, bets: sideBets)
                        }
                    }
                }
            }

            // MARK: - Auto Refresh Section
            Section("Auto Refresh") {
                HStack {
                    Text("Last odds refresh:")
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if let lastOdds = event.lastAutoOddsRefresh {
                        Text(relativeFormatter.localizedString(for: lastOdds, relativeTo: Date()))
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Text("Never")
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                HStack {
                    Text("Last score refresh:")
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if let lastScore = event.lastAutoScoreRefresh {
                        Text(relativeFormatter.localizedString(for: lastScore, relativeTo: Date()))
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Text("Never")
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddMarket) {
            AddMarketSheet(event: event)
        }
        .sheet(item: $marketToEdit) { market in
            EditMarketSheet(market: market)
        }
        .sheet(isPresented: $showingFinalScoreSheet, onDismiss: {
            // Sync selectedStatus with actual event status after sheet dismisses
            selectedStatus = event.status
        }) {
            FinalScoreSheet(event: event, bets: eventBets) {
                // On save, transition accepted bets to readyToGrade
                transitionBetsToReadyToGrade()
            }
        }
        .sheet(isPresented: $showingGradeEventSheet) {
            GradeEventSheet(event: event, betsToGrade: betsToGrade)
        }
        .alert("Void All Picks?", isPresented: $showingVoidConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Void Picks", role: .destructive) {
                voidAllBetsForCanceledEvent()
            }
        } message: {
            Text("This will void \(activeBets.count) pending/accepted pick(s) for this canceled event. This action cannot be undone.")
        }
    }

    // MARK: - Status Change Handler

    private func handleStatusChange(from oldValue: EventStatus, to newValue: EventStatus) {
        if newValue == .final {
            // Show final score sheet when changing to Final
            showingFinalScoreSheet = true
        } else {
            // For other status changes, update directly
            event.status = newValue
        }
    }

    private func transitionBetsToReadyToGrade() {
        // Transition accepted bets to readyToGrade when event is finalized
        for bet in eventBets where bet.status == .accepted {
            bet.status = .readyToGrade
        }
    }

    private func voidAllBetsForCanceledEvent() {
        // Void all pending and accepted bets for this canceled event
        let voidedCount = BetService.voidBetsForEvent(eventId: event.id.uuidString, bets: allBets)
        print("Voided \(voidedCount) bets for canceled event: \(displayName)")
    }

    // MARK: - Market Actions

    private func deleteMarkets(at offsets: IndexSet) {
        guard let markets = event.markets else { return }
        let sortedMarkets = markets.sorted(by: { $0.type.rawValue < $1.type.rawValue })
        for index in offsets {
            let market = sortedMarkets[index]
            modelContext.delete(market)
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch event.status {
        case .scheduled:
            return Theme.accent
        case .live:
            return Theme.accent
        case .final:
            return Theme.textMuted
        case .postponed:
            return Theme.warning
        case .canceled:
            return Theme.danger
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Exposure Side Row

struct ExposureSideRow: View {
    let sideExposure: SideExposure

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sideExposure.side)
                    .font(Theme.headline)
                Spacer()
                Text(formatCurrency(sideExposure.totalExposure))
                    .font(Theme.font(size: 15, weight: .bold))
                    .foregroundStyle(Theme.danger)
            }

            HStack(spacing: 16) {
                // Soft exposure (pending)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.warning)
                        .frame(width: 8, height: 8)
                    Text("Pending: \(formatCurrency(sideExposure.softExposure))")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Hard exposure (accepted)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                    Text("Accepted: \(formatCurrency(sideExposure.hardExposure))")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Event Bet Row

struct EventBetRow: View {
    let bet: Bet

    private var formattedOdds: String {
        bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
    }

    private var formattedStake: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: bet.stake as NSDecimalNumber) ?? "$\(bet.stake)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: Player name and status
            HStack {
                Text(bet.player?.name ?? "Unknown Member")
                    .font(Theme.font(size: 15, weight: .bold))

                Spacer()

                let (settlement, workflow) = PickPresenter.mapStatus(betStatus: bet.status, gradeResult: bet.gradeResult)
                StatusPill(settlementStatus: settlement, workflowStatus: workflow)
            }

            // Middle row: Side and odds
            HStack {
                Text(bet.side)
                    .font(Theme.subheadline)

                Text(formattedOdds)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Text(formattedStake)
                    .font(Theme.font(size: 15, weight: .bold))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Liability Side Row

struct LiabilitySideRow: View {
    let side: String
    let bets: [Bet]

    private var totalLiability: Decimal {
        LiabilityService.calculateTotalLiability(for: bets)
    }

    private var pendingCount: Int {
        bets.filter { $0.status == .pending }.count
    }

    private var acceptedCount: Int {
        bets.filter { $0.status == .accepted }.count
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(side)
                    .font(Theme.headline)

                Text("\(bets.count) picks (\(pendingCount) pending, \(acceptedCount) accepted)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Text(formatCurrency(totalLiability))
                .font(Theme.font(size: 15, weight: .bold))
                .foregroundStyle(Theme.danger)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Event Market Row View

struct EventMarketRowView: View {
    let market: Market

    private func formatOdds(_ odds: Int) -> String {
        odds > 0 ? "+\(odds)" : "\(odds)"
    }

    private var typeColor: Color {
        switch market.type {
        case .spread, .alternateSpread:
            return Theme.accent
        case .total, .alternateTotal, .teamTotal:
            return .purple
        case .moneyline:
            return Theme.warning
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with type badge
            HStack {
                Text(market.type.rawValue.capitalized)
                    .font(Theme.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(typeColor)
                    .clipShape(Capsule())

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Side A
            HStack {
                Text(market.sideA)
                    .font(Theme.subheadline)
                Spacer()
                Text(formatOdds(market.oddsA))
                    .font(Theme.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
            }

            // Side B
            HStack {
                Text(market.sideB)
                    .font(Theme.subheadline)
                Spacer()
                Text(formatOdds(market.oddsB))
                    .font(Theme.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Final Score Sheet

struct FinalScoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var event: Event
    let bets: [Bet]
    let onSave: () -> Void

    @State private var homeScore: String = ""
    @State private var awayScore: String = ""

    private var isFormValid: Bool {
        guard let home = Int(homeScore), let away = Int(awayScore) else {
            return false
        }
        return home >= 0 && away >= 0
    }

    private var acceptedBetsCount: Int {
        bets.filter { $0.status == .accepted }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    LabeledContent("Matchup", value: "\(event.awayTeam) @ \(event.homeTeam)")
                    LabeledContent("Sport", value: event.sport)
                }

                Section("Final Score") {
                    HStack {
                        VStack {
                            Text(event.homeTeam)
                                .font(Theme.headline)
                            TextField("Score", text: $homeScore)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(Theme.title1)
                                .frame(width: 80)
                                .padding(8)
                                .background(Theme.cardBackground)
                                .cornerRadius(8)
                        }

                        Text("-")
                            .font(Theme.title1)
                            .padding(.horizontal)

                        VStack {
                            Text(event.awayTeam)
                                .font(Theme.headline)
                            TextField("Score", text: $awayScore)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(Theme.title1)
                                .frame(width: 80)
                                .padding(8)
                                .background(Theme.cardBackground)
                                .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }

                if acceptedBetsCount > 0 {
                    Section {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(Theme.accent)
                            Text("\(acceptedBetsCount) pick(s) will be marked as ready to grade")
                                .font(Theme.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("Enter Final Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveFinalScore()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }

    private func saveFinalScore() {
        guard let home = Int(homeScore), let away = Int(awayScore) else { return }

        // Set the final score (homeScore - awayScore)
        event.finalScore = "\(home) - \(away)"
        event.status = .final

        // Trigger the callback to transition bets
        onSave()

        dismiss()
    }
}

#Preview {
    NavigationStack {
        EventDetailView(
            event: Event(
                sport: "NFL",
                league: "Football",
                homeTeam: "Patriots",
                awayTeam: "Jets",
                startTime: Date(),
                status: .scheduled
            )
        )
    }
    .modelContainer(for: [Bet.self, Event.self], inMemory: true)
}
