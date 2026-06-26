import SwiftUI
import TallystitchCore

private let currencies = ["USD", "EUR", "GBP", "CAD", "AUD", "NZD", "JPY", "CHF", "SEK", "NOK", "DKK"]

struct SettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var profile: ProfileStore

    @State private var businessName = ""
    @State private var currency = "USD"
    @State private var savingSettings = false
    @State private var settingsMsg: String?
    @State private var sampleBusy = false
    @State private var sampleMsg: String?
    @State private var showOnboarding = false

    var body: some View {
        Form {
            Section("Your workshop") {
                TextField("Business name", text: $businessName)
                Picker("Currency", selection: $currency) {
                    ForEach(currencies, id: \.self) { Text($0).tag($0) }
                }
                if let settingsMsg { Text(settingsMsg).foregroundStyle(Palette.sage700).font(.callout) }
                Button(savingSettings ? "Saving…" : "Save") { Task { await save() } }.disabled(savingSettings)
            }

            Section("Subscription") {
                LabeledContent("Status", value: statusLabel)
                if profile.profile?.subscriptionStatus == .trialing, let p = profile.profile {
                    LabeledContent("Trial ends in", value: "\(Access.trialDaysRemaining(trialEndsAt: p.trialEndsAt)) days")
                }
                Text("Subscriptions are managed on the web for now. In-app purchases arrive in a future update.")
                    .font(.caption).foregroundStyle(Palette.ink500)
            }

            Section("Getting started") {
                Button("Open setup guide") { showOnboarding = true }
                Button(sampleBusy ? "Loading…" : "Load sample data") { Task { await loadSample() } }.disabled(sampleBusy)
                Button("Clear sample data", role: .destructive) { Task { await clearSample() } }.disabled(sampleBusy)
                if let sampleMsg { Text(sampleMsg).font(.callout).foregroundStyle(Palette.ink700) }
            }

            Section("Account") {
                Button("Log out") { Task { await auth.signOut() } }
                Button("Delete my account", role: .destructive) { Task { await deleteAccount() } }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            businessName = profile.profile?.businessName ?? ""
            currency = profile.currency
        }
        .sheet(isPresented: $showOnboarding) { NavigationStack { OnboardingView() } }
    }

    private var statusLabel: String {
        switch profile.profile?.subscriptionStatus {
        case .trialing: return "Free trial"
        case .active: return "Active subscription"
        case .pastDue: return "Payment past due"
        case .canceled: return "Canceled"
        case .incomplete: return "Setup incomplete"
        case .none: return "—"
        }
    }

    private func save() async {
        savingSettings = true; settingsMsg = nil
        do { try await profile.updateBusiness(name: businessName, currency: currency); settingsMsg = "Saved." }
        catch { settingsMsg = error.localizedDescription }
        savingSettings = false
    }
    private func loadSample() async {
        sampleBusy = true; sampleMsg = nil
        do { try await SampleData.load(); sampleMsg = "Sample data loaded. Pull to refresh any tab." }
        catch { sampleMsg = error.localizedDescription }
        sampleBusy = false
    }
    private func clearSample() async {
        sampleBusy = true; sampleMsg = nil
        do { try await SampleData.clear(); sampleMsg = "Sample data cleared." }
        catch { sampleMsg = error.localizedDescription }
        sampleBusy = false
    }
    private func deleteAccount() async {
        do { try await AccountService.deleteAccount() }
        catch { settingsMsg = error.localizedDescription }
    }
}
