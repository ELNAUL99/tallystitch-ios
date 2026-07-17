import XCTest
@testable import TallystitchCore

// The CodingKeys boundary is runtime-checked, not compile-checked: a renamed
// column with a stale key fails only when real JSON hits the decoder. These
// tests feed PostgREST-shaped JSON (snake_case, ISO-8601 timestamps) through
// the models so that failure happens here instead of in the running app.
final class ModelsDecodingTests: XCTestCase {
    // Mirrors supabase-swift's decoder: ISO-8601, fractional seconds optional.
    private static let decoder: JSONDecoder = {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = withFractional.date(from: string) ?? plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try Self.decoder.decode(type, from: Data(json.utf8))
    }

    func testProfileDecodesFromPostgrestJSON() throws {
        let json = """
        {
          "id": "u-1", "email": "maker@example.com",
          "business_name": null, "currency": "EUR",
          "onboarding_completed_at": null,
          "stripe_customer_id": null,
          "subscription_status": "trialing",
          "trial_ends_at": "2026-07-31T00:00:00+00:00",
          "created_at": "2026-07-17T10:30:00.123456+00:00"
        }
        """
        let p = try decode(Profile.self, json)
        XCTAssertEqual(p.id, "u-1")
        XCTAssertEqual(p.currency, "EUR")
        XCTAssertNil(p.businessName)
        XCTAssertNil(p.onboardingCompletedAt)
        XCTAssertEqual(p.subscriptionStatus, .trialing)
    }

    func testSubscriptionStatusRawValues() {
        // These strings are the Postgres enum labels; the web/RN apps write
        // them and this app must read them identically.
        XCTAssertEqual(SubscriptionStatus(rawValue: "past_due"), .pastDue)
        XCTAssertEqual(SubscriptionStatus(rawValue: "trialing"), .trialing)
        XCTAssertEqual(SubscriptionStatus(rawValue: "active"), .active)
        XCTAssertEqual(SubscriptionStatus(rawValue: "canceled"), .canceled)
        XCTAssertEqual(SubscriptionStatus(rawValue: "incomplete"), .incomplete)
    }

    func testMaterialDecodesAndLowStockBoundary() throws {
        let json = """
        {
          "id": "m-1", "user_id": "u-1", "name": "Soy wax", "unit": "g",
          "cost_per_unit": 0.012, "stock_on_hand": 1000,
          "low_stock_threshold": 1000,
          "created_at": "2026-07-01T09:00:00+00:00"
        }
        """
        let m = try decode(TallystitchCore.Material.self, json)
        XCTAssertEqual(m.costPerUnit, 0.012)
        // Boundary: stock exactly at the threshold counts as low.
        XCTAssertTrue(m.isLowStock)
    }

    func testMaterialWithoutThresholdIsNeverLow() throws {
        let json = """
        {
          "id": "m-2", "user_id": "u-1", "name": "Wick", "unit": "piece",
          "cost_per_unit": 0.18, "stock_on_hand": 0,
          "low_stock_threshold": null, "created_at": null
        }
        """
        let m = try decode(TallystitchCore.Material.self, json)
        XCTAssertFalse(m.isLowStock, "no threshold means no low-stock warning, even at zero")
    }

    func testProductDecodesWithNullableFields() throws {
        let json = """
        {
          "id": "p-1", "user_id": "u-1", "name": "Candle",
          "sku": null, "sale_price": null,
          "unit_cost_cached": 4.86, "created_at": null
        }
        """
        let p = try decode(Product.self, json)
        XCTAssertNil(p.sku)
        XCTAssertNil(p.salePrice)
        XCTAssertEqual(p.unitCostCached, 4.86)
    }

    func testOrderDecodesSourceEnumAndNullGross() throws {
        let json = """
        {
          "id": "o-1", "user_id": "u-1", "source": "etsy_csv",
          "external_order_id": "etsy-123",
          "order_date": "2026-07-10T00:00:00+00:00",
          "gross_amount": null, "fees": 1.25, "shipping": 5.5, "notes": null
        }
        """
        let o = try decode(Order.self, json)
        XCTAssertEqual(o.source, .etsyCsv)
        XCTAssertNil(o.grossAmount)
        XCTAssertEqual(o.shipping, 5.5)
    }

    func testOrderItemDecodesSnapshotColumn() throws {
        let json = """
        {
          "id": "oi-1", "order_id": "o-1", "product_id": "p-1",
          "quantity": 2, "unit_sale_price": 22.0, "unit_cost_snapshot": 4.86
        }
        """
        let item = try decode(OrderItem.self, json)
        XCTAssertEqual(item.unitCostSnapshot, 4.86)
        XCTAssertEqual(item.unitSalePrice, 22.0)
    }

    func testRecipeItemDecodes() throws {
        let json = """
        { "id": "r-1", "product_id": "p-1", "material_id": "m-1", "quantity": 220 }
        """
        let r = try decode(RecipeItem.self, json)
        XCTAssertEqual(r.productId, "p-1")
        XCTAssertEqual(r.quantity, 220)
    }
}
