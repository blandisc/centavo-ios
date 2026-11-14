import SwiftUI

/// The two halves of the app (2026-10-31): «Hoy», the screen it always had, and «Mi dinero».
/// In «Hoy», beside the tabs, the brass «+» of «Anotar gasto» (owner, 2026-11-14), where the
/// search used to sit. iOS 27 draws no tab apart from the bar (not even the search role's), so
/// it is the system's glass button, laid over the bar's row.
struct RootView: View {
    private enum Place: Hashable { case today, money }
    @State private var place = Place.today
    @State private var addRequests = 0

    var body: some View {
        TabView(selection: $place) {
            Tab("Hoy", systemImage: "calendar", value: Place.today) {
                ExpenseListView(addRequests: addRequests)
            }
            Tab("Mi dinero", systemImage: "wallet.bifold", value: Place.money) {
                MoneyRootView()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if place == .today {
                AddCircle { addRequests += 1 }
            }
        }
    }
}

/// The «+»: a circle of Liquid Glass in the app's brass (the same as «Hoy» in the tabs), as
/// tall as the tab bar, its middle on the bar's. It answers the finger like the bar beside it
/// (owner, 2026-11-14: «más liquid glass», «el mismo color»).
private struct AddCircle: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.ticket(.heading))
                .foregroundStyle(Theme.onBrass)
                .frame(width: Theme.Size.addCircle, height: Theme.Size.addCircle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Theme.brass).interactive(), in: Circle())
        .accessibilityLabel("Anotar gasto")
        .padding(.trailing, Theme.Space.xl)
        .padding(.bottom, Theme.Space.tabBarDrop)
        // Stays down with the keyboard up, behind it, like the tab bar.
        .ignoresSafeArea(.keyboard)
    }
}
