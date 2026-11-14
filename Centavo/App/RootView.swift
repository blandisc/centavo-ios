import SwiftUI

/// The two halves of the app (2026-10-31): «Hoy», the screen it always had, and «Mi dinero».
/// Beside the tabs, on its own, the «+» of «Anotar gasto» (owner, 2026-11-14): it is not a third
/// place to go, so tapping it never stays selected; it goes to «Hoy» and opens the sheet there.
struct RootView: View {
    private enum Place: Hashable { case today, money, add }
    @State private var place = Place.today
    @State private var addRequests = 0

    var body: some View {
        // The search role keeps it last and apart where iOS draws it so (26); nothing in it searches.
        let selection = Binding<Place>(
            get: { place },
            set: { new in
                guard new == .add else { place = new; return }
                place = .today
                addRequests += 1
            }
        )
        TabView(selection: selection) {
            Tab("Hoy", systemImage: "calendar", value: Place.today) {
                ExpenseListView(addRequests: addRequests)
            }
            Tab("Mi dinero", systemImage: "wallet.bifold", value: Place.money) {
                MoneyRootView()
            }
            Tab(value: Place.add, role: .search) {
                EmptyView()
            } label: {
                Label("Anotar gasto", systemImage: "plus")
            }
        }
    }
}
