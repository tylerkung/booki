import SwiftUI
import SwiftData

/// Unified view for syncing games: removes old games, imports new ones, updates odds
/// Focuses on pre-game state only - no live updates
struct SyncGamesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @EnvironmentObject private var syncService: SyncService
    @Query private var events: [Event]

    @StateObject private var oddsService = OddsAPIService.shared

    @State private var isSyncing = false
    @State private var isLoadingSports = true
    @State private var errorMessage: String?
    @State private var syncResult: SyncResult?
    @State private var selectedSports: Set<String> = []
    @State private var activeSports: [(key: String, name: String)] = []

    /// All supported sports (filtered to active ones on load)
    private static let allSports: [(key: String, name: String)] = [
        ("basketball_nba", "NBA"),
        ("americanfootball_nfl", "NFL"),
        ("basketball_ncaab", "NCAAB"),
        ("americanfootball_ncaaf", "NCAAF"),
        ("baseball_mlb", "MLB"),
        ("icehockey_nhl", "NHL"),
    ]

    /// Events imported from the API
    private var importedEvents: [Event] {
        events.filter { $0.externalId != nil && $0.externalSource == "the-odds-api" }
    }

    /// Old events that should be removed (already started or completed)
    private var staleEvents: [Event] {
        let now = Date()
        return importedEvents.filter { $0.startTime < now || $0.status == .final }
    }

    struct SyncResult {
        let eventsRemoved: Int
        let eventsAdded: Int
        let oddsUpdated: Int
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !oddsService.hasAPIKey {
                    noAPIKeyView
                } else if isLoadingSports {
                    loadingSportsView
                } else if let error = errorMessage {
                    errorView(error)
                } else if let result = syncResult {
                    successView(result)
                } else if activeSports.isEmpty {
                    noSportsView
                } else {
                    syncView
                }
            }
            .background(Theme.background)
            .navigationTitle("Sync Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadActiveSports()
        }
    }

    // MARK: - Views

    private var loadingSportsView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Checking available sports...")
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSportsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sportscourt")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textMuted)

            Text("No Active Sports")
                .font(.title2)
                .fontWeight(.semibold)

            Text("There are no sports with upcoming games right now. Check back later.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                Task {
                    await loadActiveSports()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noAPIKeyView: some View {
        ContentUnavailableView(
            "No API Key",
            systemImage: "key.slash",
            description: Text("Add your Odds API key in Settings to sync games.")
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

    private func successView(_ result: SyncResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.font(size: 48))
                .foregroundStyle(Theme.accent)

            Text("Games Synced")
                .font(Theme.title2)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                if result.eventsRemoved > 0 {
                    Label("\(result.eventsRemoved) old games removed", systemImage: "trash")
                        .foregroundStyle(Theme.textSecondary)
                }
                if result.eventsAdded > 0 {
                    Label("\(result.eventsAdded) new games added", systemImage: "plus.circle")
                        .foregroundStyle(Theme.win)
                }
                if result.oddsUpdated > 0 {
                    Label("\(result.oddsUpdated) odds updated", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Theme.accent)
                }
                if result.eventsRemoved == 0 && result.eventsAdded == 0 && result.oddsUpdated == 0 {
                    Text("Everything is up to date")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .font(Theme.body)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var syncView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(Theme.font(size: 48))
                    .foregroundStyle(Theme.accent)

                Text("Sync Games")
                    .font(Theme.title2)
                    .fontWeight(.semibold)

                Text("Remove old games and fetch fresh upcoming games with current odds.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 24)

            // Sport selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Sports")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(activeSports, id: \.key) { sport in
                        SportToggleButton(
                            name: sport.name,
                            isSelected: selectedSports.contains(sport.key),
                            action: {
                                if selectedSports.contains(sport.key) {
                                    selectedSports.remove(sport.key)
                                } else {
                                    selectedSports.insert(sport.key)
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal)

            // Status info
            if !staleEvents.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.warning)
                    Text("\(staleEvents.count) old games will be removed")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let remaining = oddsService.quotaRemaining {
                Text("API quota: \(remaining) calls remaining")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            // Sync button
            Button {
                Task {
                    await syncGames()
                }
            } label: {
                HStack {
                    if isSyncing {
                        ProgressView()
                            .tint(.white)
                        Text("Syncing...")
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync Games")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(isSyncing || selectedSports.isEmpty)
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Actions

    private func loadActiveSports() async {
        guard oddsService.hasAPIKey else {
            isLoadingSports = false
            return
        }

        isLoadingSports = true
        errorMessage = nil

        do {
            let activeKeys = try await oddsService.fetchActiveSportKeys()
            activeSports = Self.allSports.filter { activeKeys.contains($0.key) }
            isLoadingSports = false
        } catch let error as OddsAPIError {
            errorMessage = error.localizedDescription
            isLoadingSports = false
        } catch {
            errorMessage = error.localizedDescription
            isLoadingSports = false
        }
    }

    private func syncGames() async {
        isSyncing = true
        errorMessage = nil

        var totalRemoved = 0
        var totalAdded = 0
        var totalOddsUpdated = 0

        do {
            let bookieId = authManager.currentBookieId

            // Step 1: Remove stale events (already started or completed)
            for event in staleEvents {
                modelContext.delete(event)
                totalRemoved += 1
            }

            // Step 2: Fetch and sync each selected sport
            for sportKey in selectedSports {
                let oddsEvents = try await oddsService.fetchOdds(sport: sportKey)

                for oddsEvent in oddsEvents {
                    // Check if we already have this event
                    if let existingEvent = importedEvents.first(where: { $0.externalId == oddsEvent.id }) {
                        // Update odds for existing event
                        let updated = updateEventOdds(existingEvent, from: oddsEvent)
                        if updated {
                            existingEvent.lastOddsUpdate = Date()
                            existingEvent.needsSync = true
                            existingEvent.version += 1
                            totalOddsUpdated += 1
                        }
                    } else {
                        // Add new event
                        let newEvent = OddsAPIMapper.mapToEvent(from: oddsEvent, bookieId: bookieId)
                        modelContext.insert(newEvent)

                        // Add markets
                        let markets = OddsAPIMapper.mapToMarkets(
                            from: oddsEvent,
                            bookmaker: oddsService.currentBookmaker,
                            event: newEvent
                        )
                        for market in markets {
                            modelContext.insert(market)
                        }

                        totalAdded += 1
                    }
                }
            }

            try modelContext.save()

            // Trigger upload to sync events to Supabase
            Task {
                await syncService.triggerUpload()
            }

            syncResult = SyncResult(
                eventsRemoved: totalRemoved,
                eventsAdded: totalAdded,
                oddsUpdated: totalOddsUpdated
            )
            isSyncing = false

        } catch let error as OddsAPIError {
            errorMessage = error.localizedDescription
            isSyncing = false
        } catch {
            errorMessage = error.localizedDescription
            isSyncing = false
        }
    }

    /// Updates an existing event's markets with fresh odds
    private func updateEventOdds(_ event: Event, from oddsEvent: OddsEvent) -> Bool {
        guard let bookmakers = oddsEvent.bookmakers,
              let selectedBookmaker = bookmakers.first(where: { $0.key == oddsService.currentBookmaker }) ?? bookmakers.first,
              let existingMarkets = event.markets else {
            return false
        }

        var updated = false

        for oddsMarket in selectedBookmaker.markets {
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

            switch type {
            case .moneyline:
                if let homeOutcome = oddsMarket.outcomes.first(where: { $0.name == oddsEvent.homeTeam }),
                   let awayOutcome = oddsMarket.outcomes.first(where: { $0.name == oddsEvent.awayTeam }) {
                    if localMarket.oddsA != awayOutcome.price || localMarket.oddsB != homeOutcome.price {
                        localMarket.oddsA = awayOutcome.price
                        localMarket.oddsB = homeOutcome.price
                        localMarket.updatedAt = Date()
                        updated = true
                    }
                }

            case .spread:
                if let homeOutcome = oddsMarket.outcomes.first(where: { $0.name == oddsEvent.homeTeam }),
                   let awayOutcome = oddsMarket.outcomes.first(where: { $0.name == oddsEvent.awayTeam }) {
                    let awaySpread = formatSpread(awayOutcome.point ?? 0)
                    let homeSpread = formatSpread(homeOutcome.point ?? 0)
                    let newSideA = "\(oddsEvent.awayTeam) \(awaySpread)"
                    let newSideB = "\(oddsEvent.homeTeam) \(homeSpread)"

                    if localMarket.sideA != newSideA || localMarket.sideB != newSideB ||
                       localMarket.oddsA != awayOutcome.price || localMarket.oddsB != homeOutcome.price {
                        localMarket.sideA = newSideA
                        localMarket.sideB = newSideB
                        localMarket.oddsA = awayOutcome.price
                        localMarket.oddsB = homeOutcome.price
                        localMarket.updatedAt = Date()
                        updated = true
                    }
                }

            case .total:
                if let overOutcome = oddsMarket.outcomes.first(where: { $0.name == "Over" }),
                   let underOutcome = oddsMarket.outcomes.first(where: { $0.name == "Under" }) {
                    let totalValue = overOutcome.point ?? underOutcome.point ?? 0
                    let newSideA = "Over \(formatTotal(totalValue))"
                    let newSideB = "Under \(formatTotal(totalValue))"

                    if localMarket.sideA != newSideA || localMarket.sideB != newSideB ||
                       localMarket.oddsA != overOutcome.price || localMarket.oddsB != underOutcome.price {
                        localMarket.sideA = newSideA
                        localMarket.sideB = newSideB
                        localMarket.oddsA = overOutcome.price
                        localMarket.oddsB = underOutcome.price
                        localMarket.updatedAt = Date()
                        updated = true
                    }
                }

            case .alternateSpread, .alternateTotal, .teamTotal:
                break // Alternate lines are handled server-side via sync_games
            }
        }

        return updated
    }

    // MARK: - Helpers

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
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}

// MARK: - Sport Toggle Button

private struct SportToggleButton: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(name)
                    .fontWeight(.medium)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Theme.accent.opacity(0.15) : Theme.cardBackground)
            .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SyncGamesView()
        .environmentObject(AuthManager())
        .modelContainer(for: [Event.self, Market.self], inMemory: true)
}
