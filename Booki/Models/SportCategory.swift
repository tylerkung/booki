import Foundation

/// Metadata for a league within a sport category
struct LeagueInfo: Identifiable {
    let id: String
    let displayName: String
    let matchesEvent: (Event) -> Bool
}

/// Centralized sport category enum grouping leagues under sports
/// Provides display names, icons, and league lists for sport hub pages
enum SportCategory: String, CaseIterable, Identifiable {
    case basketball
    case football
    case baseball
    case hockey
    case soccer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .basketball: return "Basketball"
        case .football: return "Football"
        case .baseball: return "Baseball"
        case .hockey: return "Hockey"
        case .soccer: return "Soccer"
        }
    }

    var iconName: String {
        switch self {
        case .basketball: return "basketball.fill"
        case .football: return "football.fill"
        case .baseball: return "baseball.diamond.bases"
        case .hockey: return "hockey.puck.fill"
        case .soccer: return "soccerball"
        }
    }

    var leagues: [LeagueInfo] {
        switch self {
        case .basketball:
            return [
                LeagueInfo(id: "nba", displayName: "NBA") { $0.sport == "Basketball" && $0.league == "NBA" },
                LeagueInfo(id: "ncaab", displayName: "NCAAB") { $0.sport == "Basketball" && $0.league == "NCAAB" },
                LeagueInfo(id: "wnba", displayName: "WNBA") { $0.sport == "Basketball" && $0.league == "WNBA" },
            ]
        case .football:
            return [
                LeagueInfo(id: "nfl", displayName: "NFL") { $0.sport == "Football" && $0.league == "NFL" },
                LeagueInfo(id: "ncaaf", displayName: "NCAAF") { $0.sport == "Football" && $0.league == "NCAAF" },
            ]
        case .baseball:
            return [
                LeagueInfo(id: "mlb", displayName: "MLB") { $0.sport == "Baseball" && $0.league == "MLB" },
            ]
        case .hockey:
            return [
                LeagueInfo(id: "nhl", displayName: "NHL") { $0.sport == "Hockey" && $0.league == "NHL" },
            ]
        case .soccer:
            return [
                LeagueInfo(id: "epl", displayName: "EPL") { $0.sport == "Soccer" && $0.league == "EPL" },
                LeagueInfo(id: "mls", displayName: "MLS") { $0.sport == "Soccer" && $0.league == "MLS" },
            ]
        }
    }

    /// Match an Event to its SportCategory
    static func fromEvent(_ event: Event) -> SportCategory? {
        allCases.first { category in
            category.displayName == event.sport
        }
    }

    /// Popular sports for Search tab quick access
    static var popular: [SportCategory] {
        [.basketball, .football, .baseball, .hockey]
    }
}
