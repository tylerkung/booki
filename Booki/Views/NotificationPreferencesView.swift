import SwiftUI
@preconcurrency import Supabase

struct NotificationPreferencesView: View {
    @State private var picksGraded = true
    @State private var balanceChanges = true
    @State private var gameResults = true
    @State private var isLoading = true
    @State private var hasRow = false

    private let supabase = SupabaseClientManager.shared.client

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Alerts")

                VStack(spacing: 0) {
                    Toggle(isOn: $picksGraded) {
                        Label("Pick results", systemImage: "checkmark.seal")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: picksGraded) { _, newValue in
                        Task { await savePreference("picks_graded", value: newValue) }
                    }

                    settingsDivider

                    Toggle(isOn: $balanceChanges) {
                        Label("Balance changes", systemImage: "dollarsign.circle")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: balanceChanges) { _, newValue in
                        Task { await savePreference("balance_changes", value: newValue) }
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
            let response: [NotificationPreferenceRow] = try await supabase
                .from("notification_preferences")
                .select()
                .eq("user_id", value: userId.uuidString.lowercased())
                .execute()
                .value

            if let row = response.first {
                picksGraded = row.picksGraded
                balanceChanges = row.balanceChanges
                gameResults = row.gameResults
                hasRow = true
            } else {
                // Insert default row
                let newRow = NotificationPreferenceInsert(userId: userId.uuidString.lowercased())
                try await supabase
                    .from("notification_preferences")
                    .insert(newRow)
                    .execute()
                hasRow = true
            }
        } catch {
            print("NotificationPreferencesView: Failed to load preferences: \(error)")
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
            print("NotificationPreferencesView: Failed to save \(column): \(error)")
        }
    }
}

// MARK: - Codable Records

private struct NotificationPreferenceRow: Codable {
    let picksGraded: Bool
    let balanceChanges: Bool
    let gameResults: Bool

    enum CodingKeys: String, CodingKey {
        case picksGraded = "picks_graded"
        case balanceChanges = "balance_changes"
        case gameResults = "game_results"
    }
}

private struct NotificationPreferenceInsert: Codable {
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
