import XCTest
@testable import Booki

final class PickPresenterTests: XCTestCase {

    // MARK: - Helpers

    func assertDecimalEqual(_ actual: Decimal, _ expected: Decimal, accuracy: Decimal = Decimal(string: "0.01")!, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        let difference = abs(actual - expected)
        XCTAssertTrue(difference < accuracy, "\(message) - Expected \(expected), got \(actual) (difference: \(difference))", file: file, line: line)
    }

    // MARK: - formatOdds

    func testFormatOdds_Positive() {
        XCTAssertEqual(PickPresenter.formatOdds(150), "+150")
    }

    func testFormatOdds_Negative() {
        XCTAssertEqual(PickPresenter.formatOdds(-110), "-110")
    }

    func testFormatOdds_Zero() {
        // 0 is not > 0, so no "+" prefix
        XCTAssertEqual(PickPresenter.formatOdds(0), "0")
    }

    func testFormatOdds_EvenMoney() {
        XCTAssertEqual(PickPresenter.formatOdds(100), "+100")
    }

    // MARK: - americanToDecimal

    func testAmericanToDecimal_Positive() {
        // +150 → 2.5
        let result = PickPresenter.americanToDecimal(150)
        assertDecimalEqual(result, Decimal(string: "2.5")!)
    }

    func testAmericanToDecimal_Negative() {
        // -200 → 1.5
        let result = PickPresenter.americanToDecimal(-200)
        assertDecimalEqual(result, Decimal(string: "1.5")!)
    }

    func testAmericanToDecimal_EvenMoney() {
        // +100 → 2.0
        let result = PickPresenter.americanToDecimal(100)
        assertDecimalEqual(result, Decimal(2))
    }

    func testAmericanToDecimal_Zero() {
        // 0 → 1.0 (safety: treated as even money)
        let result = PickPresenter.americanToDecimal(0)
        assertDecimalEqual(result, Decimal(1))
    }

    // MARK: - decimalToAmerican

    func testDecimalToAmerican_Positive() {
        // 2.5 → +150
        let result = PickPresenter.decimalToAmerican(Decimal(string: "2.5")!)
        XCTAssertEqual(result, 150)
    }

    func testDecimalToAmerican_Negative() {
        // 1.5 → -200
        let result = PickPresenter.decimalToAmerican(Decimal(string: "1.5")!)
        XCTAssertEqual(result, -200)
    }

    func testDecimalToAmerican_EvenMoney() {
        // 2.0 → +100
        let result = PickPresenter.decimalToAmerican(Decimal(2))
        XCTAssertEqual(result, 100)
    }

    func testDecimalToAmerican_BelowOne() {
        // < 1 → 0 (edge case)
        let result = PickPresenter.decimalToAmerican(Decimal(string: "0.5")!)
        XCTAssertEqual(result, 0)
    }

    // MARK: - Round-trip accuracy

    func testRoundTrip_PositiveOdds() {
        let original = 250
        let decimal = PickPresenter.americanToDecimal(original)
        let roundTripped = PickPresenter.decimalToAmerican(decimal)
        XCTAssertEqual(roundTripped, original)
    }

    func testRoundTrip_NegativeOdds() {
        let original = -200
        let decimal = PickPresenter.americanToDecimal(original)
        let roundTripped = PickPresenter.decimalToAmerican(decimal)
        XCTAssertEqual(roundTripped, original)
    }

    func testRoundTrip_EvenMoney() {
        let original = 100
        let decimal = PickPresenter.americanToDecimal(original)
        let roundTripped = PickPresenter.decimalToAmerican(decimal)
        XCTAssertEqual(roundTripped, original)
    }

    // MARK: - formatDecimal

    func testFormatDecimal_WholeNumber() {
        let result = PickPresenter.formatDecimal(Decimal(100))
        XCTAssertEqual(result, "100.00")
    }

    func testFormatDecimal_TwoDecimals() {
        let result = PickPresenter.formatDecimal(Decimal(string: "49.99")!)
        XCTAssertEqual(result, "49.99")
    }

    func testFormatDecimal_Zero() {
        let result = PickPresenter.formatDecimal(Decimal.zero)
        XCTAssertEqual(result, "0.00")
    }

    func testFormatDecimal_LargeNumber() {
        let result = PickPresenter.formatDecimal(Decimal(12345))
        XCTAssertEqual(result, "12345.00")
    }

    // MARK: - mapStatus

    func testMapStatus_Pending() {
        let (settlement, workflow) = PickPresenter.mapStatus(betStatus: .pending, gradeResult: nil)
        XCTAssertEqual(settlement, .open)
        XCTAssertEqual(workflow, .pending)
    }

    func testMapStatus_Accepted() {
        let (settlement, workflow) = PickPresenter.mapStatus(betStatus: .accepted, gradeResult: nil)
        XCTAssertEqual(settlement, .open)
        XCTAssertEqual(workflow, .approved)
    }

    func testMapStatus_ReadyToGrade() {
        let (settlement, workflow) = PickPresenter.mapStatus(betStatus: .readyToGrade, gradeResult: nil)
        XCTAssertEqual(settlement, .open)
        XCTAssertEqual(workflow, .approved)
    }

    func testMapStatus_Declined() {
        let (settlement, workflow) = PickPresenter.mapStatus(betStatus: .declined, gradeResult: nil)
        XCTAssertEqual(settlement, .open)
        XCTAssertEqual(workflow, .rejected)
    }

    func testMapStatus_Void() {
        let (settlement, workflow) = PickPresenter.mapStatus(betStatus: .void, gradeResult: nil)
        XCTAssertEqual(settlement, .void)
        XCTAssertEqual(workflow, .approved)
    }

    func testMapStatus_GradedWin() {
        let (settlement, workflow) = PickPresenter.mapStatus(betStatus: .graded, gradeResult: .win)
        XCTAssertEqual(settlement, .won)
        XCTAssertEqual(workflow, .approved)
    }

    func testMapStatus_GradedLoss() {
        let (settlement, workflow) = PickPresenter.mapStatus(betStatus: .graded, gradeResult: .loss)
        XCTAssertEqual(settlement, .lost)
        XCTAssertEqual(workflow, .approved)
    }

    func testMapStatus_GradedPush() {
        let (settlement, workflow) = PickPresenter.mapStatus(betStatus: .graded, gradeResult: .push)
        XCTAssertEqual(settlement, .push)
        XCTAssertEqual(workflow, .approved)
    }

    func testMapStatus_SettledWin() {
        let (settlement, workflow) = PickPresenter.mapStatus(betStatus: .settled, gradeResult: .win)
        XCTAssertEqual(settlement, .won)
        XCTAssertEqual(workflow, .approved)
    }

    func testMapStatus_SettledLoss() {
        let (settlement, workflow) = PickPresenter.mapStatus(betStatus: .settled, gradeResult: .loss)
        XCTAssertEqual(settlement, .lost)
        XCTAssertEqual(workflow, .approved)
    }

    func testMapStatus_GradedNoResult() {
        // Graded but no gradeResult → open/approved (shouldn't happen but handle gracefully)
        let (settlement, workflow) = PickPresenter.mapStatus(betStatus: .graded, gradeResult: nil)
        XCTAssertEqual(settlement, .open)
        XCTAssertEqual(workflow, .approved)
    }
}
