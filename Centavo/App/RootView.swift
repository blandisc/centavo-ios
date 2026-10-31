import SwiftUI

/// The two halves of the app (2026-10-31): «Hoy», the screen it always had, and «Mi dinero».
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Hoy", systemImage: "calendar") {
                ExpenseListView()
            }
            Tab("Mi dinero", systemImage: "wallet.bifold") {
                MoneyRootView()
            }
        }
    }
}
