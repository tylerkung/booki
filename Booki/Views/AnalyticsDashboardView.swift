import SwiftUI
import SwiftData

struct AnalyticsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(OnboardingManager.self) private var onboardingManager: OnboardingManager?
    @EnvironmentObject private var syncService: SyncService
    @Query private var bets: [Bet]
    @Query private var players: [Player]
    @Query private var ledgerEntries: [LedgerEntry]

    @State private var showOnboardingFromCard = false
    @State private var lastUpdated = Date()

    private var summaries: [PlayerAnalyticsSummary] {
        let activePlayers = players.filter { $0.status == .active }
        return PlayerAttentionService.generateSummaries(
            players: activePlayers,
            bets: bets,
            ledgerEntries: ledgerEntries
        )
    }

    // MARK: - Aggregated Metrics

    private var totalExposure: Decimal {
        summaries.reduce(.zero) { $0 + $1.exposure.grossExposure }
    }

    private var totalPendingBets: Int {
        summaries.reduce(0) { $0 + $1.exposure.pendingBetCount }
    }

    private var totalPendingStake: Decimal {
        bets.filter { $0.status == .pending || $0.status == .accepted }
            .reduce(.zero) { $0 + $1.stake }
    }

    private var topRiskSummary: PlayerAnalyticsSummary? {
        summaries.first(where: { $0.pas.score > 0 })
    }

    private var overduePlayers: [PlayerAnalyticsSummary] {
        summaries.filter(\.isOverdue)
    }

    private var totalOverdueAmount: Decimal {
        overduePlayers.reduce(.zero) { $0 + $1.overdueAmount }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Finish Setup Card
                if let manager = onboardingManager, !manager.isOnboardingComplete {
                    FinishSetupCard(
                        onboardingManager: manager,
                        onResume: { showOnboardingFromCard = true }
                    )
                    .padding(.horizontal, 16)
                }

                if players.filter({ $0.status == .active }).isEmpty {
                    emptyState
                } else {
                    // Summary Cards 2x2
                    summaryCardsGrid
                        .padding(.horizontal, 16)

                    // Last updated
                    Text("Last updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Analytics")
        .onAppear { lastUpdated = Date() }
        .onChange(of: bets.count) { lastUpdated = Date() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SyncStatusIndicator(syncService: syncService)
            }
        }
        .fullScreenCover(isPresented: $showOnboardingFromCard) {
            if let manager = onboardingManager {
                OnboardingContainerView(
                    onboardingManager: manager,
                    startAt: manager.nextIncompleteStep,
                    onComplete: { showOnboardingFromCard = false },
                    onSkip: { showOnboardingFromCard = false }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textMuted)

            Text("No Players Yet")
                .font(Theme.title3)
                .foregroundStyle(Theme.textPrimary)

            Text("Add players to start tracking analytics and risk.")
                .font(Theme.bodyFont(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Summary Cards Grid

    private var summaryCardsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            // Card 1 — Net Exposure
            SummaryCard(
                icon: "chart.line.uptrend.xyaxis",
                label: "Net Exposure",
                value: formatCurrency(totalExposure),
                valueColor: totalExposure > 0 ? Theme.danger : Theme.textPrimary
            )

            // Card 2 — Pending Bets
            SummaryCard(
                icon: "clock.badge.exclamationmark",
                label: "Pending Bets",
                value: "\(totalPendingBets)",
                subtitle: formatCurrency(totalPendingStake) + " at stake",
                valueColor: totalPendingBets > 0 ? Theme.warning : Theme.textPrimary
            )

            // Card 3 — Top Risk Player
            topRiskCard

            // Card 4 — Outstanding Balances
            SummaryCard(
                icon: "exclamationmark.triangle.fill",
                label: "Outstanding",
                value: overduePlayers.isEmpty ? "All clear" : formatCurrency(totalOverdueAmount),
                subtitle: overduePlayers.isEmpty ? nil : "\(overduePlayers.count) player\(overduePlayers.count == 1 ? "" : "s")",
                valueColor: overduePlayers.isEmpty ? Theme.accent : Theme.danger
            )
        }
    }

    private var topRiskCard: some View {
        Group {
            if let top = topRiskSummary {
                SummaryCard(
                    icon: "person.fill.exclamationmark",
                    label: "Top Risk",
                    value: top.player.name,
                    subtitle: top.pas.reasonChips.first,
                    valueColor: top.pas.label == "High" ? Theme.danger : Theme.warning
                )
            } else {
                SummaryCard(
                    icon: "checkmark.shield.fill",
                    label: "Top Risk",
                    value: "All clear",
                    valueColor: Theme.accent
                )
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
}

// MARK: - Summary Card

private struct SummaryCard: View {
    let icon: String
    let label: String
    let value: String
    var subtitle: String? = nil
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)

                Text(label.uppercased())
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.5)
            }

            Text(value)
                .font(Theme.font(size: 20, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let subtitle {
                Text(subtitle)
                    .font(Theme.bodyFont(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardStyle()
    }
}

#Preview {
    NavigationStack {
        AnalyticsDashboardView()
    }
    .modelContainer(for: [Bet.self, Event.self, Player.self, LedgerEntry.self], inMemory: true)
    .environmentObject(SyncService())
}
