import XCTest
@testable import TallystitchCore

// The aggregation was extracted from DashboardViewModel precisely so it
// could be pinned down here. These cases match the ViewModel's previous
// behavior exactly — grouping, the "Unknown" fallback, and revenue-desc
// ordering — so the extraction is provably behavior-preserving.
final class DashboardMathTests: XCTestCase {

    func testEmptyInputIsZero() {
        let s = DashboardMath.aggregate([])
        XCTAssertEqual(s.revenue, 0)
        XCTAssertTrue(s.byProduct.isEmpty)
    }

    func testSingleLine() {
        let s = DashboardMath.aggregate([
            .init(productName: "Candle", quantity: 3, unitSalePrice: 22),
        ])
        XCTAssertEqual(s.revenue, 66, accuracy: 1e-9)
        XCTAssertEqual(s.byProduct, [.init(name: "Candle", units: 3, revenue: 66)])
    }

    func testGroupsByProductAcrossOrders() {
        // Two separate orders both selling candles must merge into one row.
        let s = DashboardMath.aggregate([
            .init(productName: "Candle", quantity: 2, unitSalePrice: 22),
            .init(productName: "Soap", quantity: 1, unitSalePrice: 9.5),
            .init(productName: "Candle", quantity: 1, unitSalePrice: 22),
        ])
        XCTAssertEqual(s.revenue, 2 * 22 + 9.5 + 22, accuracy: 1e-9)
        XCTAssertEqual(s.byProduct.count, 2)
        XCTAssertEqual(s.byProduct[0], .init(name: "Candle", units: 3, revenue: 66))
    }

    func testNilProductNameGroupsUnderUnknownAndKeepsRevenue() {
        // A deleted/unreadable product must not silently drop revenue.
        let s = DashboardMath.aggregate([
            .init(productName: nil, quantity: 2, unitSalePrice: 10),
            .init(productName: nil, quantity: 1, unitSalePrice: 10),
        ])
        XCTAssertEqual(s.revenue, 30, accuracy: 1e-9)
        XCTAssertEqual(s.byProduct, [.init(name: "Unknown", units: 3, revenue: 30)])
    }

    func testSortedByRevenueDescending() {
        let s = DashboardMath.aggregate([
            .init(productName: "Small", quantity: 1, unitSalePrice: 5),
            .init(productName: "Big", quantity: 1, unitSalePrice: 100),
            .init(productName: "Mid", quantity: 2, unitSalePrice: 20),
        ])
        XCTAssertEqual(s.byProduct.map(\.name), ["Big", "Mid", "Small"])
    }

    func testZeroQuantityLineContributesNothingButStillGroups() {
        let s = DashboardMath.aggregate([
            .init(productName: "Candle", quantity: 0, unitSalePrice: 22),
        ])
        XCTAssertEqual(s.revenue, 0)
        XCTAssertEqual(s.byProduct, [.init(name: "Candle", units: 0, revenue: 0)])
    }
}
