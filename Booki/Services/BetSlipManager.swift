import Foundation
import SwiftUI
/// Bet mode for the slip - Singles (individual bets) or Parlay (combined)
/// US-041: Support Multi-Bet (Parlay) Selections
enum BetMode: String, Codable, CaseIterable {
    case singles = "Singles"
    case parlay = "Multi"
}

/// Extended selection model for bet slip with event details for display
/// US-040: Build Persistent Bet Slip
struct BetSlipItem: Equatable, Hashable, Codable {
    let eventId: UUID
    let marketId: UUID
    let side: String
    let odds: Int
    let marketType: MarketType
    /// Indicates which side of the market was selected: "a" for sideA/oddsA, "b" for sideB/oddsB
    /// Used by Edge Functions which expect side as 'a' or 'b'
    let sideIndicator: String

    // Display info stored with selection
    let eventDescription: String  // e.g., "Lakers vs Celtics"
    let marketDescription: String // e.g., "Spread: Lakers -3.5"

    func hash(into hasher: inout Hasher) {
        hasher.combine(eventId)
        hasher.combine(marketId)
        hasher.combine(side)
    }

    static func == (lhs: BetSlipItem, rhs: BetSlipItem) -> Bool {
        lhs.eventId == rhs.eventId && lhs.marketId == rhs.marketId && lhs.side == rhs.side
    }

    /// Create from a BetSlipSelection with event context
    init(from selection: BetSlipSelection, eventDescription: String, marketDescription: String) {
        self.eventId = selection.eventId
        self.marketId = selection.marketId
        self.side = selection.side
        self.odds = selection.odds
        self.marketType = selection.marketType
        self.sideIndicator = selection.sideIndicator
        self.eventDescription = eventDescription
        self.marketDescription = marketDescription
    }

    /// Direct initializer
    init(eventId: UUID, marketId: UUID, side: String, odds: Int, marketType: MarketType, sideIndicator: String, eventDescription: String, marketDescription: String) {
        self.eventId = eventId
        self.marketId = marketId
        self.side = side
        self.odds = odds
        self.marketType = marketType
        self.sideIndicator = sideIndicator
        self.eventDescription = eventDescription
        self.marketDescription = marketDescription
    }

    /// Convert to BetSlipSelection for compatibility with existing code
    var asSelection: BetSlipSelection {
        BetSlipSelection(
            eventId: eventId,
            marketId: marketId,
            side: side,
            odds: odds,
            marketType: marketType,
            sideIndicator: sideIndicator
        )
    }
}

/// Manager for persistent bet slip storage
/// US-040: Build Persistent Bet Slip
/// US-041: Support Multi-Bet (Parlay) Selections
/// US-042: Improved Stake Entry
@MainActor
@Observable
class BetSlipManager {
    static let shared = BetSlipManager()

    private let userDefaultsKey = "betSlipItems"
    private let betModeKey = "betSlipMode"
    private let stakeKey = "betSlipStake"
    private let itemStakesKey = "betSlipItemStakes"

    /// Array of bet slip items (order preserved)
    private(set) var items: [BetSlipItem] = []

    /// Per-item stakes for singles mode (US-003)
    /// Key is "\(marketId)_\(sideIndicator)" to uniquely identify each selection
    private(set) var itemStakes: [String: Decimal] = [:]

    /// Generate unique key for item stakes (marketId + sideIndicator)
    func itemStakeKey(marketId: UUID, sideIndicator: String) -> String {
        return "\(marketId.uuidString)_\(sideIndicator)"
    }

    /// Bet mode (singles or parlay)
    /// US-041: Support Multi-Bet (Parlay) Selections
    var betMode: BetMode = .singles {
        didSet {
            saveBetMode()
        }
    }

    /// US-005: Message shown when mode auto-switches (e.g., from parlay to singles due to conflicts)
    var modeSwitchMessage: String?

    /// Stake amount (US-042)
    var stake: Decimal = 0 {
        didSet {
            saveStake()
        }
    }

    /// Quick-pick stake amounts (US-042)
    static let quickPickAmounts: [Decimal] = [5, 10, 25, 50, 100]

    /// Maximum selections allowed
    let maxSelections = 10

    // MARK: - Parlay Conflict Detection (US-003)

    /// Check if selections contain conflicting picks that can't be combined in a parlay
    var hasConflictingSelections: Bool {
        parlayConflictReason != nil
    }

    /// Identifies the specific conflict reason, or nil if no conflicts
    private var parlayConflictReason: String? {
        // Both sides of same market
        let marketGroups = Dictionary(grouping: items) { $0.marketId }
        for (_, marketItems) in marketGroups {
            if marketItems.count > 1 {
                return "Multi-Pick unavailable: conflicting selections on same market"
            }
        }

        // Same-game checks
        let eventGroups = Dictionary(grouping: items) { $0.eventId }
        for (_, eventItems) in eventGroups {
            guard eventItems.count > 1 else { continue }

            // Same market type on same game (e.g. two moneylines)
            let typeGroups = Dictionary(grouping: eventItems) { $0.marketType.rawValue }
            for (_, typeItems) in typeGroups {
                if typeItems.count > 1 {
                    return "Multi-Pick unavailable: conflicting selections on same game"
                }
            }

            // Correlated markets: spread/alt spread + moneyline on same game
            let types = Set(eventItems.map { $0.marketType })
            let hasMoneyline = types.contains(.moneyline)
            let hasSpread = types.contains(.spread) || types.contains(.alternateSpread)
            if hasMoneyline && hasSpread {
                return "Multi-Pick unavailable: spread and moneyline are correlated on the same game"
            }
        }

        // Correlated: futures/outright team + moneyline/spread on a game involving that team
        let outrightPicks = items.filter { $0.marketType == .outright }
        let gamePicks = items.filter { $0.marketType == .moneyline || $0.marketType == .spread || $0.marketType == .alternateSpread }
        for outright in outrightPicks {
            let teamName = outright.side.lowercased()
            for game in gamePicks {
                if game.eventDescription.lowercased().contains(teamName) {
                    return "Multi-Pick unavailable: futures and game pick are correlated for the same team"
                }
            }
        }

        return nil
    }

    /// Get a human-readable description of why parlay is unavailable due to conflicts
    var conflictDescription: String? {
        parlayConflictReason
    }

    // MARK: - Futures Parlay Detection

    /// Whether any selection in the slip is an outright/futures market
    var containsOutrightSelection: Bool {
        items.contains { $0.marketType == .outright }
    }

    // MARK: - Same-Game Parlay Warning

    /// No longer needed — correlated market conflicts handled by hasConflictingSelections
    var sameGameParlayWarning: String? { nil }

    private init() {
        loadItems()
        loadBetMode()
        loadStake()
        loadItemStakes()
    }

    // MARK: - Parlay Odds Calculation (US-041)

    /// Convert American odds to decimal odds
    private func toDecimalOdds(_ americanOdds: Int) -> Double {
        if americanOdds > 0 {
            return (Double(americanOdds) / 100.0) + 1.0
        } else {
            return (100.0 / Double(abs(americanOdds))) + 1.0
        }
    }

    /// Convert decimal odds back to American odds
    private func toAmericanOdds(_ decimalOdds: Double) -> Int {
        if decimalOdds >= 2.0 {
            return Int(round((decimalOdds - 1.0) * 100.0))
        } else {
            return Int(round(-100.0 / (decimalOdds - 1.0)))
        }
    }

    /// Calculate combined parlay odds (multiply decimal odds)
    /// Returns nil if no items
    var combinedParlayOdds: Int? {
        guard !items.isEmpty else { return nil }

        let combinedDecimal = items.reduce(1.0) { result, item in
            result * toDecimalOdds(item.odds)
        }

        return toAmericanOdds(combinedDecimal)
    }

    /// Formatted combined parlay odds string
    var formattedParlayOdds: String? {
        guard let odds = combinedParlayOdds else { return nil }
        return odds >= 0 ? "+\(odds)" : "\(odds)"
    }

    // MARK: - Payout Calculation (US-042)

    /// Calculate potential payout from American odds and stake
    /// Payout includes the original stake (total return)
    func calculatePayout(odds: Int, stake: Decimal) -> Decimal {
        guard stake > 0 else { return 0 }

        let decimalOdds = toDecimalOdds(odds)
        return stake * Decimal(decimalOdds)
    }

    /// US-001: Calculate "to win" (profit only) from American odds and stake
    /// For +odds: toWin = wager × (odds/100). For -odds: toWin = wager × (100/|odds|)
    func calculateToWin(odds: Int, stake: Decimal) -> Decimal {
        guard stake > 0 else { return 0 }
        if odds >= 0 {
            return stake * Decimal(odds) / Decimal(100)
        } else {
            return stake * Decimal(100) / Decimal(abs(odds))
        }
    }

    /// US-001: Calculate required wager from desired "to win" amount and odds
    /// For +odds: wager = toWin / (odds/100). For -odds: wager = toWin / (100/|odds|)
    func calculateWagerFromToWin(odds: Int, toWin: Decimal) -> Decimal {
        guard toWin > 0, odds != 0 else { return 0 }
        if odds >= 0 {
            return toWin * Decimal(100) / Decimal(odds)
        } else {
            return toWin * Decimal(abs(odds)) / Decimal(100)
        }
    }

    /// Calculate payout for a single bet (using current stake)
    func singleBetPayout(for item: BetSlipItem) -> Decimal {
        return calculatePayout(odds: item.odds, stake: stake)
    }

    /// Calculate total payout for singles mode (sum of individual payouts)
    var totalSinglesPayout: Decimal {
        guard stake > 0 else { return 0 }
        return items.reduce(Decimal.zero) { total, item in
            total + singleBetPayout(for: item)
        }
    }

    /// Calculate total stake for singles mode (stake * number of bets)
    var totalSinglesStake: Decimal {
        return stake * Decimal(items.count)
    }

    /// Calculate payout for parlay mode (combined odds * stake)
    var parlayPayout: Decimal {
        guard stake > 0, let odds = combinedParlayOdds else { return 0 }
        return calculatePayout(odds: odds, stake: stake)
    }

    /// Current total stake based on bet mode
    var currentTotalStake: Decimal {
        switch betMode {
        case .singles:
            return totalSinglesStake
        case .parlay:
            return stake
        }
    }

    /// Current total payout based on bet mode
    var currentTotalPayout: Decimal {
        switch betMode {
        case .singles:
            return totalSinglesPayout
        case .parlay:
            return parlayPayout
        }
    }

    /// Validate stake against available credit (US-042)
    func isStakeValid(availableCredit: Decimal) -> Bool {
        guard stake > 0 else { return false }
        return currentTotalStake <= availableCredit
    }

    /// Validate individual stakes (for singles mode) against available credit (US-006)
    func isIndividualStakeValid(availableCredit: Decimal) -> Bool {
        guard individualTotalStake > 0 else { return false }
        return individualTotalStake <= availableCredit
    }

    /// Set stake from quick-pick amount (US-042)
    func setQuickPickStake(_ amount: Decimal) {
        stake = amount
    }

    // MARK: - Per-Item Stakes (US-003)

    /// Set stake for an individual bet item
    func setItemStake(marketId: UUID, sideIndicator: String, stake: Decimal) {
        let key = itemStakeKey(marketId: marketId, sideIndicator: sideIndicator)
        itemStakes[key] = stake
        saveItemStakes()
    }

    /// Get stake for an individual bet item (returns 0 if not set)
    func getItemStake(marketId: UUID, sideIndicator: String) -> Decimal {
        let key = itemStakeKey(marketId: marketId, sideIndicator: sideIndicator)
        return itemStakes[key] ?? 0
    }

    /// Total stake from individual item stakes (sum of all per-bet stakes)
    var individualTotalStake: Decimal {
        return itemStakes.values.reduce(Decimal.zero) { $0 + $1 }
    }

    /// Total payout from individual item stakes
    var individualTotalPayout: Decimal {
        return items.reduce(Decimal.zero) { total, item in
            let itemStake = getItemStake(marketId: item.marketId, sideIndicator: item.sideIndicator)
            guard itemStake > 0 else { return total }
            return total + calculatePayout(odds: item.odds, stake: itemStake)
        }
    }

    // MARK: - Public API

    /// Number of selections in the bet slip
    var count: Int { items.count }

    /// Check if bet slip is empty
    var isEmpty: Bool { items.isEmpty }

    /// Check if a selection is in the bet slip
    func contains(_ selection: BetSlipSelection) -> Bool {
        items.contains { $0.asSelection == selection }
    }

    /// Get all selections as BetSlipSelection set (for compatibility)
    var selectionsSet: Set<BetSlipSelection> {
        Set(items.map { $0.asSelection })
    }

    /// Add a selection to the bet slip
    func add(_ item: BetSlipItem) {
        guard items.count < maxSelections else { return }
        guard !items.contains(where: { $0.asSelection == item.asSelection }) else { return }
        items.append(item)
        saveItems()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // US-003/US-005: If adding this item creates a conflict while in parlay mode, switch to singles
        if betMode == .parlay && hasConflictingSelections {
            // US-005: Initialize per-item stakes from parlay stake before switching
            initializeItemStakesFromParlay()
            betMode = .singles
            modeSwitchMessage = "Switched to Singles: conflicting selections on the same game"
        }
    }

    /// US-005: Initialize per-item stakes when switching from parlay to singles
    /// Distributes the current parlay stake evenly across all items, or sets to zero if no stake
    private func initializeItemStakesFromParlay() {
        guard !items.isEmpty else { return }

        if stake > 0 {
            // Distribute parlay stake evenly across items
            let perItemStake = Decimal(NSDecimalNumber(decimal: stake / Decimal(items.count)).intValue)
            for item in items {
                let key = itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
                if itemStakes[key] == nil || itemStakes[key] == 0 {
                    itemStakes[key] = perItemStake
                }
            }
        } else {
            // No parlay stake set — initialize all to zero
            for item in items {
                let key = itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
                if itemStakes[key] == nil {
                    itemStakes[key] = 0
                }
            }
        }
        saveItemStakes()
    }

    /// Add from BetSlipSelection with event context
    func add(selection: BetSlipSelection, eventDescription: String, marketDescription: String) {
        let item = BetSlipItem(
            from: selection,
            eventDescription: eventDescription,
            marketDescription: marketDescription
        )
        add(item)
    }

    /// Remove a selection from the bet slip
    func remove(_ selection: BetSlipSelection) {
        // Find matching items to remove their stakes
        for item in items where item.asSelection == selection {
            let key = itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
            itemStakes.removeValue(forKey: key)
        }
        items.removeAll { $0.asSelection == selection }
        if !hasConflictingSelections { modeSwitchMessage = nil }
        saveItems()
        saveItemStakes()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Remove item at index
    func remove(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        let item = items[index]
        let key = itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
        itemStakes.removeValue(forKey: key)
        items.remove(at: index)
        if !hasConflictingSelections { modeSwitchMessage = nil }
        saveItems()
        saveItemStakes()
    }

    /// Toggle a selection (add if not present, remove if present)
    func toggle(_ selection: BetSlipSelection, eventDescription: String, marketDescription: String) {
        if contains(selection) {
            remove(selection)
        } else {
            add(selection: selection, eventDescription: eventDescription, marketDescription: marketDescription)
        }
    }

    /// Remove selections for events that are no longer bettable (started, locked, canceled, etc.)
    /// Call this with the set of currently bettable event IDs to purge stale picks
    func purgeExpiredSelections(bettableEventIds: Set<UUID>) {
        let staleItems = items.filter { !bettableEventIds.contains($0.eventId) }
        guard !staleItems.isEmpty else { return }
        for item in staleItems {
            let key = itemStakeKey(marketId: item.marketId, sideIndicator: item.sideIndicator)
            itemStakes.removeValue(forKey: key)
        }
        items.removeAll { !bettableEventIds.contains($0.eventId) }
        saveItems()
        saveItemStakes()
    }

    /// Clear all selections
    func clearAll() {
        items.removeAll()
        itemStakes.removeAll()
        modeSwitchMessage = nil
        saveItems()
        saveItemStakes()
    }

    // MARK: - Persistence

    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            let decoder = JSONDecoder()
            items = try decoder.decode([BetSlipItem].self, from: data)
        } catch {
            print("Failed to decode bet slip items: \(error)")
            items = []
        }
    }

    private func saveItems() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(items)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Failed to encode bet slip items: \(error)")
        }
    }

    private func loadBetMode() {
        guard let rawValue = UserDefaults.standard.string(forKey: betModeKey),
              let mode = BetMode(rawValue: rawValue) else {
            betMode = .singles
            return
        }
        betMode = mode
    }

    private func saveBetMode() {
        UserDefaults.standard.set(betMode.rawValue, forKey: betModeKey)
    }

    private func loadStake() {
        let stakeValue = UserDefaults.standard.double(forKey: stakeKey)
        stake = Decimal(stakeValue)
    }

    private func saveStake() {
        UserDefaults.standard.set(NSDecimalNumber(decimal: stake).doubleValue, forKey: stakeKey)
    }

    private func loadItemStakes() {
        guard let data = UserDefaults.standard.data(forKey: itemStakesKey) else { return }
        do {
            let decoder = JSONDecoder()
            // Decode as [String: Double] - keys are now "marketId_sideIndicator" format
            let stringDict = try decoder.decode([String: Double].self, from: data)
            itemStakes = stringDict.reduce(into: [String: Decimal]()) { result, pair in
                result[pair.key] = Decimal(pair.value)
            }
        } catch {
            print("Failed to decode item stakes: \(error)")
            itemStakes = [:]
        }
    }

    private func saveItemStakes() {
        do {
            let encoder = JSONEncoder()
            // Convert Decimal to Double for encoding
            let stringDict = itemStakes.reduce(into: [String: Double]()) { result, pair in
                result[pair.key] = NSDecimalNumber(decimal: pair.value).doubleValue
            }
            let data = try encoder.encode(stringDict)
            UserDefaults.standard.set(data, forKey: itemStakesKey)
        } catch {
            print("Failed to encode item stakes: \(error)")
        }
    }
}
