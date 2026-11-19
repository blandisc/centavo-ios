import SwiftUI

/// Something that didn't save: what (the title) and what it means for the person (the detail).
/// The title names the thing — «No se guardó el corte» — so the alert reads from its first
/// line; the detail calms first: «Nada cambió. Intenta otra vez.» (owner, 2026-11-16, D2-A).
struct SaveProblem: Equatable {
    static let unchanged = String(localized: "Nada cambió. Intenta otra vez.")
    /// For a save that can fail more than once in a row: how to get out of it.
    static let unchangedPersisting = String(localized: "Nada cambió. Intenta otra vez; si sigue, cierra la app y vuelve a abrirla.")

    let title: String
    var detail: String = SaveProblem.unchanged

    /// A literal title: looked up in the catalog. The detail is shown as it is: pass
    /// `String(localized: "…")` for one of its own.
    init(title: LocalizedStringResource, detail: String = SaveProblem.unchanged) {
        self.init(title: String(localized: title), detail: detail)
    }

    /// A title made at run time, shown as it is.
    @_disfavoredOverload
    init<S: StringProtocol>(title: S, detail: String = SaveProblem.unchanged) {
        self.title = String(title)
        self.detail = detail
    }
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
            // «··· › Ajustes» said «Más › Ajustes» with VoiceOver (`MenuPath`): the backup's errors.
            Text(MenuPath.forAlert(problem.wrappedValue?.detail ?? ""))
        }
    }

    /// The same alert when it's always the same thing that didn't save. A literal title is
    /// looked up in the catalog; the detail is shown as it is.
    func problemAlert(_ title: LocalizedStringResource, isPresented: Binding<Bool>,
                      detail: String = SaveProblem.unchanged) -> some View {
        problemAlert(String(localized: title), isPresented: isPresented, detail: detail)
    }

    /// The same, with a title made at run time.
    @_disfavoredOverload
    func problemAlert<S: StringProtocol>(_ title: S, isPresented: Binding<Bool>,
                                         detail: String = SaveProblem.unchanged) -> some View {
        alert(String(title), isPresented: isPresented) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(MenuPath.forAlert(detail))
        }
    }
}
