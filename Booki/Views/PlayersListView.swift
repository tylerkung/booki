import SwiftUI
import SwiftData

struct PlayersListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var players: [Player]
    @Query private var bets: [Bet]
    @Query private var ledgerEntries: [LedgerEntry]

    @State private var showArchived = false
    @State private var showingAddPlayer = false

    private var filteredPlayers: [Player] {
        if showArchived {
            return players
        } else {
            return players.filter { $0.status != .archived }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredPlayers.isEmpty {
                    ContentUnavailableView(
                        "No Players",
                        systemImage: "person.2.slash",
                        description: Text("Add players to start managing your book.")
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
                }
            }
            .navigationTitle("Players")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle(isOn: $showArchived) {
                        Label("Show Archived", systemImage: "archivebox")
                    }
                    .toggleStyle(.button)
                    .tint(showArchived ? .blue : .secondary)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddPlayer = true
                    } label: {
                        Label("Add Player", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: Player.self) { player in
                PlayerDetailView(player: player)
            }
            .sheet(isPresented: $showingAddPlayer) {
                AddPlayerSheet()
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
        case .active: return .green
        case .archived: return .gray
        case .banned: return .red
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
                        .font(.headline)

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor)
                        .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    Text("Balance: \(formattedBalance)")
                        .font(.subheadline)
                        .foregroundStyle(balanceColor)

                    Text("Limit: \(formattedCreditLimit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Utilization percentage
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(utilization))%")
                    .font(.title3.bold())
                    .foregroundStyle(utilizationColor)

                Text("Utilized")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var utilizationColor: Color {
        if utilization >= 90 {
            return .red
        } else if utilization >= 70 {
            return .orange
        } else {
            return .primary
        }
    }

    private var balanceColor: Color {
        // Positive balance = player owes bookie (secondary color)
        // Negative balance = bookie owes player (green - player is winning)
        balance >= 0 ? .secondary : .green
    }
}

// MARK: - Player Detail View

struct PlayerDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBets: [Bet]
    @Query private var allLedgerEntries: [LedgerEntry]
    @Query private var events: [Event]

    let player: Player

    @State private var showingArchiveConfirmation = false
    @State private var showingBanConfirmation = false
    @State private var showingReactivateConfirmation = false
    @State private var showingAdjustmentSheet = false

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
        case .active: return .green
        case .archived: return .gray
        case .banned: return .red
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
        balanceSummary.balanceOwed >= 0 ? Color.secondary : Color.green
    }

    private var availableCreditColor: Color {
        balanceSummary.availableCredit >= 0 ? Color.primary : Color.red
    }

    private var openLiabilityColor: Color {
        balanceSummary.openLiability > 0 ? Color.orange : Color.secondary
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
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(statusColor)
                        .clipShape(Capsule())
                }

                if let email = player.email {
                    LabeledContent("Email", value: email)
                }
            }

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

            // MARK: - Bet History Section
            Section("Bet History (\(playerBets.count))") {
                if playerBets.isEmpty {
                    Text("No bets yet")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(playerBets) { bet in
                        PlayerBetRowView(
                            bet: bet,
                            eventName: eventName(for: bet)
                        )
                    }
                }
            }

            // MARK: - Actions Section
            Section("Actions") {
                // Balance Adjustment
                Button {
                    showingAdjustmentSheet = true
                } label: {
                    Label("Adjust Balance", systemImage: "dollarsign.circle")
                }

                // Status Actions (contextual)
                statusActionButtons
            }
        }
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdjustmentSheet) {
            BalanceAdjustmentSheet(player: player)
        }
        .confirmationDialog(
            "Archive this player?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Player") {
                archivePlayer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archived players retain their history but are hidden from the active players list.")
        }
        .confirmationDialog(
            "Ban this player?",
            isPresented: $showingBanConfirmation,
            titleVisibility: .visible
        ) {
            Button("Ban Player", role: .destructive) {
                banPlayer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Banned players cannot submit new bets. Their existing bets and history are retained.")
        }
        .confirmationDialog(
            "Reactivate this player?",
            isPresented: $showingReactivateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reactivate Player") {
                reactivatePlayer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore the player to active status, allowing them to submit new bets.")
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
                Label("Archive Player", systemImage: "archivebox")
            }

            Button(role: .destructive) {
                showingBanConfirmation = true
            } label: {
                Label("Ban Player", systemImage: "person.crop.circle.badge.xmark")
            }

        case .archived:
            Button {
                showingReactivateConfirmation = true
            } label: {
                Label("Reactivate Player", systemImage: "arrow.uturn.backward.circle")
            }
            .tint(.green)

        case .banned:
            Button {
                showingReactivateConfirmation = true
            } label: {
                Label("Reactivate Player", systemImage: "arrow.uturn.backward.circle")
            }
            .tint(.green)
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

    // MARK: - Helpers

    private func eventName(for bet: Bet) -> String {
        if let event = events.first(where: { $0.id.uuidString == bet.eventId }) {
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
    let eventName: String

    private var formattedOdds: String {
        bet.odds > 0 ? "+\(bet.odds)" : "\(bet.odds)"
    }

    private var formattedStake: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: bet.stake as NSDecimalNumber) ?? "$\(bet.stake)"
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
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: bet.createdAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: Event name and status
            HStack {
                Text(eventName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(bet.status.rawValue.capitalized)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(statusColor)
                    .clipShape(Capsule())
            }

            // Middle row: Side and odds
            HStack {
                Text(bet.side)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.secondary)

                Text(formattedOdds)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formattedStake)
                    .font(.caption)
                    .fontWeight(.medium)
            }

            // Bottom row: Date and result (if any)
            HStack {
                Text(formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if let result = bet.gradeResult {
                    Text(result.rawValue.capitalized)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(gradeResultColor(result))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func gradeResultColor(_ result: GradeResult) -> Color {
        switch result {
        case .win: return .green
        case .loss: return .red
        case .push: return .orange
        }
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
                        Text("A negative adjustment credits the player (reduces what they owe).")
                    } else {
                        Text("A positive adjustment debits the player (increases what they owe).")
                    }
                }

                Section {
                    if let value = amountDecimal {
                        LabeledContent("Adjustment Amount") {
                            Text(formatCurrency(value))
                                .foregroundStyle(value >= 0 ? Color.secondary : Color.green)
                        }
                    }
                } header: {
                    Text("Preview")
                }
            }
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

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var creditLimitString: String = ""

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
                    Text("Player Details")
                } footer: {
                    Text("Name is required. Email and credit limit are optional.")
                }

                Section {
                    LabeledContent("Name") {
                        Text(name.isEmpty ? "—" : name)
                            .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    }

                    LabeledContent("Email") {
                        Text(email.isEmpty ? "Not provided" : email)
                            .foregroundStyle(email.isEmpty ? .secondary : .primary)
                    }

                    LabeledContent("Credit Limit") {
                        Text(formattedCreditLimit)
                    }
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle("Add Player")
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

        let player = PlayerService.addPlayer(
            name: trimmedName,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            creditLimit: creditLimit
        )

        modelContext.insert(player)
        dismiss()
    }
}

#Preview {
    PlayersListView()
        .modelContainer(for: [Player.self, Bet.self, LedgerEntry.self], inMemory: true)
}
