import Foundation

// MARK: - Player Sync Models

/// Response type for player records from Supabase
struct PlayerRecord: Codable {
    let id: UUID
    let bookieId: UUID
    let authUserId: UUID?
    let name: String
    let email: String?
    let creditLimit: Decimal
    let status: String
    let collectionStatus: String?
    let collectionStatusDate: Date?
    let promisedPaymentDate: Date?
    let username: String?
    let passwordHash: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case bookieId = "bookie_id"
        case authUserId = "auth_user_id"
        case name
        case email
        case creditLimit = "credit_limit"
        case status
        case collectionStatus = "collection_status"
        case collectionStatusDate = "collection_status_date"
        case promisedPaymentDate = "promised_payment_date"
        case username
        case passwordHash = "password_hash"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Event Sync Models

/// Response type for event records from Supabase
struct EventRecord: Codable {
    let id: UUID
    let bookieId: UUID
    let name: String
    let sport: String
    let league: String?
    let startTime: Date
    let status: String
    let homeTeam: String
    let awayTeam: String
    let finalScore: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case bookieId = "bookie_id"
        case name
        case sport
        case league
        case startTime = "start_time"
        case status
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case finalScore = "final_score"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Bet Sync Models

/// Response type for bet records from Supabase
struct BetRecord: Codable {
    let id: UUID
    let bookieId: UUID
    let playerId: UUID
    let eventId: String
    let ticketId: UUID
    let market: String?
    let side: String
    let odds: Int
    let stake: Decimal
    let status: String
    let gradeResult: String?
    let isParlay: Bool
    let parlayLegs: Int
    let policyViolationReason: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case bookieId = "bookie_id"
        case playerId = "player_id"
        case eventId = "event_id"
        case ticketId = "ticket_id"
        case market
        case side
        case odds
        case stake
        case status
        case gradeResult = "grade_result"
        case isParlay = "is_parlay"
        case parlayLegs = "parlay_legs"
        case policyViolationReason = "policy_violation_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Ledger Entry Sync Models

/// Response type for ledger entry records from Supabase
struct LedgerEntryRecord: Codable {
    let id: UUID
    let bookieId: UUID
    let playerId: UUID
    let betId: UUID?
    let amount: Decimal
    let type: String
    let description: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case bookieId = "bookie_id"
        case playerId = "player_id"
        case betId = "bet_id"
        case amount
        case type
        case description
        case createdAt = "created_at"
    }
}

// MARK: - Acceptance Policy Sync Models

/// Response type for acceptance policy records from Supabase
struct AcceptancePolicyRecord: Codable {
    let id: UUID
    let bookieId: UUID
    let maxStake: Decimal
    let requireApprovalAbove: Decimal?
    let autoAcceptEnabled: Bool
    let autoAcceptNewPlayers: Bool
    let newPlayerBetThreshold: Int
    let autoAcceptParlays: Bool
    let parlayMaxLegs: Int
    let eventLockOffsetMinutes: Int
    let parlayPushVoidPolicy: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case bookieId = "bookie_id"
        case maxStake = "max_stake"
        case requireApprovalAbove = "require_approval_above"
        case autoAcceptEnabled = "auto_accept_enabled"
        case autoAcceptNewPlayers = "auto_accept_new_players"
        case newPlayerBetThreshold = "new_player_bet_threshold"
        case autoAcceptParlays = "auto_accept_parlays"
        case parlayMaxLegs = "parlay_max_legs"
        case eventLockOffsetMinutes = "event_lock_offset_minutes"
        case parlayPushVoidPolicy = "parlay_push_void_policy"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Settlement Period Sync Models (not in DB schema yet, placeholder)

/// Response type for settlement period records from Supabase
/// Note: This table needs to be added to the database schema
struct SettlementPeriodRecord: Codable {
    let id: UUID
    let bookieId: UUID
    let weekEndingDate: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case bookieId = "bookie_id"
        case weekEndingDate = "week_ending_date"
        case createdAt = "created_at"
    }
}

// MARK: - Player Settlement Sync Models (not in DB schema yet, placeholder)

/// Response type for player settlement records from Supabase
/// Note: This table needs to be added to the database schema
struct PlayerSettlementRecord: Codable {
    let id: UUID
    let bookieId: UUID
    let playerId: UUID
    let periodWeekEndingDate: Date
    let isSettled: Bool
    let settledAt: Date?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case bookieId = "bookie_id"
        case playerId = "player_id"
        case periodWeekEndingDate = "period_week_ending_date"
        case isSettled = "is_settled"
        case settledAt = "settled_at"
        case notes
    }
}
