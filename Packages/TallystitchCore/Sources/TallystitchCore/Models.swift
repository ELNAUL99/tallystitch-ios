import Foundation

// Domain models — mirror the Postgres schema and the web/RN types. Decoded
// straight from Supabase's PostgREST JSON, so the CodingKeys match column
// names (snake_case).

public enum SubscriptionStatus: String, Codable, Sendable {
    case trialing, active, pastDue = "past_due", canceled, incomplete
}

public struct Profile: Codable, Identifiable, Sendable {
    public let id: String
    public let email: String
    public let businessName: String?
    public let currency: String
    public let onboardingCompletedAt: Date?
    public let stripeCustomerId: String?
    public let subscriptionStatus: SubscriptionStatus
    public let trialEndsAt: Date
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, currency
        case businessName = "business_name"
        case onboardingCompletedAt = "onboarding_completed_at"
        case stripeCustomerId = "stripe_customer_id"
        case subscriptionStatus = "subscription_status"
        case trialEndsAt = "trial_ends_at"
        case createdAt = "created_at"
    }
}

public struct Material: Codable, Identifiable, Sendable {
    public let id: String
    public let userId: String
    public var name: String
    public var unit: String
    public var costPerUnit: Double
    public var stockOnHand: Double
    public var lowStockThreshold: Double?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, unit
        case userId = "user_id"
        case costPerUnit = "cost_per_unit"
        case stockOnHand = "stock_on_hand"
        case lowStockThreshold = "low_stock_threshold"
        case createdAt = "created_at"
    }

    public init(
        id: String, userId: String, name: String, unit: String,
        costPerUnit: Double, stockOnHand: Double, lowStockThreshold: Double?,
        createdAt: Date? = nil
    ) {
        self.id = id; self.userId = userId; self.name = name; self.unit = unit
        self.costPerUnit = costPerUnit; self.stockOnHand = stockOnHand
        self.lowStockThreshold = lowStockThreshold; self.createdAt = createdAt
    }

    public var isLowStock: Bool {
        guard let threshold = lowStockThreshold else { return false }
        return stockOnHand <= threshold
    }
}

public struct Product: Codable, Identifiable, Sendable {
    public let id: String
    public let userId: String
    public var name: String
    public var sku: String?
    public var salePrice: Double?
    public var unitCostCached: Double
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, sku
        case userId = "user_id"
        case salePrice = "sale_price"
        case unitCostCached = "unit_cost_cached"
        case createdAt = "created_at"
    }
}

public struct RecipeItem: Codable, Identifiable, Sendable {
    public let id: String
    public let productId: String
    public let materialId: String
    public var quantity: Double

    enum CodingKeys: String, CodingKey {
        case id, quantity
        case productId = "product_id"
        case materialId = "material_id"
    }
}

public enum OrderSource: String, Codable, Sendable {
    case manual, etsyCsv = "etsy_csv", other
}

public struct Order: Codable, Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let source: OrderSource
    public let externalOrderId: String?
    public let orderDate: Date
    public let grossAmount: Double?
    public let fees: Double
    public let shipping: Double
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, source, fees, shipping, notes
        case userId = "user_id"
        case externalOrderId = "external_order_id"
        case orderDate = "order_date"
        case grossAmount = "gross_amount"
    }
}

public struct OrderItem: Codable, Identifiable, Sendable {
    public let id: String
    public let orderId: String
    public let productId: String
    public var quantity: Double
    public var unitSalePrice: Double
    public var unitCostSnapshot: Double

    enum CodingKeys: String, CodingKey {
        case id, quantity
        case orderId = "order_id"
        case productId = "product_id"
        case unitSalePrice = "unit_sale_price"
        case unitCostSnapshot = "unit_cost_snapshot"
    }
}

// MARK: - Access gate (mirror of hasAppAccess on web/RN)

public enum Access {
    public static func hasAppAccess(status: SubscriptionStatus, trialEndsAt: Date) -> Bool {
        if status == .active { return true }
        if status == .trialing { return trialEndsAt > Date() }
        return false
    }

    public static func trialDaysRemaining(trialEndsAt: Date) -> Int {
        let seconds = trialEndsAt.timeIntervalSinceNow
        return max(0, Int(ceil(seconds / 86_400)))
    }
}
