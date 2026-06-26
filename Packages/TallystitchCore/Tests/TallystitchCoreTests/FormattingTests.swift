import XCTest
@testable import TallystitchCore

// Why: assert the pure number/percent logic (locale-independent). Currency
// strings are locale-dependent, so we only sanity-check that formatting
// produces a non-empty string containing the digits — not an exact match.
final class FormattingTests: XCTestCase {

    func testQtyDropsTrailingZerosForWholeNumbers() {
        XCTAssertEqual(Formatting.qty(3.0), "3")
        XCTAssertEqual(Formatting.qty(10.0), "10")
    }

    func testQtyKeepsFractions() {
        XCTAssertEqual(Formatting.qty(2.5), "2.50")
        XCTAssertEqual(Formatting.qty(0.5), "0.50")
    }

    func testQtyNilIsDash() {
        XCTAssertEqual(Formatting.qty(nil), "—")
    }

    func testPercent() {
        XCTAssertEqual(Formatting.percent(0.75), "75.0%")
        XCTAssertEqual(Formatting.percent(0.333), "33.3%")
        XCTAssertEqual(Formatting.percent(nil), "—")
    }

    func testCurrencyProducesStringWithDigits() {
        let s = Formatting.currency(12.5, code: "USD")
        XCTAssertTrue(s.contains("12"))
        XCTAssertNotEqual(s, "—")
    }

    func testCurrencyNilIsDash() {
        XCTAssertEqual(Formatting.currency(nil), "—")
    }
}
