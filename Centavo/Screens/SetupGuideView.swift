import SwiftUI

/// Step-by-step guide to create the Shortcuts "Transaction" automation.
/// Apple does not let an app create that automation for the user.
struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [String] = [
        "Abre la app Atajos y ve a la pestaña Automatización.",
        "Toca «+» y elige «Transacción».",
        "Selecciona tus tarjetas de Wallet y elige «Ejecutar inmediatamente».",
        "Agrega la acción «Registrar gasto» de Centavo.",
        "En Monto, Comercio y Tarjeta elige las variables de la transacción.",
        "Listo: el próximo pago con Wallet aparece aquí solo.",
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Label {
                        Text(step)
                    } icon: {
                        Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Section {
                    Link("Abrir Atajos", destination: URL(string: "shortcuts://")!)
                }
            }
            .navigationTitle("Configurar atajo")
            .toolbar {
                Button("Listo") { dismiss() }
            }
        }
    }
}

#Preview { SetupGuideView() }
