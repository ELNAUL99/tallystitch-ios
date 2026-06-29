import SwiftUI
import TallystitchCore

struct MaterialsListView: View {
    @EnvironmentObject var profile: ProfileStore
    @State private var materials: [TallystitchCore.Material] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error { Text(error).foregroundStyle(Palette.danger).font(.callout) }
                if materials.isEmpty && loaded {
                    Card {
                        VStack(spacing: 8) {
                            Text("No materials yet").font(.headline)
                            Text("A material is anything you buy to make your products — yarn, oil, jars.")
                                .multilineTextAlignment(.center).foregroundStyle(Palette.ink500)
                            NavigationLink("Add your first material") { MaterialFormView() }
                                .buttonStyle(PrimaryButton())
                        }
                    }
                } else {
                    Card {
                        VStack(spacing: 0) {
                            ForEach(materials) { m in
                                NavigationLink { MaterialFormView(existing: m) } label: { MaterialRow(material: m, currency: profile.currency) }
                                if m.id != materials.last?.id { Divider().background(Palette.cream200) }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.cream50)
        .navigationTitle("Materials")
        .toolbar { NavigationLink { MaterialFormView() } label: { Image(systemName: "plus") } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { materials = try await MaterialsService.list() } catch { self.error = error.localizedDescription }
        loaded = true
    }
}

struct MaterialRow: View {
    let material: TallystitchCore.Material
    let currency: String
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(material.name).font(.body.weight(.medium)).foregroundStyle(Palette.ink900)
                Text("\(Formatting.currency(material.costPerUnit, code: currency)) / \(material.unit)")
                    .font(.caption).foregroundStyle(Palette.ink500)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(Formatting.qty(material.stockOnHand)) \(material.unit)").foregroundStyle(Palette.ink900)
                if material.isLowStock {
                    Text("Low").font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Palette.amberBg).foregroundStyle(Palette.amberFg).clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct MaterialFormView: View {
    @EnvironmentObject var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    var existing: TallystitchCore.Material?

    @State private var name = ""
    @State private var unit = "piece"
    @State private var cost = "0"
    @State private var stock = "0"
    @State private var lowThreshold = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Unit (g, ml, piece…)", text: $unit).autocapitalization(.none)
                TextField("Cost per unit (\(profile.currency))", text: $cost).keyboardType(.decimalPad)
                TextField("Current stock", text: $stock).keyboardType(.decimalPad)
                TextField("Alert when below (optional)", text: $lowThreshold).keyboardType(.decimalPad)
            }
            if let error { Text(error).foregroundStyle(Palette.danger) }
            Section {
                Button(busy ? "Saving…" : "Save") { Task { await save() } }.disabled(busy)
                if existing != nil {
                    Button("Delete material", role: .destructive) { Task { await remove() } }.disabled(busy)
                }
            }
        }
        .navigationTitle(existing == nil ? "Add material" : "Edit material")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: seed)
    }

    private func seed() {
        guard let m = existing else { return }
        name = m.name; unit = m.unit
        cost = String(m.costPerUnit); stock = String(m.stockOnHand)
        lowThreshold = m.lowStockThreshold.map { String($0) } ?? ""
    }

    private func save() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Name is required."; return }
        busy = true; error = nil
        let input = MaterialsService.Input(
            name: name.trimmingCharacters(in: .whitespaces),
            unit: unit.trimmingCharacters(in: .whitespaces),
            cost_per_unit: Double(cost) ?? 0,
            stock_on_hand: Double(stock) ?? 0,
            low_stock_threshold: lowThreshold.isEmpty ? nil : Double(lowThreshold)
        )
        do {
            if let m = existing { try await MaterialsService.update(id: m.id, input) }
            else { try await MaterialsService.create(input) }
            dismiss()
        } catch { self.error = error.localizedDescription }
        busy = false
    }

    private func remove() async {
        guard let m = existing else { return }
        busy = true; error = nil
        do { try await MaterialsService.delete(id: m.id); dismiss() }
        catch { self.error = error.localizedDescription }
        busy = false
    }
}
