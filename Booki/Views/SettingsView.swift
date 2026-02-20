import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var syncService: SyncService
    @Query private var bookies: [Bookie]

    @State private var showingEditProfile = false
    @State private var isSyncing = false
    @State private var showingSeedDataConfirmation = false
    @State private var showingSeedDataSuccess = false
    @State private var seededEventCount = 0
    @State private var showingLogoutConfirmation = false
    @State private var showingLogoutError = false
    @State private var logoutErrorMessage = ""

    // Alert Threshold settings
    @AppStorage("balanceThreshold") private var balanceThreshold: Double = 500.0
    @AppStorage("agingThreshold") private var agingThreshold: Int = 7

    // Odds API settings (US-011)
    @AppStorage("oddsAPIKey") private var oddsAPIKey: String = ""
    @AppStorage("oddsAPIBookmaker") private var oddsAPIBookmaker: String = "draftkings"
    @StateObject private var oddsService = OddsAPIService.shared
    @State private var isTestingAPI = false
    @State private var showingAPITestResult = false
    @State private var apiTestSuccess = false
    @State private var apiTestMessage = ""

    // Auto-pilot settings (US-010)
    @State private var manualBetAcceptance = false
    @State private var manualBetGrading = false
    @State private var isSavingSettings = false
    @State private var showingSettingsError = false
    @State private var settingsErrorMessage = ""

    private var currentBookie: Bookie? {
        bookies.first
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Bookie Profile Section
                Section {
                    if let bookie = currentBookie {
                        LabeledContent("Name", value: bookie.name)
                        LabeledContent("Email", value: bookie.email)
                        LabeledContent("Status") {
                            Text(bookie.subscriptionStatus.rawValue.capitalized)
                                .foregroundStyle(subscriptionStatusColor(bookie.subscriptionStatus))
                        }

                        Button {
                            showingEditProfile = true
                        } label: {
                            Label("Edit Profile", systemImage: "pencil")
                        }
                    } else {
                        Text("No profile configured")
                            .foregroundStyle(Theme.textSecondary)
                            .italic()

                        Button {
                            showingEditProfile = true
                        } label: {
                            Label("Create Profile", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Organizer Profile")
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Alert Thresholds Section
                Section {
                    HStack {
                        Text("Balance Threshold")
                        Spacer()
                        TextField("Amount", value: $balanceThreshold, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    Stepper("Aging Threshold: \(agingThreshold) days", value: $agingThreshold, in: 1...90)
                } header: {
                    Text("Balance Alerts")
                } footer: {
                    Text("Get alerted when members have balances above the threshold or aging balances older than the specified days.")
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Bet Management Section (US-010)
                Section {
                    // Auto-pilot mode toggles
                    Toggle(isOn: $manualBetAcceptance) {
                        Label("Require Manual Pick Approval", systemImage: "hand.raised")
                    }
                    .onChange(of: manualBetAcceptance) { _, newValue in
                        Task {
                            await saveAutoPilotSettings(manualBetAcceptance: newValue, manualBetGrading: nil)
                        }
                    }

                    Toggle(isOn: $manualBetGrading) {
                        Label("Grade Picks Manually", systemImage: "checkmark.circle")
                    }
                    .onChange(of: manualBetGrading) { _, newValue in
                        Task {
                            await saveAutoPilotSettings(manualBetAcceptance: nil, manualBetGrading: newValue)
                        }
                    }

                    NavigationLink {
                        AcceptancePolicySettingsView()
                    } label: {
                        Label("Acceptance Rules", systemImage: "checkmark.shield")
                    }
                } header: {
                    Text("Pick Management")
                } footer: {
                    if manualBetAcceptance || manualBetGrading {
                        Text("Manual mode enabled. You'll need to review picks and/or grade them yourself.")
                    } else {
                        Text("Auto-pilot mode: Picks are auto-accepted and auto-graded when games complete.")
                    }
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Odds API Section (US-011)
                Section {
                    SecureField("API Key", text: $oddsAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()

                    Picker("Bookmaker", selection: $oddsAPIBookmaker) {
                        Text("DraftKings").tag("draftkings")
                        Text("FanDuel").tag("fanduel")
                        Text("BetMGM").tag("betmgm")
                        Text("Caesars").tag("caesars")
                    }

                    if let remaining = oddsService.quotaRemaining {
                        LabeledContent("API Calls Remaining") {
                            HStack {
                                Text("\(remaining)")
                                if remaining < 100 {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.warning)
                                }
                            }
                        }
                    }

                    Button {
                        Task {
                            await testAPIConnection()
                        }
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            if isTestingAPI {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(oddsAPIKey.isEmpty || isTestingAPI)
                } header: {
                    Text("Odds API")
                } footer: {
                    if let remaining = oddsService.quotaRemaining, remaining < 100 {
                        Text("Low API quota. Your quota resets monthly.")
                            .foregroundStyle(Theme.warning)
                    } else {
                        Text("Get your API key from the-odds-api.com")
                    }
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Data Management Section
                Section {
                    NavigationLink {
                        ExportDataView()
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingSeedDataConfirmation = true
                    } label: {
                        Label("Load Sample Data", systemImage: "sportscourt")
                    }
                } header: {
                    Text("Data Management")
                } footer: {
                    Text("Export your data or load sample events for testing.")
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Sync Section
                Section {
                    Button {
                        Task {
                            isSyncing = true
                            await syncService.sync()
                            isSyncing = false
                        }
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isSyncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSyncing)
                } header: {
                    Text("Data")
                } footer: {
                    if let lastSync = syncService.lastSyncedAt {
                        Text("Last synced: \(lastSync.formatted())")
                    } else {
                        Text("Not synced yet")
                    }
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - Account Section
                Section {
                    Button(role: .destructive) {
                        showingLogoutConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Log Out")
                        }
                        .font(Theme.headline)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.danger)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Account")
                } footer: {
                    if let userId = authManager.currentUserId {
                        Text("Signed in as \(userId)")
                    }
                }
                .listRowBackground(Theme.cardBackground)

                // MARK: - About Section
                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Platform", value: "iOS")
                } header: {
                    Text("About")
                }
                .listRowBackground(Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .sheet(isPresented: $showingEditProfile) {
                EditProfileSheet(existingBookie: currentBookie)
            }
            .alert("Load Sample Data", isPresented: $showingSeedDataConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear & Load", role: .destructive) {
                    loadSampleData()
                }
            } message: {
                Text("This will delete all existing events and load 12 sample games across NFL, NBA, and MLB with markets.")
            }
            .alert("Sample Data Loaded", isPresented: $showingSeedDataSuccess) {
                Button("OK") { }
            } message: {
                Text("Successfully loaded \(seededEventCount) sample events with markets.")
            }
            .alert("Log Out", isPresented: $showingLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    performLogout()
                }
            } message: {
                Text("Are you sure you want to log out?")
            }
            .alert("Logout Error", isPresented: $showingLogoutError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(logoutErrorMessage)
            }
            .alert(apiTestSuccess ? "Connection Successful" : "Connection Failed", isPresented: $showingAPITestResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(apiTestMessage)
            }
            .alert("Settings Error", isPresented: $showingSettingsError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(settingsErrorMessage)
            }
            .onAppear {
                loadAutoPilotSettings()
            }
        }
    }

    // MARK: - US-010: Auto-Pilot Settings

    private func loadAutoPilotSettings() {
        // Load from local Bookie model
        if let bookie = currentBookie {
            manualBetAcceptance = bookie.manualBetAcceptance
            manualBetGrading = bookie.manualBetGrading
        }
    }

    private func saveAutoPilotSettings(manualBetAcceptance: Bool?, manualBetGrading: Bool?) async {
        guard let bookie = currentBookie else { return }

        isSavingSettings = true
        defer { isSavingSettings = false }

        // Update local model
        if let acceptance = manualBetAcceptance {
            bookie.manualBetAcceptance = acceptance
        }
        if let grading = manualBetGrading {
            bookie.manualBetGrading = grading
        }
        bookie.updatedAt = Date()

        // Sync to Supabase
        do {
            try await BookieService.updateSettings(
                bookieId: bookie.id,
                manualBetAcceptance: manualBetAcceptance,
                manualBetGrading: manualBetGrading
            )
        } catch {
            settingsErrorMessage = error.localizedDescription
            showingSettingsError = true
        }
    }

    // MARK: - US-011: Test API Connection

    private func testAPIConnection() async {
        isTestingAPI = true

        // Update the service with the current key
        oddsService.setAPIKey(oddsAPIKey)
        oddsService.setBookmaker(oddsAPIBookmaker)

        do {
            let sports = try await oddsService.fetchSports()
            apiTestSuccess = true
            apiTestMessage = "Successfully connected! Found \(sports.count) sports available."
            showingAPITestResult = true
        } catch let error as OddsAPIError {
            apiTestSuccess = false
            apiTestMessage = error.localizedDescription
            showingAPITestResult = true
        } catch {
            apiTestSuccess = false
            apiTestMessage = error.localizedDescription
            showingAPITestResult = true
        }

        isTestingAPI = false
    }

    private func performLogout() {
        Task {
            do {
                SyncService.clearLocalData(context: modelContext)
                try await authManager.signOut()
            } catch {
                logoutErrorMessage = error.localizedDescription
                showingLogoutError = true
            }
        }
    }

    private func loadSampleData() {
        do {
            try SeedDataService.clearAllEvents(in: modelContext)
            let events = SeedDataService.seedMockData(in: modelContext)
            seededEventCount = events.count
            showingSeedDataSuccess = true
        } catch {
            print("Failed to seed data: \(error)")
        }
    }

    private func subscriptionStatusColor(_ status: SubscriptionStatus) -> Color {
        switch status {
        case .active: return Theme.accent
        case .inactive: return Theme.danger
        case .trial: return Theme.warning
        }
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existingBookie: Bookie?

    @State private var name: String = ""
    @State private var email: String = ""

    private var isValidInput: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Profile Details")
                } footer: {
                    Text("Both name and email are required.")
                }
                .listRowBackground(Theme.cardBackground)

                Section {
                    LabeledContent("Name") {
                        Text(name.isEmpty ? "—" : name)
                            .foregroundStyle(name.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                    }

                    LabeledContent("Email") {
                        Text(email.isEmpty ? "—" : email)
                            .foregroundStyle(email.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                    }
                } header: {
                    Text("Preview")
                }
                .listRowBackground(Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(existingBookie == nil ? "Create Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(!isValidInput)
                }
            }
            .onAppear {
                if let bookie = existingBookie {
                    name = bookie.name
                    email = bookie.email
                }
            }
        }
    }

    private func saveProfile() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        if let bookie = existingBookie {
            // Update existing bookie
            bookie.name = trimmedName
            bookie.email = trimmedEmail
            bookie.updatedAt = Date()
        } else {
            // Create new bookie
            let newBookie = Bookie(
                email: trimmedEmail,
                name: trimmedName
            )
            modelContext.insert(newBookie)
        }

        dismiss()
    }
}

// MARK: - Export Data View

struct ExportDataView: View {
    @Query(sort: \Bet.createdAt, order: .reverse) private var bets: [Bet]
    @Query(sort: \LedgerEntry.createdAt, order: .reverse) private var ledgerEntries: [LedgerEntry]
    @Query private var events: [Event]

    @State private var showingBetExportShare = false
    @State private var betExportURL: URL?
    @State private var showingLedgerExportShare = false
    @State private var ledgerExportURL: URL?

    private func eventName(for eventId: String) -> String {
        if let event = events.first(where: { $0.id.uuidString.lowercased() == eventId.lowercased() }) {
            return "\(event.awayTeam) @ \(event.homeTeam)"
        }
        return eventId
    }

    private func betDescription(for bet: Bet?) -> String {
        guard let bet = bet else { return "" }
        let event = eventName(for: bet.eventId)
        return "\(event) - \(bet.side) \(formatOdds(bet.odds))"
    }

    private func formatOdds(_ odds: Int) -> String {
        odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    private func calculatePayout(for bet: Bet) -> Decimal? {
        guard bet.status == .settled, let result = bet.gradeResult else {
            return nil
        }

        switch result {
        case .win:
            return LiabilityService.calculatePayout(stake: bet.stake, odds: bet.odds)
        case .loss:
            return -bet.stake
        case .push:
            return Decimal.zero
        }
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func generateBetsCSV() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2

        var csv = "Date,Member,Event,Market,Side,Odds,Stake,Status,Result,Return\n"

        for bet in bets {
            let date = dateFormatter.string(from: bet.createdAt)
            let playerName = escapeCSV(bet.player?.name ?? "Unknown")
            let event = escapeCSV(eventName(for: bet.eventId))
            let market = escapeCSV(bet.market)
            let side = escapeCSV(bet.side)
            let odds = formatOdds(bet.odds)
            let stake = numberFormatter.string(from: bet.stake as NSDecimalNumber) ?? "0.00"
            let status = bet.status.rawValue.capitalized
            let result = bet.gradeResult?.rawValue.capitalized ?? ""
            let payout: String
            if let payoutValue = calculatePayout(for: bet) {
                payout = numberFormatter.string(from: payoutValue as NSDecimalNumber) ?? ""
            } else {
                payout = ""
            }

            csv += "\(date),\(playerName),\(event),\(market),\(side),\(odds),\(stake),\(status),\(result),\(payout)\n"
        }

        return csv
    }

    private func exportBetsToFile() -> URL? {
        let csv = generateBetsCSV()
        let fileName = "booki_bets_export.csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to write CSV file: \(error)")
            return nil
        }
    }

    private func generateLedgerCSV() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2

        var csv = "Date,Member,Type,Amount,Description,Related Pick\n"

        for entry in ledgerEntries {
            let date = dateFormatter.string(from: entry.createdAt)
            let playerName = escapeCSV(entry.player?.name ?? "Unknown")
            let type = entry.type.rawValue.capitalized
            let amount = numberFormatter.string(from: entry.amount as NSDecimalNumber) ?? "0.00"
            let description = escapeCSV(entry.entryDescription)
            let relatedBet = escapeCSV(betDescription(for: entry.bet))

            csv += "\(date),\(playerName),\(type),\(amount),\(description),\(relatedBet)\n"
        }

        return csv
    }

    private func exportLedgerToFile() -> URL? {
        let csv = generateLedgerCSV()
        let fileName = "booki_ledger_export.csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to write CSV file: \(error)")
            return nil
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    if let url = exportBetsToFile() {
                        betExportURL = url
                        showingBetExportShare = true
                    }
                } label: {
                    Label("Export Picks (\(bets.count))", systemImage: "list.bullet.rectangle")
                }
                .disabled(bets.isEmpty)

                Button {
                    if let url = exportLedgerToFile() {
                        ledgerExportURL = url
                        showingLedgerExportShare = true
                    }
                } label: {
                    Label("Export Ledger (\(ledgerEntries.count))", systemImage: "doc.text")
                }
                .disabled(ledgerEntries.isEmpty)
            } header: {
                Text("Export Options")
            } footer: {
                Text("Export your data to CSV format for external record-keeping and analysis.")
            }
            .listRowBackground(Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingBetExportShare) {
            if let url = betExportURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showingLedgerExportShare) {
            if let url = ledgerExportURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
        .modelContainer(for: [Bookie.self], inMemory: true)
}
