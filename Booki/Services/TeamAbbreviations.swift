import Foundation

/// Maps team names to standard North American sport abbreviations.
/// College teams use full-name matching; pro teams use mascot-based lookup.
enum TeamAbbreviations {

    /// Look up abbreviation for a team name like "Milwaukee Bucks" → "MIL"
    /// 1. Exact match on full name (handles college teams)
    /// 2. Pro mascot match on last word(s) (handles pro teams — checked before college prefix strip)
    /// 3. Suffix match on school name ("Boston College Eagles" → "Boston College" → "BC")
    /// 4. Fallback: first 3 chars uppercased
    static func abbreviation(for teamName: String) -> String {
        let normalized = teamName.trimmingCharacters(in: .whitespaces)

        // 1. Exact full-name match
        if let abbr = collegeMap[normalized] {
            return abbr
        }

        let words = normalized.split(separator: " ").map(String.init)

        // 2. Pro mascot matching (last two words, then last word)
        //    Checked before college prefix-strip to avoid "Oklahoma City Thunder" → "Oklahoma" → "OU"
        if words.count >= 2 {
            let lastTwo = "\(words[words.count - 2]) \(words[words.count - 1])"
            if let abbr = mascotMap[lastTwo] {
                return abbr
            }
        }
        if let last = words.last, let abbr = mascotMap[last] {
            return abbr
        }

        // 3. College prefix-strip ("Boston College Eagles" → "Boston College" → "BC")
        if words.count >= 2 {
            let prefix1 = words.dropLast().joined(separator: " ")
            if let abbr = collegeMap[prefix1] {
                return abbr
            }
            if words.count >= 3 {
                let prefix2 = words.dropLast(2).joined(separator: " ")
                if let abbr = collegeMap[prefix2] {
                    return abbr
                }
            }
        }

        // 4. Fallback
        return String((words.first ?? normalized).prefix(3)).uppercased()
    }

    // MARK: - College Teams

    private static let collegeMap: [String: String] = [
        // ACC
        "Boston College": "BC", "Clemson": "CLEM", "Duke": "DUKE",
        "Florida State": "FSU", "Georgia Tech": "GT", "Louisville": "LOU",
        "Miami (FL)": "MIA", "NC State": "NCST", "Pittsburgh": "PITT",
        "Syracuse": "SYR", "North Carolina": "UNC", "Virginia": "UVA",
        "Virginia Tech": "VT", "Wake Forest": "WAKE",

        // Big Ten
        "Illinois": "ILL", "Indiana": "IND", "Iowa": "IOWA",
        "Michigan": "MICH", "Michigan State": "MSU", "Minnesota": "MINN",
        "Nebraska": "NEB", "Northwestern": "NW", "Ohio State": "OSU",
        "Penn State": "PSU", "Purdue": "PUR", "Rutgers": "RUTG",
        "Maryland": "UMD", "Wisconsin": "WIS",

        // Big 12
        "Baylor": "BAY", "Iowa State": "ISU", "Kansas": "KU",
        "Kansas State": "KSU", "Oklahoma": "OU", "Oklahoma State": "OKST",
        "TCU": "TCU", "Texas": "TEX", "Texas Tech": "TTU",
        "West Virginia": "WVU",

        // Pac-12
        "Arizona": "ARIZ", "Arizona State": "ASU", "Cal": "CAL",
        "California": "CAL", "Colorado": "COLO", "Oregon": "ORE",
        "Oregon State": "ORST", "Stanford": "STAN", "UCLA": "UCLA",
        "USC": "USC", "Utah": "UTAH", "Washington": "WASH",
        "Washington State": "WSU",

        // SEC
        "Alabama": "BAMA", "Arkansas": "ARK", "Auburn": "AUB",
        "Florida": "UF", "Georgia": "UGA", "Kentucky": "UK",
        "LSU": "LSU", "Ole Miss": "MISS", "Mississippi State": "MSST",
        "Missouri": "MIZ", "South Carolina": "SCAR", "Tennessee": "TENN",
        "Texas A&M": "TAMU", "Vanderbilt": "VAN",

        // Independents
        "BYU": "BYU", "Army": "ARMY", "UMass": "UMASS", "Notre Dame": "ND",

        // AAC
        "Cincinnati": "CIN", "UConn": "CONN", "ECU": "ECU",
        "East Carolina": "ECU", "Houston": "HOU", "Memphis": "MEM",
        "Navy": "NAVY", "SMU": "SMU", "South Florida": "USF",
        "Temple": "TEM", "Tulane": "TULN", "Tulsa": "TLSA", "UCF": "UCF",

        // Conference USA
        "Charlotte": "CHAR", "FAU": "FAU", "Florida Atlantic": "FAU",
        "FIU": "FIU", "Florida International": "FIU",
        "Louisiana Tech": "LT", "Marshall": "MRSH",
        "Middle Tennessee": "MTSU", "North Texas": "UNT",
        "Old Dominion": "ODU", "Rice": "RICE", "Southern Miss": "USM",
        "UTEP": "UTEP", "UTSA": "UTSA", "WKU": "WKU", "Western Kentucky": "WKU",

        // MAC
        "Akron": "AKR", "Ball State": "BALL", "Bowling Green": "BGSU",
        "Buffalo": "BUFF", "Central Michigan": "CMU", "Eastern Michigan": "EMU",
        "Kent State": "KENT", "Miami (OH)": "M-OH", "Northern Illinois": "NIU",
        "Ohio": "OHIO", "Toledo": "TOL", "Western Michigan": "WMU",

        // Mountain West
        "Air Force": "AFA", "Boise State": "BSU", "Colorado State": "CSU",
        "Fresno State": "FRES", "Hawaii": "HAW", "Hawai'i": "HAW",
        "Nevada": "NEV", "New Mexico": "UNM", "San Diego State": "SDSU",
        "San José State": "SJSU", "San Jose State": "SJSU",
        "UNLV": "UNLV", "Utah State": "USU", "Wyoming": "WYO",

        // Sun Belt
        "Appalachian State": "APP", "Arkansas State": "ARST",
        "Georgia Southern": "GASO", "Georgia State": "GSU",
        "Idaho": "IDHO", "Louisiana Lafayette": "ULL", "Louisiana-Lafayette": "ULL",
        "Louisiana Monroe": "ULM", "Louisiana-Monroe": "ULM",
        "New Mexico State": "NMSU", "South Alabama": "USA",
        "Texas State": "TXST", "Troy": "TROY",

        // Big Sky
        "Cal Poly": "CP", "Eastern Washington": "EWU", "Idaho State": "IDST",
        "Montana": "MONT", "Montana State": "MTST", "North Dakota": "UND",
        "Northern Arizona": "NAU", "Northern Colorado": "UNCO",
        "Portland State": "PRST", "Sacramento State": "SAC",
        "Southern Utah": "SUU", "UC Davis": "UCD", "Weber State": "WEB",

        // Big South
        "Charleston Southern": "CHSO", "Coastal Carolina": "CCAR",
        "Gardner-Webb": "WEBB", "Kennesaw State": "KENN",
        "Liberty": "LIB", "Monmouth": "MONM", "Presbyterian": "PRE",

        // CAA
        "Albany": "ALBY", "Delaware": "DEL", "Elon": "ELON",
        "James Madison": "JMU", "Maine": "MNE",
        "New Hampshire": "UNH", "Rhode Island": "URI", "Richmond": "RICH",
        "Stony Brook": "STON", "Towson": "TOWS", "Villanova": "NOVA",
        "William & Mary": "W&M",

        // Ivy League
        "Brown": "BRWN", "Cornell": "COR", "Columbia": "CLMB",
        "Dartmouth": "DART", "Harvard": "HARV", "UPenn": "PENN",
        "Pennsylvania": "PENN", "Princeton": "PRIN", "Yale": "YALE",

        // MEAC
        "Bethune-Cookman": "COOK", "Delaware State": "DSU",
        "Florida A&M": "FAMU", "Hampton": "HAMP", "Howard": "HOW",
        "Morgan State": "MORG", "Norfolk State": "NORF",
        "North Carolina A&T": "NCAT", "NC Central": "NCCU",
        "Savannah State": "SAV", "South Carolina State": "SCST",

        // Missouri Valley (MVFC)
        "Illinois State": "ILST", "Indiana State": "INST",
        "Missouri State": "MOST", "North Dakota State": "NDSU",
        "Northern Iowa": "UNI", "South Dakota": "SDAK",
        "South Dakota State": "SDSU", "Southern Illinois": "SIU",
        "Western Illinois": "WIU", "Youngstown State": "YSU",

        // NEC
        "Bryant": "BRY", "Central Connecticut": "CCSU",
        "Duquesne": "DUQ", "Robert Morris": "RMU",
        "Sacred Heart": "SHU", "St. Francis (PA)": "SFU", "Wagner": "WAG",

        // Ohio Valley
        "Austin Peay": "PEAY", "Eastern Illinois": "EIU",
        "Eastern Kentucky": "EKY", "Jacksonville State": "JVST",
        "Murray State": "MURR", "Southeast Missouri": "SEMO",
        "Tennessee State": "TNST", "Tennessee Tech": "TNTC",
        "Tennessee-Martin": "UTM",

        // Patriot
        "Bucknell": "BUCK", "Colgate": "COLG", "Fordham": "FOR",
        "Georgetown": "GTWN", "Holy Cross": "HC",
        "Lafayette": "LAF", "Lehigh": "LEH",

        // Pioneer
        "Butler": "BUT", "Campbell": "CAMP", "Davidson": "DAV",
        "Dayton": "DAY", "Drake": "DRKE", "Jacksonville": "JAC",
        "Marist": "MRST", "Morehead State": "MORE", "San Diego": "USD",
        "Stetson": "STET", "Valparaiso": "VALP",

        // SoCon
        "Chattanooga": "CHAT", "ETSU": "ETSU", "East Tennessee State": "ETSU",
        "Furman": "FUR", "Mercer": "MER", "Samford": "SAM",
        "The Citadel": "CIT", "VMI": "VMI",
        "Western Carolina": "WCU", "Wofford": "WOF",

        // Southland
        "Abilene Christian": "ACU", "Central Arkansas": "UCA",
        "Houston Baptist": "HBU", "Incarnate Word": "IW",
        "Lamar": "LAM", "McNeese State": "MCNS", "McNeese": "MCNS",
        "Nicholls State": "NICH", "Nicholls": "NICH",
        "Northwestern State": "NWST", "Sam Houston State": "SHSU",
        "Sam Houston": "SHSU", "Southeastern Louisiana": "SELA",
        "Stephen F. Austin": "SFA",

        // SWAC
        "Alabama A&M": "AAMU", "Alabama State": "ALST",
        "Alcorn State": "ALCN", "Arkansas-Pine Bluff": "ARPB",
        "Grambling State": "GRAM", "Grambling": "GRAM",
        "Jackson State": "JKST", "Mississippi Valley State": "MVSU",
        "Prairie View A&M": "PV", "Prairie View": "PV",
        "Southern University": "SOU", "Texas Southern": "TXSO",
    ]

    // MARK: - Pro Mascots

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
}
