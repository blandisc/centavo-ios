import SwiftUI
import UIKit

/// The one bar over the keyboard (owner, 2026-11-11): the whole width, on the paper, stuck to
/// the keyboard's top, with what helps while typing («Sin cambio», «Siguiente») on its left and
/// «Ocultar teclado» on its right. It is part of the safe area, so the page stops scrolling
/// right above it and the field being filled is never under a button. It replaces the system's
/// keyboard toolbar, which in iOS 26 floats as loose capsules over the page (they covered the
/// end of «¿Te da rendimiento? · Opcional» and the row's own «Sin cambio»), and which does not
/// show at all in some sheets.
private struct KeyboardBar<Actions: View>: View {
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            actions()
            Spacer(minLength: Theme.Space.s)
            Button(action: hideKeyboard) {
                // In words while they fit; with large text, the system's own symbol for it.
                ViewThatFits(in: .horizontal) {
                    Text("Ocultar teclado").lineLimit(1)
                    Image(systemName: "keyboard.chevron.compact.down")
                }
            }
            .accessibilityLabel("Ocultar teclado")
            .accessibilityIdentifier("ocultar-teclado")
        }
        .font(.ticket(.footnoteStrong))
        .foregroundStyle(Theme.brass)
        .buttonStyle(.tapTarget)
        .padding(.horizontal, Theme.Space.l)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: Theme.Stroke.hairline)
        }
    }
}

extension View {
    /// Puts the keyboard's bar under this page or form (see `KeyboardBar`): only while the
    /// keyboard is up, with «Ocultar teclado» always at its right. `actions` are plain
    /// `Button`s; the bar gives them its typeface, the brass and a 44 pt touch.
    func keyboardBar<Actions: View>(@ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(KeyboardBarPlacement(actions: actions))
    }

    /// The keyboard's bar with «Ocultar teclado» alone.
    func keyboardBar() -> some View {
        keyboardBar { EmptyView() }
    }

    /// Says whether the keyboard is up: for what must step aside while typing (a step's own
    /// button at the bottom, so there are never two bars over the keyboard).
    func tracksKeyboard(_ isUp: Binding<Bool>) -> some View {
        onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isUp.wrappedValue = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isUp.wrappedValue = false
        }
    }
}

private struct KeyboardBarPlacement<Actions: View>: ViewModifier {
    @ViewBuilder var actions: () -> Actions
    @State private var keyboardUp = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: Theme.Space.none) {
                if keyboardUp { KeyboardBar(actions: actions) }
            }
            .tracksKeyboard($keyboardUp)
    }
}

@MainActor private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

#Preview("Barra del teclado") {
    @Previewable @State var text = ""
    NavigationStack {
        Form {
            Section {
                TicketTextField("Saldo", text: $text, prompt: "Escribe el saldo")
            } footer: {
                HintText("Toca el campo: la barra aparece pegada al teclado.")
            }
            .listRowBackground(Theme.surface)
        }
        .ticketForm()
        .keyboardBar {
            Button("Sin cambio") {}
            Button("Siguiente") {}
        }
    }
    .ticketPreview()
}
