import SwiftUI
import SwiftData
import UIKit
@preconcurrency import Supabase

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var bookies: [Bookie]

    @State private var showingLogoutConfirmation = false
    @State private var showingLogoutError = false
    @State private var logoutErrorMessage = ""
    @State private var showingProUpgrade = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteFinalConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?

    private var isPro: Bool {
        bookies.first?.isPro ?? false
    }

    private var currentBookie: Bookie? {
        bookies.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    settingsMenuRow(icon: "person.circle", title: "Profile", subtitle: currentBookie?.name) {
                        ProfileSettingsView()
                    }
                    menuDivider
                    settingsMenuRow(icon: "lock.rotation", title: "Change Password") {
                        ChangePasswordView()
                    }
                    menuDivider
                    subscriptionRow
                    menuDivider
                    settingsMenuRow(icon: "person.2", title: "Member Settings") {
                        MemberSettingsView()
                    }
                    menuDivider
                    if isPro {
                        settingsMenuRow(icon: "hand.raised", title: "Pick Management") {
                            PickManagementSettingsView()
                        }
                    } else {
                        pickManagementProRow
                    }
                    menuDivider
                    settingsMenuRow(icon: "info.circle", title: "About") {
                        AboutSettingsView()
                    }
                    menuDivider
                    Button {
                        showingLogoutConfirmation = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.danger)
                                .frame(width: 28, alignment: .center)

                            Text("Log Out")
                                .font(Theme.body)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.danger)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .cardStyle()
                .padding(.horizontal, 16)
                .padding(.top, 20)

                // Delete Account — separate card at bottom
                VStack(spacing: 0) {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "trash")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.danger)
                                .frame(width: 28, alignment: .center)

                            Text("Delete Account")
                                .font(Theme.body)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.danger)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .cardStyle()
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(isPresented: $showingProUpgrade) {
                ProUpgradeSheet()
            }
            .alert("Delete Account", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Continue", role: .destructive) {
                    showingDeleteFinalConfirmation = true
                }
            } message: {
                Text("This will permanently delete your account, all your data, members, picks, and history. This action cannot be undone.")
            }
            .alert("Are you sure?", isPresented: $showingDeleteFinalConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete My Account", role: .destructive) {
                    performAccountDeletion()
                }
            } message: {
                Text("This is your final confirmation. Your account and all associated data will be permanently deleted.")
            }
            .alert("Deletion Error", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deleteError ?? "")
            }
            .overlay {
                if isDeletingAccount {
                    ZStack {
                        Color.black.opacity(0.5).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(Theme.accent)
                                .scaleEffect(1.5)
                            Text("Deleting account...")
                                .font(Theme.bodyFont(size: 15, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .padding(32)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }

    // MARK: - Subscription Row

    @ViewBuilder
    private var subscriptionRow: some View {
        if isPro {
            NavigationLink {
                SubscriptionManagementView()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "crown")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, alignment: .center)

                    Text("Subscription")
                        .font(Theme.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    Text("Pro")
                        .font(Theme.body)
                        .foregroundStyle(Theme.accent)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        } else {
            Button {
                showingProUpgrade = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "crown")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, alignment: .center)

                    Text("Subscription")
                        .font(Theme.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    Text("Free")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Pick Management Pro Row (Free Tier)

    @ViewBuilder
    private var pickManagementProRow: some View {
        Button {
            showingProUpgrade = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Pick Management")
                            .font(Theme.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.textPrimary)

                        Text("PRO")
                            .font(Theme.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }

                    Text("Manual approval, grading rules, and more")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func settingsMenuRow<Destination: View>(icon: String, title: String, subtitle: String? = nil, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var menuDivider: some View {
        Divider()
            .background(Theme.border)
            .padding(.leading, 58)
    }

    private func performLogout() {
        Task {
            do {
                try await authManager.signOut()
            } catch {
                logoutErrorMessage = error.localizedDescription
                showingLogoutError = true
            }
        }
    }

    private func performAccountDeletion() {
        isDeletingAccount = true
        Task {
            do {
                let response: DeleteAccountResponse = try await EdgeFunctionService.shared.callFunction(
                    name: "delete_account",
                    body: EmptyRequest()
                )
                if response.success {
                    await MainActor.run {
                        isDeletingAccount = false
                    }
                    try await authManager.signOut()
                } else {
                    await MainActor.run {
                        isDeletingAccount = false
                        deleteError = response.error ?? "Failed to delete account"
                    }
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    deleteError = error.localizedDescription
                }
            }
        }
    }
}

private struct EmptyRequest: Encodable {}
private struct DeleteAccountResponse: Decodable {
    let success: Bool
    let error: String?
}

// MARK: - Profile Settings

struct ProfileSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var bookies: [Bookie]

    @State private var showingEditProfile = false

    private var currentBookie: Bookie? {
        bookies.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Organizer Profile")

                VStack(spacing: 0) {
                    if let bookie = currentBookie {
                        settingsDetailRow(label: "Name", value: bookie.name)
                        settingsDivider
                        settingsDetailRow(label: "Email", value: bookie.email)
                        settingsDivider
                        settingsDetailRow(label: "Status") {
                            Text(bookie.isPro ? "Pro" : "Free")
                                .foregroundStyle(bookie.isPro ? Theme.accent : Theme.textSecondary)
                        }
                        settingsDivider
                        Button {
                            showingEditProfile = true
                        } label: {
                            Label("Edit Profile", systemImage: "pencil")
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text("No profile configured")
                            .foregroundStyle(Theme.textSecondary)
                            .italic()
                            .padding(16)

                        Button {
                            showingEditProfile = true
                        } label: {
                            Label("Create Profile", systemImage: "plus.circle")
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                    }
                }
                .cardStyle()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditProfile) {
            EditProfileSheet(existingBookie: currentBookie)
        }
    }

    private func subscriptionStatusColor(_ status: SubscriptionStatus) -> Color {
        switch status {
        case .free: return Theme.textSecondary
        case .pro: return Theme.accent
        case .ultra: return Theme.gold
        // Legacy
        case .active: return Theme.accent
        case .inactive: return Theme.danger
        case .trial: return Theme.textSecondary
        }
    }
}

// MARK: - Balance Alerts Settings

struct BalanceAlertsSettingsView: View {
    @AppStorage("balanceThreshold") private var balanceThreshold: Double = 500.0
    @AppStorage("agingThreshold") private var agingThreshold: Int = 7

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Thresholds")

                VStack(spacing: 0) {
                    HStack {
                        Text("Balance Threshold")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        TextField("Amount", value: $balanceThreshold, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 100)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    settingsDivider

                    Stepper("Aging Threshold: \(agingThreshold) days", value: $agingThreshold, in: 1...90)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .cardStyle()

                Text("Get alerted when members have balances above the threshold or aging balances older than the specified days.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Balance Alerts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Pick Management Settings

struct PickManagementSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bookies: [Bookie]

    @State private var manualBetAcceptance = false
    @State private var manualBetGrading = false
    @State private var allowFuturesParlays = true
    @State private var isSavingSettings = false
    @State private var showingSettingsError = false
    @State private var settingsErrorMessage = ""

    private var currentBookie: Bookie? {
        bookies.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Auto-Pilot")

                VStack(spacing: 0) {
                    Toggle(isOn: $manualBetAcceptance) {
                        Label("Require Manual Pick Approval", systemImage: "hand.raised")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: manualBetAcceptance) { _, newValue in
                        Task {
                            await saveAutoPilotSettings(manualBetAcceptance: newValue, manualBetGrading: nil)
                        }
                    }

                    settingsDivider

                    Toggle(isOn: $manualBetGrading) {
                        Label("Grade Picks Manually", systemImage: "checkmark.circle")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: manualBetGrading) { _, newValue in
                        Task {
                            await saveAutoPilotSettings(manualBetAcceptance: nil, manualBetGrading: newValue)
                        }
                    }

                    settingsDivider

                    Toggle(isOn: $allowFuturesParlays) {
                        Label("Allow Futures in Multi-Picks", systemImage: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: allowFuturesParlays) { _, newValue in
                        Task {
                            await saveFuturesParlaysSetting(newValue)
                        }
                    }

                    settingsDivider

                    NavigationLink {
                        AcceptancePolicySettingsView()
                    } label: {
                        HStack {
                            Label("Acceptance Rules", systemImage: "checkmark.shield")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .cardStyle()

                Text(manualBetAcceptance || manualBetGrading
                     ? "Manual mode enabled. You'll need to review picks and/or grade them yourself."
                     : "Auto-pilot mode: Picks are auto-accepted and auto-graded when games complete.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Pick Management")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Settings Error", isPresented: $showingSettingsError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(settingsErrorMessage)
        }
        .onAppear {
            loadAutoPilotSettings()
        }
        .onChange(of: bookies.count) { _, _ in
            loadAutoPilotSettings()
        }
    }

    private func loadAutoPilotSettings() {
        if let bookie = currentBookie {
            manualBetAcceptance = bookie.manualBetAcceptance
            manualBetGrading = bookie.manualBetGrading
            allowFuturesParlays = bookie.allowFuturesParlays
        }
    }

    private func saveAutoPilotSettings(manualBetAcceptance: Bool?, manualBetGrading: Bool?) async {
        guard let bookie = currentBookie else { return }

        isSavingSettings = true
        defer { isSavingSettings = false }

        if let acceptance = manualBetAcceptance {
            bookie.manualBetAcceptance = acceptance
        }
        if let grading = manualBetGrading {
            bookie.manualBetGrading = grading
        }
        bookie.updatedAt = Date()

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

    private func saveFuturesParlaysSetting(_ allow: Bool) async {
        guard let bookie = currentBookie else { return }

        isSavingSettings = true
        defer { isSavingSettings = false }

        bookie.allowFuturesParlays = allow
        bookie.updatedAt = Date()

        do {
            try await BookieService.updateSettings(
                bookieId: bookie.id,
                allowFuturesParlays: allow
            )
        } catch {
            settingsErrorMessage = error.localizedDescription
            showingSettingsError = true
        }
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Query private var bookies: [Bookie]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("App Info")

                VStack(spacing: 0) {
                    settingsDetailRow(label: "Version", value: appVersion)
                    settingsDivider
                    settingsDetailRow(label: "Platform", value: "iOS")
                }
                .cardStyle()

                sectionHeader("Links")

                VStack(spacing: 0) {
                    aboutLinkRow(icon: "globe", title: "Website", url: "https://bookisports.com")
                    settingsDivider
                    aboutLinkRow(icon: "doc.text", title: "Terms of Service", url: "https://bookisports.com/terms.html")
                    settingsDivider
                    aboutLinkRow(icon: "hand.raised", title: "Privacy Policy", url: "https://bookisports.com/privacy.html")
                    settingsDivider
                    aboutLinkRow(icon: "at", title: "Twitter", url: "https://x.com/bookisports")
                }
                .cardStyle()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutLinkRow(icon: String, title: String, url: String) -> some View {
        Button {
            if let linkURL = URL(string: url) {
                openURL(linkURL)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, alignment: .center)

                Text(title)
                    .font(Theme.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager

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
            bookie.name = trimmedName
            bookie.email = trimmedEmail
            bookie.updatedAt = Date()

            let bookieId = bookie.id
            Task.detached {
                do {
                    try await BookieService.updateProfile(
                        bookieId: bookieId,
                        name: trimmedName,
                        email: trimmedEmail
                    )
                } catch {
                    print("Failed to sync profile to Supabase: \(error)")
                }
            }
        } else if let bookieId = authManager.currentBookieId {
            let newBookie = Bookie(
                id: bookieId,
                email: trimmedEmail,
                name: trimmedName
            )
            modelContext.insert(newBookie)

            Task.detached {
                do {
                    try await BookieService.updateProfile(
                        bookieId: bookieId,
                        name: trimmedName,
                        email: trimmedEmail
                    )
                } catch {
                    print("Failed to sync profile to Supabase: \(error)")
                }
            }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Export Options")

                VStack(spacing: 0) {
                    Button {
                        if let url = exportBetsToFile() {
                            betExportURL = url
                            showingBetExportShare = true
                        }
                    } label: {
                        HStack {
                            Label("Export Picks (\(bets.count))", systemImage: "list.bullet.rectangle")
                                .foregroundStyle(bets.isEmpty ? Theme.textMuted : Theme.accent)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .disabled(bets.isEmpty)

                    settingsDivider

                    Button {
                        if let url = exportLedgerToFile() {
                            ledgerExportURL = url
                            showingLedgerExportShare = true
                        }
                    } label: {
                        HStack {
                            Label("Export Ledger (\(ledgerEntries.count))", systemImage: "doc.text")
                                .foregroundStyle(ledgerEntries.isEmpty ? Theme.textMuted : Theme.accent)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .disabled(ledgerEntries.isEmpty)
                }
                .cardStyle()

                Text("Export your data to CSV format for external record-keeping and analysis.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
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

// MARK: - Change Password

struct ChangePasswordView: View {
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isSaving = false
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""

    private var passwordError: String? {
        guard !newPassword.isEmpty else { return nil }
        return newPassword.count >= 8 ? nil : "Password must be at least 8 characters"
    }

    private var confirmError: String? {
        guard !confirmPassword.isEmpty else { return nil }
        return newPassword == confirmPassword ? nil : "Passwords do not match"
    }

    private var isValid: Bool {
        !currentPassword.isEmpty &&
        !newPassword.isEmpty &&
        !confirmPassword.isEmpty &&
        newPassword.count >= 8 &&
        newPassword == confirmPassword
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Current Password")

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Password")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)

                        SecureField("Enter current password", text: $currentPassword)
                            .textContentType(.password)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .cardStyle()

                sectionHeader("New Password")

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("New Password")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)

                        SecureField("Min 8 characters", text: $newPassword)
                            .textContentType(.newPassword)
                            .foregroundStyle(Theme.textPrimary)

                        if let error = passwordError {
                            Text(error)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.danger)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    settingsDivider

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Confirm Password")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)

                        SecureField("Re-enter password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .foregroundStyle(Theme.textPrimary)

                        if let error = confirmError {
                            Text(error)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.danger)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .cardStyle()

                Button {
                    Task { await changePassword() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                        } else {
                            Text("Update Password")
                                .font(Theme.headline)
                                .fontWeight(.bold)
                                .textCase(.uppercase)
                                .tracking(1)
                        }
                    }
                    .foregroundStyle(isValid && !isSaving ? Theme.background : Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        Group {
                            if isValid && !isSaving {
                                Theme.buttonGradient
                            } else {
                                LinearGradient(colors: [Theme.elevatedBackground], startPoint: .leading, endPoint: .trailing)
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                }
                .disabled(!isValid || isSaving)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Password Updated", isPresented: $showingSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your password has been changed successfully.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func changePassword() async {
        isSaving = true
        defer { isSaving = false }

        do {
            // Re-authenticate with current password first
            let session = SupabaseClientManager.shared.client.auth.currentSession
            guard let email = session?.user.email else {
                errorMessage = "Unable to verify your account. Please log out and log back in."
                showingError = true
                return
            }
            _ = try await SupabaseClientManager.shared.client.auth.signIn(email: email, password: currentPassword)

            // Now update to the new password
            try await SupabaseClientManager.shared.client.auth.update(user: .init(password: newPassword))
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
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

// MARK: - Member Settings

struct MemberSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bookies: [Bookie]

    @State private var creditLimitText: String = ""
    @State private var isSaving = false
    @State private var saveMessage: String?

    private var currentBookie: Bookie? {
        bookies.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Default Credit Limit")

                VStack(spacing: 0) {
                    HStack {
                        Text("Credit Limit")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("$")
                                .foregroundStyle(Theme.textSecondary)
                            TextField("1000", text: $creditLimitText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 100)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    settingsDivider

                    Button {
                        saveCreditLimit()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(Theme.accent)
                            } else {
                                Label("Save", systemImage: "checkmark.circle")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(isSaving)
                }
                .cardStyle()

                Text("This credit limit will be applied to all new members who join via invite. Existing members are not affected.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 4)

                if let message = saveMessage {
                    Text(message)
                        .font(Theme.caption)
                        .foregroundStyle(message.contains("Failed") ? Theme.danger : Theme.accent)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Member Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let bookie = currentBookie {
                let value = bookie.defaultCreditLimit
                let rounded = NSDecimalNumber(decimal: value).doubleValue
                if rounded == rounded.rounded() {
                    creditLimitText = "\(Int(rounded))"
                } else {
                    creditLimitText = "\(value)"
                }
            }
        }
    }

    private func saveCreditLimit() {
        let cleaned = creditLimitText.replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(string: cleaned), value >= 0 else {
            saveMessage = "Please enter a valid amount"
            return
        }

        guard let bookie = currentBookie else { return }
        isSaving = true
        saveMessage = nil

        Task {
            do {
                let supabase = SupabaseClientManager.shared.client
                try await supabase
                    .from("bookies")
                    .update([
                        "default_credit_limit": "\(value)",
                        "updated_at": ISO8601DateFormatter().string(from: Date())
                    ])
                    .eq("id", value: bookie.id.uuidString.lowercased())
                    .execute()

                await MainActor.run {
                    bookie.defaultCreditLimit = value
                    isSaving = false
                    saveMessage = "Saved successfully"
                }

                // Clear success message after a delay
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run { saveMessage = nil }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveMessage = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Shared Settings Helpers

@MainActor
private func sectionHeader(_ title: String) -> some View {
    Text(title.uppercased())
        .font(Theme.caption)
        .fontWeight(.semibold)
        .tracking(1)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .padding(.bottom, -8)
}

@MainActor
private func settingsDetailRow(label: String, value: String) -> some View {
    HStack {
        Text(label)
            .foregroundStyle(Theme.textPrimary)
        Spacer()
        Text(value)
            .foregroundStyle(Theme.textSecondary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
}

@MainActor
private func settingsDetailRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
    HStack {
        Text(label)
            .foregroundStyle(Theme.textPrimary)
        Spacer()
        content()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
}

@MainActor
private var settingsDivider: some View {
    Divider()
        .background(Theme.border)
        .padding(.leading, 16)
}

#Preview {
    SettingsView()
        .modelContainer(for: [Bookie.self], inMemory: true)
}
