import Foundation

/// Maps team names to standard North American sport abbreviations.
/// Lookup is by mascot name (last word of team name) since that's unique within each league.
enum TeamAbbreviations {
    // MARK: - Mascot → Abbreviation

    private static let mascotMap: [String: String] = [
        // MLB
        "Angels": "LAA", "Astros": "HOU", "Athletics": "ATH", "Blue Jays": "TOR",
        "Braves": "ATL", "Brewers": "MIL", "Cardinals": "STL", "Cubs": "CHC",
        "Diamondbacks": "ARI", "Dodgers": "LAD", "Giants": "SF", "Guardians": "CLE",
        "Mariners": "SEA", "Marlins": "MIA", "Mets": "NYM", "Nationals": "WAS",
        "Orioles": "BAL", "Padres": "SD", "Phillies": "PHI", "Pirates": "PIT",
        "Rangers": "TEX", "Rays": "TB", "Red Sox": "BOS", "Reds": "CIN",
        "Rockies": "COL", "Royals": "KC", "Tigers": "DET", "Twins": "MIN",
        "White Sox": "CHW", "Yankees": "NYY",

        // NBA
        "76ers": "PHI", "Bucks": "MIL", "Bulls": "CHI", "Cavaliers": "CLE",
        "Celtics": "BOS", "Clippers": "LAC", "Grizzlies": "MEM", "Hawks": "ATL",
        "Heat": "MIA", "Hornets": "CHA", "Jazz": "UTA", "Kings": "SAC",
        "Knicks": "NYK", "Lakers": "LAL", "Magic": "ORL", "Mavericks": "DAL",
        "Nets": "BKN", "Nuggets": "DEN", "Pacers": "IND", "Pelicans": "NOP",
        "Pistons": "DET", "Raptors": "TOR", "Rockets": "HOU", "Spurs": "SAS",
        "Suns": "PHX", "Thunder": "OKC", "Timberwolves": "MIN",
        "Trailblazers": "POR", "Trail Blazers": "POR", "Warriors": "GSW", "Wizards": "WAS",

        // NFL
        "49ers": "SF", "Bears": "CHI", "Bengals": "CIN", "Bills": "BUF",
        "Broncos": "DEN", "Browns": "CLE", "Chargers": "LAC", "Chiefs": "KC",
        "Colts": "IND", "Commanders": "WAS", "Cowboys": "DAL", "Dolphins": "MIA",
        "Eagles": "PHI", "Falcons": "ATL", "Jaguars": "JAC", "Jets": "NYJ",
        "Lions": "DET", "Packers": "GB", "Panthers": "CAR", "Patriots": "NEP",
        "Raiders": "OAK", "Rams": "LAR", "Ravens": "BAL", "Saints": "NO",
        "Seahawks": "SEA", "Steelers": "PIT", "Tampa Bay": "TB", "Texans": "HOU",
        "Titans": "TEN", "Vikings": "MIN",

        // NHL
        "Avalanche": "COL", "Blackhawks": "CHI", "Blue Jackets": "CBJ", "Blues": "STL",
        "Bruins": "BOS", "Canadiens": "MTL", "Canucks": "VAN", "Capitals": "WSH",
        "Devils": "NJD", "Ducks": "ANA", "Flames": "CGY", "Flyers": "PHI",
        "Golden Knights": "VGK", "Hurricanes": "CAR", "Islanders": "NYI",
        "Kraken": "SEA", "Lightning": "TBL", "Maple Leafs": "TOR", "Oilers": "EDM",
        "Penguins": "PIT", "Predators": "NSH", "Red Wings": "DET", "Sabres": "BUF",
        "Senators": "OTT", "Sharks": "SJS", "Stars": "DAL",
        "Utah Hockey Club": "UTA", "Wild": "MIN",

        // WNBA
        "Dream": "ATL", "Sky": "CHI", "Sun": "CON", "Wings": "DAL",
        "Fever": "IND", "Aces": "LV", "Sparks": "LAS", "Lynx": "MIN",
        "Liberty": "NYL", "Mercury": "PHO", "Storm": "SEA", "Mystics": "WAS",
    ]

    /// Look up abbreviation for a full team name like "Milwaukee Bucks" → "MIL"
    /// Tries multi-word mascots first ("Red Sox", "Blue Jays"), then single last word.
    /// Falls back to first 3 chars of the team name uppercased.
    static func abbreviation(for teamName: String) -> String {
        let words = teamName.split(separator: " ").map(String.init)
        guard words.count >= 2 else {
            return String(teamName.prefix(3)).uppercased()
        }

        // Try last two words (handles "Red Sox", "Blue Jays", "Trail Blazers", etc.)
        if words.count >= 2 {
            let lastTwo = "\(words[words.count - 2]) \(words[words.count - 1])"
            if let abbr = mascotMap[lastTwo] {
                return abbr
            }
        }

        // Try last word (handles most teams)
        if let abbr = mascotMap[words.last!] {
            return abbr
        }

        // Fallback: first 3 chars of first word
        return String(words[0].prefix(3)).uppercased()
    }
}
