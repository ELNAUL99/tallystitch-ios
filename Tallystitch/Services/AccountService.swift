import Foundation
import Supabase
import TallystitchCore

// Account deletion goes through the same delete-account Edge Function the RN
// app uses — a mobile client can't hold the service-role key, so the deletion
// runs server-side where the function re-derives the user from their JWT.
// Sample data load/clear mirror the RN sampleData.ts (is_sample tagging).
enum AccountService {
    static func deleteAccount() async throws {
        try await supabase.functions.invoke("delete-account")
        try? await supabase.auth.signOut()
    }
}

enum SampleData {
    static func load() async throws {
        let userId = try await supabase.auth.session.user.id.uuidString.lowercased()

        // 1. materials
        struct MatRow: Encodable {
            let user_id: String; let name: String; let unit: String
            let cost_per_unit: Double; let stock_on_hand: Double
            let low_stock_threshold: Double?; let is_sample: Bool
        }
        struct MatResult: Decodable { let id: String; let name: String }
        let matPayload = Sample.materials.map {
            MatRow(user_id: userId, name: $0.name, unit: $0.unit, cost_per_unit: $0.cost,
                   stock_on_hand: $0.stock, low_stock_threshold: $0.low, is_sample: true)
        }
        let mats: [MatResult] = try await supabase.from("materials").insert(matPayload).select("id, name").execute().value
        var matByName: [String: String] = [:]
        for m in mats { matByName[m.name] = m.id }

        // 2. products + recipes
        var prodByName: [String: String] = [:]
        for p in Sample.products {
            struct ProdRow: Encodable { let user_id: String; let name: String; let sku: String; let sale_price: Double; let is_sample: Bool }
            struct ProdResult: Decodable { let id: String }
            let created: [ProdResult] = try await supabase.from("products")
                .insert(ProdRow(user_id: userId, name: p.name, sku: p.sku, sale_price: p.price, is_sample: true))
                .select("id").execute().value
            guard let prodId = created.first?.id else { continue }
            prodByName[p.name] = prodId

            struct RecipeRow: Encodable { let product_id: String; let material_id: String; let quantity: Double }
            let recipe = p.recipe.compactMap { item -> RecipeRow? in
                guard let matId = matByName[item.name] else { return nil }
                return RecipeRow(product_id: prodId, material_id: matId, quantity: item.qty)
            }
            try await supabase.from("recipe_items").insert(recipe).execute()
        }

        // 3. orders
        for o in Sample.orders {
            let date = Date().addingTimeInterval(-Double(o.daysAgo) * 86_400)
            let lines = o.lines.compactMap { line -> (String, Double, Double)? in
                guard let prodId = prodByName[line.product] else { return nil }
                return (prodId, line.qty, line.price)
            }
            let gross = lines.reduce(0) { $0 + $1.1 * $1.2 }
            struct OrderRow: Encodable {
                let user_id: String; let source: String; let order_date: String
                let gross_amount: Double; let shipping: Double; let is_sample: Bool
            }
            struct OrderResult: Decodable { let id: String }
            let created: [OrderResult] = try await supabase.from("orders").insert(OrderRow(
                user_id: userId, source: "manual",
                order_date: ISO8601DateFormatter().string(from: date),
                gross_amount: gross, shipping: o.shipping, is_sample: true
            )).select("id").execute().value
            guard let orderId = created.first?.id else { continue }

            struct ItemRow: Encodable { let order_id: String; let product_id: String; let quantity: Double; let unit_sale_price: Double }
            let items = lines.map { ItemRow(order_id: orderId, product_id: $0.0, quantity: $0.1, unit_sale_price: $0.2) }
            try await supabase.from("order_items").insert(items).execute()
        }
    }

    static func clear() async throws {
        let userId = try await supabase.auth.session.user.id.uuidString.lowercased()
        // Order matters: orders (stock reverses via trigger) → products → materials.
        try await supabase.from("orders").delete().eq("user_id", value: userId).eq("is_sample", value: true).execute()
        try await supabase.from("products").delete().eq("user_id", value: userId).eq("is_sample", value: true).execute()
        try await supabase.from("materials").delete().eq("user_id", value: userId).eq("is_sample", value: true).execute()
    }
}
