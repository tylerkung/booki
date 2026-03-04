import SwiftUI
import SwiftData

/// Dashboard card showing tonight's exposure at a glance
struct TonightsExposureCard: View {
    @Query private var events: [Event]
    @Query private var bets: [Bet]

    /// High exposure threshold (hardcoded for v1)
    private let highExposureThreshold: Decimal = 1_000

    // MARK: - Computed Properties

    /// Events starting between now and end of current day (local timezone)
    private var tonightsEvents: [Event] {
        let calendar = Calendar.current
        let now = Date()
        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) else {
            return []
        }

        return events.filter { event in
            event.startTime >= now &&
            event.startTime <= endOfDay &&
            (event.status == .scheduled || event.status == .live)
        }
    }

    /// Event IDs for tonight's events (lowercased for comparison)
    private var tonightsEventIds: Set<String> {
        Set(tonightsEvents.map { $0.id.uuidString.lowercased() })
    }

    /// Exposure calculations for tonight's events
    private var tonightsExposures: [EventExposure] {
        let allExposures = ExposureService.calculateAllEventExposures(from: bets)
        return allExposures.filter { tonightsEventIds.contains($0.eventId.lowercased()) }
    }

    /// Total potential loss across tonight's games
    private var totalPotentialLoss: Decimal {
        tonightsExposures.reduce(Decimal.zero) { $0 + $1.maxExposure }
    }

    /// The event with the highest exposure tonight
    private var highestRiskGame: (event: Event, exposure: Decimal)? {
        guard let topExposure = tonightsExposures.max(by: { $0.maxExposure < $1.maxExposure }),
              topExposure.maxExposure > 0 else {
            return nil
        }

        let event = tonightsEvents.first {
            $0.id.uuidString.lowercased() == topExposure.eventId.lowercased()
        }

        guard let event else { return nil }
        return (event, topExposure.maxExposure)
    }

    /// Count of games with exposure >= threshold
    private var highExposureGameCount: Int {
        tonightsExposures.filter { $0.maxExposure >= highExposureThreshold }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.accentSecondary, Theme.accentTertiary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tonight's Open Activity")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("\(tonightsEvents.count) game\(tonightsEvents.count == 1 ? "" : "s") tonight")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                // High exposure badge
                if highExposureGameCount > 0 {
                    Text("\(highExposureGameCount) high risk")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Theme.danger)
                        )
                }
            }

            if tonightsEvents.isEmpty {
                // Empty state
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)

                    Text("No games tonight")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                // Total potential loss
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                        Text("Total Potential Loss")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Text(Theme.formatCurrency(totalPotentialLoss))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            totalPotentialLoss >= highExposureThreshold
                                ? LinearGradient(
                                    colors: [Theme.danger, Theme.accentTertiary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [Theme.textPrimary, Theme.textSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                }

                // Highest risk game
                if let riskGame = highestRiskGame {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.warning)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(riskGame.event.awayTeam) @ \(riskGame.event.homeTeam)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)

                            Text("Highest activity: \(Theme.formatCurrency(riskGame.exposure))")
                                .font(.caption)
                                .foregroundStyle(Theme.warning)
                        }

                        Spacer()

                        Text(formatTime(riskGame.event.startTime))
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                // View Exposure button
                NavigationLink {
                    EventsListView()
                } label: {
                    HStack {
                        Text("View Open Activity")
                            .font(.system(size: 14, weight: .bold))

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
