import SwiftUI
@preconcurrency import Supabase

struct BookieNotificationPreferencesView: View {
    @State private var newMembers = true
    @State private var pickSubmissions = false
    @State private var riskAlerts = true
    @State private var gameResults = true
    @State private var isLoading = true
    @State private var hasRow = false

    private let supabase = SupabaseClientManager.shared.client

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Alerts")

                VStack(spacing: 0) {
                    Toggle(isOn: $newMembers) {
                        Label("New members", systemImage: "person.badge.plus")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: newMembers) { _, newValue in
                        guard !isLoading else { return }
                        Task { await savePreference("new_members", value: newValue) }
                    }

                    settingsDivider

                    Toggle(isOn: $pickSubmissions) {
                        Label("Pick submissions", systemImage: "paperplane")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: pickSubmissions) { _, newValue in
                        guard !isLoading else { return }
                        Task { await savePreference("pick_submissions", value: newValue) }
                    }

                    settingsDivider

                    Toggle(isOn: $riskAlerts) {
                        Label("Risk alerts", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: riskAlerts) { _, newValue in
                        guard !isLoading else { return }
                        Task { await savePreference("risk_alerts", value: newValue) }
                    }

                    settingsDivider

                    Toggle(isOn: $gameResults) {
                        Label("Game results", systemImage: "sportscourt")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: gameResults) { _, newValue in
                        guard !isLoading else { return }
                        Task { await savePreference("game_results", value: newValue) }
                    }
                }
                .cardStyle()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPreferences()
        }
    }

    // MARK: - Data

    private func loadPreferences() async {
        guard let userId = try? await supabase.auth.session.user.id else { return }

        do {
            let response: [BookieNotificationPreferenceRow] = try await supabase
                .from("notification_preferences")
                .select()
                .eq("user_id", value: userId.uuidString.lowercased())
                .execute()
                .value

            if let row = response.first {
                newMembers = row.newMembers
                pickSubmissions = row.pickSubmissions
                riskAlerts = row.riskAlerts
                gameResults = row.gameResults
                hasRow = true
            } else {
                // Insert default row
                let newRow = BookieNotificationPreferenceInsert(userId: userId.uuidString.lowercased())
                try await supabase
                    .from("notification_preferences")
                    .insert(newRow)
                    .execute()
                hasRow = true
            }
        } catch {
            print("BookieNotificationPreferencesView: Failed to load preferences: \(error)")
        }

        isLoading = false
    }

    private func savePreference(_ column: String, value: Bool) async {
        guard let userId = try? await supabase.auth.session.user.id else { return }

        do {
            try await supabase
                .from("notification_preferences")
                .update([column: value])
                .eq("user_id", value: userId.uuidString.lowercased())
                .execute()
        } catch {
            print("BookieNotificationPreferencesView: Failed to save \(column): \(error)")
        }
    }
}

// MARK: - Codable Records

private struct BookieNotificationPreferenceRow: Codable {
    let newMembers: Bool
    let pickSubmissions: Bool
    let riskAlerts: Bool
    let gameResults: Bool

    enum CodingKeys: String, CodingKey {
        case newMembers = "new_members"
        case pickSubmissions = "pick_submissions"
        case riskAlerts = "risk_alerts"
        case gameResults = "game_results"
    }
}

private struct BookieNotificationPreferenceInsert: Codable {
    let userId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

// MARK: - Helpers

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
private var settingsDivider: some View {
    Divider()
        .background(Theme.border)
        .padding(.leading, 16)
}
