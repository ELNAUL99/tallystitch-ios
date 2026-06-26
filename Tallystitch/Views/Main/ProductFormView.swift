import SwiftUI
import TallystitchCore

// The product editor — where the wedge happens. Unit cost, profit/unit and
// margin recompute live as the user edits the recipe, the same as the web's
// ProductEditor.
struct ProductFormView: View {
    @EnvironmentObject var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    var existing: Product?

    @State private var name = ""
    @State private var sku = ""
    @State private var salePrice = ""
    @State private var rows: [RecipeRowState] = []
    @State private var materials: [Material] = []
    @State private var ready = false
    @State private var busy = false
    @State private var error: String?

    struct RecipeRowState: Identifiable {
        let id = UUID()
        var materialId: String = ""
        var quantity: String = ""
    }

    private var materialsById: [String: Material] {
        Dictionary(uniqueKeysWithValues: materials.map { ($0.id, $0) })
    }

    private var unitCost: Double {
        rows.reduce(0) { total, row in
            guard let m = materialsById[row.materialId], let q = Double(row.quantity) else { return total }
            return total + q * m.costPerUnit
        }
    }
    private var priceValue: Double? { salePrice.isEmpty ? nil : Double(salePrice) }
    private var profit: Double? { priceValue.map { $0 - unitCost } }
    private var margin: Double? { StockMath.marginPct(salePrice: priceValue, unitCost: unitCost) }

    var body: some View {
        Group {
            if !ready {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.cream50)
            } else if materials.isEmpty {
                Card {
                    VStack(spacing: 8) {
                        Text("Add a material first").font(.headline)
                        Text("You need at least one material before building a recipe.")
                            .multilineTextAlignment(.center).foregroundStyle(Palette.ink500)
                    }
                }.padding(20)
            } else {
                form
            }
        }
        .background(Palette.cream50)
        .navigationTitle(existing?.name ?? "New product")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LabeledField(label: "Product name", text: $name)
                HStack(spacing: 12) {
                    LabeledField(label: "SKU (optional)", text: $sku)
                    LabeledField(label: "Sale price (\(profile.currency))", text: $salePrice, keyboard: .decimalPad)
                }

                HStack {
                    Text("Recipe").font(.headline)
                    Spacer()
                    Button("+ Add material") { rows.append(RecipeRowState()) }
                        .foregroundStyle(Palette.clay700).font(.body.weight(.medium))
                }

                ForEach($rows) { $row in
                    RecipeRowEditor(row: $row, materials: materials, currency: profile.currency) {
                        rows.removeAll { $0.id == row.id }
                    }
                }

                Card {
                    VStack(spacing: 8) {
                        liveRow("What it costs you", Formatting.currency(unitCost, code: profile.currency))
                        liveRow("Sale price", Formatting.currency(priceValue, code: profile.currency))
                        liveRow("Profit per unit", Formatting.currency(profit, code: profile.currency),
                                color: (profit ?? 0) < 0 ? Palette.danger : Palette.ink900)
                        liveRow("Margin", Formatting.percent(margin))
                    }
                }

                if let error { Text(error).foregroundStyle(Palette.danger).font(.callout) }

                Button(busy ? "Saving…" : "Save") { Task { await save() } }
                    .buttonStyle(PrimaryButton()).disabled(busy)
                if existing != nil {
                    Button("Delete product", role: .destructive) { Task { await remove() } }
                        .frame(maxWidth: .infinity).disabled(busy)
                }
            }
            .padding(20)
        }
    }

    private func liveRow(_ label: String, _ value: String, color: Color = Palette.ink900) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.ink500).font(.subheadline)
            Spacer()
            Text(value).font(.body.weight(.medium)).foregroundStyle(color)
        }
    }

    private func prepare() async {
        guard !ready else { return }
        do {
            materials = try await MaterialsService.list()
            if let p = existing {
                name = p.name; sku = p.sku ?? ""; salePrice = p.salePrice.map(String.init) ?? ""
                let recipe = try await ProductsService.recipe(productId: p.id)
                rows = recipe.map { RecipeRowState(materialId: $0.materialId, quantity: String($0.quantity)) }
            }
        } catch { self.error = error.localizedDescription }
        ready = true
    }

    private func save() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Name is required."; return }
        busy = true; error = nil
        let recipe = rows.compactMap { row -> ProductsService.RecipeInput? in
            guard !row.materialId.isEmpty, let q = Double(row.quantity), q > 0 else { return nil }
            return ProductsService.RecipeInput(materialId: row.materialId, quantity: q)
        }
        let input = ProductsService.Input(
            name: name.trimmingCharacters(in: .whitespaces),
            sku: sku.isEmpty ? nil : sku,
            salePrice: salePrice.isEmpty ? nil : Double(salePrice),
            recipe: recipe
        )
        do {
            if let p = existing { try await ProductsService.update(id: p.id, input) }
            else { try await ProductsService.create(input) }
            dismiss()
        } catch { self.error = error.localizedDescription }
        busy = false
    }

    private func remove() async {
        guard let p = existing else { return }
        busy = true; error = nil
        do { try await ProductsService.delete(id: p.id); dismiss() }
        catch { self.error = error.localizedDescription }
        busy = false
    }
}

struct RecipeRowEditor: View {
    @Binding var row: ProductFormView.RecipeRowState
    let materials: [Material]
    let currency: String
    let onRemove: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Material", selection: $row.materialId) {
                    Text("— pick a material —").tag("")
                    ForEach(materials) { m in Text(m.name).tag(m.id) }
                }
                .pickerStyle(.menu)
                HStack {
                    TextField("Quantity", text: $row.quantity).keyboardType(.decimalPad)
                        .padding(8)
                        .background(Palette.cream50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button("Remove", role: .destructive, action: onRemove)
                }
            }
        }
    }
}
