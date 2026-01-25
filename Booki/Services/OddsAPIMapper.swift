import Foundation
import SwiftData

// MARK: - US-006: Odds API Mapper

/// Maps The Odds API responses to app models
struct OddsAPIMapper {

    // MARK: - Sport Key Mapping

    /// Maps API sport keys to app-friendly sport and league names
    private static let sportKeyMapping: [String: (sport: String, league: String)] = [
        "americanfootball_nfl": ("Football", "NFL"),
        "americanfootball_ncaaf": ("Football", "NCAAF"),
        "basketball_nba": ("Basketball", "NBA"),
        "basketball_ncaab": ("Basketball", "NCAAB"),
        "basketball_wnba": ("Basketball", "WNBA"),
        "baseball_mlb": ("Baseball", "MLB"),
        "icehockey_nhl": ("Hockey", "NHL"),
        "soccer_epl": ("Soccer", "EPL"),
        "soccer_usa_mls": ("Soccer", "MLS"),
        "soccer_germany_bundesliga": ("Soccer", "Bundesliga"),
        "soccer_spain_la_liga": ("Soccer", "La Liga"),
        "soccer_italy_serie_a": ("Soccer", "Serie A"),
        "soccer_france_ligue_one": ("Soccer", "Ligue 1"),
        "mma_mixed_martial_arts": ("MMA", "UFC"),
        "boxing_boxing": ("Boxing", "Boxing"),
        "golf_pga_championship": ("Golf", "PGA"),
        "tennis_atp_australian_open": ("Tennis", "ATP"),
    ]

    // MARK: - Event Mapping

    /// Converts an OddsEvent from the API to an Event model
    /// - Parameters:
    ///   - oddsEvent: The API event to convert
    ///   - bookieId: The bookie ID to assign to the event
    /// - Returns: A new Event model
    static func mapToEvent(from oddsEvent: OddsEvent, bookieId: UUID?) -> Event {
        let (sport, league) = sportKeyMapping[oddsEvent.sportKey] ?? parseSportKey(oddsEvent.sportKey)

        return Event(
            sport: sport,
            league: league,
            homeTeam: oddsEvent.homeTeam,
            awayTeam: oddsEvent.awayTeam,
            startTime: oddsEvent.commenceTime,
            status: .scheduled,
            bookieId: bookieId,
            externalId: oddsEvent.id,
            externalSource: "the-odds-api",
            lastOddsUpdate: Date()
        )
    }

    /// Parses a sport key into sport and league when not in the mapping
    private static func parseSportKey(_ key: String) -> (sport: String, league: String) {
        // Format is usually "sport_league" like "basketball_nba"
        let parts = key.split(separator: "_")
        if parts.count >= 2 {
            let sport = String(parts[0]).capitalized
            let league = String(parts[1...].joined(separator: " ")).uppercased()
            return (sport, league)
        }
        return (key.capitalized, "")
    }

    // MARK: - Market Mapping

    /// Converts OddsEvent markets to Market models
    /// - Parameters:
    ///   - oddsEvent: The API event containing bookmaker data
    ///   - bookmaker: The bookmaker key to extract odds from (e.g., "draftkings")
    ///   - event: The Event model to associate markets with
    /// - Returns: Array of Market models
    static func mapToMarkets(from oddsEvent: OddsEvent, bookmaker: String, event: Event) -> [Market] {
        guard let bookmakers = oddsEvent.bookmakers,
              let selectedBookmaker = bookmakers.first(where: { $0.key == bookmaker }) ?? bookmakers.first else {
            return []
        }

        var markets: [Market] = []

        for oddsMarket in selectedBookmaker.markets {
            switch oddsMarket.key {
            case "h2h":
                // Moneyline market
                if let market = mapMoneylineMarket(oddsMarket, event: event, oddsEvent: oddsEvent) {
                    markets.append(market)
                }

            case "spreads":
                // Spread market
                if let market = mapSpreadMarket(oddsMarket, event: event, oddsEvent: oddsEvent) {
                    markets.append(market)
                }

            case "totals":
                // Total (over/under) market
                if let market = mapTotalMarket(oddsMarket, event: event) {
                    markets.append(market)
                }

            default:
                break
            }
        }

        return markets
    }

    // MARK: - Individual Market Mapping

    private static func mapMoneylineMarket(_ oddsMarket: OddsMarket, event: Event, oddsEvent: OddsEvent) -> Market? {
        guard oddsMarket.outcomes.count >= 2 else { return nil }

        // Find home and away team outcomes
        let homeOutcome = oddsMarket.outcomes.first { $0.name == oddsEvent.homeTeam }
        let awayOutcome = oddsMarket.outcomes.first { $0.name == oddsEvent.awayTeam }

        guard let home = homeOutcome, let away = awayOutcome else { return nil }

        return Market(
            type: .moneyline,
            sideA: oddsEvent.awayTeam,
            sideB: oddsEvent.homeTeam,
            oddsA: away.price,
            oddsB: home.price,
            event: event
        )
    }

    private static func mapSpreadMarket(_ oddsMarket: OddsMarket, event: Event, oddsEvent: OddsEvent) -> Market? {
        guard oddsMarket.outcomes.count >= 2 else { return nil }

        // Find home and away team outcomes
        let homeOutcome = oddsMarket.outcomes.first { $0.name == oddsEvent.homeTeam }
        let awayOutcome = oddsMarket.outcomes.first { $0.name == oddsEvent.awayTeam }

        guard let home = homeOutcome, let away = awayOutcome else { return nil }

        // Format spread with point value (e.g., "Lakers -3.5")
        let awaySpread = formatSpread(away.point ?? 0)
        let homeSpread = formatSpread(home.point ?? 0)

        return Market(
            type: .spread,
            sideA: "\(oddsEvent.awayTeam) \(awaySpread)",
            sideB: "\(oddsEvent.homeTeam) \(homeSpread)",
            oddsA: away.price,
            oddsB: home.price,
            event: event
        )
    }

    private static func mapTotalMarket(_ oddsMarket: OddsMarket, event: Event) -> Market? {
        guard oddsMarket.outcomes.count >= 2 else { return nil }

        // Find over and under outcomes
        let overOutcome = oddsMarket.outcomes.first { $0.name == "Over" }
        let underOutcome = oddsMarket.outcomes.first { $0.name == "Under" }

        guard let over = overOutcome, let under = underOutcome else { return nil }

        let totalValue = over.point ?? under.point ?? 0

        return Market(
            type: .total,
            sideA: "Over \(formatTotal(totalValue))",
            sideB: "Under \(formatTotal(totalValue))",
            oddsA: over.price,
            oddsB: under.price,
            event: event
        )
    }

    // MARK: - Formatting Helpers

    private static func formatSpread(_ value: Double) -> String {
        if value > 0 {
            return "+\(formatNumber(value))"
        } else {
            return formatNumber(value)
        }
    }

    private static func formatTotal(_ value: Double) -> String {
        return formatNumber(value)
    }

    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }
}
