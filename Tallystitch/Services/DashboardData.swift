import Foundation
import Supabase
import TallystitchCore

// The first injected seam at the data boundary — the "targeted injection"
// step ARCHITECTURE.md's trade-offs list as the planned fix. The protocol
// lets DashboardViewModel take a fake in tests instead of reaching for the
// global client; LiveDashboardData is the production implementation and the
// ViewModel's default, so no call site changes. Deliberately scoped to one
// boundary rather than protocolizing every service: abstraction where a mock
// is actually needed, not everywhere as doctrine.
protocol DashboardDataProviding: Sendable {
    func fetchOrders(since: Date) async throws -> [SalesService.SaleRow]
    func fetchMaterials() async throws -> [TallystitchCore.Material]
}

struct LiveDashboardData: DashboardDataProviding {
    func fetchOrders(since: Date) async throws -> [SalesService.SaleRow] {
        try await supabase
            .from("orders")
            .select("id, source, external_order_id, order_date, gross_amount, order_items(quantity, unit_sale_price, products(name))")
            .gte("order_date", value: ISO8601DateFormatter().string(from: since))
            .execute().value
    }

    func fetchMaterials() async throws -> [TallystitchCore.Material] {
        try await supabase
            .from("materials")
            .select()
            .order("stock_on_hand", ascending: true)
            .execute().value
    }
}
