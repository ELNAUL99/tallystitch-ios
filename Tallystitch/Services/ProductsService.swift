import Foundation
import Supabase
import TallystitchCore

// Mirror of RN src/lib/products.ts. Recipe save = delete-all + insert so the
// recipe_items_recompute trigger keeps products.unit_cost_cached fresh for
// free; duplicate material rows are collapsed client-side because the schema
// has a unique (product_id, material_id).
enum ProductsService {
    struct RecipeInput { let materialId: String; let quantity: Double }
    struct Input {
        let name: String
        let sku: String?
        let salePrice: Double?
        let recipe: [RecipeInput]
    }

    static func list() async throws -> [Product] {
        try await supabase.from("products").select().order("name", ascending: true).execute().value
    }

    static func get(id: String) async throws -> Product? {
        let rows: [Product] = try await supabase
            .from("products").select().eq("id", value: id).limit(1).execute().value
        return rows.first
    }

    static func recipe(productId: String) async throws -> [RecipeItem] {
        try await supabase
            .from("recipe_items").select().eq("product_id", value: productId).execute().value
    }

    static func create(_ input: Input) async throws {
        let userId = try await supabase.auth.session.user.id
        struct Row: Encodable { let user_id: String; let name: String; let sku: String?; let sale_price: Double? }
        let created: [Product] = try await supabase.from("products").insert(Row(
            user_id: userId.uuidString.lowercased(),
            name: input.name, sku: input.sku, sale_price: input.salePrice
        )).select().execute().value
        guard let product = created.first else { throw AppError.message("Could not create product") }
        try await replaceRecipe(productId: product.id, input.recipe)
    }

    static func update(id: String, _ input: Input) async throws {
        struct Row: Encodable { let name: String; let sku: String?; let sale_price: Double? }
        try await supabase.from("products")
            .update(Row(name: input.name, sku: input.sku, sale_price: input.salePrice))
            .eq("id", value: id).execute()
        try await replaceRecipe(productId: id, input.recipe)
    }

    static func delete(id: String) async throws {
        do {
            try await supabase.from("products").delete().eq("id", value: id).execute()
        } catch {
            if isForeignKeyViolation(error) {
                throw AppError.message("This product has sales recorded against it and cannot be deleted.")
            }
            throw error
        }
    }

    private static func replaceRecipe(productId: String, _ rows: [RecipeInput]) async throws {
        try await supabase.from("recipe_items").delete().eq("product_id", value: productId).execute()

        // Collapse duplicate materials (sum quantities) — the unique index would
        // otherwise reject the second insert of the same material.
        var byMaterial: [String: Double] = [:]
        for r in rows { byMaterial[r.materialId, default: 0] += r.quantity }
        guard !byMaterial.isEmpty else { return }

        struct RecipeRow: Encodable { let product_id: String; let material_id: String; let quantity: Double }
        let payload = byMaterial.map { RecipeRow(product_id: productId, material_id: $0.key, quantity: $0.value) }
        try await supabase.from("recipe_items").insert(payload).execute()
    }
}
