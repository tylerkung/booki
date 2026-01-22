import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bets: [Bet]
    @Query private var events: [Event]

    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Exposure Overview Section
                Section {
                    ExposureCard(totalExposure: viewModel.totalExposure)
                }

                // MARK: - Pending Bets Count Section
                Section {
                    PendingBetsCard(count: viewModel.pendingBetsCount)
                }

                // MARK: - Pending Bets Queue Section
                Section {
                    if viewModel.pendingBets.isEmpty {
                        Text("No pending bets")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.pendingBets) { bet in
                            PendingBetRow(
                                bet: bet,
                                eventName: eventName(for: bet),
                                onAccept: { acceptBet(bet) },
                                onDecline: { declineBet(bet) }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    declineBet(bet)
                                } label: {
                                    Label("Decline", systemImage: "xmark.circle")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    acceptBet(bet)
                                } label: {
                                    Label("Accept", systemImage: "checkmark.circle")
                                }
                                .tint(.green)
                            }
                        }
                    }
                } header: {
                    Text("Pending Bets Queue")
                }

                // MARK: - Top Risk Events Section
                Section {
                    if viewModel.topRiskEvents.isEmpty {
                        Text("No active exposure")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.topRiskEvents) { item in
                            if let event = events.first(where: { $0.id.uuidString == item.eventId }) {
                                NavigationLink(value: event) {
                                    RiskEventRow(item: item)
                                }
                            } else {
                                RiskEventRow(item: item)
                            }
                        }
                    }
                } header: {
                    Text("Top Risk Events")
                }
            }
            .navigationTitle("Dashboard")
            .refreshable {
                viewModel.refresh(bets: bets, events: events)
            }
            .onAppear {
                viewModel.refresh(bets: bets, events: events)
            }
            .onChange(of: bets.count) {
                viewModel.refresh(bets: bets, events: events)
            }
            .onChange(of: bets.map { $0.status }) {
                viewModel.refresh(bets: bets, events: events)
            }
            .navigationDestination(for: Event.self) { event in
                EventDetailView(event: event)
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

    private func acceptBet(_ bet: Bet) {
        let result = BetService.acceptBet(bet)
        switch result {
        case .success:
            viewModel.refresh(bets: bets, events: events)
        case .failure:
            break
        }
    }

    private func declineBet(_ bet: Bet) {
        let result = BetService.declineBet(bet)
        switch result {
        case .success:
            viewModel.refresh(bets: bets, events: events)
        case .failure:
            break
        }
    }
}

// MARK: - Exposure Card

struct ExposureCard: View {
    let totalExposure: Decimal

    private var formattedExposure: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: totalExposure as NSDecimalNumber) ?? "$\(totalExposure)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total Open Exposure")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(formattedExposure)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(totalExposure > 0 ? .red : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

// MARK: - Pending Bets Card

struct PendingBetsCard: View {
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(count > 0 ? .orange : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Pending Bets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("\(count)")
                    .font(.title2.bold())
                    .foregroundStyle(count > 0 ? .orange : .primary)
            }

            Spacer()

            if count > 0 {
                Text("Action Required")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pending Bet Row

struct PendingBetRow: View {
    let bet: Bet
    let eventName: String
    let onAccept: () -> Void
    let onDecline: () -> Void

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: Player name and event
            HStack {
                Text(bet.player?.name ?? "Unknown Player")
                    .font(.headline)

                Spacer()

                Text(eventName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Middle row: Side, odds, stake
            HStack {
                Text(bet.side)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Text(formattedOdds)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formattedStake)
                    .font(.subheadline.bold())
            }

            // Bottom row: Action buttons
            HStack(spacing: 12) {
                Button {
                    onAccept()
                } label: {
                    Label("Accept", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    onDecline()
                } label: {
                    Label("Decline", systemImage: "xmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Risk Event Row

struct RiskEventRow: View {
    let item: EventRiskItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.headline)

                if let startTime = item.formattedStartTime {
                    Text(startTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(item.formattedExposure)
                .font(.subheadline.bold())
                .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Bet.self, Event.self], inMemory: true)
}
