import SwiftUI

/// The two halves of the app (2026-10-31): «Hoy», the screen it always had, and «Mi dinero»
/// (off for the launch, 2026-11-18: `Features.money`; then only «Hoy», without tabs).
/// In «Hoy», beside the tabs, the brass «+» of «Anotar gasto» (owner, 2026-11-14), where the
/// search used to sit. iOS 27 draws no tab apart from the bar (not even the search role's), so
/// it is the system's glass button, laid over the bar's row.
struct RootView: View {
    private enum Place: Hashable { case today, money }
    @State private var place = Place.today
    @State private var addRequests = 0

    var body: some View {
        if Features.money {
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
                    AddCircle(besideTabs: true) { addRequests += 1 }
                }
            }
        } else {
            // «Mi dinero» off (owner, 2026-11-18): no tab bar for one tab. The «+» stays at the
            // bottom right, and the list leaves room under its last row for it. A bar of the
            // system's, not an inset: the list blurs under the «+» as it did under the tabs
            // (2026-11-14); under a plain inset it was cut off sharp behind the glass.
            ExpenseListView(addRequests: addRequests)
                .safeAreaBar(edge: .bottom, alignment: .trailing, spacing: Theme.Space.none) {
                    AddCircle(besideTabs: false) { addRequests += 1 }
                }
        }
    }
}

/// The «+»: the system's glass, the same as the tab bar's, with a brass «+» (owner,
/// 2026-11-14, option A over brass glass), as tall as the bar and with its middle on the bar's.
private struct AddCircle: View {
    /// Laid over the tab bar's row (with «Mi dinero»), or on its own at the bottom.
    let besideTabs: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.ticket(.heading))
                .foregroundStyle(Theme.brass)
                // The glass adds its own margin around this: together, the bar's height.
                .frame(width: Theme.Size.addCircle, height: Theme.Size.addCircle)
        }
        .ticketGlass()
        .buttonBorderShape(.circle)
        .accessibilityLabel("Anotar gasto")
        .padding(.trailing, Theme.Space.xl)
        .padding(.bottom, besideTabs ? Theme.Space.tabBarDrop : Theme.Space.xs)
        // Stays down with the keyboard up, behind it, as the tab bar does.
        .ignoresSafeArea(.keyboard)
    }
}
