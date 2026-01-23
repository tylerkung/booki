import Foundation
import SwiftUI
import Combine

/// Bet mode for the slip - Singles (individual bets) or Parlay (combined)
/// US-041: Support Multi-Bet (Parlay) Selections
enum BetMode: String, Codable, CaseIterable {
    case singles = "Singles"
    case parlay = "Parlay"
}

/// Extended selection model for bet slip with event details for display
/// US-040: Build Persistent Bet Slip
struct BetSlipItem: Equatable, Hashable, Codable {
    let eventId: UUID
    let marketId: UUID
    let side: String
    let odds: Int
    let marketType: MarketType

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
        self.eventDescription = eventDescription
        self.marketDescription = marketDescription
    }

    /// Direct initializer
    init(eventId: UUID, marketId: UUID, side: String, odds: Int, marketType: MarketType, eventDescription: String, marketDescription: String) {
        self.eventId = eventId
        self.marketId = marketId
        self.side = side
        self.odds = odds
        self.marketType = marketType
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
            marketType: marketType
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

    /// Published array of bet slip items (order preserved)
    @Published private(set) var items: [BetSlipItem] = []

    /// Published bet mode (singles or parlay)
    /// US-041: Support Multi-Bet (Parlay) Selections
    @Published var betMode: BetMode = .singles {
        didSet {
            saveBetMode()
        }
    }

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

    private init() {
        loadItems()
        loadBetMode()
        loadStake()
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

    /// Set stake from quick-pick amount (US-042)
    func setQuickPickStake(_ amount: Decimal) {
        stake = amount
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
        items.removeAll { $0.asSelection == selection }
        saveItems()
    }

    /// Remove item at index
    func remove(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        items.remove(at: index)
        saveItems()
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
        saveItems()
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
}
