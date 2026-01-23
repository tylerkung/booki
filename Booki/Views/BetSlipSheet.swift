import SwiftUI

/// Full bet slip sheet showing all selections
/// US-040: Build Persistent Bet Slip
struct BetSlipSheet: View {
    @ObservedObject private var betSlipManager = BetSlipManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if betSlipManager.isEmpty {
                    emptyState
                } else {
                    selectionsList
                }
            }
            .navigationTitle("Bet Slip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if !betSlipManager.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            withAnimation {
                                betSlipManager.clearAll()
                            }
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView(
            "No Selections",
            systemImage: "ticket",
            description: Text("Tap odds buttons on game cards to add selections to your bet slip.")
        )
    }

    // MARK: - Selections List

    @ViewBuilder
    private var selectionsList: some View {
        List {
            // Header with count
            Section {
                HStack {
                    Text("\(betSlipManager.count) Selection\(betSlipManager.count == 1 ? "" : "s")")
                        .font(.headline)
                    Spacer()
                    Text("Max \(betSlipManager.maxSelections)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Selections
            Section {
                ForEach(Array(betSlipManager.items.enumerated()), id: \.element.marketId) { index, item in
                    BetSlipItemRow(item: item)
                }
                .onDelete(perform: deleteItems)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Delete Handler

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            betSlipManager.remove(at: index)
        }
    }
}

// MARK: - Bet Slip Item Row

/// Row view for a single bet slip selection
struct BetSlipItemRow: View {
    let item: BetSlipItem

    private var formattedOdds: String {
        item.odds >= 0 ? "+\(item.odds)" : "\(item.odds)"
    }

    private var marketTypeLabel: String {
        switch item.marketType {
        case .spread: return "Spread"
        case .total: return "Total"
        case .moneyline: return "Moneyline"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Event description
            Text(item.eventDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Selection details
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.side)
                        .font(.headline)

                    Text(marketTypeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Odds badge
                Text(formattedOdds)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BetSlipSheet()
}
