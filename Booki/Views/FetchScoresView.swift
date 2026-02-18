import SwiftUI
import SwiftData

// MARK: - US-009, US-010: Fetch Scores UI

struct FetchScoresView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var syncService: SyncService
    @Query private var events: [Event]

    @StateObject private var oddsService = OddsAPIService.shared

    @State private var isFetching = false
    @State private var errorMessage: String?
    @State private var updateResult: UpdateResult?

    /// Events that were imported from the API and may need score updates
    private var importedEvents: [Event] {
        events.filter { $0.externalId != nil && $0.externalSource == "the-odds-api" }
    }

    /// Unique sport keys from imported events
    private var sportKeys: Set<String> {
        Set(importedEvents.compactMap { sportKeyFromEvent($0) })
    }

    struct UpdateResult {
        let eventsUpdated: Int
        let eventsChecked: Int
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !oddsService.hasAPIKey {
                    noAPIKeyView
                } else if importedEvents.isEmpty {
                    noEventsView
                } else if let error = errorMessage {
                    errorView(error)
                } else if let result = updateResult {
                    successView(result)
                } else {
                    fetchView
                }
            }
            .background(Theme.background)
            .navigationTitle("Fetch Scores")
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
            description: Text("Add your Odds API key in Settings to fetch scores.")
        )
    }

    private var noEventsView: some View {
        ContentUnavailableView(
            "No Imported Events",
            systemImage: "sportscourt",
            description: Text("Import events from the Odds API first to fetch scores.")
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

    private func successView(_ result: UpdateResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.font(size: 48))
                .foregroundStyle(Theme.accent)

            Text("Scores Updated")
                .font(Theme.title2)
                .fontWeight(.semibold)

            VStack(spacing: 4) {
                Text("Updated scores for \(result.eventsUpdated) events")
                    .font(Theme.body)

                Text("Checked \(result.eventsChecked) total scores")
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

    private var fetchView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sportscourt")
                .font(Theme.font(size: 64))
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 8) {
                Text("Ready to Fetch Scores")
                    .font(Theme.title2)
                    .fontWeight(.semibold)

                Text("This will check for completed games and update scores for \(importedEvents.count) imported events.")
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
                    await fetchScores()
                }
            } label: {
                HStack {
                    if isFetching {
                        ProgressView()
                            .tint(.white)
                        Text("Fetching...")
                    } else {
                        Image(systemName: "arrow.down.circle")
                        Text("Fetch Scores")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(isFetching)
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Actions

    private func fetchScores() async {
        isFetching = true
        errorMessage = nil

        var totalUpdated = 0
        var totalChecked = 0

        do {
            for sportKey in sportKeys {
                let scores = try await oddsService.fetchScores(sport: sportKey, daysFrom: 7)
                totalChecked += scores.count

                let updated = updateEventsWithScores(scores)
                totalUpdated += updated
            }

            try modelContext.save()

            // Trigger upload to sync updated events to Supabase
            Task {
                await syncService.triggerUpload()
            }

            updateResult = UpdateResult(
                eventsUpdated: totalUpdated,
                eventsChecked: totalChecked
            )
            isFetching = false

        } catch let error as OddsAPIError {
            errorMessage = error.localizedDescription
            isFetching = false
        } catch {
            errorMessage = error.localizedDescription
            isFetching = false
        }
    }

    // MARK: - US-009: Update Events with Scores

    /// Updates events with scores from the API
    /// - Parameter scores: Array of scores from the API
    /// - Returns: Number of events updated
    private func updateEventsWithScores(_ scores: [OddsScore]) -> Int {
        var updatedCount = 0

        for score in scores {
            // Find matching event by external ID
            guard let event = importedEvents.first(where: { $0.externalId == score.id }) else {
                continue
            }

            // Skip if already completed with scores
            if event.status == .final && event.homeScore != nil && event.awayScore != nil {
                continue
            }

            // Parse scores
            if let teamScores = score.scores {
                let homeScoreValue = teamScores.first(where: { $0.name == score.homeTeam })
                let awayScoreValue = teamScores.first(where: { $0.name == score.awayTeam })

                if let homeStr = homeScoreValue?.score,
                   let awayStr = awayScoreValue?.score,
                   let home = Int(homeStr),
                   let away = Int(awayStr) {

                    event.homeScore = home
                    event.awayScore = away
                    event.status = .final
                    event.finalScore = "\(away)-\(home)"
                    event.needsSync = true
                    event.version += 1

                    updatedCount += 1
                }
            }
        }

        return updatedCount
    }

    // MARK: - Helpers

    /// Maps an Event back to its sport key based on sport/league
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
}

#Preview {
    FetchScoresView()
        .modelContainer(for: [Event.self, Market.self], inMemory: true)
}
