import SwiftUI

/// Shown instead of the app when the on-device store cannot be opened.
struct StoreErrorView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No se pudo abrir tu base de datos", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Tus gastos siguen guardados en el teléfono: no se borró nada. Cierra Centavo por completo y vuelve a abrirlo. Si pasa otra vez, reinicia el teléfono, y no desinstales la app: perderías los gastos.")
        }
    }
}

#Preview { StoreErrorView() }
