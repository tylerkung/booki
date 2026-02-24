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
    case mma
    case tennis
    case golf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .basketball: return "Basketball"
        case .football: return "Football"
        case .baseball: return "Baseball"
        case .hockey: return "Hockey"
        case .soccer: return "Soccer"
        case .mma: return "MMA"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        }
    }

    var iconName: String {
        switch self {
        case .basketball: return "basketball.fill"
        case .football: return "football.fill"
        case .baseball: return "baseball.diamond.bases"
        case .hockey: return "hockey.puck.fill"
        case .soccer: return "soccerball"
        case .mma: return "figure.martial.arts"
        case .tennis: return "tennisball.fill"
        case .golf: return "figure.golf"
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
        case .mma:
            return [
                LeagueInfo(id: "ufc", displayName: "UFC") { $0.sport == "MMA" && $0.league == "UFC" },
            ]
        case .tennis:
            return [
                LeagueInfo(id: "atp", displayName: "ATP") { $0.sport == "Tennis" && $0.league == "ATP" },
                LeagueInfo(id: "wta", displayName: "WTA") { $0.sport == "Tennis" && $0.league == "WTA" },
            ]
        case .golf:
            return [
                LeagueInfo(id: "pga", displayName: "PGA") { $0.sport == "Golf" && $0.league == "PGA" },
                LeagueInfo(id: "masters", displayName: "Masters") { $0.sport == "Golf" && $0.league == "Masters" },
                LeagueInfo(id: "the_open", displayName: "The Open") { $0.sport == "Golf" && $0.league == "The Open" },
                LeagueInfo(id: "us_open", displayName: "US Open") { $0.sport == "Golf" && $0.league == "US Open" },
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
        [.basketball, .football, .baseball, .hockey, .golf, .mma, .tennis]
    }

    /// Look up the SF Symbol icon name for a sport string, falling back to "sportscourt"
    static func iconName(for sport: String) -> String {
        allCases.first { $0.displayName == sport }?.iconName ?? "sportscourt"
    }
}
