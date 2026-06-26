import Foundation
import Supabase
import TallystitchCore

// Mirror of RN src/lib/sales.ts. Sale creation goes through the same atomic
// create_order_with_items RPC the web uses — parent order + items + every
// stock-deduction trigger in one transaction. Delete just removes the parent;
// the AFTER DELETE trigger adds the stock back.
enum SalesService {
    struct LineInput { let productId: String; let quantity: Double; let unitSalePrice: Double }
    struct SaleInput {
        let orderDate: Date
        let fees: Double
        let shipping: Double
        let notes: String?
        let lines: [LineInput]
    }

    /// A sale row with its nested items + product names, for the list screen.
    struct SaleRow: Decodable, Identifiable {
        let id: String
        let source: String
        let externalOrderId: String?
        let orderDate: Date
        let grossAmount: Double?
        let orderItems: [Item]

        struct Item: Decodable {
            let quantity: Double
            let unitSalePrice: Double
            let products: ProductName?
            struct ProductName: Decodable { let name: String }
            enum CodingKeys: String, CodingKey {
                case quantity, products
                case unitSalePrice = "unit_sale_price"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, source
            case externalOrderId = "external_order_id"
            case orderDate = "order_date"
            case grossAmount = "gross_amount"
            case orderItems = "order_items"
        }
    }

    static func list(limit: Int = 200) async throws -> [SaleRow] {
        try await supabase
            .from("orders")
            .select("id, source, external_order_id, order_date, gross_amount, order_items(quantity, unit_sale_price, products(name))")
            .order("order_date", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    static func productsForPicker() async throws -> [Product] {
        try await supabase.from("products").select().order("name", ascending: true).execute().value
    }

    static func create(_ input: SaleInput) async throws {
        let userId = try await supabase.auth.session.user.id

        // The RPC computes gross itself; we just send the lines as JSON.
        struct Item: Encodable { let product_id: String; let quantity: Double; let unit_sale_price: Double }
        struct Params: Encodable {
            let p_user: String
            let p_source: String
            let p_external_order_id: String?
            let p_order_date: String
            let p_fees: Double
            let p_shipping: Double
            let p_notes: String?
            let p_is_sample: Bool
            let p_items: [Item]
        }

        let iso = ISO8601DateFormatter().string(from: input.orderDate)
        let params = Params(
            p_user: userId.uuidString.lowercased(),
            p_source: "manual",
            p_external_order_id: nil,
            p_order_date: iso,
            p_fees: input.fees,
            p_shipping: input.shipping,
            p_notes: input.notes,
            p_is_sample: false,
            p_items: input.lines.map { Item(product_id: $0.productId, quantity: $0.quantity, unit_sale_price: $0.unitSalePrice) }
        )
        try await supabase.rpc("create_order_with_items", params: params).execute()
    }

    static func delete(id: String) async throws {
        try await supabase.from("orders").delete().eq("id", value: id).execute()
    }
}
