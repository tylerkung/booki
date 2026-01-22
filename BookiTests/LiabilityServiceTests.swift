import XCTest
@testable import Booki

final class LiabilityServiceTests: XCTestCase {

    // MARK: - Helper for Decimal comparison with tolerance

    /// Asserts that two Decimal values are equal within a small tolerance
    /// This accounts for floating-point precision issues with Decimal division
    func assertDecimalEqual(_ actual: Decimal, _ expected: Decimal, accuracy: Decimal = Decimal(string: "0.01")!, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        let difference = abs(actual - expected)
        XCTAssertTrue(difference < accuracy, "\(message) - Expected \(expected), got \(actual) (difference: \(difference))", file: file, line: line)
    }

    // MARK: - Negative Odds Tests

    func testNegativeOddsPayout_Standard() {
        // -110 odds: $110 bet wins $100
        let stake = Decimal(110)
        let odds = -110
        let payout = LiabilityService.calculatePayout(stake: stake, odds: odds)

        assertDecimalEqual(payout, Decimal(100), "Negative odds (-110) should return payout of 100 for stake of 110")
    }

    func testNegativeOddsPayout_HeavyFavorite() {
        // -200 odds: $200 bet wins $100
        let stake = Decimal(200)
        let odds = -200
        let payout = LiabilityService.calculatePayout(stake: stake, odds: odds)

        assertDecimalEqual(payout, Decimal(100), "Negative odds (-200) should return payout of 100 for stake of 200")
    }

    func testNegativeOddsPayout_SmallStake() {
        // -110 odds: $11 bet wins $10
        let stake = Decimal(11)
        let odds = -110
        let payout = LiabilityService.calculatePayout(stake: stake, odds: odds)

        assertDecimalEqual(payout, Decimal(10), "Negative odds (-110) should return payout of 10 for stake of 11")
    }

    func testNegativeOddsPayout_FractionalResult() {
        // -150 odds: $100 bet wins $66.67 (approximately)
        let stake = Decimal(100)
        let odds = -150
        let payout = LiabilityService.calculatePayout(stake: stake, odds: odds)

        // 100 * (100 / 150) = 66.666...
        let expected = Decimal(100) * (Decimal(100) / Decimal(150))
        XCTAssertEqual(payout, expected, "Negative odds (-150) should correctly calculate fractional payout")
    }

    // MARK: - Positive Odds Tests

    func testPositiveOddsPayout_Standard() {
        // +150 odds: $100 bet wins $150
        let stake = Decimal(100)
        let odds = 150
        let payout = LiabilityService.calculatePayout(stake: stake, odds: odds)

        assertDecimalEqual(payout, Decimal(150), "Positive odds (+150) should return payout of 150 for stake of 100")
    }

    func testPositiveOddsPayout_BigUnderdog() {
        // +300 odds: $100 bet wins $300
        let stake = Decimal(100)
        let odds = 300
        let payout = LiabilityService.calculatePayout(stake: stake, odds: odds)

        assertDecimalEqual(payout, Decimal(300), "Positive odds (+300) should return payout of 300 for stake of 100")
    }

    func testPositiveOddsPayout_SmallStake() {
        // +200 odds: $50 bet wins $100
        let stake = Decimal(50)
        let odds = 200
        let payout = LiabilityService.calculatePayout(stake: stake, odds: odds)

        assertDecimalEqual(payout, Decimal(100), "Positive odds (+200) should return payout of 100 for stake of 50")
    }

    func testPositiveOddsPayout_EvenMoney() {
        // +100 odds (even money): $100 bet wins $100
        let stake = Decimal(100)
        let odds = 100
        let payout = LiabilityService.calculatePayout(stake: stake, odds: odds)

        assertDecimalEqual(payout, Decimal(100), "Even money (+100) should return payout equal to stake")
    }

    // MARK: - Bet Liability Tests

    func testCalculateLiabilityForBet() {
        let bet = Bet(
            eventId: "event-1",
            market: "spread",
            side: "Team A",
            odds: -110,
            stake: Decimal(110),
            status: .pending
        )

        let liability = LiabilityService.calculateLiability(for: bet)
        assertDecimalEqual(liability, Decimal(100), "Liability for bet with -110 odds and $110 stake should be $100")
    }

    func testCalculateTotalLiability() {
        let bets = [
            Bet(eventId: "e1", market: "spread", side: "A", odds: -110, stake: Decimal(110), status: .pending),
            Bet(eventId: "e2", market: "moneyline", side: "B", odds: 150, stake: Decimal(100), status: .accepted)
        ]

        let totalLiability = LiabilityService.calculateTotalLiability(for: bets)
        // First bet: 110 * (100/110) = 100
        // Second bet: 100 * (150/100) = 150
        // Total: 250
        assertDecimalEqual(totalLiability, Decimal(250), "Total liability should be sum of individual liabilities")
    }

    // MARK: - Active Bets Filtering Tests

    func testActiveBetsFiltersPendingAndAccepted() {
        let bets = [
            Bet(eventId: "e1", market: "spread", side: "A", odds: -110, stake: Decimal(100), status: .pending),
            Bet(eventId: "e2", market: "spread", side: "B", odds: 110, stake: Decimal(100), status: .accepted),
            Bet(eventId: "e3", market: "spread", side: "A", odds: -110, stake: Decimal(100), status: .declined),
            Bet(eventId: "e4", market: "spread", side: "B", odds: 110, stake: Decimal(100), status: .settled),
            Bet(eventId: "e5", market: "spread", side: "A", odds: -110, stake: Decimal(100), status: .void),
            Bet(eventId: "e6", market: "spread", side: "B", odds: 110, stake: Decimal(100), status: .graded)
        ]

        let activeBets = LiabilityService.activeBets(from: bets)

        XCTAssertEqual(activeBets.count, 2, "Should only include pending and accepted bets")
        XCTAssertTrue(activeBets.allSatisfy { $0.status == .pending || $0.status == .accepted })
    }

    func testCalculateActiveLiability() {
        let bets = [
            Bet(eventId: "e1", market: "spread", side: "A", odds: -110, stake: Decimal(110), status: .pending),
            Bet(eventId: "e2", market: "moneyline", side: "B", odds: 150, stake: Decimal(100), status: .accepted),
            Bet(eventId: "e3", market: "spread", side: "A", odds: -110, stake: Decimal(220), status: .settled) // Should be excluded
        ]

        let activeLiability = LiabilityService.calculateActiveLiability(for: bets)
        // First bet (pending): 110 * (100/110) = 100
        // Second bet (accepted): 100 * (150/100) = 150
        // Third bet (settled): excluded
        // Total: 250
        assertDecimalEqual(activeLiability, Decimal(250), "Active liability should only include pending and accepted bets")
    }

    func testEmptyBetsArray() {
        let bets: [Bet] = []

        let totalLiability = LiabilityService.calculateTotalLiability(for: bets)
        let activeBets = LiabilityService.activeBets(from: bets)
        let activeLiability = LiabilityService.calculateActiveLiability(for: bets)

        XCTAssertEqual(totalLiability, Decimal.zero, "Total liability for empty array should be zero")
        XCTAssertEqual(activeBets.count, 0, "Active bets for empty array should be empty")
        XCTAssertEqual(activeLiability, Decimal.zero, "Active liability for empty array should be zero")
    }

    // MARK: - Edge Cases

    func testZeroStake() {
        let payout = LiabilityService.calculatePayout(stake: Decimal.zero, odds: -110)
        XCTAssertEqual(payout, Decimal.zero, "Zero stake should result in zero payout")
    }

    func testLargeOdds() {
        // +1000 odds: $100 bet wins $1000
        let stake = Decimal(100)
        let odds = 1000
        let payout = LiabilityService.calculatePayout(stake: stake, odds: odds)

        assertDecimalEqual(payout, Decimal(1000), "Large positive odds should calculate correctly")
    }

    func testLargeNegativeOdds() {
        // -1000 odds: $1000 bet wins $100
        let stake = Decimal(1000)
        let odds = -1000
        let payout = LiabilityService.calculatePayout(stake: stake, odds: odds)

        assertDecimalEqual(payout, Decimal(100), "Large negative odds should calculate correctly")
    }
}
