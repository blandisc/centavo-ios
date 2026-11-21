import SwiftUI

/// The «→» beside an amount: the decimal pad has no return key, and a keyboard bar does
/// not show inside a sheet, so while the amount is typed the arrow lives in its row and takes
/// the cursor to the next field. Its room is always kept, so it does not push what is beside
/// it each time the keyboard comes and goes. The fixed expense's sheet (2026-11-18) uses it;
/// the same arrow as the expense sheet's.
///
///     NextKey("Ir al nombre", visible: amountFocused) { nameFocused = true }
///
/// Its title is what VoiceOver reads: where it goes («Ir al nombre»), never a bare «Siguiente»
/// (owner, X1-B, 2026-11-20).
struct NextKey: View {
    let title: LocalizedStringResource
    let visible: Bool
    var identifier = "siguiente-teclado"
    let action: () -> Void

    init(_ title: LocalizedStringResource, visible: Bool, identifier: String = "siguiente-teclado",
         action: @escaping () -> Void) {
        self.title = title
        self.visible = visible
        self.identifier = identifier
        self.action = action
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(String(localized: title), systemImage: "arrow.right", action: action)
            .labelStyle(.iconOnly)
            .font(.ticket(.footnoteStrong))
            .foregroundStyle(Theme.brass)
            // The arrow on the card's edge, mirroring «0.00»; the target stays 44.
            .frame(minWidth: Theme.Size.tapTarget, minHeight: Theme.Size.tapTarget,
                   alignment: .trailing)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .opacity(visible ? Theme.Opacity.visible : Theme.Opacity.hidden)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
            .animation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion), value: visible)
            .accessibilityIdentifier(identifier)
    }
}

#Preview("Ir al siguiente campo") {
    Form {
        Section {
            HStack(spacing: Theme.Space.s) {
                AmountInputField("Monto", text: .constant("1,200"), prompt: "0.00")
                NextKey("Ir al nombre", visible: true) {}
            }
        }
        .listRowBackground(Theme.surface)
    }
    .ticketForm()
    .ticketPreview()
}
