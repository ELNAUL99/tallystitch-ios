import SwiftUI
import TallystitchCore

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var revenue = 0.0
    // Why cogs stays 0 here: unit cost snapshot isn't selected by the lean
    // mobile query; revenue is the headline. (Cost-of-goods belongs in a
    // Postgres view/RPC — see Known trade-offs.)
    @Published var cogs = 0.0
    @Published var byProduct: [DashboardMath.ProductAgg] = []
    @Published var lowStock: [TallystitchCore.Material] = []
    @Published var loaded = false
    @Published var error: String?

    private let data: DashboardDataProviding

    // Injected data boundary: production uses the default; tests pass a fake.
    // The default parameter keeps the call site (`DashboardViewModel()`)
    // unchanged.
    init(data: DashboardDataProviding = LiveDashboardData()) {
        self.data = data
    }

    func load() async {
        error = nil
        do {
            let since = Date().addingTimeInterval(-30 * 86_400)
            async let orders = data.fetchOrders(since: since)
            async let materials = data.fetchMaterials()
            let (ordersResult, materialsResult) = try await (orders, materials)

            // Flatten SDK rows into pure lines; the fold itself lives (and is
            // tested) in TallystitchCore.DashboardMath.
            let lines = ordersResult.flatMap { order in
                order.orderItems.map {
                    DashboardMath.Line(
                        productName: $0.products?.name,
                        quantity: $0.quantity,
                        unitSalePrice: $0.unitSalePrice
                    )
                }
            }
            let summary = DashboardMath.aggregate(lines)
            revenue = summary.revenue
            byProduct = summary.byProduct
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
                        // Grouping guarantees unique names, so name is a valid identity.
                        ForEach(vm.byProduct, id: \.name) { row in
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
