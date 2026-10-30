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
        HStack(spacing: Theme.Space.m) {
            Text(summary)
                .font(.ticket(.detail))
                .foregroundStyle(enabled ? Theme.ink : Theme.muted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                // On the line of the sections' text (card 16 + row 16).
                .padding(.leading, Theme.Space.l)
                .accessibilityIdentifier("resumen-guardar")
            Button(action: action) {
                Text("Guardar")
                    .font(.ticket(.button))
                    .padding(.horizontal, Theme.Space.s)
                    .frame(minHeight: Theme.Size.capsuleLabel)
            }
            .ticketProminent()
            .disabled(!enabled)
            .accessibilityIdentifier(identifier)
        }
        // 16 on each side: «Guardar» mirrors «Cancelar» at the top.
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.sm)
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
