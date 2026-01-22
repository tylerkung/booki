import XCTest
@testable import Booki

final class BalanceServiceTests: XCTestCase {

    // MARK: - Test Helpers

    private func createPlayer(creditLimit: Decimal = 1000) -> Player {
        return Player(name: "Test Player", creditLimit: creditLimit)
    }

    private func createBet(
        stake: Decimal,
        odds: Int,
        status: BetStatus = .pending,
        player: Player? = nil
    ) -> Bet {
        return Bet(
            eventId: "event-1",
            market: "spread",
            side: "Team A",
            odds: odds,
            stake: stake,
            status: status,
            player: player
        )
    }

    private func createLedgerEntry(
        amount: Decimal,
        type: EntryType = .settlement,
        player: Player
    ) -> LedgerEntry {
        return LedgerEntry(
            amount: amount,
            type: type,
            entryDescription: "Test entry",
            player: player
        )
    }

    // MARK: - calculateBalance Tests

    func testCalculateBalanceWithEmptyLedger() {
        let entries: [LedgerEntry] = []
        let balance = BalanceService.calculateBalance(from: entries)
        XCTAssertEqual(balance, Decimal.zero)
    }

    func testCalculateBalanceWithSinglePositiveEntry() {
        let player = createPlayer()
        let entry = createLedgerEntry(amount: 100, player: player)
        let balance = BalanceService.calculateBalance(from: [entry])
        XCTAssertEqual(balance, 100)
    }

    func testCalculateBalanceWithSingleNegativeEntry() {
        let player = createPlayer()
        let entry = createLedgerEntry(amount: -50, player: player)
        let balance = BalanceService.calculateBalance(from: [entry])
        XCTAssertEqual(balance, -50)
    }

    func testCalculateBalanceWithMultipleEntries() {
        let player = createPlayer()
        let entries = [
            createLedgerEntry(amount: 100, type: .settlement, player: player),  // Player lost $100
            createLedgerEntry(amount: -50, type: .settlement, player: player),  // Player won $50
            createLedgerEntry(amount: 25, type: .adjustment, player: player),   // Adjustment +$25
            createLedgerEntry(amount: -200, type: .paymentLogged, player: player) // Payment logged -$200
        ]
        let balance = BalanceService.calculateBalance(from: entries)
        // 100 - 50 + 25 - 200 = -125
        XCTAssertEqual(balance, -125)
    }

    // MARK: - balanceOwed Tests

    func testBalanceOwedMatchesCalculateBalance() {
        let player = createPlayer()
        let entries = [
            createLedgerEntry(amount: 100, player: player),
            createLedgerEntry(amount: -30, player: player)
        ]
        let balance = BalanceService.calculateBalance(from: entries)
        let owed = BalanceService.balanceOwed(from: entries)
        XCTAssertEqual(balance, owed)
        XCTAssertEqual(owed, 70)
    }

    // MARK: - openLiability Tests

    func testOpenLiabilityWithEmptyBets() {
        let bets: [Bet] = []
        let liability = BalanceService.openLiability(from: bets)
        XCTAssertEqual(liability, Decimal.zero)
    }

    func testOpenLiabilityWithPendingBet() {
        let player = createPlayer()
        // $100 at -110 odds = $90.91 payout (approximately)
        let bet = createBet(stake: 110, odds: -110, status: .pending, player: player)
        let liability = BalanceService.openLiability(from: [bet])
        // 110 * (100/110) = 100 (with tolerance for Decimal precision)
        XCTAssertTrue(abs(liability - 100) < Decimal(0.01), "Expected ~100, got \(liability)")
    }

    func testOpenLiabilityWithAcceptedBet() {
        let player = createPlayer()
        // $100 at +150 odds = $150 payout
        let bet = createBet(stake: 100, odds: 150, status: .accepted, player: player)
        let liability = BalanceService.openLiability(from: [bet])
        XCTAssertEqual(liability, 150)
    }

    func testOpenLiabilityExcludesDeclinedBet() {
        let player = createPlayer()
        let bet = createBet(stake: 100, odds: 150, status: .declined, player: player)
        let liability = BalanceService.openLiability(from: [bet])
        XCTAssertEqual(liability, Decimal.zero)
    }

    func testOpenLiabilityExcludesVoidBet() {
        let player = createPlayer()
        let bet = createBet(stake: 100, odds: 150, status: .void, player: player)
        let liability = BalanceService.openLiability(from: [bet])
        XCTAssertEqual(liability, Decimal.zero)
    }

    func testOpenLiabilityExcludesSettledBet() {
        let player = createPlayer()
        let bet = createBet(stake: 100, odds: 150, status: .settled, player: player)
        let liability = BalanceService.openLiability(from: [bet])
        XCTAssertEqual(liability, Decimal.zero)
    }

    func testOpenLiabilityExcludesGradedBet() {
        let player = createPlayer()
        let bet = createBet(stake: 100, odds: 150, status: .graded, player: player)
        let liability = BalanceService.openLiability(from: [bet])
        XCTAssertEqual(liability, Decimal.zero)
    }

    func testOpenLiabilityWithMixedStatuses() {
        let player = createPlayer()
        let bets = [
            createBet(stake: 100, odds: 100, status: .pending, player: player),   // $100 payout - counts
            createBet(stake: 100, odds: 100, status: .accepted, player: player),  // $100 payout - counts
            createBet(stake: 100, odds: 100, status: .declined, player: player),  // excluded
            createBet(stake: 100, odds: 100, status: .settled, player: player),   // excluded
            createBet(stake: 100, odds: 100, status: .void, player: player)       // excluded
        ]
        let liability = BalanceService.openLiability(from: bets)
        // Only pending and accepted count: 100 + 100 = 200
        XCTAssertEqual(liability, 200)
    }

    // MARK: - availableCredit Tests

    func testAvailableCreditWithNoBetsNoLedger() {
        let creditLimit: Decimal = 1000
        let bets: [Bet] = []
        let ledgerEntries: [LedgerEntry] = []

        let available = BalanceService.availableCredit(
            creditLimit: creditLimit,
            bets: bets,
            ledgerEntries: ledgerEntries
        )
        XCTAssertEqual(available, 1000)
    }

    func testAvailableCreditReducedByOpenLiability() {
        let player = createPlayer(creditLimit: 1000)
        // $100 at +100 odds = $100 payout
        let bet = createBet(stake: 100, odds: 100, status: .pending, player: player)
        let ledgerEntries: [LedgerEntry] = []

        let available = BalanceService.availableCredit(
            creditLimit: 1000,
            bets: [bet],
            ledgerEntries: ledgerEntries
        )
        // 1000 - 100 (liability) - 0 (owed) = 900
        XCTAssertEqual(available, 900)
    }

    func testAvailableCreditReducedByBalanceOwed() {
        let player = createPlayer(creditLimit: 1000)
        let bets: [Bet] = []
        // Player owes $200
        let entry = createLedgerEntry(amount: 200, player: player)

        let available = BalanceService.availableCredit(
            creditLimit: 1000,
            bets: bets,
            ledgerEntries: [entry]
        )
        // 1000 - 0 (liability) - 200 (owed) = 800
        XCTAssertEqual(available, 800)
    }

    func testAvailableCreditIncreasedByNegativeBalance() {
        let player = createPlayer(creditLimit: 1000)
        let bets: [Bet] = []
        // Bookie owes player $200 (negative balance)
        let entry = createLedgerEntry(amount: -200, player: player)

        let available = BalanceService.availableCredit(
            creditLimit: 1000,
            bets: bets,
            ledgerEntries: [entry]
        )
        // 1000 - 0 (liability) - (-200) (owed) = 1200
        XCTAssertEqual(available, 1200)
    }

    func testAvailableCreditWithBothLiabilityAndBalance() {
        let player = createPlayer(creditLimit: 1000)
        // $100 at +100 odds = $100 payout
        let bet = createBet(stake: 100, odds: 100, status: .accepted, player: player)
        // Player owes $300
        let entry = createLedgerEntry(amount: 300, player: player)

        let available = BalanceService.availableCredit(
            creditLimit: 1000,
            bets: [bet],
            ledgerEntries: [entry]
        )
        // 1000 - 100 (liability) - 300 (owed) = 600
        XCTAssertEqual(available, 600)
    }

    func testAvailableCreditCanBeNegative() {
        let player = createPlayer(creditLimit: 500)
        // Large bet: $500 at +200 odds = $1000 payout
        let bet = createBet(stake: 500, odds: 200, status: .accepted, player: player)
        // Player also owes $200
        let entry = createLedgerEntry(amount: 200, player: player)

        let available = BalanceService.availableCredit(
            creditLimit: 500,
            bets: [bet],
            ledgerEntries: [entry]
        )
        // 500 - 1000 (liability) - 200 (owed) = -700
        XCTAssertEqual(available, -700)
    }

    // MARK: - availableCredit for Player Tests

    func testAvailableCreditForPlayer() {
        let player = createPlayer(creditLimit: 1000)
        let bet = createBet(stake: 100, odds: 100, status: .pending, player: player)
        let entry = createLedgerEntry(amount: 50, player: player)

        let available = BalanceService.availableCredit(
            for: player,
            bets: [bet],
            ledgerEntries: [entry]
        )
        // 1000 - 100 (liability) - 50 (owed) = 850
        XCTAssertEqual(available, 850)
    }

    // MARK: - playerSummary Tests

    func testPlayerSummaryWithNoActivity() {
        let player = createPlayer(creditLimit: 1000)
        let bets: [Bet] = []
        let ledgerEntries: [LedgerEntry] = []

        let summary = BalanceService.playerSummary(
            for: player,
            bets: bets,
            ledgerEntries: ledgerEntries
        )

        XCTAssertEqual(summary.creditLimit, 1000)
        XCTAssertEqual(summary.openLiability, Decimal.zero)
        XCTAssertEqual(summary.balanceOwed, Decimal.zero)
        XCTAssertEqual(summary.availableCredit, 1000)
    }

    func testPlayerSummaryWithActivity() {
        let player = createPlayer(creditLimit: 2000)
        // $200 at -200 odds = $100 payout
        let bet1 = createBet(stake: 200, odds: -200, status: .accepted, player: player)
        // $100 at +150 odds = $150 payout
        let bet2 = createBet(stake: 100, odds: 150, status: .pending, player: player)
        // Player owes $500
        let entry1 = createLedgerEntry(amount: 500, player: player)
        // Bookie owes $100
        let entry2 = createLedgerEntry(amount: -100, player: player)

        let summary = BalanceService.playerSummary(
            for: player,
            bets: [bet1, bet2],
            ledgerEntries: [entry1, entry2]
        )

        XCTAssertEqual(summary.creditLimit, 2000)
        // 100 + 150 = 250
        XCTAssertEqual(summary.openLiability, 250)
        // 500 - 100 = 400
        XCTAssertEqual(summary.balanceOwed, 400)
        // 2000 - 250 - 400 = 1350
        XCTAssertEqual(summary.availableCredit, 1350)
    }

    func testPlayerSummaryAllFieldsConsistent() {
        let player = createPlayer(creditLimit: 5000)
        let bet = createBet(stake: 500, odds: 100, status: .accepted, player: player)
        let entry = createLedgerEntry(amount: 1000, player: player)

        let summary = BalanceService.playerSummary(
            for: player,
            bets: [bet],
            ledgerEntries: [entry]
        )

        // Verify the formula: availableCredit = creditLimit - openLiability - balanceOwed
        let expectedAvailable = summary.creditLimit - summary.openLiability - summary.balanceOwed
        XCTAssertEqual(summary.availableCredit, expectedAvailable)
    }

    // MARK: - Edge Cases

    func testZeroCreditLimit() {
        let player = createPlayer(creditLimit: 0)
        let summary = BalanceService.playerSummary(
            for: player,
            bets: [],
            ledgerEntries: []
        )
        XCTAssertEqual(summary.availableCredit, Decimal.zero)
    }

    func testLargeAmounts() {
        let player = createPlayer(creditLimit: Decimal(1_000_000))
        // Large bet: $100,000 at +100 odds = $100,000 payout
        let bet = createBet(stake: 100_000, odds: 100, status: .accepted, player: player)
        // Player owes $500,000
        let entry = createLedgerEntry(amount: 500_000, player: player)

        let available = BalanceService.availableCredit(
            for: player,
            bets: [bet],
            ledgerEntries: [entry]
        )
        // 1,000,000 - 100,000 - 500,000 = 400,000
        XCTAssertEqual(available, 400_000)
    }
}
