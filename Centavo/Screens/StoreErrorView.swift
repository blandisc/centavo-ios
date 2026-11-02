import SwiftUI

/// Shown instead of the app when the on-device store cannot be opened. It scrolls, so the
/// largest accessibility text sizes never cut it short (2026-11-02, second audit).
struct StoreErrorView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text("Al día")
                    .font(.ticket(.footnoteStrong))
                    .tracking(Theme.Tracking.title)
                    .textCase(.uppercase)
                Text("Al día no pudo abrir tus gastos")
                    .font(.ticket(.heading))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("error-base")
                Text("Tus gastos siguen guardados en este iPhone; no se borró nada. Cierra Al día por completo y ábrela de nuevo. Si sigue igual, reinicia el iPhone. No desinstales la app: perderías tus gastos.")
                    .font(.ticket(.callout))
                    .lineSpacing(Theme.Space.xxs)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.screen)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

#Preview { StoreErrorView().ticketPreview() }
