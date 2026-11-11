import CentavoCore
import SwiftUI

extension View {
    /// Puts the thousands in while a balance, an amount or a movement of «Mi dinero» is typed
    /// («185000» → «185,000»; owner, 2026-11-11), as `groupsThousands` does for an expense, with
    /// the rule of «Mi dinero» (`MoneyTyping.typed`): the minus in front stays (an overdrawn
    /// account, «−300» taken out of an investment) and what doesn't read is left as written, so
    /// it is said instead of trimmed into another figure. Never on a yearly rate nor an exchange
    /// rate: there «18.125» is eighteen and a bit.
    func groupsMoney(_ text: Binding<String>) -> some View {
        modifier(GroupsMoney(text: text))
    }

    /// A sheet of «Mi dinero» with «Guardar» at the bottom: moving the form puts the keyboard
    /// away, as in the expense sheet, so the number pad (which has no key to close it) never
    /// stays over the rest of the form.
    func moneySheetKeyboard() -> some View {
        scrollDismissesKeyboard(.immediately)
            // iOS 26 ignores the line above in a sheet's form: a drag does it there.
            .simultaneousGesture(DragGesture(minimumDistance: Theme.Space.xl).onChanged { _ in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
    }

    /// A step with its own floor (the first time of «Mi dinero» and its import; owner,
    /// 2026-11-11): the tab bar steps aside, so the step's button is the only thing at the
    /// bottom. Only while «Mi dinero» is open: locked, the tabs stay, or there would be no way
    /// back to «Hoy» without Face ID. They come back when the steps end or are left.
    func hidesTabsForMoneyStep() -> some View {
        modifier(HidesTabsForMoneyStep())
    }
}

private struct GroupsMoney: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        content.onChange(of: text) { old, new in
            let shown = MoneyTyping.typed(new, was: old, decimalSeparator: Locale.current.decimalSeparator ?? ".")
            if shown != new { text = shown }
        }
    }
}

private struct HidesTabsForMoneyStep: ViewModifier {
    @State private var lock = MoneyLockState.shared

    func body(content: Content) -> some View {
        content.toolbar(lock.unlocked ? .hidden : .automatic, for: .tabBar)
    }
}
