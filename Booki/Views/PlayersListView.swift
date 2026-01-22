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

// MARK: - Player Detail View (Placeholder for US-021)

struct PlayerDetailView: View {
    let player: Player

    var body: some View {
        Text("Player Detail: \(player.name)")
            .navigationTitle(player.name)
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add Player Sheet (Placeholder for US-022)

struct AddPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Add Player Form")
                .navigationTitle("Add Player")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
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
