import Foundation
import SwiftUI
import Combine

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
class BetSlipManager: ObservableObject {
    static let shared = BetSlipManager()

    private let userDefaultsKey = "betSlipItems"

    /// Published array of bet slip items (order preserved)
    @Published private(set) var items: [BetSlipItem] = []

    /// Maximum selections allowed
    let maxSelections = 10

    private init() {
        loadItems()
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
}
