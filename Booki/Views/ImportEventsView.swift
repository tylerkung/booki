import SwiftUI
import SwiftData

// MARK: - US-007: Import Events UI

struct ImportEventsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var bookies: [Bookie]
    @Query private var existingEvents: [Event]

    @StateObject private var oddsService = OddsAPIService.shared

    @State private var sports: [OddsSport] = []
    @State private var selectedSportKey: String?
    @State private var isLoadingSports = true
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var importResult: ImportResult?

    private var currentBookieId: UUID? {
        bookies.first?.id
    }

    private var existingExternalIds: Set<String> {
        Set(existingEvents.compactMap { $0.externalId })
    }

    struct ImportResult {
        let eventsImported: Int
        let eventsSkipped: Int
        let sportTitle: String
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !oddsService.hasAPIKey {
                    noAPIKeyView
                } else if isLoadingSports {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if let result = importResult {
                    successView(result)
                } else {
                    sportPickerView
                }
            }
            .background(Theme.background)
            .navigationTitle("Import Events")
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
            await loadSports()
        }
    }

    // MARK: - Views

    private var noAPIKeyView: some View {
        ContentUnavailableView(
            "No API Key",
            systemImage: "key.slash",
            description: Text("Add your Odds API key in Settings to import events.")
        )
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading sports...")
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(Theme.font(size: 48))
                .foregroundStyle(.orange)

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
                Task {
                    await loadSports()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func successView(_ result: ImportResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.font(size: 48))
                .foregroundStyle(.green)

            Text("Import Complete")
                .font(Theme.title2)
                .fontWeight(.semibold)

            VStack(spacing: 4) {
                Text("Imported \(result.eventsImported) \(result.sportTitle) events")
                    .font(Theme.body)

                if result.eventsSkipped > 0 {
                    Text("\(result.eventsSkipped) events skipped (already exist)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
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

    private var sportPickerView: some View {
        List {
            Section {
                ForEach(sports) { sport in
                    Button {
                        selectedSportKey = sport.key
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sport.title)
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.textPrimary)

                                Text(sport.group)
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()

                            if selectedSportKey == sport.key {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .listRowBackground(Theme.cardBackground)
                }
            } header: {
                Text("Select a Sport")
            } footer: {
                if let remaining = oddsService.quotaRemaining {
                    Text("API quota: \(remaining) calls remaining")
                }
            }

            if selectedSportKey != nil {
                Section {
                    Button {
                        Task {
                            await importEvents()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isImporting {
                                ProgressView()
                                    .tint(.white)
                                Text("Importing...")
                            } else {
                                Text("Import Events")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isImporting)
                    .listRowBackground(Theme.accent)
                    .foregroundStyle(Theme.background)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Actions

    private func loadSports() async {
        isLoadingSports = true
        errorMessage = nil

        do {
            sports = try await oddsService.fetchSports()
            isLoadingSports = false
        } catch let error as OddsAPIError {
            errorMessage = error.localizedDescription
            isLoadingSports = false
        } catch {
            errorMessage = error.localizedDescription
            isLoadingSports = false
        }
    }

    private func importEvents() async {
        guard let sportKey = selectedSportKey,
              let sport = sports.first(where: { $0.key == sportKey }) else {
            return
        }

        isImporting = true
        errorMessage = nil

        do {
            let oddsEvents = try await oddsService.fetchOdds(sport: sportKey)

            var importedCount = 0
            var skippedCount = 0

            for oddsEvent in oddsEvents {
                // Skip if event already exists
                if existingExternalIds.contains(oddsEvent.id) {
                    skippedCount += 1
                    continue
                }

                // Create event
                let event = OddsAPIMapper.mapToEvent(from: oddsEvent, bookieId: currentBookieId)
                modelContext.insert(event)

                // Create markets
                let markets = OddsAPIMapper.mapToMarkets(
                    from: oddsEvent,
                    bookmaker: oddsService.currentBookmaker,
                    event: event
                )
                for market in markets {
                    modelContext.insert(market)
                }

                importedCount += 1
            }

            try modelContext.save()

            importResult = ImportResult(
                eventsImported: importedCount,
                eventsSkipped: skippedCount,
                sportTitle: sport.title
            )
            isImporting = false

        } catch let error as OddsAPIError {
            errorMessage = error.localizedDescription
            isImporting = false
        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
        }
    }
}

#Preview {
    ImportEventsView()
        .modelContainer(for: [Event.self, Market.self, Bookie.self], inMemory: true)
}
