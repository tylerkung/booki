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

                // MARK: - Top Risk Events Section
                Section {
                    if viewModel.topRiskEvents.isEmpty {
                        Text("No active exposure")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.topRiskEvents) { item in
                            RiskEventRow(item: item)
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
