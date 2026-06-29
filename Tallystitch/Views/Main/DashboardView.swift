import SwiftUI
import TallystitchCore

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var revenue = 0.0
    @Published var cogs = 0.0
    @Published var byProduct: [ProductAgg] = []
    @Published var lowStock: [TallystitchCore.Material] = []
    @Published var loaded = false
    @Published var error: String?

    struct ProductAgg: Identifiable { let id = UUID(); let name: String; var units: Double; var revenue: Double; var cost: Double }

    func load() async {
        error = nil
        do {
            let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30 * 86_400))
            async let orders: [SalesService.SaleRow] = supabase
                .from("orders")
                .select("id, source, external_order_id, order_date, gross_amount, order_items(quantity, unit_sale_price, products(name))")
                .gte("order_date", value: since)
                .execute().value
            async let materials: [TallystitchCore.Material] = supabase
                .from("materials").select().order("stock_on_hand", ascending: true).execute().value

            let (ordersResult, materialsResult) = try await (orders, materials)

            var rev = 0.0, cost = 0.0
            var agg: [String: ProductAgg] = [:]
            for o in ordersResult {
                for it in o.orderItems {
                    let lineRev = it.quantity * it.unitSalePrice
                    // unit cost snapshot isn't selected here; revenue is what matters
                    // for the headline. (Cost-of-goods uses the snapshot in a fuller
                    // query — kept lean for the mobile dashboard.)
                    rev += lineRev
                    let name = it.products?.name ?? "Unknown"
                    var entry = agg[name] ?? ProductAgg(name: name, units: 0, revenue: 0, cost: 0)
                    entry.units += it.quantity
                    entry.revenue += lineRev
                    agg[name] = entry
                }
            }
            revenue = rev
            cogs = cost
            byProduct = agg.values.sorted { $0.revenue > $1.revenue }
            lowStock = materialsResult.filter(\.isLowStock)
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

struct DashboardView: View {
    @EnvironmentObject var profile: ProfileStore
    @StateObject private var vm = DashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(profile.profile?.businessName ?? "Your workshop")
                    .font(.title.weight(.semibold))
                Text("Last 30 days.").foregroundStyle(Palette.ink500).font(.subheadline)

                let profit = vm.revenue - vm.cogs
                VStack(spacing: 12) {
                    StatCard(label: "Revenue", value: Formatting.currency(vm.revenue, code: profile.currency))
                    StatCard(label: "Estimated profit", value: Formatting.currency(profit, code: profile.currency),
                             tone: profit < 0 ? .bad : (profit > 0 ? .good : .neutral))
                }

                SectionCard(title: "By product") {
                    if vm.byProduct.isEmpty {
                        Text("No sales in this period yet.").foregroundStyle(Palette.ink500).padding(.vertical, 8)
                    } else {
                        ForEach(vm.byProduct) { row in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(row.name).font(.body.weight(.medium))
                                    Text("\(Formatting.qty(row.units)) sold").font(.caption).foregroundStyle(Palette.ink500)
                                }
                                Spacer()
                                Text(Formatting.currency(row.revenue, code: profile.currency)).font(.body.weight(.medium))
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                SectionCard(title: "Low stock") {
                    if vm.lowStock.isEmpty {
                        Text("Everything looks fine.").foregroundStyle(Palette.ink500).padding(.vertical, 8)
                    } else {
                        ForEach(vm.lowStock) { m in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(m.name).font(.body.weight(.medium))
                                    Text("\(Formatting.qty(m.stockOnHand)) \(m.unit) left").font(.caption).foregroundStyle(Palette.ink500)
                                }
                                Spacer()
                                Text("Low").font(.caption.weight(.medium))
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Palette.amberBg).foregroundStyle(Palette.amberFg)
                                    .clipShape(Capsule())
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.cream50)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.load() }
        .task { if !vm.loaded { await vm.load() } }
    }
}

struct StatCard: View {
    enum Tone { case good, bad, neutral }
    let label: String
    let value: String
    var tone: Tone = .neutral
    var color: Color { tone == .good ? Palette.sage700 : (tone == .bad ? Palette.danger : Palette.ink900) }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased()).font(.caption).foregroundStyle(Palette.ink500).tracking(0.5)
                Text(value).font(.title.weight(.semibold)).foregroundStyle(color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
