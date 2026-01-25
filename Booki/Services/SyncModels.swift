import Foundation

// MARK: - Player Sync Models

/// Response type for player records from Supabase
struct PlayerRecord: Codable, Identifiable {
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

/// Insert/Update payload for player records to Supabase
struct PlayerUpsert: Codable {
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
    let inviteCode: String?
    let inviteCodeGeneratedAt: Date?
    let inviteCodeExpiresAt: Date?
    let claimedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let version: Int

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
        case inviteCode = "invite_code"
        case inviteCodeGeneratedAt = "invite_code_generated_at"
        case inviteCodeExpiresAt = "invite_code_expires_at"
        case claimedAt = "claimed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case version
    }

    /// Create upsert payload from SwiftData Player model
    init(from player: Player, bookieId: UUID) {
        self.id = player.id
        self.bookieId = bookieId
        self.authUserId = player.authUserId
        self.name = player.name
        self.email = player.email
        self.creditLimit = player.creditLimit
        self.status = player.status.rawValue
        self.collectionStatus = player.collectionStatus?.rawValue
        self.collectionStatusDate = player.collectionStatusDate
        self.promisedPaymentDate = player.promisedPaymentDate
        self.username = player.username
        self.passwordHash = player.passwordHash
        self.inviteCode = player.inviteCode
        self.inviteCodeGeneratedAt = player.inviteCodeGeneratedAt
        self.inviteCodeExpiresAt = player.inviteCodeExpiresAt
        self.claimedAt = player.claimedAt
        self.createdAt = player.createdAt
        self.updatedAt = player.updatedAt
        self.version = player.version
    }
}

// MARK: - Event Sync Models

/// Response type for event records from Supabase
struct EventRecord: Codable, Identifiable {
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

/// Insert/Update payload for event records to Supabase
struct EventUpsert: Codable {
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
    let version: Int

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
        case version
    }

    /// Create upsert payload from SwiftData Event model
    init(from event: Event, bookieId: UUID) {
        self.id = event.id
        self.bookieId = bookieId
        self.name = "\(event.awayTeam) @ \(event.homeTeam)"
        self.sport = event.sport
        self.league = event.league.isEmpty ? nil : event.league
        self.startTime = event.startTime
        self.status = event.status.rawValue
        self.homeTeam = event.homeTeam
        self.awayTeam = event.awayTeam
        self.finalScore = event.finalScore
        self.createdAt = event.startTime // Events use startTime as createdAt
        self.updatedAt = Date()
        self.version = event.version
    }
}

// MARK: - Bet Sync Models

/// Response type for bet records from Supabase
struct BetRecord: Codable, Identifiable {
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

/// Insert/Update payload for bet records to Supabase
struct BetUpsert: Codable {
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
    let version: Int

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
        case version
    }

    /// Create upsert payload from SwiftData Bet model
    /// Returns nil if bet has no associated player (required relationship)
    init?(from bet: Bet, bookieId: UUID) {
        guard let playerId = bet.player?.id else {
            return nil
        }
        self.id = bet.id
        self.bookieId = bookieId
        self.playerId = playerId
        self.eventId = bet.eventId
        self.ticketId = bet.ticketId
        self.market = bet.market.isEmpty ? nil : bet.market
        self.side = bet.side
        self.odds = bet.odds
        self.stake = bet.stake
        self.status = bet.status.rawValue
        self.gradeResult = bet.gradeResult?.rawValue
        self.isParlay = bet.isParlay
        self.parlayLegs = bet.parlayLegs
        self.policyViolationReason = bet.policyViolationReason
        self.createdAt = bet.createdAt
        self.updatedAt = Date()
        self.version = bet.version
    }
}

// MARK: - Ledger Entry Sync Models

/// Response type for ledger entry records from Supabase
struct LedgerEntryRecord: Codable, Identifiable {
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

/// Insert payload for ledger entry records to Supabase
/// Note: Ledger entries are append-only, so this is insert-only (no update)
struct LedgerEntryInsert: Codable {
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

    /// Create insert payload from SwiftData LedgerEntry model
    /// Returns nil if entry has no associated player (required relationship)
    init?(from entry: LedgerEntry, bookieId: UUID) {
        guard let playerId = entry.player?.id else {
            return nil
        }
        self.id = entry.id
        self.bookieId = bookieId
        self.playerId = playerId
        self.betId = entry.bet?.id
        self.amount = entry.amount
        self.type = entry.type.rawValue
        self.description = entry.entryDescription
        self.createdAt = entry.createdAt
    }
}

// MARK: - Acceptance Policy Sync Models

/// Response type for acceptance policy records from Supabase
struct AcceptancePolicyRecord: Codable, Identifiable {
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

/// Insert/Update payload for acceptance policy records to Supabase
struct AcceptancePolicyUpsert: Codable {
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
    let version: Int

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
        case version
    }

    /// Create upsert payload from SwiftData AcceptancePolicy model
    init(from policy: AcceptancePolicy, bookieId: UUID) {
        self.id = policy.id
        self.bookieId = bookieId
        self.maxStake = policy.autoAcceptMaxStake
        self.requireApprovalAbove = policy.requireReviewAboveStake > 0 ? policy.requireReviewAboveStake : nil
        self.autoAcceptEnabled = true // Always enabled when policy exists
        self.autoAcceptNewPlayers = policy.autoAcceptNewPlayers
        self.newPlayerBetThreshold = policy.newPlayerBetThreshold
        self.autoAcceptParlays = policy.autoAcceptParlays
        self.parlayMaxLegs = policy.parlayMaxLegs
        self.eventLockOffsetMinutes = policy.eventLockOffsetMinutes
        self.parlayPushVoidPolicy = policy.parlayPushVoidPolicy
        self.createdAt = policy.createdAt
        self.updatedAt = policy.updatedAt
        self.version = policy.version
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
