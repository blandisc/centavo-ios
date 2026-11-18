import SwiftUI

/// «Guardar» at the bottom right, under the thumb, riding above the keyboard, with a short
/// line on its left saying what will be saved, or what is still missing. The same in every
/// sheet that saves something; «Cancelar» stays at the top left, where iOS puts it.
private struct SaveBar: View {
    let summary: String
    let enabled: Bool
    let identifier: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // With accessibility type, side by side left the summary three letters wide: «Falt…»,
        // the one line saying why «Guardar» is off (2026-11-18). Stacked, it reads whole.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.sm))
            : AnyLayout(HStackLayout(spacing: Theme.Space.m))
        layout {
            summaryLine(stacked: stacked)
            saveButton(stacked: stacked)
        }
        // 16 on each side: «Guardar» mirrors «Cancelar» at the top.
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.sm)
    }

    private func summaryLine(stacked: Bool) -> some View {
        Text(summary)
            .font(.ticket(.detail))
            .foregroundStyle(enabled ? Theme.ink : Theme.muted)
            // Stacked, a few lines more, not the whole form: the bar rides above the keyboard.
            .lineLimit(stacked ? 4 : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            // On the line of the sections' text (card 16 + row 16).
            .padding(.leading, Theme.Space.l)
            .accessibilityIdentifier("resumen-guardar")
    }

    private func saveButton(stacked: Bool) -> some View {
        // Stacked, as wide as the bar, like every main action under its text.
        let width: CGFloat? = stacked ? .infinity : nil
        return Button(action: action) {
            Text("Guardar")
                .font(.ticket(.button))
                .padding(.horizontal, Theme.Space.s)
                .frame(maxWidth: width, minHeight: Theme.Size.capsuleLabel)
        }
        .ticketProminent()
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
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
        // A bar of the system's own: what scrolls under it fades, as under any toolbar.
        content.safeAreaBar(edge: .bottom) { bar }
    }
}

#Preview("Barra de guardar") {
    NavigationStack {
        Form {
            Section { Text("Contenido de la hoja").font(.ticket(.body)) }
                .listRowBackground(Theme.surface)
        }
        .ticketForm()
        .navigationBarTitleDisplayMode(.inline)
        .ticketBarTitle("Nuevo gasto")
        .saveBar("$89.00 en Oxxo", enabled: true) {}
    }
    .ticketPreview()
}
