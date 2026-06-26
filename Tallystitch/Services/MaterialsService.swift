import Foundation
import Supabase
import TallystitchCore

// Mirror of the RN src/lib/materials.ts. Thin async wrappers over PostgREST so
// the views stay declarative. RLS scopes everything to the signed-in user;
// the FK-restrict delete is translated to a friendly message.
enum MaterialsService {
    struct Input: Encodable {
        let name: String
        let unit: String
        let cost_per_unit: Double
        let stock_on_hand: Double
        let low_stock_threshold: Double?
    }

    static func list() async throws -> [Material] {
        try await supabase
            .from("materials")
            .select()
            .order("name", ascending: true)
            .execute()
            .value
    }

    static func get(id: String) async throws -> Material? {
        let rows: [Material] = try await supabase
            .from("materials")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    static func create(_ input: Input) async throws {
        let userId = try await supabase.auth.session.user.id
        struct Row: Encodable {
            let user_id: String
            let name: String
            let unit: String
            let cost_per_unit: Double
            let stock_on_hand: Double
            let low_stock_threshold: Double?
        }
        try await supabase.from("materials").insert(Row(
            user_id: userId.uuidString.lowercased(),
            name: input.name, unit: input.unit,
            cost_per_unit: input.cost_per_unit, stock_on_hand: input.stock_on_hand,
            low_stock_threshold: input.low_stock_threshold
        )).execute()
    }

    static func update(id: String, _ input: Input) async throws {
        try await supabase.from("materials").update(input).eq("id", value: id).execute()
    }

    static func delete(id: String) async throws {
        do {
            try await supabase.from("materials").delete().eq("id", value: id).execute()
        } catch {
            // Why: Postgres FK violation (23503) means a recipe still uses this
            // material — translate to plain language. Everything else rethrows.
            if isForeignKeyViolation(error) {
                throw AppError.message("This material is used in a product recipe. Remove it from recipes first.")
            }
            throw error
        }
    }
}

/// A user-facing error carrying a ready-to-show message.
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(m) = self { return m }; return nil }
}

/// Best-effort detection of a Postgres FK-violation surfaced through PostgREST.
func isForeignKeyViolation(_ error: Error) -> Bool {
    let s = String(describing: error)
    return s.contains("23503") || s.lowercased().contains("foreign key")
}
