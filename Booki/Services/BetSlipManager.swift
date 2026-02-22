import Foundation
import SwiftUI
import Combine

/// Bet mode for the slip - Singles (individual bets) or Parlay (combined)
/// US-041: Support Multi-Bet (Parlay) Selections
enum BetMode: String, Codable, CaseIterable {
    case singles = "Singles"
    case parlay = "Multi-Pick"
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
class BetSlipManager: ObservableObject {
    static let shared = BetSlipManager()

    private let userDefaultsKey = "betSlipItems"
    private let betModeKey = "betSlipMode"
    private let stakeKey = "betSlipStake"
    private let itemStakesKey = "betSlipItemStakes"

    /// Published array of bet slip items (order preserved)
    @Published private(set) var items: [BetSlipItem] = []

    /// Per-item stakes for singles mode (US-003)
    /// Key is "\(marketId)_\(sideIndicator)" to uniquely identify each selection
    @Published private(set) var itemStakes: [String: Decimal] = [:]

    /// Generate unique key for item stakes (marketId + sideIndicator)
    func itemStakeKey(marketId: UUID, sideIndicator: String) -> String {
        return "\(marketId.uuidString)_\(sideIndicator)"
    }

    /// Published bet mode (singles or parlay)
    /// US-041: Support Multi-Bet (Parlay) Selections
    @Published var betMode: BetMode = .singles {
        didSet {
            saveBetMode()
        }
    }

    /// US-005: Message shown when mode auto-switches (e.g., from parlay to singles due to conflicts)
    @Published var modeSwitchMessage: String?

    /// Published stake amount (US-042)
    @Published var stake: Decimal = 0 {
        didSet {
            saveStake()
        }
    }

    /// Quick-pick stake amounts (US-042)
    static let quickPickAmounts: [Decimal] = [5, 10, 25, 50, 100]

    /// Maximum selections allowed
    let maxSelections = 10

    // MARK: - Parlay Conflict Detection (US-003)

    /// Check if selections contain conflicting picks (opposite sides of the same market)
    /// This makes a parlay impossible since you can't bet both sides of one market
    var hasConflictingSelections: Bool {
        // Group items by marketId
        let marketGroups = Dictionary(grouping: items) { $0.marketId }

        // If any market has multiple selections with different sideIndicators, there's a conflict
        for (_, marketItems) in marketGroups {
            if marketItems.count > 1 {
                // Multiple selections on the same market = conflict
                return true
            }
        }

        // Also check for same event, same market type, different sides
        // (e.g., both ML selections on the same game)
        let eventMarketTypeGroups = Dictionary(grouping: items) { item in
            "\(item.eventId)-\(item.marketType.rawValue)"
        }

        for (_, groupItems) in eventMarketTypeGroups {
            if groupItems.count > 1 {
                // Multiple selections on same event's same market type = conflict
                return true
            }
        }

        return false
    }

    /// Get a human-readable description of why parlay is unavailable due to conflicts
    var conflictDescription: String? {
        guard hasConflictingSelections else { return nil }
        return "Multi-Pick unavailable: conflicting selections on same game"
    }

    // MARK: - Same-Game Parlay Warning (US-015)

    /// Detect when multiple items have the same eventId and warn the user
    /// Returns nil if no same-game parlay detected, or a warning string with the event name
    var sameGameParlayWarning: String? {
        guard betMode == .parlay else { return nil }

        // Group items by eventId
        let eventGroups = Dictionary(grouping: items) { $0.eventId }

        // Find events with multiple selections
        for (_, eventItems) in eventGroups {
            if eventItems.count > 1 {
                return "Same-game multi-pick: multiple picks from \(eventItems[0].eventDescription)"
            }
        }

        return nil
    }

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

    /// Clear all selections
    func clearAll() {
        items.removeAll()
        itemStakes.removeAll()
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
