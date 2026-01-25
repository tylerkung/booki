import SwiftUI
import SwiftData

/// Main view for players after they log in
/// Shows their bets, balance, and activity in a read-only format
struct PlayerMainView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: AuthManager
    @Query private var allBets: [Bet]
    @Query private var allLedgerEntries: [LedgerEntry]
    @Query private var events: [Event]
    @Query private var players: [Player]

    // MARK: - State

    @State private var showingLogoutConfirmation = false
    @State private var showingLogoutError = false
    @State private var logoutErrorMessage = ""

    // MARK: - Computed Properties

    /// Get the current player based on auth user ID
    private var currentPlayer: Player? {
        guard let authUserId = authManager.currentPlayerId else { return nil }
        return players.first { $0.authUserId == authUserId }
    }

    private var playerBets: [Bet] {
        guard let player = currentPlayer else { return [] }
        return allBets
            .filter { $0.player?.id == player.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var activeBets: [Bet] {
        playerBets.filter { $0.status == .pending || $0.status == .accepted }
    }

    private var settledBets: [Bet] {
        playerBets.filter { $0.status == .settled || $0.status == .graded }
    }

    private var playerLedgerEntries: [LedgerEntry] {
        guard let player = currentPlayer else { return [] }
        return allLedgerEntries
            .filter { $0.player?.id == player.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var currentBalance: Decimal {
        BalanceService.calculateBalance(from: playerLedgerEntries)
    }

    private var formattedBalance: String {
        formatCurrency(currentBalance)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Welcome Section
                Section {
                    if let player = currentPlayer {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Welcome back,")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(player.name)
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        .padding(.vertical, 8)
                    } else {
                        Text("Loading...")
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Balance Section
                Section("Your Balance") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Balance")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(formattedBalance)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(balanceColor)
                        }

                        Spacer()

                        // Balance indicator
                        Image(systemName: currentBalance >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.title)
                            .foregroundStyle(balanceColor)
                    }
                    .padding(.vertical, 8)

                    // Balance explanation
                    if currentBalance > 0 {
                        Text("You owe this amount to your bookie")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if currentBalance < 0 {
                        Text("Your bookie owes you this amount")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Your account is settled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Active Bets Section
                Section("Active Bets (\(activeBets.count))") {
                    if activeBets.isEmpty {
                        Text("No active bets")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(activeBets) { bet in
                            PlayerBetCard(bet: bet, eventName: eventName(for: bet))
                        }
                    }
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Settled Bets Section
                Section("Recent Results (\(settledBets.prefix(10).count))") {
                    if settledBets.isEmpty {
                        Text("No settled bets yet")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(settledBets.prefix(10)) { bet in
                            PlayerBetCard(bet: bet, eventName: eventName(for: bet))
                        }

                        if settledBets.count > 10 {
                            Text("+ \(settledBets.count - 10) more settled bets")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Recent Activity Section
                Section("Recent Activity") {
                    if playerLedgerEntries.isEmpty {
                        Text("No activity yet")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(playerLedgerEntries.prefix(10)) { entry in
                            LedgerEntryRow(entry: entry)
                        }

                        if playerLedgerEntries.count > 10 {
                            Text("+ \(playerLedgerEntries.count - 10) more entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Account Section
                Section {
                    Button(role: .destructive) {
                        showingLogoutConfirmation = true
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } header: {
                    Text("Account")
                }
                .listRowBackground(Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("My Bets")
            .alert("Log Out", isPresented: $showingLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    performLogout()
                }
            } message: {
                Text("Are you sure you want to log out?")
            }
            .alert("Logout Error", isPresented: $showingLogoutError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(logoutErrorMessage)
            }
        }
    }

    // MARK: - Helpers

    private var balanceColor: Color {
        if currentBalance > 0 {
            return .orange // owes money
        } else if currentBalance < 0 {
            return .green // winning
        } else {
            return .secondary // even
        }
    }

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
        return formatter.string(from: abs(value) as NSDecimalNumber) ?? "$\(abs(value))"
    }

    private func performLogout() {
        Task {
            do {
                try await authManager.signOut()
            } catch {
                logoutErrorMessage = error.localizedDescription
                showingLogoutError = true
            }
        }
    }
}

// MARK: - Player Bet Card

struct PlayerBetCard: View {
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

    private var gradeResultColor: Color {
        switch bet.gradeResult {
        case .win: return .green
        case .loss: return .red
        case .push: return .orange
        case nil: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Event and status
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

            // Pick details
            HStack {
                Text(bet.side)
                Text("•")
                    .foregroundStyle(.secondary)
                Text(formattedOdds)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formattedStake)
                    .fontWeight(.semibold)
            }
            .font(.caption)

            // Result if settled
            if let result = bet.gradeResult {
                HStack {
                    Text(result.rawValue.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(gradeResultColor)

                    Spacer()

                    Text(bet.createdAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(bet.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Ledger Entry Row

struct LedgerEntryRow: View {
    let entry: LedgerEntry

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let absAmount = abs(entry.amount)
        return formatter.string(from: absAmount as NSDecimalNumber) ?? "$\(absAmount)"
    }

    private var amountColor: Color {
        // Positive = player owes more (debit), Negative = player owes less (credit)
        entry.amount >= 0 ? .orange : .green
    }

    private var entryIcon: String {
        switch entry.type {
        case .settlement: return "checkmark.circle"
        case .adjustment: return "slider.horizontal.3"
        case .paymentLogged: return "banknote"
        case .reversal: return "arrow.uturn.backward.circle"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entryIcon)
                .font(.title3)
                .foregroundStyle(amountColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline)

                Text(entry.entryDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.amount >= 0 ? "+\(formattedAmount)" : "-\(formattedAmount)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(amountColor)

                Text(entry.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PlayerMainView()
        .modelContainer(for: [Player.self, Bet.self, LedgerEntry.self, Event.self], inMemory: true)
        .environmentObject(AuthManager())
}
