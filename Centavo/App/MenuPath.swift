import SwiftUI

/// A way through the «···» menu written in a sentence («··· › Ajustes › Respaldo diario»), as
/// VoiceOver says it (2026-11-19). On screen the button is only its three dots, so the texts
/// name it so; VoiceOver calls it «Más», reads the dots as «punto medio» or skips them, and the
/// way couldn't be followed. The text on screen stays as it is.
enum MenuPath {
    /// What the texts show for the menu's button.
    static let dots = "···"

    /// `shown` with the button by the name VoiceOver gives it: «Más» (in English, «More»).
    /// `button`: that name, the catalog's by default (tests pass their own).
    static func spoken(_ shown: String, button: String = MenuPath.buttonName) -> String {
        shown.replacingOccurrences(of: dots, with: button)
    }

    /// The «···» button's label in «Hoy» (`Label("Más", systemImage: "ellipsis")`).
    static var buttonName: String {
        String(localized: "Más", comment: "Hoy (main screen): «···» menu button (VoiceOver)")
    }
}

extension View {
    /// The text's way through «···» said with the button's spoken name (`MenuPath`). `shown`:
    /// the same text the view shows, already in the iPhone's language.
    func spokenMenuPath(_ shown: String) -> some View {
        accessibilityLabel(MenuPath.spoken(shown))
    }
}
