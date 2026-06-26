import SwiftUI
import TallystitchCore

private let onboardingCurrencies = ["USD", "EUR", "GBP", "CAD", "AUD", "NZD", "JPY"]

// Four-step first-run wizard — mirror of the RN onboarding. Steps gate on the
// previous; completion is driven by head-count queries refetched on appear.
struct OnboardingView: View {
    @EnvironmentObject var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var businessName = ""
    @State private var currency = "USD"
    @State private var savingBasics = false
    @State private var basicsMsg: String?
    @State private var counts = (materials: 0, products: 0, orders: 0)
    @State private var sampleBusy = false
    @State private var finishing = false

    private var hasBasics: Bool { profile.profile?.businessName != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tallystitch").foregroundStyle(Palette.clay700).font(.subheadline.weight(.semibold))
                Text("Welcome").font(.largeTitle.weight(.semibold))
                Text("Four small steps to your real numbers.").foregroundStyle(Palette.ink500)

                StepCard(n: 1, title: "Your workshop", done: hasBasics) {
                    LabeledField(label: "Business name", text: $businessName)
                    Picker("Currency", selection: $currency) {
                        ForEach(onboardingCurrencies, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu)
                    if let basicsMsg { Text(basicsMsg).foregroundStyle(Palette.sage700).font(.callout) }
                    Button(savingBasics ? "Saving…" : "Save") { Task { await saveBasics() } }
                        .buttonStyle(PrimaryButton()).disabled(savingBasics)
                }

                StepCard(n: 2, title: "Add one material", done: counts.materials > 0, disabled: !hasBasics) {
                    Text("Anything you buy to make things — yarn, oil, jars.").foregroundStyle(Palette.ink500).font(.subheadline)
                    NavigationLink("Add a material") { MaterialFormView() }
                        .buttonStyle(PrimaryButton()).disabled(!hasBasics)
                    if counts.materials > 0 { Text("✓ \(counts.materials) added").foregroundStyle(Palette.sage700).font(.subheadline) }
                }

                StepCard(n: 3, title: "Create one product recipe", done: counts.products > 0, disabled: counts.materials == 0) {
                    Text("Build a recipe and we'll calculate what it really costs.").foregroundStyle(Palette.ink500).font(.subheadline)
                    NavigationLink("Add a product") { ProductFormView() }
                        .buttonStyle(PrimaryButton()).disabled(counts.materials == 0)
                    if counts.products > 0 { Text("✓ \(counts.products) added").foregroundStyle(Palette.sage700).font(.subheadline) }
                }

                StepCard(n: 4, title: "Log one sale", done: counts.orders > 0, disabled: counts.products == 0) {
                    Text("Record a sale and watch the stock deduct itself.").foregroundStyle(Palette.ink500).font(.subheadline)
                    NavigationLink("Add a sale") { SaleFormView() }
                        .buttonStyle(PrimaryButton()).disabled(counts.products == 0)
                    if counts.orders > 0 { Text("✓ \(counts.orders) logged").foregroundStyle(Palette.sage700).font(.subheadline) }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Just want to look around?").font(.headline)
                        Text("Load a demo candle & soap shop with stock and a few orders. Clear it from Settings.")
                            .foregroundStyle(Palette.ink500).font(.subheadline)
                        Button(sampleBusy ? "Loading…" : "Load sample data") { Task { await loadSample() } }.disabled(sampleBusy)
                    }
                }

                Button(finishing ? "Finishing…" : "I'm ready — go to dashboard") { Task { await finish() } }
                    .buttonStyle(PrimaryButton()).disabled(finishing)
                Button("Skip for now") { Task { await finish() } }
                    .foregroundStyle(Palette.ink500).frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(Palette.cream50)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            businessName = profile.profile?.businessName ?? ""
            currency = profile.currency
            Task { await loadCounts() }
        }
    }

    private func loadCounts() async {
        async let m = count("materials")
        async let p = count("products")
        async let o = count("orders")
        counts = (await m, await p, await o)
    }

    private func count(_ table: String) async -> Int {
        (try? await supabase.from(table).select("*", head: true, count: .exact).execute().count) ?? 0
    }

    private func saveBasics() async {
        guard !businessName.trimmingCharacters(in: .whitespaces).isEmpty else { basicsMsg = "Add a business name to continue."; return }
        savingBasics = true; basicsMsg = nil
        do { try await profile.updateBusiness(name: businessName, currency: currency); basicsMsg = "Saved." }
        catch { basicsMsg = error.localizedDescription }
        savingBasics = false
    }
    private func loadSample() async {
        sampleBusy = true
        try? await SampleData.load()
        await loadCounts()
        sampleBusy = false
    }
    private func finish() async {
        finishing = true
        try? await profile.markOnboardingComplete()
        finishing = false
        dismiss()
    }
}

struct StepCard<Content: View>: View {
    let n: Int
    let title: String
    var done: Bool = false
    var disabled: Bool = false
    @ViewBuilder var content: Content
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(done ? Palette.sage500 : Palette.clay50).frame(width: 28, height: 28)
                        Text(done ? "✓" : "\(n)").font(.subheadline.weight(.semibold))
                            .foregroundStyle(done ? .white : Palette.clay700)
                    }
                    Text(title).font(.headline)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(disabled ? 0.6 : 1)
        }
    }
}
