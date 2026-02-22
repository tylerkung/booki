import SwiftUI
import SwiftData

// MARK: - US-013: Refresh Odds for Existing Events

struct RefreshOddsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService
    @Query private var events: [Event]

    @StateObject private var oddsService = OddsAPIService.shared

    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var refreshResult: RefreshResult?

    /// Events that were imported from the API and haven't started yet
    private var eligibleEvents: [Event] {
        let now = Date()

        return events.filter { event in
            event.externalId != nil &&
            event.externalSource == "the-odds-api" &&
            event.status == .scheduled &&
            event.startTime > now
        }
    }

    /// Unique sport keys from eligible events
    private var sportKeys: Set<String> {
        Set(eligibleEvents.compactMap { sportKeyFromEvent($0) })
    }

    struct RefreshResult {
        let eventsRefreshed: Int
        let marketsUpdated: Int
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !oddsService.hasAPIKey {
                    noAPIKeyView
                } else if eligibleEvents.isEmpty {
                    noEventsView
                } else if let error = errorMessage {
                    errorView(error)
                } else if let result = refreshResult {
                    successView(result)
                } else {
                    refreshView
                }
            }
            .background(Theme.background)
            .navigationTitle("Refresh Odds")
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

    // MARK: - Views

    private var noAPIKeyView: some View {
        ContentUnavailableView(
            "No API Key",
            systemImage: "key.slash",
            description: Text("Add your Odds API key in Settings to refresh odds.")
        )
    }

    private var noEventsView: some View {
        ContentUnavailableView(
            "No Upcoming Events",
            systemImage: "calendar",
            description: Text("No imported events within the next 24 hours to refresh.")
        )
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(Theme.font(size: 48))
                .foregroundStyle(Theme.warning)

            Text("Error")
                .font(Theme.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                errorMessage = nil
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func successView(_ result: RefreshResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.font(size: 48))
                .foregroundStyle(Theme.accent)

            Text("Odds Refreshed")
                .font(Theme.title2)
                .fontWeight(.semibold)

            VStack(spacing: 4) {
                Text("Refreshed odds for \(result.eventsRefreshed) events")
                    .font(Theme.body)

                Text("\(result.marketsUpdated) markets updated")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var refreshView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(Theme.font(size: 64))
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 8) {
                Text("Ready to Refresh")
                    .font(Theme.title2)
                    .fontWeight(.semibold)

                Text("This will update odds for \(eligibleEvents.count) events starting within 24 hours.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let remaining = oddsService.quotaRemaining {
                Text("API quota: \(remaining) calls remaining")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            Button {
                Task {
                    await refreshOdds()
                }
            } label: {
                HStack {
                    if isRefreshing {
                        ProgressView()
                            .tint(.white)
                        Text("Refreshing...")
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Odds")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(isRefreshing)
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Actions

    private func refreshOdds() async {
        isRefreshing = true
        errorMessage = nil

        var totalEventsRefreshed = 0
        var totalMarketsUpdated = 0

        do {
            for sportKey in sportKeys {
                let oddsEvents = try await oddsService.fetchOdds(sport: sportKey)

                // Match API events to local events by external ID
                for oddsEvent in oddsEvents {
                    guard let localEvent = eligibleEvents.first(where: { $0.externalId == oddsEvent.id }) else {
                        continue
                    }

                    // Update markets
                    let marketsUpdated = updateEventMarkets(localEvent, from: oddsEvent)
                    if marketsUpdated > 0 {
                        localEvent.lastOddsUpdate = Date()
                        localEvent.needsSync = true
                        localEvent.version += 1  // Force SwiftData change detection
                        totalEventsRefreshed += 1
                        totalMarketsUpdated += marketsUpdated
                    }
                }
            }

            try modelContext.save()

            // Trigger upload to sync updated events to Supabase
            Task {
                await syncService.triggerUpload()
            }

            refreshResult = RefreshResult(
                eventsRefreshed: totalEventsRefreshed,
                marketsUpdated: totalMarketsUpdated
            )
            isRefreshing = false

        } catch let error as OddsAPIError {
            errorMessage = error.localizedDescription
            isRefreshing = false
        } catch {
            errorMessage = error.localizedDescription
            isRefreshing = false
        }
    }

    /// Updates an event's markets with fresh odds from the API
    private func updateEventMarkets(_ event: Event, from oddsEvent: OddsEvent) -> Int {
        guard let bookmakers = oddsEvent.bookmakers,
              let selectedBookmaker = bookmakers.first(where: { $0.key == oddsService.currentBookmaker }) ?? bookmakers.first,
              let existingMarkets = event.markets else {
            return 0
        }

        var updatedCount = 0

        for oddsMarket in selectedBookmaker.markets {
            // Find matching local market
            let marketType: MarketType? = {
                switch oddsMarket.key {
                case "h2h": return .moneyline
                case "spreads": return .spread
                case "totals": return .total
                default: return nil
                }
            }()

            guard let type = marketType,
                  let localMarket = existingMarkets.first(where: { $0.type == type }) else {
                continue
            }

            // Update odds based on market type
            switch type {
            case .moneyline:
                if let homeOutcome = oddsMarket.outcomes.first(where: { $0.name == oddsEvent.homeTeam }),
                   let awayOutcome = oddsMarket.outcomes.first(where: { $0.name == oddsEvent.awayTeam }) {
                    localMarket.oddsA = awayOutcome.price
                    localMarket.oddsB = homeOutcome.price
                    localMarket.updatedAt = Date()
                    updatedCount += 1
                }

            case .spread:
                if let homeOutcome = oddsMarket.outcomes.first(where: { $0.name == oddsEvent.homeTeam }),
                   let awayOutcome = oddsMarket.outcomes.first(where: { $0.name == oddsEvent.awayTeam }) {
                    let awaySpread = formatSpread(awayOutcome.point ?? 0)
                    let homeSpread = formatSpread(homeOutcome.point ?? 0)
                    localMarket.sideA = "\(oddsEvent.awayTeam) \(awaySpread)"
                    localMarket.sideB = "\(oddsEvent.homeTeam) \(homeSpread)"
                    localMarket.oddsA = awayOutcome.price
                    localMarket.oddsB = homeOutcome.price
                    localMarket.updatedAt = Date()
                    updatedCount += 1
                }

            case .total:
                if let overOutcome = oddsMarket.outcomes.first(where: { $0.name == "Over" }),
                   let underOutcome = oddsMarket.outcomes.first(where: { $0.name == "Under" }) {
                    let totalValue = overOutcome.point ?? underOutcome.point ?? 0
                    localMarket.sideA = "Over \(formatTotal(totalValue))"
                    localMarket.sideB = "Under \(formatTotal(totalValue))"
                    localMarket.oddsA = overOutcome.price
                    localMarket.oddsB = underOutcome.price
                    localMarket.updatedAt = Date()
                    updatedCount += 1
                }

            case .alternateSpread, .alternateTotal, .teamTotal:
                break // Alternate lines refreshed server-side via sync_games
            }
        }

        return updatedCount
    }

    // MARK: - Helpers

    private func sportKeyFromEvent(_ event: Event) -> String? {
        let sportKeyMapping: [String: String] = [
            "Football-NFL": "americanfootball_nfl",
            "Football-NCAAF": "americanfootball_ncaaf",
            "Basketball-NBA": "basketball_nba",
            "Basketball-NCAAB": "basketball_ncaab",
            "Basketball-WNBA": "basketball_wnba",
            "Baseball-MLB": "baseball_mlb",
            "Hockey-NHL": "icehockey_nhl",
            "Soccer-EPL": "soccer_epl",
            "Soccer-MLS": "soccer_usa_mls",
            "Soccer-Bundesliga": "soccer_germany_bundesliga",
            "Soccer-La Liga": "soccer_spain_la_liga",
            "Soccer-Serie A": "soccer_italy_serie_a",
            "Soccer-Ligue 1": "soccer_france_ligue_one",
            "MMA-UFC": "mma_mixed_martial_arts",
            "Boxing-Boxing": "boxing_boxing",
            "Golf-PGA": "golf_pga_championship",
            "Tennis-ATP": "tennis_atp_australian_open",
        ]

        let key = "\(event.sport)-\(event.league)"
        return sportKeyMapping[key]
    }

    private func formatSpread(_ value: Double) -> String {
        if value > 0 {
            return "+\(formatNumber(value))"
        } else {
            return formatNumber(value)
        }
    }

    private func formatTotal(_ value: Double) -> String {
        return formatNumber(value)
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }
}

#Preview {
    RefreshOddsView()
        .modelContainer(for: [Event.self, Market.self], inMemory: true)
}
