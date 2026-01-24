import SwiftUI
import SwiftData

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
                                    policyViolationReason: bet.policyViolationReason
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
}

// MARK: - Bet Row View

struct BetRowView: View {
    let bet: Bet
    let eventName: String
    var policyViolationReason: String? = nil

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
            // Top row: Player name and status badge
            HStack {
                Text(bet.player?.name ?? "Unknown Player")
                    .font(.headline)

                Spacer()

                Text(bet.status.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor)
                    .clipShape(Capsule())
            }

            // Second row: Event name
            Text(eventName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Third row: Market and side
            HStack {
                Text(bet.market)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.secondary)

                Text(bet.side)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            // Policy violation reason (only for pending bets with violations)
            if bet.status == .pending, let reason = policyViolationReason, !reason.isEmpty {
                Text("Review: \(reason)")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }

            // Bottom row: Odds and stake
            HStack {
                Text(formattedOdds)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formattedStake)
                    .font(.subheadline.bold())
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
    @State private var showingReverseConfirmation = false

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

            // MARK: - Bet Details Section
            Section("Bet Details") {
                LabeledContent("Market", value: bet.market)
                LabeledContent("Side", value: bet.side)
                LabeledContent("Odds", value: formattedOdds)
                LabeledContent("Stake", value: formattedStake)
            }

            // MARK: - Payout Section
            Section("Potential Payout") {
                LabeledContent("Profit if Win", value: formattedPotentialPayout)
                    .foregroundStyle(.green)
                LabeledContent("Total Return", value: formattedTotalReturn)
                    .fontWeight(.semibold)
            }

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

            // MARK: - Meta Section
            Section("Details") {
                LabeledContent("Created", value: formattedDate)
                LabeledContent("Bet ID", value: bet.id.uuidString.prefix(8) + "...")
                    .font(.caption)
            }

            // MARK: - Actions Section
            if shouldShowActions {
                Section("Actions") {
                    actionButtons
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Bet Details")
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
        .confirmationDialog(
            "Reverse this settlement?",
            isPresented: $showingReverseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reverse Settlement", role: .destructive) {
                reverseBet()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(reversalImpactDescription) The bet will return to 'graded' status and can be re-settled if needed.")
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
            Button {
                showingSettleConfirmation = true
            } label: {
                Label("Settle Bet", systemImage: "dollarsign.circle.fill")
            }
            .tint(.green)

        case .settled:
            Button(role: .destructive) {
                showingReverseConfirmation = true
            } label: {
                Label("Reverse Settlement", systemImage: "arrow.uturn.backward.circle.fill")
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

#Preview {
    BetsListView()
        .modelContainer(for: [Bet.self, Event.self], inMemory: true)
}
