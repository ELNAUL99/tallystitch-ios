import SwiftUI

// Native tab bar with SF Symbols — the iOS-native feel that motivated the
// Swift rewrite. Each tab hosts its own NavigationStack so push/pop works
// per-tab the way users expect.
struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { MaterialsListView() }
                .tabItem { Label("Materials", systemImage: "shippingbox.fill") }

            NavigationStack { ProductsListView() }
                .tabItem { Label("Products", systemImage: "square.stack.3d.up.fill") }

            NavigationStack { SalesListView() }
                .tabItem { Label("Sales", systemImage: "cart.fill") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
