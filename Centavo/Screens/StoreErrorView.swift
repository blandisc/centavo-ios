import SwiftUI

/// Shown instead of the app when the on-device store cannot be opened.
struct StoreErrorView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Al día")
                .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                .tracking(2)
                .textCase(.uppercase)
            Text("No se pudo abrir tu base de datos")
                .font(.ticket(22, weight: .medium, relativeTo: .title2))
                .accessibilityIdentifier("error-base")
            Text("Tus gastos siguen guardados en el teléfono: no se borró nada. Cierra Al día por completo y vuelve a abrirlo. Si pasa otra vez, reinicia el teléfono, y no desinstales la app: perderías los gastos.")
                .font(.ticket(14, relativeTo: .callout))
                .lineSpacing(5)
                .foregroundStyle(Theme.muted)
        }
        .padding(Theme.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.background.ignoresSafeArea())
    }
}

#Preview { StoreErrorView().preferredColorScheme(.dark) }
