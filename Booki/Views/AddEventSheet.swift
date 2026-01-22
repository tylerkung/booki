import SwiftUI
import SwiftData

struct AddEventSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var sport: String = "NFL"
    @State private var league: String = ""
    @State private var homeTeam: String = ""
    @State private var awayTeam: String = ""
    @State private var startTime: Date = Date()

    /// Available sports for picker
    private let sports = ["NFL", "NBA", "MLB", "NHL", "Soccer", "UFC", "Tennis", "Other"]

    /// Validation: all fields required
    private var isFormValid: Bool {
        !league.trimmingCharacters(in: .whitespaces).isEmpty &&
        !homeTeam.trimmingCharacters(in: .whitespaces).isEmpty &&
        !awayTeam.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sport", selection: $sport) {
                        ForEach(sports, id: \.self) { sportOption in
                            Text(sportOption).tag(sportOption)
                        }
                    }

                    TextField("League", text: $league)
                        .textContentType(.organizationName)
                } header: {
                    Text("Sport & League")
                }

                Section {
                    TextField("Home Team", text: $homeTeam)
                    TextField("Away Team", text: $awayTeam)
                } header: {
                    Text("Teams")
                }

                Section {
                    DatePicker(
                        "Start Time",
                        selection: $startTime,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text("Schedule")
                }
            }
            .navigationTitle("Add Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEvent()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }

    private func saveEvent() {
        let event = Event(
            sport: sport,
            league: league.trimmingCharacters(in: .whitespaces),
            homeTeam: homeTeam.trimmingCharacters(in: .whitespaces),
            awayTeam: awayTeam.trimmingCharacters(in: .whitespaces),
            startTime: startTime,
            status: .scheduled
        )

        modelContext.insert(event)
        dismiss()
    }
}

#Preview {
    AddEventSheet()
        .modelContainer(for: Event.self, inMemory: true)
}
