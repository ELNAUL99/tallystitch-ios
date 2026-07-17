// Standalone verification runner.
//
// Why: this machine's Command Line Tools have no XCTest and a SwiftPM that
// can't resolve the manifest, so `swift test` can't run here. The real XCTest
// suites (Tests/) are correct and will run under Xcode on a capable Mac. This
// script lets us still get a genuine pass/fail signal NOW by compiling the
// actual source files together with plain asserts:
//
//   swiftc Sources/TallystitchCore/*.swift Scripts/verify.swift -o /tmp/verify
//   /tmp/verify
//
// It mirrors the high-value StockMath cases so the core deduction math is
// verified natively even on the build-blocked machine.

import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String) {
    if cond { print("  ok  - \(name)") }
    else { print("  FAIL- \(name)"); failures += 1 }
}
func approx(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) < eps }

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
let productsById = [lavenderSoap.id: lavenderSoap, candle.id: candle]

print("StockMath")
// computeUnitCost
check(approx(StockMath.computeUnitCost(recipe: lavenderSoap.recipe,
        materialCost: ["m_oil": 0.02, "m_lye": 0.10, "m_scent": 0.50]), 2.0),
      "unit cost sums recipe*cost")
check(approx(StockMath.computeUnitCost(recipe: [], materialCost: [:]), 0), "empty recipe is zero")

// single sale
var stock = StockMath.buildStockMap([("m_oil", 1000), ("m_lye", 100), ("m_scent", 50)])
var after = StockMath.applyOrderLine(stock, product: lavenderSoap, orderQty: 3)
check(after["m_oil"] == 850 && after["m_lye"] == 85 && after["m_scent"] == 47, "single sale deducts per material")
check(stock["m_oil"] == 1000, "apply does not mutate input")

// multi-item shared material
stock = StockMath.buildStockMap([("m_oil", 1000), ("m_lye", 100), ("m_scent", 60), ("m_wax", 1000), ("m_wick", 50)])
after = StockMath.applyOrderLines(stock, productsById: productsById, lines: [
    OrderLine(productId: "p_soap", quantity: 2, unitSalePrice: 8),
    OrderLine(productId: "p_candle", quantity: 5, unitSalePrice: 20),
])
check(after["m_scent"] == 38, "shared material consumed across products (60-22=38)")
check(after["m_wax"] == 0 && after["m_wick"] == 45, "candle materials deducted")

// reversal round-trip
let start = StockMath.buildStockMap([("m_oil", 500), ("m_lye", 30), ("m_scent", 12)])
let applied = StockMath.applyOrderLine(start, product: lavenderSoap, orderQty: 4)
let reversed = StockMath.applyOrderLine(applied, product: lavenderSoap, orderQty: -4)
check(reversed["m_oil"] == 500 && reversed["m_lye"] == 30 && reversed["m_scent"] == 12, "reversal round-trips")

// product swap on update
let s2 = StockMath.buildStockMap([("m_oil", 1000), ("m_lye", 100), ("m_scent", 50), ("m_wax", 1000), ("m_wick", 20)])
let a = StockMath.applyOrderLine(s2, product: lavenderSoap, orderQty: 2)
let b = StockMath.applyOrderLine(a, product: lavenderSoap, orderQty: -2)
let c = StockMath.applyOrderLine(b, product: candle, orderQty: 2)
check(c["m_oil"] == 1000 && c["m_wax"] == 600 && c["m_wick"] == 18, "product swap reverses old, applies new")

// oversell
let low = StockMath.applyOrderLine(StockMath.buildStockMap([("m_oil", 40), ("m_lye", 100), ("m_scent", 100)]),
                                   product: lavenderSoap, orderQty: 1)
check(StockMath.wouldOversell(low).contains("m_oil") && !StockMath.wouldOversell(low).contains("m_lye"),
      "oversell flags negative materials only")

// margin
check(StockMath.marginPct(salePrice: nil, unitCost: 5) == nil, "margin nil without price")
check(approx(StockMath.marginPct(salePrice: 20, unitCost: 5) ?? -1, 0.75), "margin 0.75 for 20/5")

print("Formatting")
check(Formatting.qty(3.0) == "3", "qty drops trailing zeros")
check(Formatting.qty(2.5) == "2.50", "qty keeps fractions")
check(Formatting.qty(nil) == "—", "qty nil is dash")
check(Formatting.percent(0.75) == "75.0%", "percent 75.0%")
check(Formatting.currency(nil) == "—", "currency nil is dash")
check(Formatting.currency(12.5, code: "USD").contains("12"), "currency contains digits")

print("Access gate")
let inADay = Date().addingTimeInterval(86_400)
let aDayAgo = Date().addingTimeInterval(-86_400)
check(Access.hasAppAccess(status: .active, trialEndsAt: aDayAgo), "active passes even with expired trial")
check(Access.hasAppAccess(status: .trialing, trialEndsAt: inADay), "trialing passes before trial end")
check(!Access.hasAppAccess(status: .trialing, trialEndsAt: aDayAgo), "trialing locked after trial end")
check(!Access.hasAppAccess(status: .canceled, trialEndsAt: inADay), "canceled locked despite future trial date")
check(!Access.hasAppAccess(status: .pastDue, trialEndsAt: inADay), "past_due locked despite future trial date")
check(Access.trialDaysRemaining(trialEndsAt: Date().addingTimeInterval(0.5 * 86_400)) == 1, "half a day left ceils to 1")
check(Access.trialDaysRemaining(trialEndsAt: aDayAgo) == 0, "expired trial clamps to 0 days")

print("")
if failures == 0 { print("ALL CHECKS PASSED") }
else { print("\(failures) CHECK(S) FAILED"); exit(1) }
