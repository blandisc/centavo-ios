import SwiftUI

/// Something that didn't save: what (the title) and what it means for the person (the detail).
/// The title names the thing — «No se guardó el corte» — so the alert reads from its first
/// line; the detail calms first: «Nada cambió. Intenta otra vez.» (owner, 2026-11-16, D2-A).
struct SaveProblem: Equatable {
    static let unchanged = "Nada cambió. Intenta otra vez."
    /// For a save that can fail more than once in a row: how to get out of it.
    static let unchangedPersisting = "Nada cambió. Intenta otra vez; si sigue, cierra la app y vuelve a abrirla."

    let title: String
    var detail: String = SaveProblem.unchanged
}

extension View {
    /// The one way to say something didn't save: a system alert with the problem's title, its
    /// detail and a single «Aceptar». It shows while `problem` is set and clears it when dismissed.
    func problemAlert(problem: Binding<SaveProblem?>) -> some View {
        alert(problem.wrappedValue?.title ?? "",
              isPresented: Binding(get: { problem.wrappedValue != nil },
                                   set: { if !$0 { problem.wrappedValue = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(problem.wrappedValue?.detail ?? "")
        }
    }

    /// The same alert when it's always the same thing that didn't save.
    func problemAlert(_ title: String, isPresented: Binding<Bool>,
                      detail: String = SaveProblem.unchanged) -> some View {
        alert(title, isPresented: isPresented) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(detail)
        }
    }
}
