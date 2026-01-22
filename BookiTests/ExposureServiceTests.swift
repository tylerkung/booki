import XCTest
@testable import Booki

final class ExposureServiceTests: XCTestCase {

    // MARK: - Helper for Decimal comparison with tolerance

    func assertDecimalEqual(_ actual: Decimal, _ expected: Decimal, accuracy: Decimal = Decimal(string: "0.01")!, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        let difference = abs(actual - expected)
        XCTAssertTrue(difference < accuracy, "\(message) - Expected \(expected), got \(actual) (difference: \(difference))", file: file, line: line)
    }

    // MARK: - Exposure Bets Filtering Tests

    func testExposureBetsFiltersPendingAndAccepted() {
        let bets = [
            Bet(eventId: "e1", market: "spread", side: "A", odds: -110, stake: Decimal(100), status: .pending),
            Bet(eventId: "e2", market: "spread", side: "B", odds: 110, stake: Decimal(100), status: .accepted),
            Bet(eventId: "e3", market: "spread", side: "A", odds: -110, stake: Decimal(100), status: .declined),
            Bet(eventId: "e4", market: "spread", side: "B", odds: 110, stake: Decimal(100), status: .settled),
            Bet(eventId: "e5", market: "spread", side: "A", odds: -110, stake: Decimal(100), status: .void),
            Bet(eventId: "e6", market: "spread", side: "B", odds: 110, stake: Decimal(100), status: .graded),
            Bet(eventId: "e7", market: "spread", side: "A", odds: -110, stake: Decimal(100), status: .readyToGrade)
        ]

        let exposureBets = ExposureService.exposureBets(from: bets)

        XCTAssertEqual(exposureBets.count, 2, "Should only include pending and accepted bets")
        XCTAssertTrue(exposureBets.allSatisfy { $0.status == .pending || $0.status == .accepted })
    }

    func testExposureBetsWithEmptyArray() {
        let bets: [Bet] = []
        let exposureBets = ExposureService.exposureBets(from: bets)
        XCTAssertEqual(exposureBets.count, 0, "Empty input should return empty array")
    }

    // MARK: - Group Bets By Event Tests

    func testGroupBetsByEvent() {
        let bets = [
            Bet(eventId: "event-1", market: "spread", side: "A", odds: -110, stake: Decimal(100), status: .pending),
            Bet(eventId: "event-1", market: "moneyline", side: "B", odds: 150, stake: Decimal(50), status: .accepted),
            Bet(eventId: "event-2", market: "total", side: "over", odds: -110, stake: Decimal(110), status: .pending)
        ]

        let grouped = ExposureService.groupBetsByEvent(bets)

        XCTAssertEqual(grouped.count, 2, "Should have 2 event groups")
        XCTAssertEqual(grouped["event-1"]?.count, 2, "Event 1 should have 2 bets")
        XCTAssertEqual(grouped["event-2"]?.count, 1, "Event 2 should have 1 bet")
    }

    // MARK: - Event Exposure Calculation Tests

    func testCalculateEventExposureSingleSide() {
        // Single side with both pending and accepted bets
        let bets = [
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: -110, stake: Decimal(110), status: .pending),
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: -110, stake: Decimal(110), status: .accepted)
        ]

        let exposure = ExposureService.calculateEventExposure(eventId: "e1", bets: bets)

        XCTAssertEqual(exposure.eventId, "e1")
        XCTAssertEqual(exposure.sides.count, 1, "Should have 1 side")

        let teamASide = exposure.sides.first!
        // Each bet: 110 * (100/110) = 100 liability
        assertDecimalEqual(teamASide.softExposure, Decimal(100), "Soft exposure should be 100")
        assertDecimalEqual(teamASide.hardExposure, Decimal(100), "Hard exposure should be 100")
        assertDecimalEqual(teamASide.totalExposure, Decimal(200), "Total exposure should be 200")
        assertDecimalEqual(exposure.maxExposure, Decimal(200), "Max exposure should be 200")
    }

    func testCalculateEventExposureTwoSides() {
        // Two sides for the same event
        let bets = [
            // Team A: pending bet with -110 odds, $110 stake = $100 liability
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: -110, stake: Decimal(110), status: .pending),
            // Team A: accepted bet with -110 odds, $220 stake = $200 liability
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: -110, stake: Decimal(220), status: .accepted),
            // Team B: accepted bet with +150 odds, $100 stake = $150 liability
            Bet(eventId: "e1", market: "spread", side: "Team B", odds: 150, stake: Decimal(100), status: .accepted)
        ]

        let exposure = ExposureService.calculateEventExposure(eventId: "e1", bets: bets)

        XCTAssertEqual(exposure.sides.count, 2, "Should have 2 sides")

        // Team A: soft=100, hard=200, total=300
        // Team B: soft=0, hard=150, total=150
        // Max exposure = 300 (Team A)
        assertDecimalEqual(exposure.maxExposure, Decimal(300), "Max exposure should be Team A's 300")
    }

    func testCalculateEventExposureSoftVsHard() {
        let bets = [
            // Only pending bets for Team A
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: 100, stake: Decimal(100), status: .pending),
            // Only accepted bets for Team B
            Bet(eventId: "e1", market: "spread", side: "Team B", odds: 100, stake: Decimal(100), status: .accepted)
        ]

        let exposure = ExposureService.calculateEventExposure(eventId: "e1", bets: bets)

        // Find Team A side
        let teamA = exposure.sides.first { $0.side == "Team A" }!
        let teamB = exposure.sides.first { $0.side == "Team B" }!

        assertDecimalEqual(teamA.softExposure, Decimal(100), "Team A soft exposure")
        assertDecimalEqual(teamA.hardExposure, Decimal.zero, "Team A hard exposure")

        assertDecimalEqual(teamB.softExposure, Decimal.zero, "Team B soft exposure")
        assertDecimalEqual(teamB.hardExposure, Decimal(100), "Team B hard exposure")

        assertDecimalEqual(exposure.maxSoftExposure, Decimal(100), "Max soft should be 100")
        assertDecimalEqual(exposure.maxHardExposure, Decimal(100), "Max hard should be 100")
    }

    // MARK: - All Event Exposures Tests

    func testCalculateAllEventExposures() {
        let bets = [
            // Event 1: Team A with $100 liability
            Bet(eventId: "event-1", market: "spread", side: "Team A", odds: -110, stake: Decimal(110), status: .accepted),
            // Event 1: Team B with $150 liability
            Bet(eventId: "event-1", market: "spread", side: "Team B", odds: 150, stake: Decimal(100), status: .accepted),
            // Event 2: Over with $100 liability
            Bet(eventId: "event-2", market: "total", side: "Over", odds: -110, stake: Decimal(110), status: .pending),
            // Event 2: Under with $200 liability
            Bet(eventId: "event-2", market: "total", side: "Under", odds: 200, stake: Decimal(100), status: .accepted),
            // Settled bet - should be excluded
            Bet(eventId: "event-1", market: "spread", side: "Team A", odds: -110, stake: Decimal(1000), status: .settled)
        ]

        let exposures = ExposureService.calculateAllEventExposures(from: bets)

        XCTAssertEqual(exposures.count, 2, "Should have 2 events")

        // Event 1: max(Team A=100, Team B=150) = 150
        // Event 2: max(Over=100, Under=200) = 200
        let event1 = exposures.first { $0.eventId == "event-1" }!
        let event2 = exposures.first { $0.eventId == "event-2" }!

        assertDecimalEqual(event1.maxExposure, Decimal(150), "Event 1 max exposure should be 150")
        assertDecimalEqual(event2.maxExposure, Decimal(200), "Event 2 max exposure should be 200")
    }

    func testCalculateAllEventExposuresExcludesInactiveBets() {
        let bets = [
            Bet(eventId: "e1", market: "spread", side: "A", odds: -110, stake: Decimal(110), status: .declined),
            Bet(eventId: "e2", market: "spread", side: "A", odds: -110, stake: Decimal(110), status: .void),
            Bet(eventId: "e3", market: "spread", side: "A", odds: -110, stake: Decimal(110), status: .settled),
            Bet(eventId: "e4", market: "spread", side: "A", odds: -110, stake: Decimal(110), status: .graded),
            Bet(eventId: "e5", market: "spread", side: "A", odds: -110, stake: Decimal(110), status: .readyToGrade)
        ]

        let exposures = ExposureService.calculateAllEventExposures(from: bets)

        XCTAssertEqual(exposures.count, 0, "Should have no events - all bets are inactive")
    }

    // MARK: - Total Exposure Tests

    func testCalculateTotalExposure() {
        let bets = [
            // Event 1: max exposure is Team B with $200 liability
            Bet(eventId: "event-1", market: "spread", side: "Team A", odds: -110, stake: Decimal(110), status: .accepted),
            Bet(eventId: "event-1", market: "spread", side: "Team B", odds: 200, stake: Decimal(100), status: .accepted),
            // Event 2: max exposure is Over with $300 liability
            Bet(eventId: "event-2", market: "total", side: "Over", odds: 300, stake: Decimal(100), status: .pending),
            Bet(eventId: "event-2", market: "total", side: "Under", odds: 100, stake: Decimal(50), status: .accepted)
        ]

        let totalExposure = ExposureService.calculateTotalExposure(from: bets)

        // Event 1: Team A = 100, Team B = 200, max = 200
        // Event 2: Over = 300, Under = 50, max = 300
        // Total = 200 + 300 = 500
        assertDecimalEqual(totalExposure, Decimal(500), "Total exposure should be 500")
    }

    func testCalculateTotalExposureEmptyBets() {
        let bets: [Bet] = []
        let totalExposure = ExposureService.calculateTotalExposure(from: bets)
        XCTAssertEqual(totalExposure, Decimal.zero, "Empty bets should have zero total exposure")
    }

    // MARK: - Single Event Exposure Query Tests

    func testCalculateExposureForSpecificEvent() {
        let bets = [
            Bet(eventId: "event-1", market: "spread", side: "A", odds: -110, stake: Decimal(110), status: .accepted),
            Bet(eventId: "event-2", market: "total", side: "Over", odds: 200, stake: Decimal(100), status: .pending)
        ]

        let event1Exposure = ExposureService.calculateExposure(forEvent: "event-1", from: bets)
        let event2Exposure = ExposureService.calculateExposure(forEvent: "event-2", from: bets)

        XCTAssertNotNil(event1Exposure, "Event 1 should have exposure")
        XCTAssertNotNil(event2Exposure, "Event 2 should have exposure")

        assertDecimalEqual(event1Exposure!.maxExposure, Decimal(100), "Event 1 exposure")
        assertDecimalEqual(event2Exposure!.maxExposure, Decimal(200), "Event 2 exposure")
    }

    func testCalculateExposureForNonexistentEvent() {
        let bets = [
            Bet(eventId: "event-1", market: "spread", side: "A", odds: -110, stake: Decimal(110), status: .accepted)
        ]

        let exposure = ExposureService.calculateExposure(forEvent: "event-999", from: bets)

        XCTAssertNil(exposure, "Nonexistent event should return nil")
    }

    func testCalculateExposureForEventWithOnlyInactiveBets() {
        let bets = [
            Bet(eventId: "event-1", market: "spread", side: "A", odds: -110, stake: Decimal(110), status: .settled),
            Bet(eventId: "event-1", market: "spread", side: "B", odds: 150, stake: Decimal(100), status: .void)
        ]

        let exposure = ExposureService.calculateExposure(forEvent: "event-1", from: bets)

        XCTAssertNil(exposure, "Event with only inactive bets should return nil")
    }

    // MARK: - Edge Cases

    func testExposureWithManyBetsSameSide() {
        // Multiple bets on same side should sum up
        let bets = [
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: 100, stake: Decimal(100), status: .accepted),
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: 100, stake: Decimal(100), status: .accepted),
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: 100, stake: Decimal(100), status: .accepted)
        ]

        let exposure = ExposureService.calculateEventExposure(eventId: "e1", bets: bets)

        // 3 bets @ $100 liability each = $300 total
        assertDecimalEqual(exposure.maxExposure, Decimal(300), "Multiple bets on same side should sum")
    }

    func testExposureWithZeroStakeBets() {
        let bets = [
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: -110, stake: Decimal.zero, status: .accepted)
        ]

        let exposure = ExposureService.calculateEventExposure(eventId: "e1", bets: bets)

        assertDecimalEqual(exposure.maxExposure, Decimal.zero, "Zero stake bet should have zero exposure")
    }

    func testEventExposureMaxWithUnbalancedSides() {
        // Scenario: Heavy action on one side
        let bets = [
            // Team A: $500 total liability (5 bets @ $100 each)
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: 100, stake: Decimal(100), status: .accepted),
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: 100, stake: Decimal(100), status: .accepted),
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: 100, stake: Decimal(100), status: .accepted),
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: 100, stake: Decimal(100), status: .accepted),
            Bet(eventId: "e1", market: "spread", side: "Team A", odds: 100, stake: Decimal(100), status: .accepted),
            // Team B: $50 total liability
            Bet(eventId: "e1", market: "spread", side: "Team B", odds: 100, stake: Decimal(50), status: .accepted)
        ]

        let exposure = ExposureService.calculateEventExposure(eventId: "e1", bets: bets)

        // Event exposure is the max of sides = Team A's $500
        assertDecimalEqual(exposure.maxExposure, Decimal(500), "Max exposure should be the higher side")

        let teamA = exposure.sides.first { $0.side == "Team A" }!
        let teamB = exposure.sides.first { $0.side == "Team B" }!

        assertDecimalEqual(teamA.totalExposure, Decimal(500))
        assertDecimalEqual(teamB.totalExposure, Decimal(50))
    }
}
