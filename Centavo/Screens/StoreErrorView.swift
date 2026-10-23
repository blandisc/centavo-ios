import SwiftUI

/// Shown instead of the app when the on-device store cannot be opened.
struct StoreErrorView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Al día")
                .font(.ticket(.footnoteStrong))
                .tracking(Theme.Tracking.title)
                .textCase(.uppercase)
            Text("No se pudo abrir tu base de datos")
                .font(.ticket(.heading))
                .accessibilityIdentifier("error-base")
            Text("Tus gastos siguen guardados en el teléfono: no se borró nada. Cierra Al día por completo y vuelve a abrirlo. Si pasa otra vez, reinicia el teléfono, y no desinstales la app: perderías los gastos.")
                .font(.ticket(.callout))
                .lineSpacing(Theme.Space.xxs)
                .foregroundStyle(Theme.muted)
        }
        .padding(Theme.Space.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.background.ignoresSafeArea())
    }
}

#Preview { StoreErrorView().ticketPreview() }
