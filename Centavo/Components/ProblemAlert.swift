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
    /// The same thing again, from the alert («Intentar otra vez», audit CT-3, 2026-11-20). `nil`
    /// only when trying again can't help (a file that was refused): then a single «Entendido, cerrar».
    var retry: (@MainActor () -> Void)?

    /// A literal title: looked up in the catalog. The detail is shown as it is: pass
    /// `String(localized: "…")` for one of its own.
    init(title: LocalizedStringResource, detail: String = SaveProblem.unchanged,
         retry: (@MainActor () -> Void)?) {
        self.init(title: String(localized: title), detail: detail, retry: retry)
    }

    /// A title made at run time, shown as it is.
    @_disfavoredOverload
    init<S: StringProtocol>(title: S, detail: String = SaveProblem.unchanged,
                            retry: (@MainActor () -> Void)?) {
        self.title = String(title)
        self.detail = detail
        self.retry = retry
    }

    /// Two problems are the same when they say the same; the retry is not compared.
    static func == (lhs: SaveProblem, rhs: SaveProblem) -> Bool {
        lhs.title == rhs.title && lhs.detail == rhs.detail && (lhs.retry == nil) == (rhs.retry == nil)
    }
}

/// The buttons of every problem alert: «Intentar otra vez» and «Ahora no», or only «Entendido,
/// cerrar» when trying again can't help. Never «Aceptar» (owner, X1-B, 2026-11-20: a button says
/// what it does).
private struct ProblemButtons: View {
    let retry: (@MainActor () -> Void)?

    var body: some View {
        if let retry {
            Button("Intentar otra vez") {
                // After the alert is gone: a second failure shows its own alert, instead of being
                // cleared by this one's dismissal.
                Task { @MainActor in
                    try? await Task.sleep(for: Theme.Motion.alertHandoff)
                    retry()
                }
            }
            .accessibilityIdentifier("aviso-reintentar")
            Button("Ahora no", role: .cancel) {}
                .accessibilityIdentifier("aviso-ahora-no")
        } else {
            Button("Entendido, cerrar", role: .cancel) {}
                .accessibilityIdentifier("aviso-cerrar")
        }
    }
}

extension View {
    /// The one way to say something didn't save: a system alert with the problem's title, its
    /// detail, «Intentar otra vez» (which runs the problem's `retry`) and «Ahora no». It shows
    /// while `problem` is set and clears it when dismissed.
    func problemAlert(problem: Binding<SaveProblem?>) -> some View {
        let retry = problem.wrappedValue?.retry
        return alert(problem.wrappedValue?.title ?? "",
                     isPresented: Binding(get: { problem.wrappedValue != nil },
                                          set: { if !$0 { problem.wrappedValue = nil } })) {
            ProblemButtons(retry: retry)
        } message: {
            // «··· › Ajustes» said «Más › Ajustes» with VoiceOver (`MenuPath`): the backup's errors.
            Text(MenuPath.forAlert(problem.wrappedValue?.detail ?? ""))
        }
    }

    /// The same alert when it's always the same thing that didn't save. A literal title is
    /// looked up in the catalog; the detail is shown as it is.
    func problemAlert(_ title: LocalizedStringResource, isPresented: Binding<Bool>,
                      detail: String = SaveProblem.unchanged,
                      retry: (@MainActor () -> Void)?) -> some View {
        problemAlert(String(localized: title), isPresented: isPresented, detail: detail, retry: retry)
    }

    /// The same, with a title made at run time.
    @_disfavoredOverload
    func problemAlert<S: StringProtocol>(_ title: S, isPresented: Binding<Bool>,
                                         detail: String = SaveProblem.unchanged,
                                         retry: (@MainActor () -> Void)?) -> some View {
        alert(String(title), isPresented: isPresented) {
            ProblemButtons(retry: retry)
        } message: {
            Text(MenuPath.forAlert(detail))
        }
    }
}
