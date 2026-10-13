import SwiftUI

/// Step-by-step guide to create the Shortcuts "Transaction" automation.
/// Apple does not let an app create that automation for the user.
struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [String] = [
        "Abre la app Atajos y ve a la pestaña Automatización.",
        "Toca «+» y elige «Transacción» (en versiones recientes de iOS se llama «Wallet»).",
        "Selecciona tus tarjetas, deja marcadas todas las categorías y elige «Ejecutar inmediatamente».",
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
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.tint)
                                .frame(minWidth: 20, alignment: .leading)
                            Text(step)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section("Bueno saber") {
                    ForEach(notes, id: \.self) { note in
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Link(destination: URL(string: "shortcuts://")!) {
                        Label("Abrir Atajos", systemImage: "arrow.up.forward.app")
                    }
                }
            }
            .navigationTitle("Configurar atajo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .accessibilityIdentifier("hoja-listo")
                }
            }
        }
    }
}

#Preview { SetupGuideView() }
