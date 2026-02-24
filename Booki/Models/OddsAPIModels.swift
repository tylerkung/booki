import Foundation

// MARK: - US-002: API Response Models for The Odds API

/// Sport model from The Odds API
struct OddsSport: Codable, Identifiable {
    let key: String
    let group: String
    let title: String
    let description: String
    let active: Bool
    let hasOutrights: Bool

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, group, title, description, active
        case hasOutrights = "has_outrights"
    }
}

/// Event model from The Odds API
struct OddsEvent: Codable, Identifiable {
    let id: String
    let sportKey: String
    let sportTitle: String
    let commenceTime: Date
    let homeTeam: String?
    let awayTeam: String?
    let bookmakers: [OddsBookmaker]?

    enum CodingKeys: String, CodingKey {
        case id
        case sportKey = "sport_key"
        case sportTitle = "sport_title"
        case commenceTime = "commence_time"
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case bookmakers
    }
}

/// Bookmaker model from The Odds API
struct OddsBookmaker: Codable {
    let key: String
    let title: String
    let lastUpdate: Date
    let markets: [OddsMarket]

    enum CodingKeys: String, CodingKey {
        case key, title, markets
        case lastUpdate = "last_update"
    }
}

/// Market model from The Odds API
struct OddsMarket: Codable {
    let key: String
    let lastUpdate: Date
    let outcomes: [OddsOutcome]

    enum CodingKeys: String, CodingKey {
        case key, outcomes
        case lastUpdate = "last_update"
    }
}

/// Outcome model from The Odds API
struct OddsOutcome: Codable {
    let name: String
    let price: Int
    let point: Double?
}

/// Score model from The Odds API
struct OddsScore: Codable, Identifiable {
    let id: String
    let sportKey: String
    let sportTitle: String
    let commenceTime: Date
    let completed: Bool
    let homeTeam: String
    let awayTeam: String
    let scores: [TeamScore]?

    enum CodingKeys: String, CodingKey {
        case id
        case sportKey = "sport_key"
        case sportTitle = "sport_title"
        case commenceTime = "commence_time"
        case completed
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case scores
    }
}

/// Individual team score from scores endpoint
struct TeamScore: Codable {
    let name: String
    let score: String
}
