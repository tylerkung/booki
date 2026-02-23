import XCTest
@testable import Booki

final class ParlayGradingServiceTests: XCTestCase {

    // MARK: - Helpers

    func assertDecimalEqual(_ actual: Decimal, _ expected: Decimal, accuracy: Decimal = Decimal(string: "0.01")!, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        let difference = abs(actual - expected)
        XCTAssertTrue(difference < accuracy, "\(message) - Expected \(expected), got \(actual) (difference: \(difference))", file: file, line: line)
    }

    private func makeBet(odds: Int, stake: Decimal = 100, status: BetStatus = .accepted, gradeResult: GradeResult? = nil, ticketId: UUID = UUID()) -> Bet {
        Bet(
            eventId: "event-1",
            market: "moneyline",
            side: "Team A",
            odds: odds,
            stake: stake,
            status: status,
            gradeResult: gradeResult,
            ticketId: ticketId
        )
    }

    // MARK: - americanToDecimal

    func testAmericanToDecimal_PositiveOdds() {
        // +150 → 2.5
        let result = ParlayGradingService.americanToDecimal(odds: 150)
        assertDecimalEqual(result, Decimal(string: "2.5")!)
    }

    func testAmericanToDecimal_NegativeOdds() {
        // -110 → 1 + 100/110 = 1.909...
        let result = ParlayGradingService.americanToDecimal(odds: -110)
        assertDecimalEqual(result, Decimal(string: "1.909")!, accuracy: Decimal(string: "0.001")!)
    }

    func testAmericanToDecimal_EvenMoney() {
        // +100 → 2.0
        let result = ParlayGradingService.americanToDecimal(odds: 100)
        assertDecimalEqual(result, Decimal(2))
    }

    func testAmericanToDecimal_Zero() {
        // 0 → 1 + 0/100 = 1.0 (edge: positive branch since >= 0)
        let result = ParlayGradingService.americanToDecimal(odds: 0)
        assertDecimalEqual(result, Decimal(1))
    }

    func testAmericanToDecimal_LargePositive() {
        // +1000 → 11.0
        let result = ParlayGradingService.americanToDecimal(odds: 1000)
        assertDecimalEqual(result, Decimal(11))
    }

    func testAmericanToDecimal_LargeNegative() {
        // -200 → 1 + 100/200 = 1.5
        let result = ParlayGradingService.americanToDecimal(odds: -200)
        assertDecimalEqual(result, Decimal(string: "1.5")!)
    }

    // MARK: - calculateParlayPayout

    func testParlayPayout_TwoLegs() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: -110, stake: 100, ticketId: ticketId),
            makeBet(odds: 150, stake: 100, ticketId: ticketId)
        ]
        // Decimal odds: 1.909... × 2.5 = 4.772...
        // Profit: 100 × 4.772... - 100 = 377.27...
        let payout = ParlayGradingService.calculateParlayPayout(stake: 100, bets: bets, excludeVoidPush: false)
        let leg1 = ParlayGradingService.americanToDecimal(odds: -110)
        let leg2 = ParlayGradingService.americanToDecimal(odds: 150)
        let expected = Decimal(100) * leg1 * leg2 - Decimal(100)
        assertDecimalEqual(payout, expected)
    }

    func testParlayPayout_ThreeLegs() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: -110, stake: 50, ticketId: ticketId),
            makeBet(odds: 100, stake: 50, ticketId: ticketId),
            makeBet(odds: 200, stake: 50, ticketId: ticketId)
        ]
        let leg1 = ParlayGradingService.americanToDecimal(odds: -110)
        let leg2 = ParlayGradingService.americanToDecimal(odds: 100)
        let leg3 = ParlayGradingService.americanToDecimal(odds: 200)
        let expected = Decimal(50) * leg1 * leg2 * leg3 - Decimal(50)
        let payout = ParlayGradingService.calculateParlayPayout(stake: 50, bets: bets, excludeVoidPush: false)
        assertDecimalEqual(payout, expected)
    }

    func testParlayPayout_EmptyLegs() {
        let payout = ParlayGradingService.calculateParlayPayout(stake: 100, bets: [], excludeVoidPush: false)
        XCTAssertEqual(payout, Decimal.zero)
    }

    func testParlayPayout_ExcludeVoidPush() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: 150, stake: 100, gradeResult: .win, ticketId: ticketId),
            makeBet(odds: -110, stake: 100, gradeResult: .push, ticketId: ticketId),
            makeBet(odds: 200, stake: 100, status: .void, ticketId: ticketId)
        ]
        // Only the +150 leg should count
        let payout = ParlayGradingService.calculateParlayPayout(stake: 100, bets: bets, excludeVoidPush: true)
        let expected = Decimal(100) * ParlayGradingService.americanToDecimal(odds: 150) - Decimal(100)
        assertDecimalEqual(payout, expected)
    }

    // MARK: - calculateParlayOutcome

    func testOutcome_AllWins() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: -110, stake: 100, gradeResult: .win, ticketId: ticketId),
            makeBet(odds: 150, stake: 100, gradeResult: .win, ticketId: ticketId)
        ]
        let outcome = ParlayGradingService.calculateParlayOutcome(bets: bets, policy: .reduceLegReprice)
        if case .win(let payout) = outcome {
            let leg1 = ParlayGradingService.americanToDecimal(odds: -110)
            let leg2 = ParlayGradingService.americanToDecimal(odds: 150)
            let expected = Decimal(100) * leg1 * leg2 - Decimal(100)
            assertDecimalEqual(payout, expected)
        } else {
            XCTFail("Expected .win, got \(outcome)")
        }
    }

    func testOutcome_AnyLoss() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: -110, stake: 100, gradeResult: .win, ticketId: ticketId),
            makeBet(odds: 150, stake: 100, gradeResult: .loss, ticketId: ticketId)
        ]
        let outcome = ParlayGradingService.calculateParlayOutcome(bets: bets, policy: .reduceLegReprice)
        XCTAssertEqual(outcome, .loss)
    }

    func testOutcome_AllPending() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: -110, stake: 100, ticketId: ticketId),
            makeBet(odds: 150, stake: 100, ticketId: ticketId)
        ]
        let outcome = ParlayGradingService.calculateParlayOutcome(bets: bets, policy: .reduceLegReprice)
        XCTAssertEqual(outcome, .pending)
    }

    func testOutcome_PartiallyGraded() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: -110, stake: 100, gradeResult: .win, ticketId: ticketId),
            makeBet(odds: 150, stake: 100, ticketId: ticketId) // pending (no gradeResult)
        ]
        let outcome = ParlayGradingService.calculateParlayOutcome(bets: bets, policy: .reduceLegReprice)
        XCTAssertEqual(outcome, .partiallyGraded(gradedCount: 1, totalCount: 2))
    }

    func testOutcome_LossShortCircuitsPending() {
        // Even with pending legs, a loss is still a loss
        let ticketId = UUID()
        let bets = [
            makeBet(odds: -110, stake: 100, gradeResult: .loss, ticketId: ticketId),
            makeBet(odds: 150, stake: 100, ticketId: ticketId)
        ]
        let outcome = ParlayGradingService.calculateParlayOutcome(bets: bets, policy: .reduceLegReprice)
        XCTAssertEqual(outcome, .loss)
    }

    func testOutcome_PushWithTreatAsPush() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: -110, stake: 100, gradeResult: .win, ticketId: ticketId),
            makeBet(odds: 150, stake: 100, gradeResult: .push, ticketId: ticketId)
        ]
        let outcome = ParlayGradingService.calculateParlayOutcome(bets: bets, policy: .treatAsPush)
        XCTAssertEqual(outcome, .push)
    }

    func testOutcome_PushWithReduceLegReprice() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: -110, stake: 100, gradeResult: .win, ticketId: ticketId),
            makeBet(odds: 150, stake: 100, gradeResult: .push, ticketId: ticketId)
        ]
        let outcome = ParlayGradingService.calculateParlayOutcome(bets: bets, policy: .reduceLegReprice)
        // Push leg removed, only -110 leg remains
        if case .win(let payout) = outcome {
            let expected = Decimal(100) * ParlayGradingService.americanToDecimal(odds: -110) - Decimal(100)
            assertDecimalEqual(payout, expected)
        } else {
            XCTFail("Expected .win with repriced payout, got \(outcome)")
        }
    }

    func testOutcome_VoidWithTreatAsPush() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: -110, stake: 100, gradeResult: .win, ticketId: ticketId),
            makeBet(odds: 150, stake: 100, status: .void, ticketId: ticketId)
        ]
        let outcome = ParlayGradingService.calculateParlayOutcome(bets: bets, policy: .treatAsPush)
        XCTAssertEqual(outcome, .push)
    }

    func testOutcome_VoidWithReduceLegReprice() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: 200, stake: 100, gradeResult: .win, ticketId: ticketId),
            makeBet(odds: -110, stake: 100, status: .void, ticketId: ticketId)
        ]
        let outcome = ParlayGradingService.calculateParlayOutcome(bets: bets, policy: .reduceLegReprice)
        if case .win(let payout) = outcome {
            let expected = Decimal(100) * ParlayGradingService.americanToDecimal(odds: 200) - Decimal(100)
            assertDecimalEqual(payout, expected)
        } else {
            XCTFail("Expected .win with repriced payout, got \(outcome)")
        }
    }

    func testOutcome_AllLegsVoid_Push() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: -110, stake: 100, status: .void, ticketId: ticketId),
            makeBet(odds: 150, stake: 100, status: .void, ticketId: ticketId)
        ]
        // Both policies should return push when all legs void
        let outcome1 = ParlayGradingService.calculateParlayOutcome(bets: bets, policy: .reduceLegReprice)
        XCTAssertEqual(outcome1, .push)

        let outcome2 = ParlayGradingService.calculateParlayOutcome(bets: bets, policy: .treatAsPush)
        XCTAssertEqual(outcome2, .push)
    }

    func testOutcome_AllLegsPush_Push() {
        let ticketId = UUID()
        let bets = [
            makeBet(odds: -110, stake: 100, gradeResult: .push, ticketId: ticketId),
            makeBet(odds: 150, stake: 100, gradeResult: .push, ticketId: ticketId)
        ]
        let outcome = ParlayGradingService.calculateParlayOutcome(bets: bets, policy: .reduceLegReprice)
        XCTAssertEqual(outcome, .push)
    }

    func testOutcome_EmptyBets() {
        let outcome = ParlayGradingService.calculateParlayOutcome(bets: [], policy: .reduceLegReprice)
        XCTAssertEqual(outcome, .pending)
    }
}
