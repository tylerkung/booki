import SwiftUI

/// Full bet slip sheet showing all selections
/// US-040: Build Persistent Bet Slip
/// US-041: Support Multi-Bet (Parlay) Selections
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
            // Header with count and mode toggle (US-041)
            Section {
                VStack(spacing: 12) {
                    HStack {
                        Text("\(betSlipManager.count) Selection\(betSlipManager.count == 1 ? "" : "s")")
                            .font(.headline)
                        Spacer()
                        Text("Max \(betSlipManager.maxSelections)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Singles/Parlay Toggle (US-041)
                    Picker("Bet Mode", selection: $betSlipManager.betMode) {
                        ForEach(BetMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            // Selections
            Section {
                ForEach(Array(betSlipManager.items.enumerated()), id: \.element.marketId) { index, item in
                    BetSlipItemRow(item: item, onRemove: {
                        withAnimation {
                            betSlipManager.remove(at: index)
                        }
                    })
                }
                .onDelete(perform: deleteItems)
            }

            // Combined Parlay Odds (US-041)
            if betSlipManager.betMode == .parlay && betSlipManager.count > 1 {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(betSlipManager.count)-Leg Parlay")
                                .font(.headline)
                            Text("Combined odds")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let parlayOdds = betSlipManager.formattedParlayOdds {
                            Text(parlayOdds)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }
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
/// US-041: Added onRemove callback for X button
struct BetSlipItemRow: View {
    let item: BetSlipItem
    let onRemove: () -> Void

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
        HStack(spacing: 12) {
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

            // X button to remove (US-041)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BetSlipSheet()
}
