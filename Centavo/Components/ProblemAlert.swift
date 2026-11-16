import SwiftUI

extension View {
    /// The one way to say something didn't save: a system alert with the title, the reason
    /// as its message and a single «Aceptar». It shows while `problem` holds a reason and
    /// clears it when dismissed.
    func problemAlert(_ title: LocalizedStringKey = "No se guardó", problem: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(get: { problem.wrappedValue != nil },
                                          set: { if !$0 { problem.wrappedValue = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(problem.wrappedValue ?? "")
        }
    }

    /// The same alert when the reason is always the same sentence.
    func problemAlert(_ title: LocalizedStringKey = "No se guardó", isPresented: Binding<Bool>,
                      message: LocalizedStringKey) -> some View {
        alert(title, isPresented: isPresented) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}
