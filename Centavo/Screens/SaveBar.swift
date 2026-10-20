import SwiftUI

/// «Guardar» at the bottom right, under the thumb, riding above the keyboard, with a short
/// line on its left saying what will be saved, or what is still missing. The same in every
/// sheet that saves something; «Cancelar» stays at the top left, where iOS puts it.
private struct SaveBar: View {
    let summary: String
    let enabled: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(summary)
                .font(.ticket(12, relativeTo: .footnote))
                .foregroundStyle(enabled ? Theme.ink : Theme.muted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("resumen-guardar")
            Button(action: action) {
                Text("Guardar")
                    .font(.ticket(14, weight: .semibold, relativeTo: .body))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 34)
            }
            .modifier(ProminentCapsule())
            .disabled(!enabled)
            .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.vertical, 10)
    }
}

/// The system's prominent button in brass: Liquid Glass on iOS 26, a filled capsule before.
private struct ProminentCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonStyle(.glassProminent).tint(Theme.brass)
        } else {
            content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(Theme.brass)
        }
    }
}

extension View {
    /// Puts the sheet's «Guardar» at the bottom (see `SaveBar`).
    func saveBar(_ summary: String, enabled: Bool, identifier: String = "hoja-guardar",
                 action: @escaping () -> Void) -> some View {
        modifier(SaveBarPlacement(bar: SaveBar(summary: summary, enabled: enabled,
                                               identifier: identifier, action: action)))
    }
}

private struct SaveBarPlacement: ViewModifier {
    let bar: SaveBar

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // A bar of the system's own: what scrolls under it fades, as under any toolbar.
            content.safeAreaBar(edge: .bottom) { bar }
        } else {
            content.safeAreaInset(edge: .bottom) { bar.background(Theme.background) }
        }
    }
}
