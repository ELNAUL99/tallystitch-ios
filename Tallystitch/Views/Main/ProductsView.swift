import SwiftUI
import TallystitchCore

struct ProductsListView: View {
    @EnvironmentObject var profile: ProfileStore
    @State private var products: [Product] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error { Text(error).foregroundStyle(Palette.danger).font(.callout) }
                if products.isEmpty && loaded {
                    Card {
                        VStack(spacing: 8) {
                            Text("No products yet").font(.headline)
                            Text("A product is something you sell. Build its recipe and we'll calculate what it really costs.")
                                .multilineTextAlignment(.center).foregroundStyle(Palette.ink500)
                            NavigationLink("Add your first product") { ProductFormView() }
                                .buttonStyle(PrimaryButton())
                        }
                    }
                } else {
                    Card {
                        VStack(spacing: 0) {
                            ForEach(products) { p in
                                NavigationLink { ProductFormView(existing: p) } label: { ProductRow(product: p, currency: profile.currency) }
                                if p.id != products.last?.id { Divider().background(Palette.cream200) }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.cream50)
        .navigationTitle("Products")
        .toolbar { NavigationLink { ProductFormView() } label: { Image(systemName: "plus") } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { products = try await ProductsService.list() } catch { self.error = error.localizedDescription }
        loaded = true
    }
}

struct ProductRow: View {
    let product: Product
    let currency: String
    var body: some View {
        let cost = product.unitCostCached
        let price = product.salePrice
        let profit = price.map { $0 - cost }
        let margin = StockMath.marginPct(salePrice: price, unitCost: cost)
        return HStack {
            VStack(alignment: .leading) {
                Text(product.name).font(.body.weight(.medium)).foregroundStyle(Palette.ink900)
                Text("Cost \(Formatting.currency(cost, code: currency)) · Price \(Formatting.currency(price, code: currency))")
                    .font(.caption).foregroundStyle(Palette.ink500)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(Formatting.currency(profit, code: currency))
                    .font(.body.weight(.medium))
                    .foregroundStyle((profit ?? 0) < 0 ? Palette.danger : Palette.ink900)
                Text(Formatting.percent(margin)).font(.caption).foregroundStyle(Palette.ink500)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
