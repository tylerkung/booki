import XCTest
@testable import Booki

final class AcceptancePolicyServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makePolicy(
        autoAcceptMaxStake: Decimal = 1000,
        requireReviewAboveStake: Decimal = 5000,
        autoAcceptNewPlayers: Bool = true,
        newPlayerBetThreshold: Int = 5,
        autoAcceptParlays: Bool = true,
        parlayMaxLegs: Int = 10,
        eventLockOffsetMinutes: Int = 0
    ) -> AcceptancePolicy {
        AcceptancePolicy(
            autoAcceptMaxStake: autoAcceptMaxStake,
            requireReviewAboveStake: requireReviewAboveStake,
            autoAcceptNewPlayers: autoAcceptNewPlayers,
            newPlayerBetThreshold: newPlayerBetThreshold,
            autoAcceptParlays: autoAcceptParlays,
            parlayMaxLegs: parlayMaxLegs,
            eventLockOffsetMinutes: eventLockOffsetMinutes
        )
    }

    private func makeFutureEvent(minutesFromNow: Double = 60) -> Event {
        Event(
            sport: "Basketball",
            league: "NBA",
            homeTeam: "Lakers",
            awayTeam: "Celtics",
            startTime: Date().addingTimeInterval(minutesFromNow * 60),
            status: .scheduled
        )
    }

    private func makeLiveEvent() -> Event {
        Event(
            sport: "Basketball",
            league: "NBA",
            homeTeam: "Lakers",
            awayTeam: "Celtics",
            startTime: Date().addingTimeInterval(-1800), // started 30 min ago
            status: .live
        )
    }

    private func makeFinalEvent() -> Event {
        Event(
            sport: "Basketball",
            league: "NBA",
            homeTeam: "Lakers",
            awayTeam: "Celtics",
            startTime: Date().addingTimeInterval(-7200), // started 2 hours ago
            status: .final
        )
    }

    // MARK: - Clean Pass

    func testCleanPass_NoViolations() {
        let policy = makePolicy()
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: false, parlayLegs: 0,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertTrue(violations.isEmpty)
    }

    // MARK: - stakeTooHigh

    func testStakeTooHigh() {
        let policy = makePolicy(autoAcceptMaxStake: 100)
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 150, isParlay: false, parlayLegs: 0,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertTrue(violations.contains(.stakeTooHigh))
    }

    func testStakeAtLimit_NoViolation() {
        let policy = makePolicy(autoAcceptMaxStake: 100)
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 100, isParlay: false, parlayLegs: 0,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertFalse(violations.contains(.stakeTooHigh))
    }

    // MARK: - stakeRequiresReview

    func testStakeRequiresReview() {
        let policy = makePolicy(requireReviewAboveStake: 500)
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 600, isParlay: false, parlayLegs: 0,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertTrue(violations.contains(.stakeRequiresReview))
    }

    func testStakeAtReviewLimit_NoViolation() {
        let policy = makePolicy(requireReviewAboveStake: 500)
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 500, isParlay: false, parlayLegs: 0,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertFalse(violations.contains(.stakeRequiresReview))
    }

    // MARK: - newPlayer

    func testNewPlayer_RequiresReview() {
        let policy = makePolicy(autoAcceptNewPlayers: false, newPlayerBetThreshold: 5)
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: false, parlayLegs: 0,
            playerBetCount: 3, event: event, policy: policy
        )
        XCTAssertTrue(violations.contains(.newPlayer))
    }

    func testNewPlayer_AutoAcceptEnabled_NoViolation() {
        let policy = makePolicy(autoAcceptNewPlayers: true, newPlayerBetThreshold: 5)
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: false, parlayLegs: 0,
            playerBetCount: 1, event: event, policy: policy
        )
        XCTAssertFalse(violations.contains(.newPlayer))
    }

    func testEstablishedPlayer_NoViolation() {
        let policy = makePolicy(autoAcceptNewPlayers: false, newPlayerBetThreshold: 5)
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: false, parlayLegs: 0,
            playerBetCount: 5, event: event, policy: policy
        )
        XCTAssertFalse(violations.contains(.newPlayer))
    }

    // MARK: - parlayNotAllowed

    func testParlayNotAllowed() {
        let policy = makePolicy(autoAcceptParlays: false)
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: true, parlayLegs: 3,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertTrue(violations.contains(.parlayNotAllowed))
    }

    func testParlayAllowed_NoViolation() {
        let policy = makePolicy(autoAcceptParlays: true)
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: true, parlayLegs: 3,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertFalse(violations.contains(.parlayNotAllowed))
    }

    func testSingleBet_NoParlayViolation() {
        let policy = makePolicy(autoAcceptParlays: false)
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: false, parlayLegs: 0,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertFalse(violations.contains(.parlayNotAllowed))
    }

    // MARK: - parlayTooManyLegs

    func testParlayTooManyLegs() {
        let policy = makePolicy(parlayMaxLegs: 4)
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: true, parlayLegs: 6,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertTrue(violations.contains(.parlayTooManyLegs))
    }

    func testParlayAtMaxLegs_NoViolation() {
        let policy = makePolicy(parlayMaxLegs: 4)
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: true, parlayLegs: 4,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertFalse(violations.contains(.parlayTooManyLegs))
    }

    // MARK: - eventLocked

    func testEventLocked_LiveEvent() {
        let policy = makePolicy()
        let event = makeLiveEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: false, parlayLegs: 0,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertTrue(violations.contains(.eventLocked))
    }

    func testEventLocked_FinalEvent() {
        let policy = makePolicy()
        let event = makeFinalEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: false, parlayLegs: 0,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertTrue(violations.contains(.eventLocked))
    }

    func testEventLocked_WithinOffset() {
        // Event starts in 5 minutes, lock offset is 10 minutes
        let policy = makePolicy(eventLockOffsetMinutes: 10)
        let event = makeFutureEvent(minutesFromNow: 5)
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: false, parlayLegs: 0,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertTrue(violations.contains(.eventLocked))
    }

    func testEventNotLocked_OutsideOffset() {
        // Event starts in 60 minutes, lock offset is 10 minutes
        let policy = makePolicy(eventLockOffsetMinutes: 10)
        let event = makeFutureEvent(minutesFromNow: 60)
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 50, isParlay: false, parlayLegs: 0,
            playerBetCount: 10, event: event, policy: policy
        )
        XCTAssertFalse(violations.contains(.eventLocked))
    }

    // MARK: - Multiple Violations

    func testMultipleViolations() {
        let policy = makePolicy(
            autoAcceptMaxStake: 100,
            requireReviewAboveStake: 200,
            autoAcceptNewPlayers: false,
            newPlayerBetThreshold: 5,
            autoAcceptParlays: false,
            parlayMaxLegs: 2
        )
        let event = makeFutureEvent()
        let violations = AcceptancePolicyService.evaluateBet(
            stake: 300, isParlay: true, parlayLegs: 4,
            playerBetCount: 1, event: event, policy: policy
        )
        XCTAssertTrue(violations.contains(.stakeTooHigh))
        XCTAssertTrue(violations.contains(.stakeRequiresReview))
        XCTAssertTrue(violations.contains(.newPlayer))
        XCTAssertTrue(violations.contains(.parlayNotAllowed))
        XCTAssertTrue(violations.contains(.parlayTooManyLegs))
        XCTAssertEqual(violations.count, 5)
    }

    // MARK: - Violation Descriptions

    func testViolationDescription() {
        XCTAssertEqual(AcceptancePolicyService.violationDescription(.stakeTooHigh), "Stake exceeds auto-accept limit")
        XCTAssertEqual(AcceptancePolicyService.violationDescription(.stakeRequiresReview), "Stake requires manual review")
        XCTAssertEqual(AcceptancePolicyService.violationDescription(.newPlayer), "New player requires review")
        XCTAssertEqual(AcceptancePolicyService.violationDescription(.parlayNotAllowed), "Parlays require manual review")
        XCTAssertEqual(AcceptancePolicyService.violationDescription(.parlayTooManyLegs), "Parlay has too many legs")
        XCTAssertEqual(AcceptancePolicyService.violationDescription(.eventLocked), "Event is locked for betting")
    }

    func testCombinedViolationDescription() {
        let violations: [PolicyViolation] = [.stakeTooHigh, .newPlayer]
        let combined = AcceptancePolicyService.combinedViolationDescription(violations)
        XCTAssertEqual(combined, "Stake exceeds auto-accept limit, New player requires review")
    }

    func testCombinedViolationDescription_Empty() {
        let combined = AcceptancePolicyService.combinedViolationDescription([])
        XCTAssertEqual(combined, "")
    }
}
