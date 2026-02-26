import SwiftUI
import SwiftData
@preconcurrency import Supabase

struct PlayerProfileEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let player: Player

    @State private var nameText: String = ""
    @State private var emailText: String = ""
    @State private var isSaving = false
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var emailConfirmationMessage: String?

    private var isValidInput: Bool {
        !nameText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasChanges: Bool {
        nameText.trimmingCharacters(in: .whitespaces) != player.name ||
        emailText.trimmingCharacters(in: .whitespaces) != (player.email ?? "")
    }

    private var memberSinceDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: player.createdAt)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Profile")

                VStack(spacing: 0) {
                    editableRow(label: "Name") {
                        TextField("Name", text: $nameText)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.trailing)
                    }

                    settingsDivider

                    editableRow(label: "Email") {
                        TextField("Email", text: $emailText)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.trailing)
                    }

                    if let message = emailConfirmationMessage {
                        settingsDivider

                        HStack(alignment: .top, spacing: 0) {
                            Image(systemName: "envelope.badge")
                                .foregroundStyle(Theme.accent)
                                .frame(width: 50, alignment: .leading)
                                .padding(.top, 2)
                            Text(message)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .cardStyle()

                sectionHeader("Details")

                VStack(spacing: 0) {
                    readOnlyRow(label: "Organizer", value: player.bookie?.name ?? "—")
                    settingsDivider
                    readOnlyRow(label: "Member Since", value: memberSinceDate)
                }
                .cardStyle()

                Button {
                    Task { await saveProfile() }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(Theme.background)
                        }
                        Text("Save")
                            .font(Theme.body)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isValidInput && hasChanges && !isSaving ? Theme.accent : Theme.accent.opacity(0.3))
                    .foregroundStyle(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!isValidInput || !hasChanges || isSaving)
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nameText = player.name
            emailText = player.email ?? ""
        }
        .alert("Profile Updated", isPresented: $showingSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your profile has been saved.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Row Helpers

    private func editableRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            content()
        }
        .font(Theme.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func readOnlyRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.textMuted)
        }
        .font(Theme.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

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

    private var settingsDivider: some View {
        Divider()
            .background(Theme.border)
            .padding(.leading, 16)
    }

    // MARK: - Save Logic

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedName = nameText.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = emailText.trimmingCharacters(in: .whitespaces)
        let nameChanged = trimmedName != player.name
        let emailChanged = trimmedEmail != (player.email ?? "")

        do {
            let supabase = SupabaseClientManager.shared.client
            let playerId = player.id.uuidString.lowercased()

            // Update name in players table via RLS policy
            if nameChanged {
                try await supabase
                    .from("players")
                    .update(["name": trimmedName])
                    .eq("id", value: playerId)
                    .execute()

                await MainActor.run {
                    player.name = trimmedName
                }
            }

            // Update email via Supabase auth (triggers confirmation email)
            if emailChanged {
                try await supabase.auth.update(user: .init(email: trimmedEmail))

                await MainActor.run {
                    emailConfirmationMessage = "A confirmation email has been sent to \(trimmedEmail). Your email will update once confirmed."
                }
            }

            if nameChanged && !emailChanged {
                showingSuccess = true
            }
            // If email changed, don't dismiss — show the confirmation message inline
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
