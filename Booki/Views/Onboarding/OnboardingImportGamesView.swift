import SwiftUI
import SwiftData

/// Sport option for onboarding import
struct OnboardingSport: Identifiable {
    let id: String  // API sport key
    let name: String
    let icon: String

    static let available: [OnboardingSport] = [
        OnboardingSport(id: "basketball_nba", name: "NBA", icon: "basketball.fill"),
        OnboardingSport(id: "americanfootball_nfl", name: "NFL", icon: "football.fill"),
        OnboardingSport(id: "basketball_ncaab", name: "NCAAB", icon: "basketball.fill"),
        OnboardingSport(id: "americanfootball_ncaaf", name: "NCAAF", icon: "football.fill"),
        OnboardingSport(id: "baseball_mlb", name: "MLB", icon: "baseball.fill"),
        OnboardingSport(id: "icehockey_nhl", name: "NHL", icon: "hockey.puck.fill")
    ]
}

/// Import games screen (Step 4)
/// Allows bookie to import games from selected sports
struct OnboardingImportGamesView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Query private var events: [Event]
    @Query private var bookies: [Bookie]

    // MARK: - Properties

    let onContinue: () -> Void

    // MARK: - State

    @State private var selectedSports: Set<String> = []
    @State private var isImporting: Bool = false
    @State private var isLoadingSports: Bool = true
    @State private var importComplete: Bool = false
    @State private var gamesImported: Int = 0
    @State private var errorMessage: String?
    @State private var activeSportsList: [OnboardingSport] = []

    @StateObject private var oddsService = OddsAPIService.shared

    // MARK: - Computed

    private var currentBookieId: UUID? {
        bookies.first?.id
    }

    private var existingExternalIds: Set<String> {
        Set(events.compactMap { $0.externalId })
    }

    private var canImport: Bool {
        !selectedSports.isEmpty && oddsService.hasAPIKey
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Let's add upcoming games.")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)

                Text("Select sports to import")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 32)

            if !oddsService.hasAPIKey {
                noAPIKeyView
            } else if isLoadingSports {
                checkingSportsView
            } else if importComplete {
                successView
            } else if isImporting {
                loadingView
            } else if activeSportsList.isEmpty {
                noSportsView
            } else {
                sportSelectionView
            }

            Spacer()

            // Import Button (only show during selection)
            if !isLoadingSports && !isImporting && !importComplete && !activeSportsList.isEmpty && oddsService.hasAPIKey {
                Button(action: importGames) {
                    Text("Import Games")
                        .font(Theme.headline)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canImport)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Theme.backgroundGradient)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isLoadingSports)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isImporting)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: importComplete)
        .task {
            await loadActiveSports()
        }
    }

    // MARK: - No API Key View

    private var noAPIKeyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.slash")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textMuted)

            Text("API Key Required")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Text("Add your Odds API key in Settings to import games.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: onContinue) {
                Text("Skip for Now")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Checking Sports View

    private var checkingSportsView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.accent)

            Text("Checking available sports...")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - No Sports View

    private var noSportsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sportscourt")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textMuted)

            Text("No Active Sports")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Text("There are no sports with upcoming games right now.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: onContinue) {
                Text("Skip for Now")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Sport Selection View

    private var sportSelectionView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Sport chips
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(activeSportsList) { sport in
                        SportChip(
                            sport: sport,
                            isSelected: selectedSports.contains(sport.id),
                            action: { toggleSport(sport.id) }
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.accent)

            Text("Importing games...")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Text("This may take a moment")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)

            Text("\(gamesImported) games imported")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .onAppear {
            // Auto-advance after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onContinue()
            }
        }
    }

    // MARK: - Actions

    private func loadActiveSports() async {
        guard oddsService.hasAPIKey else {
            isLoadingSports = false
            return
        }

        isLoadingSports = true

        do {
            let activeKeys = try await oddsService.fetchActiveSportKeys()
            activeSportsList = OnboardingSport.available.filter { activeKeys.contains($0.id) }
            isLoadingSports = false
        } catch {
            // On error, fall back to showing all sports
            activeSportsList = OnboardingSport.available
            isLoadingSports = false
        }
    }

    private func toggleSport(_ sportId: String) {
        if selectedSports.contains(sportId) {
            selectedSports.remove(sportId)
        } else {
            selectedSports.insert(sportId)
        }
    }

    private func importGames() {
        guard canImport else { return }

        isImporting = true
        errorMessage = nil
        gamesImported = 0

        Task {
            var totalImported = 0
            var errors: [String] = []

            for sportKey in selectedSports {
                do {
                    let oddsEvents = try await oddsService.fetchOdds(sport: sportKey)

                    // Filter out duplicates
                    let newEvents = oddsEvents.filter { !existingExternalIds.contains($0.id) }

                    // Map and save events
                    for oddsEvent in newEvents {
                        if let bookieId = currentBookieId {
                            let event = OddsAPIMapper.mapToEvent(from: oddsEvent, bookieId: bookieId)
                            modelContext.insert(event)

                            let markets = OddsAPIMapper.mapToMarkets(
                                from: oddsEvent,
                                bookmaker: oddsService.currentBookmaker,
                                event: event
                            )
                            for market in markets {
                                modelContext.insert(market)
                            }
                            totalImported += 1
                        }
                    }
                } catch {
                    errors.append("\(sportKey): \(error.localizedDescription)")
                }
            }

            // Save all
            try? modelContext.save()

            await MainActor.run {
                gamesImported = totalImported
                if !errors.isEmpty {
                    errorMessage = errors.joined(separator: "\n")
                }
                isImporting = false
                importComplete = true
            }
        }
    }
}

// MARK: - Sport Chip

private struct SportChip: View {
    let sport: OnboardingSport
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: sport.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textMuted)

                Text(sport.name)
                    .font(.headline)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(isSelected ? Theme.accent.opacity(0.15) : Theme.cardBackground)
            .cornerRadius(Theme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1)
            )
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingImportGamesView(onContinue: { print("Continue") })
        .modelContainer(for: [Event.self, Bookie.self])
}
