import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bookies: [Bookie]

    @State private var showingEditProfile = false

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
                            .foregroundStyle(.secondary)
                            .italic()

                        Button {
                            showingEditProfile = true
                        } label: {
                            Label("Create Profile", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Bookie Profile")
                }

                // MARK: - Data Management Section
                Section {
                    NavigationLink {
                        ExportDataView()
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Data Management")
                } footer: {
                    Text("Export your bets and ledger data to CSV format for record-keeping.")
                }

                // MARK: - About Section
                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Platform", value: "iOS")
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingEditProfile) {
                EditProfileSheet(existingBookie: currentBookie)
            }
        }
    }

    private func subscriptionStatusColor(_ status: SubscriptionStatus) -> Color {
        switch status {
        case .active: return .green
        case .inactive: return .red
        case .trial: return .orange
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

                Section {
                    LabeledContent("Name") {
                        Text(name.isEmpty ? "—" : name)
                            .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    }

                    LabeledContent("Email") {
                        Text(email.isEmpty ? "—" : email)
                            .foregroundStyle(email.isEmpty ? .secondary : .primary)
                    }
                } header: {
                    Text("Preview")
                }
            }
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
    var body: some View {
        List {
            Section {
                NavigationLink {
                    Text("Bet export will be implemented in US-029")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Export Bets", systemImage: "list.bullet.rectangle")
                }

                NavigationLink {
                    Text("Ledger export will be implemented in US-030")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Export Ledger", systemImage: "doc.text")
                }
            } header: {
                Text("Export Options")
            } footer: {
                Text("Export your data to CSV format for external record-keeping and analysis.")
            }
        }
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Bookie.self], inMemory: true)
}
