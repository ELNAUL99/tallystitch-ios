import XCTest
@testable import TallystitchCore

// Port of the web's src/lib/stock.test.ts — the core correctness risk of the
// whole product. Both implementations (SQL trigger, JS helper, Swift helper)
// must stay aligned.
final class StockMathTests: XCTestCase {

    let lavenderSoap = ProductRef(id: "p_soap", unitCost: 0, recipe: [
        RecipeRef(materialId: "m_oil", quantity: 50),
        RecipeRef(materialId: "m_lye", quantity: 5),
        RecipeRef(materialId: "m_scent", quantity: 1),
    ])

    let candle = ProductRef(id: "p_candle", unitCost: 0, recipe: [
        RecipeRef(materialId: "m_wax", quantity: 200),
        RecipeRef(materialId: "m_scent", quantity: 4),
        RecipeRef(materialId: "m_wick", quantity: 1),
    ])

    var productsById: [String: ProductRef] {
        [lavenderSoap.id: lavenderSoap, candle.id: candle]
    }

    // MARK: computeUnitCost

    func testUnitCostSumsRecipeTimesCost() {
        let costs = ["m_oil": 0.02, "m_lye": 0.10, "m_scent": 0.50]
        // 50*0.02 + 5*0.10 + 1*0.50 = 1.00 + 0.50 + 0.50 = 2.00
        XCTAssertEqual(StockMath.computeUnitCost(recipe: lavenderSoap.recipe, materialCost: costs), 2.0, accuracy: 1e-6)
    }

    func testUnitCostTreatsMissingMaterialsAsZero() {
        let costs = ["m_oil": 0.02]
        XCTAssertEqual(StockMath.computeUnitCost(recipe: lavenderSoap.recipe, materialCost: costs), 50 * 0.02, accuracy: 1e-6)
    }

    func testUnitCostEmptyRecipeIsZero() {
        XCTAssertEqual(StockMath.computeUnitCost(recipe: [], materialCost: [:]), 0)
    }

    // MARK: applyOrderLine

    func testSingleSaleDeductsPerMaterial() {
        let stock = StockMath.buildStockMap([("m_oil", 1000), ("m_lye", 100), ("m_scent", 50)])
        let after = StockMath.applyOrderLine(stock, product: lavenderSoap, orderQty: 3)
        XCTAssertEqual(after["m_oil"], 1000 - 150)
        XCTAssertEqual(after["m_lye"], 100 - 15)
        XCTAssertEqual(after["m_scent"], 50 - 3)
    }

    func testApplyDoesNotMutateInput() {
        let stock = StockMath.buildStockMap([("m_oil", 1000)])
        let product = ProductRef(id: "p", unitCost: 0, recipe: [RecipeRef(materialId: "m_oil", quantity: 10)])
        _ = StockMath.applyOrderLine(stock, product: product, orderQty: 2)
        XCTAssertEqual(stock["m_oil"], 1000)
    }

    // MARK: applyOrderLines (multi-item)

    func testSharedMaterialAcrossProducts() {
        let stock = StockMath.buildStockMap([
            ("m_oil", 1000), ("m_lye", 100), ("m_scent", 60), ("m_wax", 1000), ("m_wick", 50),
        ])
        let after = StockMath.applyOrderLines(stock, productsById: productsById, lines: [
            OrderLine(productId: "p_soap", quantity: 2, unitSalePrice: 8),
            OrderLine(productId: "p_candle", quantity: 5, unitSalePrice: 20),
        ])
        XCTAssertEqual(after["m_oil"], 1000 - 2 * 50)
        XCTAssertEqual(after["m_lye"], 100 - 2 * 5)
        XCTAssertEqual(after["m_scent"], 60 - (2 * 1 + 5 * 4)) // 60 - 22 = 38
        XCTAssertEqual(after["m_wax"], 1000 - 5 * 200)
        XCTAssertEqual(after["m_wick"], 50 - 5)
    }

    // MARK: reversal

    func testReversalRoundTrips() {
        let start = StockMath.buildStockMap([("m_oil", 500), ("m_lye", 30), ("m_scent", 12)])
        let after = StockMath.applyOrderLine(start, product: lavenderSoap, orderQty: 4)
        let reversed = StockMath.applyOrderLine(after, product: lavenderSoap, orderQty: -4)
        for (k, v) in start { XCTAssertEqual(reversed[k], v) }
    }

    // MARK: update (reverse old, apply new)

    func testChangingQuantityNetsToSingleDelta() {
        let start = StockMath.buildStockMap([("m_oil", 1000), ("m_lye", 100), ("m_scent", 50)])
        let applied = StockMath.applyOrderLine(start, product: lavenderSoap, orderQty: 3)
        let reversed = StockMath.applyOrderLine(applied, product: lavenderSoap, orderQty: -3)
        let reapplied = StockMath.applyOrderLine(reversed, product: lavenderSoap, orderQty: 5)
        XCTAssertEqual(reapplied["m_oil"], 1000 - 250)
        XCTAssertEqual(reapplied["m_lye"], 100 - 25)
        XCTAssertEqual(reapplied["m_scent"], 50 - 5)
    }

    func testChangingProductReversesOldAppliesNew() {
        let start = StockMath.buildStockMap([
            ("m_oil", 1000), ("m_lye", 100), ("m_scent", 50), ("m_wax", 1000), ("m_wick", 20),
        ])
        let a = StockMath.applyOrderLine(start, product: lavenderSoap, orderQty: 2)
        let b = StockMath.applyOrderLine(a, product: lavenderSoap, orderQty: -2)
        let c = StockMath.applyOrderLine(b, product: candle, orderQty: 2)
        XCTAssertEqual(c["m_oil"], 1000)
        XCTAssertEqual(c["m_lye"], 100)
        XCTAssertEqual(c["m_scent"], 50 - 2 * 4)
        XCTAssertEqual(c["m_wax"], 1000 - 2 * 200)
        XCTAssertEqual(c["m_wick"], 20 - 2)
    }

    // MARK: oversell projection

    func testFlagsMaterialsThatWouldGoNegative() {
        let stock = StockMath.buildStockMap([("m_oil", 40), ("m_lye", 100), ("m_scent", 100)])
        let after = StockMath.applyOrderLine(stock, product: lavenderSoap, orderQty: 1)
        XCTAssertTrue(StockMath.wouldOversell(after).contains("m_oil"))
        XCTAssertFalse(StockMath.wouldOversell(after).contains("m_lye"))
    }

    func testEmptyWhenStockSufficient() {
        let stock = StockMath.buildStockMap([("m_oil", 100), ("m_lye", 100), ("m_scent", 100)])
        let after = StockMath.applyOrderLine(stock, product: lavenderSoap, orderQty: 1)
        XCTAssertEqual(StockMath.wouldOversell(after).count, 0)
    }

    // MARK: margin

    func testMarginNilWithoutPrice() {
        XCTAssertNil(StockMath.marginPct(salePrice: nil, unitCost: 5))
        XCTAssertNil(StockMath.marginPct(salePrice: 0, unitCost: 5))
    }

    func testMarginComputation() {
        // price 20, cost 5 → (20-5)/20 = 0.75
        XCTAssertEqual(StockMath.marginPct(salePrice: 20, unitCost: 5)!, 0.75, accuracy: 1e-9)
    }
}
