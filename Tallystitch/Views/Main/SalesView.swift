import SwiftUI
import TallystitchCore

struct SalesListView: View {
    @EnvironmentObject var profile: ProfileStore
    @State private var sales: [SalesService.SaleRow] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error { Text(error).foregroundStyle(Palette.danger).font(.callout) }
                if sales.isEmpty && loaded {
                    Card {
                        VStack(spacing: 8) {
                            Text("No sales yet").font(.headline)
                            Text("Log a sale at a fair or an order that came in. We'll do the stock math for you.")
                                .multilineTextAlignment(.center).foregroundStyle(Palette.ink500)
                            NavigationLink("Add your first sale") { SaleFormView() }
                                .buttonStyle(PrimaryButton())
                        }
                    }
                } else {
                    Card {
                        VStack(spacing: 0) {
                            ForEach(sales) { sale in
                                SaleRowView(sale: sale, currency: profile.currency)
                                    .swipeActions {
                                        Button("Delete", role: .destructive) { Task { await delete(sale) } }
                                    }
                                if sale.id != sales.last?.id { Divider().background(Palette.cream200) }
                            }
                        }
                    }
                    Text("Swipe a sale left to delete it (stock is added back).")
                        .font(.caption).foregroundStyle(Palette.ink500).frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .background(Palette.cream50)
        .navigationTitle("Sales")
        .toolbar { NavigationLink { SaleFormView() } label: { Image(systemName: "plus") } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { sales = try await SalesService.list() } catch { self.error = error.localizedDescription }
        loaded = true
    }
    private func delete(_ sale: SalesService.SaleRow) async {
        do { try await SalesService.delete(id: sale.id); await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct SaleRowView: View {
    let sale: SalesService.SaleRow
    let currency: String
    private var revenue: Double {
        sale.grossAmount ?? sale.orderItems.reduce(0) { $0 + $1.quantity * $1.unitSalePrice }
    }
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sale.orderDate.formatted(date: .abbreviated, time: .omitted)).font(.body.weight(.medium))
                ForEach(Array(sale.orderItems.enumerated()), id: \.offset) { _, it in
                    Text("\(Formatting.qty(it.quantity)) × \(it.products?.name ?? "Unknown")")
                        .font(.subheadline).foregroundStyle(Palette.ink700)
                }
            }
            Spacer()
            Text(Formatting.currency(revenue, code: currency)).font(.body.weight(.medium))
        }
        .padding(.vertical, 10)
    }
}

struct SaleFormView: View {
    @EnvironmentObject var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var orderDate = Date()
    @State private var shipping = "0"
    @State private var fees = "0"
    @State private var notes = ""
    @State private var lines: [LineState] = []
    @State private var products: [Product] = []
    @State private var ready = false
    @State private var busy = false
    @State private var error: String?

    struct LineState: Identifiable {
        let id = UUID()
        var productId: String = ""
        var quantity: String = "1"
        var price: String = ""
    }

    var body: some View {
        Group {
            if !ready {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.cream50)
            } else if products.isEmpty {
                Card {
                    VStack(spacing: 8) {
                        Text("No products yet").font(.headline)
                        Text("Add a product with a recipe before recording a sale.")
                            .multilineTextAlignment(.center).foregroundStyle(Palette.ink500)
                    }
                }.padding(20)
            } else {
                form
            }
        }
        .background(Palette.cream50)
        .navigationTitle("Add sale")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DatePicker("Sale date", selection: $orderDate, in: ...Date(), displayedComponents: .date)

                HStack {
                    Text("What did you sell?").font(.headline)
                    Spacer()
                    Button("+ Add line") { lines.append(LineState(productId: products.first?.id ?? "")) }
                        .foregroundStyle(Palette.clay700).font(.body.weight(.medium))
                }

                ForEach($lines) { $line in
                    Card {
                        VStack(spacing: 8) {
                            Picker("Product", selection: $line.productId) {
                                ForEach(products) { p in Text(p.name).tag(p.id) }
                            }.pickerStyle(.menu)
                            HStack {
                                TextField("Qty", text: $line.quantity).keyboardType(.decimalPad)
                                    .padding(8).background(Palette.cream50).clipShape(RoundedRectangle(cornerRadius: 8))
                                TextField("Price", text: $line.price).keyboardType(.decimalPad)
                                    .padding(8).background(Palette.cream50).clipShape(RoundedRectangle(cornerRadius: 8))
                                if lines.count > 1 {
                                    Button("Remove", role: .destructive) { lines.removeAll { $0.id == line.id } }
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    LabeledField(label: "Shipping", text: $shipping, keyboard: .decimalPad)
                    LabeledField(label: "Fees", text: $fees, keyboard: .decimalPad)
                }
                LabeledField(label: "Notes (optional)", text: $notes)

                if let error { Text(error).foregroundStyle(Palette.danger).font(.callout) }

                Button(busy ? "Saving…" : "Record sale") { Task { await save() } }
                    .buttonStyle(PrimaryButton()).disabled(busy)
            }
            .padding(20)
        }
    }

    private func prepare() async {
        guard !ready else { return }
        do {
            products = try await SalesService.productsForPicker()
            if let first = products.first {
                lines = [LineState(productId: first.id, quantity: "1", price: first.salePrice.map(String.init) ?? "")]
            }
        } catch { self.error = error.localizedDescription }
        ready = true
    }

    private func save() async {
        let clean = lines.compactMap { l -> SalesService.LineInput? in
            guard !l.productId.isEmpty, let q = Double(l.quantity), q > 0, let p = Double(l.price), p >= 0 else { return nil }
            return SalesService.LineInput(productId: l.productId, quantity: q, unitSalePrice: p)
        }
        guard !clean.isEmpty else { error = "Add at least one valid line."; return }
        busy = true; error = nil
        do {
            try await SalesService.create(.init(
                orderDate: orderDate, fees: Double(fees) ?? 0, shipping: Double(shipping) ?? 0,
                notes: notes.isEmpty ? nil : notes, lines: clean
            ))
            dismiss()
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}
