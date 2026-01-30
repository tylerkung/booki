import SwiftUI
import SwiftData

/// Information about parlay partial grading status
struct ParlayPartialInfo {
    let gradedCount: Int
    let totalLegs: Int
    let willLose: Bool
    let awaitingCount: Int

    var isPartiallyGraded: Bool {
        gradedCount > 0 && gradedCount < totalLegs
    }
}

/// Filter options for bets list
enum BetFilter: String, CaseIterable {
    case pending = "Pending"
    case open = "Open"
    case readyToGrade = "Ready to Grade"
    case settled = "Settled"
    case all = "All"

    /// Returns the bet statuses that match this filter
    var matchingStatuses: [BetStatus] {
        switch self {
        case .pending:
            return [.pending]
        case .open:
            return [.accepted]
        case .readyToGrade:
            return [.readyToGrade]
        case .settled:
            return [.settled, .graded, .declined, .void]
        case .all:
            return BetStatus.allCases
        }
    }
}

extension BetStatus: CaseIterable {
    static var allCases: [BetStatus] {
        [.pending, .accepted, .declined, .readyToGrade, .graded, .settled, .void]
    }
}

struct BetsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bets: [Bet]
    @Query private var events: [Event]

    @State private var selectedFilter: BetFilter = .all

    /// Filtered bets based on selected filter
    private var filteredBets: [Bet] {
        bets.filter { selectedFilter.matchingStatuses.contains($0.status) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Filter Picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(BetFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // MARK: - Bets List
                List {
                    if filteredBets.isEmpty {
                        ContentUnavailableView(
                            "No Bets",
                            systemImage: "list.bullet.rectangle",
                            description: Text("No bets match the selected filter.")
                        )
                    } else {
                        ForEach(filteredBets) { bet in
                            NavigationLink(value: bet) {
                                BetRowView(
                                    bet: bet,
                                    eventName: eventName(for: bet),
                                    betDisplayName: betDisplayName(for: bet),
                                    policyViolationReason: bet.policyViolationReason,
                                    parlayInfo: parlayInfo(for: bet)
                                )
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
            }
            .background(Theme.background)
            .navigationTitle("Bets")
            .navigationDestination(for: Bet.self) { bet in
                BetDetailView(bet: bet)
            }
        }
    }

    // MARK: - Helper Methods

    private func eventName(for bet: Bet) -> String {
        if let event = events.first(where: { $0.id.uuidString == bet.eventId }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    /// Creates a display name for the bet ticket
    /// - Single bets: "Lakers ML -150" or "OKC -6.5 (-110)"
    /// - Parlays: "3-leg parlay +450"
    private func betDisplayName(for bet: Bet) -> String {
        if bet.isParlay {
            // For parlays, show leg count and combined odds
            let parlayBets = bets.filter { $0.ticketId == bet.ticketId }
            let combinedOdds = calculateCombinedOdds(for: parlayBets)
            let oddsString = combinedOdds > 0 ? "+\(combinedOdds)" : "\(combinedOdds)"
            return "\(parlayBets.count)-leg parlay \(oddsString)"
        } else {
            // For singles, show side with odds
            let oddsString = bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
            return "\(bet.side) \(oddsString)"
        }
    }

    /// Calculate combined American odds for a parlay
    private func calculateCombinedOdds(for parlayBets: [Bet]) -> Int {
        let combinedDecimal = parlayBets.reduce(Decimal(1)) { result, bet in
            result * americanToDecimal(bet.odds)
        }
        return decimalToAmerican(combinedDecimal)
    }

    private func americanToDecimal(_ odds: Int) -> Decimal {
        if odds > 0 {
            return 1 + Decimal(odds) / 100
        } else {
            return 1 + 100 / Decimal(abs(odds))
        }
    }

    private func decimalToAmerican(_ decimal: Decimal) -> Int {
        if decimal >= 2 {
            return Int(truncating: ((decimal - 1) * 100) as NSDecimalNumber)
        } else {
            return Int(truncating: (-100 / (decimal - 1)) as NSDecimalNumber)
        }
    }

    /// Calculate parlay partial info for a bet
    private func parlayInfo(for bet: Bet) -> ParlayPartialInfo? {
        guard bet.isParlay else { return nil }

        // Find all bets with the same ticketId
        let parlayBets = bets.filter { $0.ticketId == bet.ticketId }
        guard parlayBets.count > 1 else { return nil }

        let gradedCount = parlayBets.filter { $0.gradeResult != nil || $0.status == .void }.count
        let totalLegs = parlayBets.count
        let awaitingCount = totalLegs - gradedCount
        let willLose = parlayBets.contains { $0.gradeResult == .loss }

        return ParlayPartialInfo(
            gradedCount: gradedCount,
            totalLegs: totalLegs,
            willLose: willLose,
            awaitingCount: awaitingCount
        )
    }
}

// MARK: - Bet Row View

struct BetRowView: View {
    let bet: Bet
    let eventName: String
    let betDisplayName: String
    var policyViolationReason: String? = nil
    var parlayInfo: ParlayPartialInfo? = nil

    private var formattedOdds: String {
        if bet.odds > 0 {
            return "+\(bet.odds)"
        } else {
            return "\(bet.odds)"
        }
    }

    private var formattedStake: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: bet.stake as NSDecimalNumber) ?? "$\(bet.stake)"
    }

    private var potentialPayout: Decimal {
        LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
    }

    private var formattedPotentialPayout: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: potentialPayout as NSDecimalNumber) ?? "$\(potentialPayout)"
    }

    private var statusColor: Color {
        switch bet.status {
        case .pending:
            return .orange
        case .accepted:
            return .blue
        case .declined:
            return .red
        case .readyToGrade:
            return .purple
        case .graded:
            return .indigo
        case .settled:
            return .green
        case .void:
            return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: Bet display name and status badge
            HStack {
                Text(betDisplayName)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                // Show parlay partial badge if applicable
                if let info = parlayInfo, info.isPartiallyGraded {
                    Text("Partial (\(info.gradedCount)/\(info.totalLegs))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.warning)
                        .clipShape(Capsule())
                } else {
                    Text(bet.status.rawValue.capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor)
                        .clipShape(Capsule())
                }
            }

            // Second row: Player name
            Text(bet.player?.name ?? "Unknown Player")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textSecondary)

            // Third row: Event name
            Text(eventName)
                .font(.caption)
                .foregroundStyle(Theme.textMuted)

            // Policy violation reason (only for pending bets with violations)
            if bet.status == .pending, let reason = policyViolationReason, !reason.isEmpty {
                Text("Review: \(reason)")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }

            // Parlay will lose indicator
            if let info = parlayInfo, info.willLose {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("Parlay will lose when settled")
                        .font(.caption)
                }
                .foregroundStyle(Theme.danger)
            }

            // Bottom row: Stake and To Win
            HStack {
                Spacer()

                Text("Stake: \(formattedStake)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                Text("•")
                    .foregroundStyle(Theme.textMuted)

                Text("To Win: \(formattedPotentialPayout)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Bet Detail View

struct BetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var events: [Event]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var allBets: [Bet]
    @Query private var policies: [AcceptancePolicy]

    let bet: Bet

    /// Get the current parlay push/void policy
    private var parlayPolicy: ParlayPushVoidPolicy {
        policies.first?.parlayPushVoidPolicyEnum ?? .reduceLegReprice
    }

    /// Get all bets with the same ticketId (for parlay settlement)
    private var parlayBets: [Bet] {
        allBets.filter { $0.ticketId == bet.ticketId }
    }

    @State private var showingVoidConfirmation = false
    @State private var showingSettleConfirmation = false
    @State private var showingOverrideGradeSheet = false
    @State private var overrideNewOutcome: String = "win"
    @State private var overrideReason: String = ""
    @State private var overrideIsLoading = false
    @State private var overrideErrorMessage: String?
    @State private var showingOverrideError = false

    // Reverse Settlement state
    @State private var showingReverseSettlementSheet = false
    @State private var reverseReason: String = ""
    @State private var reverseIsLoading = false
    @State private var reverseErrorMessage: String?
    @State private var showingReverseError = false
    @State private var showingReverseSuccess = false

    // MARK: - Computed Properties

    private var event: Event? {
        events.first { $0.id.uuidString == bet.eventId }
    }

    private var eventName: String {
        if let event = event {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return "Event \(bet.eventId.prefix(8))"
    }

    /// Creates a display name for the bet ticket
    /// - Single bets: "Lakers ML -150" or "OKC -6.5 (-110)"
    /// - Parlays: "3-leg parlay +450"
    private var betDisplayName: String {
        if bet.isParlay {
            // For parlays, show leg count and combined odds
            let combinedOdds = calculateCombinedOdds(for: parlayBets)
            let oddsString = combinedOdds > 0 ? "+\(combinedOdds)" : "\(combinedOdds)"
            return "\(parlayBets.count)-leg parlay \(oddsString)"
        } else {
            // For singles, show side with odds
            let oddsString = bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
            return "\(bet.side) \(oddsString)"
        }
    }

    /// Calculate combined American odds for a parlay
    private func calculateCombinedOdds(for parlayBets: [Bet]) -> Int {
        let combinedDecimal = parlayBets.reduce(Decimal(1)) { result, bet in
            result * americanToDecimal(bet.odds)
        }
        return decimalToAmerican(combinedDecimal)
    }

    private func americanToDecimal(_ odds: Int) -> Decimal {
        if odds > 0 {
            return 1 + Decimal(odds) / 100
        } else {
            return 1 + 100 / Decimal(abs(odds))
        }
    }

    private func decimalToAmerican(_ decimal: Decimal) -> Int {
        if decimal >= 2 {
            return Int(truncating: ((decimal - 1) * 100) as NSDecimalNumber)
        } else {
            return Int(truncating: (-100 / (decimal - 1)) as NSDecimalNumber)
        }
    }

    private var formattedOdds: String {
        bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
    }

    private var formattedStake: String {
        formatCurrency(bet.stake)
    }

    private var potentialPayout: Decimal {
        LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
    }

    private var formattedPotentialPayout: String {
        formatCurrency(potentialPayout)
    }

    private var totalReturn: Decimal {
        bet.stake + potentialPayout
    }

    private var formattedTotalReturn: String {
        formatCurrency(totalReturn)
    }

    private var statusColor: Color {
        switch bet.status {
        case .pending: return .orange
        case .accepted: return .blue
        case .declined: return .red
        case .readyToGrade: return .purple
        case .graded: return .indigo
        case .settled: return .green
        case .void: return .gray
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: bet.createdAt)
    }

    // MARK: - Parlay Partial Grading Info

    /// Whether this is a parlay that is only partially graded
    private var isParlayPartiallyGraded: Bool {
        guard bet.isParlay else { return false }
        let gradedCount = parlayBets.filter { $0.gradeResult != nil || $0.status == .void }.count
        return gradedCount > 0 && gradedCount < parlayBets.count
    }

    /// Number of legs awaiting results
    private var legsAwaitingCount: Int {
        guard bet.isParlay else { return 0 }
        return parlayBets.filter { $0.gradeResult == nil && $0.status != .void }.count
    }

    /// Whether the parlay already has a losing leg (will lose when settled)
    private var parlayWillLose: Bool {
        guard bet.isParlay else { return false }
        return parlayBets.contains { $0.gradeResult == .loss }
    }

    /// Whether all parlay legs are graded and settlement can proceed
    private var isParlayFullyGraded: Bool {
        guard bet.isParlay else { return true }
        return parlayBets.allSatisfy { $0.gradeResult != nil || $0.status == .void }
    }

    // MARK: - Body

    var body: some View {
        List {
            // MARK: - Status Section
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(bet.status.rawValue.capitalized)
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
                            .foregroundStyle(gradeResultColor(gradeResult))
                    }
                }
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Event Section
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
            .listRowBackground(Theme.cardBackground)

            // MARK: - Bet Details Section
            Section("Bet Details") {
                LabeledContent("Market", value: bet.market)
                LabeledContent("Side", value: bet.side)
                LabeledContent("Odds", value: formattedOdds)
                LabeledContent("Stake", value: formattedStake)
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Payout Section
            Section("Potential Payout") {
                LabeledContent("Profit if Win", value: formattedPotentialPayout)
                    .foregroundStyle(.green)
                LabeledContent("Total Return", value: formattedTotalReturn)
                    .fontWeight(.semibold)
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Player Section
            Section("Player") {
                if let player = bet.player {
                    LabeledContent("Name", value: player.name)
                    if let email = player.email {
                        LabeledContent("Email", value: email)
                    }
                } else {
                    Text("Unknown Player")
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Meta Section
            Section("Details") {
                LabeledContent("Created", value: formattedDate)
                LabeledContent("Bet ID", value: bet.id.uuidString.prefix(8) + "...")
                    .font(.caption)
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - History Section
            Section("History") {
                NavigationLink {
                    BetHistoryView(betId: bet.id)
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.accent)
                        Text("View History")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
            .listRowBackground(Theme.cardBackground)

            // MARK: - Actions Section
            if shouldShowActions {
                Section("Actions") {
                    actionButtons
                }
                .listRowBackground(Theme.cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(betDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Void this bet?",
            isPresented: $showingVoidConfirmation,
            titleVisibility: .visible
        ) {
            Button("Void Bet", role: .destructive) {
                voidBet()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. The bet will be marked as void.")
        }
        .confirmationDialog(
            "Settle this bet?",
            isPresented: $showingSettleConfirmation,
            titleVisibility: .visible
        ) {
            Button("Settle Bet") {
                settleBet()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let result = bet.gradeResult {
                Text("This will create a ledger entry for a \(result.rawValue) settlement.")
            } else {
                Text("This will create a ledger entry for the settlement.")
            }
        }
        .sheet(isPresented: $showingReverseSettlementSheet) {
            reverseSettlementSheetContent
        }
        .sheet(isPresented: $showingOverrideGradeSheet) {
            overrideGradeSheetContent
        }
        .alert("Reversal Successful", isPresented: $showingReverseSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The settlement has been reversed. The bet has returned to 'graded' status.")
        }
        .alert("Reversal Failed", isPresented: $showingReverseError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reverseErrorMessage ?? "An unknown error occurred.")
        }
        .alert("Override Failed", isPresented: $showingOverrideError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(overrideErrorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Actions View

    private var shouldShowActions: Bool {
        switch bet.status {
        case .pending, .accepted, .graded, .settled:
            return true
        default:
            return false
        }
    }

    /// Calculate the balance impact description for reversal warning
    private var reversalImpactDescription: String {
        if let settlementEntry = ledgerEntries.first(where: { $0.bet?.id == bet.id && $0.type == .settlement }) {
            let amount = settlementEntry.amount
            let formattedAmount = formatCurrency(abs(amount))
            if amount > 0 {
                return "This will remove \(formattedAmount) from the player's balance."
            } else if amount < 0 {
                return "This will add \(formattedAmount) to the player's balance."
            } else {
                return "This will have no impact on the player's balance (push)."
            }
        }
        return "This will reverse the settlement and adjust the player's balance."
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch bet.status {
        case .pending:
            Button {
                acceptBet()
            } label: {
                Label("Accept Bet", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)

            Button(role: .destructive) {
                declineBet()
            } label: {
                Label("Decline Bet", systemImage: "xmark.circle.fill")
            }

        case .accepted:
            Button(role: .destructive) {
                showingVoidConfirmation = true
            } label: {
                Label("Void Bet", systemImage: "trash.circle.fill")
            }

        case .graded:
            // For parlays, check if all legs are graded before allowing settlement
            if bet.isParlay {
                if isParlayPartiallyGraded {
                    // Show partial status badge
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Partial (\(parlayBets.count - legsAwaitingCount)/\(parlayBets.count))")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.warning)
                            Text("Cannot settle - \(legsAwaitingCount) leg\(legsAwaitingCount == 1 ? "" : "s") awaiting results")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }

                    // Show if parlay will lose
                    if parlayWillLose {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.danger)
                            Text("Parlay will lose when settled")
                                .font(.caption)
                                .foregroundStyle(Theme.danger)
                        }
                    }
                } else if isParlayFullyGraded {
                    // All legs graded, allow settlement
                    if parlayWillLose {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.danger)
                            Text("Parlay will lose when settled")
                                .font(.caption)
                                .foregroundStyle(Theme.danger)
                        }
                    }

                    Button {
                        showingSettleConfirmation = true
                    } label: {
                        Label("Settle Parlay", systemImage: "dollarsign.circle.fill")
                    }
                    .tint(.green)
                }
            } else {
                // Single bet - allow settlement
                Button {
                    showingSettleConfirmation = true
                } label: {
                    Label("Settle Bet", systemImage: "dollarsign.circle.fill")
                }
                .tint(.green)
            }

            // Override Grade button for graded bets (requires a grade to have been set)
            if bet.gradeResult != nil {
                Button {
                    prepareOverrideGradeSheet()
                } label: {
                    Label("Override Grade", systemImage: "pencil.circle.fill")
                }
                .tint(Theme.warning)
            }

        case .settled:
            Button(role: .destructive) {
                prepareReverseSettlementSheet()
            } label: {
                Label("Reverse Settlement", systemImage: "arrow.uturn.backward.circle.fill")
            }

            // Override Grade button for settled bets (will reverse settlement first)
            if bet.gradeResult != nil {
                Button {
                    prepareOverrideGradeSheet()
                } label: {
                    Label("Override Grade", systemImage: "pencil.circle.fill")
                }
                .tint(Theme.warning)
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func acceptBet() {
        let result = BetService.acceptBet(bet)
        switch result {
        case .success:
            break
        case .failure(let error):
            print("Failed to accept bet: \(error)")
        }
    }

    private func declineBet() {
        let result = BetService.declineBet(bet)
        switch result {
        case .success:
            break
        case .failure(let error):
            print("Failed to decline bet: \(error)")
        }
    }

    private func voidBet() {
        let result = BetService.voidBet(bet)
        switch result {
        case .success:
            break
        case .failure(let error):
            print("Failed to void bet: \(error)")
        }
    }

    private func settleBet() {
        // Handle parlay bets using group settlement
        if bet.isParlay {
            let result = GradingService.settleParlayBets(parlayBets, policy: parlayPolicy)
            switch result {
            case .success(let ledgerEntry):
                modelContext.insert(ledgerEntry)
            case .failure(let error):
                print("Failed to settle parlay: \(error)")
            }
        } else {
            // Handle single bets
            let result = GradingService.settleBet(bet)
            switch result {
            case .success(let ledgerEntry):
                modelContext.insert(ledgerEntry)
            case .failure(let error):
                print("Failed to settle bet: \(error)")
            }
        }
    }

    private func reverseBet() {
        let result = GradingService.reverseBet(bet, ledgerEntries: ledgerEntries)
        switch result {
        case .success(let reversalEntry):
            modelContext.insert(reversalEntry)
        case .failure(let error):
            print("Failed to reverse bet: \(error)")
        }
    }

    // MARK: - Override Grade

    /// Available outcome options for override (includes void)
    private let overrideOutcomeOptions = ["win", "loss", "push", "void"]

    /// Prepare the override grade sheet with current values
    private func prepareOverrideGradeSheet() {
        overrideNewOutcome = bet.gradeResult?.rawValue ?? "win"
        overrideReason = ""
        overrideIsLoading = false
        overrideErrorMessage = nil
        showingOverrideGradeSheet = true
    }

    /// Whether the confirm button should be disabled
    private var isOverrideConfirmDisabled: Bool {
        overrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        overrideNewOutcome == bet.gradeResult?.rawValue ||
        overrideIsLoading
    }

    /// Human-readable label for an outcome
    private func outcomeLabel(_ outcome: String) -> String {
        switch outcome {
        case "win": return "Win"
        case "loss": return "Loss"
        case "push": return "Push"
        case "void": return "Void"
        default: return outcome.capitalized
        }
    }

    /// Color for an outcome
    private func outcomeColor(_ outcome: String) -> Color {
        switch outcome {
        case "win": return Theme.accent
        case "loss": return Theme.danger
        case "push": return Theme.warning
        case "void": return Theme.textMuted
        default: return Theme.textSecondary
        }
    }

    /// The sheet content for overriding a grade
    @ViewBuilder
    private var overrideGradeSheetContent: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Current Grade Display
                    VStack(spacing: 8) {
                        Text("Current Grade")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        if let currentGrade = bet.gradeResult {
                            Text(outcomeLabel(currentGrade.rawValue))
                                .font(.title2.bold())
                                .foregroundStyle(outcomeColor(currentGrade.rawValue))
                        } else {
                            Text("Not Graded")
                                .font(.title2.bold())
                                .foregroundStyle(Theme.textMuted)
                        }

                        if bet.status == .settled {
                            Text("Settlement will be reversed")
                                .font(.caption)
                                .foregroundStyle(Theme.warning)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.cardBackground)
                    .cornerRadius(Theme.cornerRadius)

                    // New Grade Picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("New Grade")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        Picker("New Grade", selection: $overrideNewOutcome) {
                            ForEach(overrideOutcomeOptions, id: \.self) { outcome in
                                Text(outcomeLabel(outcome))
                                    .tag(outcome)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Reason TextField
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reason (Required)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        TextField("Enter reason for override...", text: $overrideReason, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Theme.cardBackground)
                            .cornerRadius(Theme.cornerRadiusSmall)
                            .lineLimit(3...6)
                    }

                    Spacer()

                    // Confirm Button
                    Button {
                        Task {
                            await submitOverrideGrade()
                        }
                    } label: {
                        if overrideIsLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Confirm Override")
                                .font(.headline)
                                .foregroundStyle(Theme.background)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(isOverrideConfirmDisabled ? Theme.accent.opacity(0.5) : Theme.accent)
                    .cornerRadius(Theme.cornerRadiusSmall)
                    .disabled(isOverrideConfirmDisabled)
                }
                .padding()
            }
            .navigationTitle("Override Grade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingOverrideGradeSheet = false
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    /// Submit the override grade request to the Edge Function
    private func submitOverrideGrade() async {
        overrideIsLoading = true

        do {
            let request = OverrideGradeRequest(
                betId: bet.id,
                newOutcome: overrideNewOutcome,
                reason: overrideReason.trimmingCharacters(in: .whitespacesAndNewlines),
                idempotencyKey: UUID().uuidString
            )

            let response: OverrideGradeResponse = try await EdgeFunctionService.shared.callFunction(
                name: "override_grade",
                body: request
            )

            // Update local bet with response
            await MainActor.run {
                if let newGradeResult = GradeResult(rawValue: response.bet.gradeResult ?? "") {
                    bet.gradeResult = newGradeResult
                }
                if let newStatus = BetStatus(rawValue: response.bet.status) {
                    bet.status = newStatus
                }

                overrideIsLoading = false
                showingOverrideGradeSheet = false
            }
        } catch let error as EdgeFunctionError {
            await MainActor.run {
                overrideIsLoading = false
                overrideErrorMessage = error.errorDescription
                showingOverrideGradeSheet = false
                showingOverrideError = true
            }
        } catch {
            await MainActor.run {
                overrideIsLoading = false
                overrideErrorMessage = error.localizedDescription
                showingOverrideGradeSheet = false
                showingOverrideError = true
            }
        }
    }

    // MARK: - Reverse Settlement

    /// Prepare the reverse settlement sheet with reset values
    private func prepareReverseSettlementSheet() {
        reverseReason = ""
        reverseIsLoading = false
        reverseErrorMessage = nil
        showingReverseSettlementSheet = true
    }

    /// Whether the reverse confirm button should be disabled
    private var isReverseConfirmDisabled: Bool {
        reverseReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reverseIsLoading
    }

    /// The sheet content for reversing a settlement
    @ViewBuilder
    private var reverseSettlementSheetContent: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Warning Section
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.warning)

                        Text("Reverse Settlement")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.textPrimary)

                        Text("This will undo the ledger entry created when this bet was settled. The player's balance will be adjusted accordingly.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.cardBackground)
                    .cornerRadius(Theme.cornerRadius)

                    // Impact Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Balance Impact")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        Text(reversalImpactDescription)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground)
                            .cornerRadius(Theme.cornerRadiusSmall)
                    }

                    // Reason TextField
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reason (Required)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        TextField("Enter reason for reversal...", text: $reverseReason, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Theme.cardBackground)
                            .cornerRadius(Theme.cornerRadiusSmall)
                            .lineLimit(3...6)
                    }

                    Spacer()

                    // Confirm Button
                    Button {
                        Task {
                            await submitReverseSettlement()
                        }
                    } label: {
                        if reverseIsLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Confirm Reversal")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(isReverseConfirmDisabled ? Theme.danger.opacity(0.5) : Theme.danger)
                    .cornerRadius(Theme.cornerRadiusSmall)
                    .disabled(isReverseConfirmDisabled)
                }
                .padding()
            }
            .navigationTitle("Reverse Settlement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingReverseSettlementSheet = false
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    /// Submit the reverse settlement request to the Edge Function
    private func submitReverseSettlement() async {
        reverseIsLoading = true

        do {
            let request = ReverseSettlementRequest(
                betId: bet.id,
                reason: reverseReason.trimmingCharacters(in: .whitespacesAndNewlines),
                idempotencyKey: UUID().uuidString
            )

            let response: ReverseSettlementResponse = try await EdgeFunctionService.shared.callFunction(
                name: "reverse_settlement",
                body: request
            )

            // Update local bet with response
            await MainActor.run {
                if let newStatus = BetStatus(rawValue: response.bet.status) {
                    bet.status = newStatus
                }

                reverseIsLoading = false
                showingReverseSettlementSheet = false
                showingReverseSuccess = true
            }
        } catch let error as EdgeFunctionError {
            await MainActor.run {
                reverseIsLoading = false
                reverseErrorMessage = error.errorDescription
                showingReverseSettlementSheet = false
                showingReverseError = true
            }
        } catch {
            await MainActor.run {
                reverseIsLoading = false
                reverseErrorMessage = error.localizedDescription
                showingReverseSettlementSheet = false
                showingReverseError = true
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

    private func gradeResultColor(_ result: GradeResult) -> Color {
        switch result {
        case .win: return .green
        case .loss: return .red
        case .push: return .orange
        }
    }
}

// MARK: - Override Grade Request/Response

/// Request body for override_grade Edge Function
private struct OverrideGradeRequest: Encodable {
    let betId: UUID
    let newOutcome: String
    let reason: String
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case betId = "bet_id"
        case newOutcome = "new_outcome"
        case reason
        case idempotencyKey = "idempotency_key"
    }
}

/// Response from override_grade Edge Function
private struct OverrideGradeResponse: Decodable {
    let success: Bool
    let bet: OverrideGradeBetResponse
    let settlementReversed: Bool

    enum CodingKeys: String, CodingKey {
        case success
        case bet
        case settlementReversed = "settlement_reversed"
    }
}

/// Bet data from override_grade response
private struct OverrideGradeBetResponse: Decodable {
    let id: UUID
    let status: String
    let gradeResult: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case gradeResult = "grade_result"
    }
}

// MARK: - Reverse Settlement Request/Response

/// Request body for reverse_settlement Edge Function
private struct ReverseSettlementRequest: Encodable {
    let betId: UUID
    let reason: String
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case betId = "bet_id"
        case reason
        case idempotencyKey = "idempotency_key"
    }
}

/// Response from reverse_settlement Edge Function
private struct ReverseSettlementResponse: Decodable {
    let success: Bool
    let bet: ReverseSettlementBetResponse
    let reversalEntry: ReverseSettlementLedgerResponse

    enum CodingKeys: String, CodingKey {
        case success
        case bet
        case reversalEntry = "reversal_entry"
    }
}

/// Bet data from reverse_settlement response
private struct ReverseSettlementBetResponse: Decodable {
    let id: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case status
    }
}

/// Ledger entry data from reverse_settlement response
private struct ReverseSettlementLedgerResponse: Decodable {
    let id: UUID
    let amount: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case id
        case amount
        case type
    }
}

#Preview {
    BetsListView()
        .modelContainer(for: [Bet.self, Event.self], inMemory: true)
}
