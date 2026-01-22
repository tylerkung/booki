import SwiftUI
import SwiftData

struct EventsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Event.startTime) private var events: [Event]

    /// Group events by sport and league
    private var groupedEvents: [(key: String, events: [Event])] {
        let grouped = Dictionary(grouping: events) { "\($0.sport) - \($0.league)" }
        return grouped
            .map { (key: $0.key, events: $0.value.sorted { $0.startTime < $1.startTime }) }
            .sorted { first, second in
                // Sort groups by the earliest event start time
                guard let firstEvent = first.events.first,
                      let secondEvent = second.events.first else { return false }
                return firstEvent.startTime < secondEvent.startTime
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if events.isEmpty {
                    ContentUnavailableView(
                        "No Events",
                        systemImage: "sportscourt",
                        description: Text("Add events to start managing your book.")
                    )
                } else {
                    ForEach(groupedEvents, id: \.key) { group in
                        Section {
                            ForEach(group.events) { event in
                                NavigationLink(value: event) {
                                    EventListRowView(event: event)
                                }
                            }
                        } header: {
                            Text(group.key)
                        }
                    }
                }
            }
            .navigationTitle("Events")
            .navigationDestination(for: Event.self) { event in
                EventDetailView(event: event)
            }
        }
    }
}

// MARK: - Event List Row View

struct EventListRowView: View {
    let event: Event

    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: event.startTime)
    }

    private var statusColor: Color {
        switch event.status {
        case .scheduled:
            return .blue
        case .live:
            return .green
        case .final:
            return .gray
        }
    }

    private var statusText: String {
        switch event.status {
        case .scheduled:
            return "Scheduled"
        case .live:
            return "Live"
        case .final:
            return "Final"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // Teams
                Text("\(event.awayTeam) @ \(event.homeTeam)")
                    .font(.headline)

                // Start time
                Text(formattedStartTime)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Final score if available
                if let finalScore = event.finalScore {
                    Text("Final: \(finalScore)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Status badge
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    EventsListView()
        .modelContainer(for: [Event.self, Market.self, Bet.self], inMemory: true)
}
