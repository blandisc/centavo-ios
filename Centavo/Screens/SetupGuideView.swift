import SwiftUI

/// Step-by-step guide to create the Shortcuts "Transaction" automation.
/// Apple does not let an app create that automation for the user.
struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [String] = [
        "Abre la app Atajos y ve a la pestaña Automatización.",
        "Toca «+» y elige «Transacción» (en versiones recientes de iOS se llama «Wallet»).",
        "Selecciona tus tarjetas, deja marcadas todas las categorías y elige «Ejecutar inmediatamente». Si además activas que te avise al ejecutarse, cada pago te dirá cuánto te queda del presupuesto.",
        "Agrega la acción «Registrar gasto» de Centavo.",
        "En Monto, Comercio y Tarjeta elige las variables de la transacción.",
        "Listo: el próximo pago con Wallet aparece aquí solo.",
    ]

    private let notes: [String] = [
        "Solo se anotan los pagos en los que acercas el iPhone o el reloj a la terminal. Las compras en línea y dentro de apps anótalas tú.",
        "Con algunos bancos el aviso de Wallet llega tarde y el atajo no alcanza a correr. Si un pago no aparece, anótalo tú.",
        "Un pago rechazado también puede anotarse. Deslízalo hacia la izquierda y bórralo.",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String(format: "%02d", index + 1))
                                .foregroundStyle(Theme.brass)
                                .frame(minWidth: 28, alignment: .leading)
                            Text(step).foregroundStyle(Theme.ink)
                        }
                        .font(.ticket(13, relativeTo: .footnote))
                        .lineSpacing(4)
                        .accessibilityElement(children: .combine)
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    ForEach(notes, id: \.self) { note in
                        Text(note)
                            .font(.ticket(12, relativeTo: .footnote))
                            .lineSpacing(4)
                            .foregroundStyle(Theme.muted)
                    }
                } header: {
                    Text("Bueno saber").ticketCaption()
                }
                .listRowBackground(Theme.surface)

                Section {
                    Link(destination: URL(string: "shortcuts://")!) {
                        Label("Abrir Atajos", systemImage: "arrow.up.forward.app")
                            .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                            .tracking(1.4)
                            .textCase(.uppercase)
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Configurar atajo")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                        .accessibilityIdentifier("hoja-listo")
                }
            }
        }
    }
}

#Preview { SetupGuideView().preferredColorScheme(.dark) }
