import Foundation
import SwiftData

/// Service for seeding mock game data for testing purposes
enum SeedDataService {

    /// Generates mock events with markets for testing
    /// - Parameter modelContext: The SwiftData model context
    /// - Returns: Array of created events
    @discardableResult
    static func seedMockData(in modelContext: ModelContext) -> [Event] {
        var events: [Event] = []

        // NFL Games
        events.append(contentsOf: createNFLGames())

        // NBA Games
        events.append(contentsOf: createNBAGames())

        // MLB Games
        events.append(contentsOf: createMLBGames())

        // Insert all events into the context
        for event in events {
            modelContext.insert(event)
        }

        return events
    }

    /// Clears all existing events and their markets
    /// - Parameter modelContext: The SwiftData model context
    static func clearAllEvents(in modelContext: ModelContext) throws {
        try modelContext.delete(model: Event.self)
    }

    // MARK: - NFL Games

    private static func createNFLGames() -> [Event] {
        let calendar = Calendar.current
        let now = Date()

        var games: [Event] = []

        // Game 1: Chiefs vs Bills - Scheduled (upcoming)
        let game1 = Event(
            sport: "NFL",
            league: "AFC Championship",
            homeTeam: "Buffalo Bills",
            awayTeam: "Kansas City Chiefs",
            startTime: calendar.date(byAdding: .hour, value: 4, to: now)!,
            status: .scheduled
        )
        game1.markets = [
            Market(type: .spread, sideA: "Chiefs -2.5", sideB: "Bills +2.5", oddsA: -110, oddsB: -110, event: game1),
            Market(type: .total, sideA: "Over 48.5", sideB: "Under 48.5", oddsA: -110, oddsB: -110, event: game1),
            Market(type: .moneyline, sideA: "Chiefs", sideB: "Bills", oddsA: -130, oddsB: +110, event: game1)
        ]
        games.append(game1)

        // Game 2: 49ers vs Eagles - Live
        let game2 = Event(
            sport: "NFL",
            league: "NFC Championship",
            homeTeam: "Philadelphia Eagles",
            awayTeam: "San Francisco 49ers",
            startTime: calendar.date(byAdding: .hour, value: -1, to: now)!,
            status: .live
        )
        game2.markets = [
            Market(type: .spread, sideA: "49ers -3", sideB: "Eagles +3", oddsA: -105, oddsB: -115, event: game2),
            Market(type: .total, sideA: "Over 45.5", sideB: "Under 45.5", oddsA: -108, oddsB: -112, event: game2),
            Market(type: .moneyline, sideA: "49ers", sideB: "Eagles", oddsA: -150, oddsB: +130, event: game2)
        ]
        games.append(game2)

        // Game 3: Cowboys vs Packers - Scheduled (tomorrow)
        let game3 = Event(
            sport: "NFL",
            league: "Wild Card",
            homeTeam: "Green Bay Packers",
            awayTeam: "Dallas Cowboys",
            startTime: calendar.date(byAdding: .day, value: 1, to: now)!,
            status: .scheduled
        )
        game3.markets = [
            Market(type: .spread, sideA: "Cowboys -1.5", sideB: "Packers +1.5", oddsA: -110, oddsB: -110, event: game3),
            Market(type: .total, sideA: "Over 47", sideB: "Under 47", oddsA: -110, oddsB: -110, event: game3),
            Market(type: .moneyline, sideA: "Cowboys", sideB: "Packers", oddsA: -120, oddsB: +100, event: game3)
        ]
        games.append(game3)

        // Game 4: Ravens vs Dolphins - Scheduled
        let game4 = Event(
            sport: "NFL",
            league: "Wild Card",
            homeTeam: "Miami Dolphins",
            awayTeam: "Baltimore Ravens",
            startTime: calendar.date(byAdding: .hour, value: 28, to: now)!,
            status: .scheduled
        )
        game4.markets = [
            Market(type: .spread, sideA: "Ravens -6.5", sideB: "Dolphins +6.5", oddsA: -110, oddsB: -110, event: game4),
            Market(type: .total, sideA: "Over 44.5", sideB: "Under 44.5", oddsA: -110, oddsB: -110, event: game4),
            Market(type: .moneyline, sideA: "Ravens", sideB: "Dolphins", oddsA: -280, oddsB: +230, event: game4)
        ]
        games.append(game4)

        return games
    }

    // MARK: - NBA Games

    private static func createNBAGames() -> [Event] {
        let calendar = Calendar.current
        let now = Date()

        var games: [Event] = []

        // Game 1: Lakers vs Celtics - Live
        let game1 = Event(
            sport: "NBA",
            league: "Regular Season",
            homeTeam: "Boston Celtics",
            awayTeam: "Los Angeles Lakers",
            startTime: calendar.date(byAdding: .minute, value: -45, to: now)!,
            status: .live
        )
        game1.markets = [
            Market(type: .spread, sideA: "Lakers +7.5", sideB: "Celtics -7.5", oddsA: -110, oddsB: -110, event: game1),
            Market(type: .total, sideA: "Over 224.5", sideB: "Under 224.5", oddsA: -110, oddsB: -110, event: game1),
            Market(type: .moneyline, sideA: "Lakers", sideB: "Celtics", oddsA: +260, oddsB: -320, event: game1)
        ]
        games.append(game1)

        // Game 2: Nuggets vs Heat - Scheduled (tonight)
        let game2 = Event(
            sport: "NBA",
            league: "Regular Season",
            homeTeam: "Miami Heat",
            awayTeam: "Denver Nuggets",
            startTime: calendar.date(byAdding: .hour, value: 3, to: now)!,
            status: .scheduled
        )
        game2.markets = [
            Market(type: .spread, sideA: "Nuggets -4.5", sideB: "Heat +4.5", oddsA: -110, oddsB: -110, event: game2),
            Market(type: .total, sideA: "Over 218", sideB: "Under 218", oddsA: -110, oddsB: -110, event: game2),
            Market(type: .moneyline, sideA: "Nuggets", sideB: "Heat", oddsA: -180, oddsB: +155, event: game2)
        ]
        games.append(game2)

        // Game 3: Warriors vs Suns - Scheduled
        let game3 = Event(
            sport: "NBA",
            league: "Regular Season",
            homeTeam: "Phoenix Suns",
            awayTeam: "Golden State Warriors",
            startTime: calendar.date(byAdding: .hour, value: 6, to: now)!,
            status: .scheduled
        )
        game3.markets = [
            Market(type: .spread, sideA: "Warriors +2", sideB: "Suns -2", oddsA: -110, oddsB: -110, event: game3),
            Market(type: .total, sideA: "Over 230.5", sideB: "Under 230.5", oddsA: -105, oddsB: -115, event: game3),
            Market(type: .moneyline, sideA: "Warriors", sideB: "Suns", oddsA: +110, oddsB: -130, event: game3)
        ]
        games.append(game3)

        // Game 4: Bucks vs 76ers - Scheduled (tomorrow)
        let game4 = Event(
            sport: "NBA",
            league: "Regular Season",
            homeTeam: "Philadelphia 76ers",
            awayTeam: "Milwaukee Bucks",
            startTime: calendar.date(byAdding: .day, value: 1, to: now)!,
            status: .scheduled
        )
        game4.markets = [
            Market(type: .spread, sideA: "Bucks -3", sideB: "76ers +3", oddsA: -108, oddsB: -112, event: game4),
            Market(type: .total, sideA: "Over 221", sideB: "Under 221", oddsA: -110, oddsB: -110, event: game4)
        ]
        games.append(game4)

        return games
    }

    // MARK: - MLB Games

    private static func createMLBGames() -> [Event] {
        let calendar = Calendar.current
        let now = Date()

        var games: [Event] = []

        // Game 1: Yankees vs Red Sox - Scheduled
        let game1 = Event(
            sport: "MLB",
            league: "AL East",
            homeTeam: "Boston Red Sox",
            awayTeam: "New York Yankees",
            startTime: calendar.date(byAdding: .hour, value: 5, to: now)!,
            status: .scheduled
        )
        game1.markets = [
            Market(type: .spread, sideA: "Yankees -1.5", sideB: "Red Sox +1.5", oddsA: +140, oddsB: -160, event: game1),
            Market(type: .total, sideA: "Over 9.5", sideB: "Under 9.5", oddsA: -105, oddsB: -115, event: game1),
            Market(type: .moneyline, sideA: "Yankees", sideB: "Red Sox", oddsA: -135, oddsB: +115, event: game1)
        ]
        games.append(game1)

        // Game 2: Dodgers vs Giants - Live
        let game2 = Event(
            sport: "MLB",
            league: "NL West",
            homeTeam: "San Francisco Giants",
            awayTeam: "Los Angeles Dodgers",
            startTime: calendar.date(byAdding: .hour, value: -2, to: now)!,
            status: .live
        )
        game2.markets = [
            Market(type: .spread, sideA: "Dodgers -1.5", sideB: "Giants +1.5", oddsA: -120, oddsB: +100, event: game2),
            Market(type: .total, sideA: "Over 8", sideB: "Under 8", oddsA: -110, oddsB: -110, event: game2),
            Market(type: .moneyline, sideA: "Dodgers", sideB: "Giants", oddsA: -185, oddsB: +160, event: game2)
        ]
        games.append(game2)

        // Game 3: Braves vs Mets - Scheduled
        let game3 = Event(
            sport: "MLB",
            league: "NL East",
            homeTeam: "New York Mets",
            awayTeam: "Atlanta Braves",
            startTime: calendar.date(byAdding: .hour, value: 7, to: now)!,
            status: .scheduled
        )
        game3.markets = [
            Market(type: .spread, sideA: "Braves -1.5", sideB: "Mets +1.5", oddsA: +135, oddsB: -155, event: game3),
            Market(type: .total, sideA: "Over 8.5", sideB: "Under 8.5", oddsA: -110, oddsB: -110, event: game3),
            Market(type: .moneyline, sideA: "Braves", sideB: "Mets", oddsA: -145, oddsB: +125, event: game3)
        ]
        games.append(game3)

        // Game 4: Astros vs Rangers - Scheduled (tomorrow)
        let game4 = Event(
            sport: "MLB",
            league: "AL West",
            homeTeam: "Texas Rangers",
            awayTeam: "Houston Astros",
            startTime: calendar.date(byAdding: .day, value: 1, to: now)!,
            status: .scheduled
        )
        game4.markets = [
            Market(type: .spread, sideA: "Astros -1.5", sideB: "Rangers +1.5", oddsA: +145, oddsB: -165, event: game4),
            Market(type: .total, sideA: "Over 9", sideB: "Under 9", oddsA: -108, oddsB: -112, event: game4),
            Market(type: .moneyline, sideA: "Astros", sideB: "Rangers", oddsA: -125, oddsB: +105, event: game4)
        ]
        games.append(game4)

        return games
    }
}
