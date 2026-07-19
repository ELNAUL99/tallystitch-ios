import Foundation

// Why this exists: the dashboard's revenue/per-product aggregation used to
// live inside DashboardViewModel, where it was untestable (the ViewModel
// reaches for the network). Extracting the pure folding logic into the core
// makes it testable with nothing but a compiler — the same reasoning that
// put StockMath here. The ViewModel now just fetches, maps rows into
// DashboardMath.Line, and calls aggregate.
public enum DashboardMath {

    /// One order line, reduced to exactly what the aggregation needs.
    public struct Line: Sendable {
        public let productName: String?
        public let quantity: Double
        public let unitSalePrice: Double

        public init(productName: String?, quantity: Double, unitSalePrice: Double) {
            self.productName = productName
            self.quantity = quantity
            self.unitSalePrice = unitSalePrice
        }
    }

    public struct ProductAgg: Sendable, Equatable {
        public let name: String
        public var units: Double
        public var revenue: Double

        public init(name: String, units: Double, revenue: Double) {
            self.name = name
            self.units = units
            self.revenue = revenue
        }
    }

    public struct Summary: Sendable {
        public let revenue: Double
        /// Sorted by revenue, descending.
        public let byProduct: [ProductAgg]
    }

    /// Fold order lines into total revenue + a per-product breakdown.
    /// Lines with a nil product name group under "Unknown" — a deleted or
    /// unreadable product must not silently drop its revenue from the total.
    public static func aggregate(_ lines: [Line]) -> Summary {
        var revenue = 0.0
        var byName: [String: ProductAgg] = [:]

        for line in lines {
            let lineRevenue = line.quantity * line.unitSalePrice
            revenue += lineRevenue
            let name = line.productName ?? "Unknown"
            var entry = byName[name] ?? ProductAgg(name: name, units: 0, revenue: 0)
            entry.units += line.quantity
            entry.revenue += lineRevenue
            byName[name] = entry
        }

        return Summary(
            revenue: revenue,
            byProduct: byName.values.sorted { $0.revenue > $1.revenue }
        )
    }
}
