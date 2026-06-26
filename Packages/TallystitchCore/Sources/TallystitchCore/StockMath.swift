import Foundation

// Pure functions that mirror the SQL triggers (supabase/migrations/0001) and
// the web's src/lib/stock.ts. Used for: (a) CSV-import preview projection,
// (b) unit tests of the deduction rule. The authoritative deduction still
// happens in Postgres on insert/update/delete of order_items — these helpers
// must stay aligned with public.tg_order_items_stock.

public struct RecipeRef: Sendable {
    public let materialId: String
    public let quantity: Double
    public init(materialId: String, quantity: Double) {
        self.materialId = materialId
        self.quantity = quantity
    }
}

public struct ProductRef: Sendable {
    public let id: String
    public let unitCost: Double
    public let recipe: [RecipeRef]
    public init(id: String, unitCost: Double, recipe: [RecipeRef]) {
        self.id = id
        self.unitCost = unitCost
        self.recipe = recipe
    }
}

public struct OrderLine: Sendable {
    public let productId: String
    public let quantity: Double
    public let unitSalePrice: Double
    public init(productId: String, quantity: Double, unitSalePrice: Double) {
        self.productId = productId
        self.quantity = quantity
        self.unitSalePrice = unitSalePrice
    }
}

public enum StockMath {
    /// material_id -> stock_on_hand
    public typealias StockMap = [String: Double]

    public static func buildStockMap(_ materials: [(id: String, stock: Double)]) -> StockMap {
        var map: StockMap = [:]
        for m in materials { map[m.id] = m.stock }
        return map
    }

    /// Apply one order line to a stock map and return a new map. Mirrors the
    /// SQL: for each recipe item of the product, deduct (recipeQty * orderQty)
    /// from the corresponding material's stock.
    public static func applyOrderLine(
        _ stock: StockMap, product: ProductRef, orderQty: Double
    ) -> StockMap {
        var next = stock
        for item in product.recipe {
            let current = next[item.materialId] ?? 0
            next[item.materialId] = current - item.quantity * orderQty
        }
        return next
    }

    /// Apply many order lines in sequence.
    public static func applyOrderLines(
        _ stock: StockMap, productsById: [String: ProductRef], lines: [OrderLine]
    ) -> StockMap {
        var current = stock
        for line in lines {
            guard let product = productsById[line.productId] else { continue }
            current = applyOrderLine(current, product: product, orderQty: line.quantity)
        }
        return current
    }

    /// Unit cost = sum(recipe.qty * material.cost). Mirrors
    /// public.recompute_product_unit_cost.
    public static func computeUnitCost(
        recipe: [RecipeRef], materialCost: [String: Double]
    ) -> Double {
        var total = 0.0
        for item in recipe {
            let cost = materialCost[item.materialId] ?? 0
            total += item.quantity * cost
        }
        return total
    }

    /// Material ids that would be driven below zero by the applied order.
    public static func wouldOversell(_ stockAfter: StockMap) -> [String] {
        stockAfter.filter { $0.value < 0 }.map { $0.key }
    }

    /// Margin for a sale: (price - cost) / price. nil if no positive price.
    public static func marginPct(salePrice: Double?, unitCost: Double) -> Double? {
        guard let price = salePrice, price > 0 else { return nil }
        return (price - unitCost) / price
    }
}
