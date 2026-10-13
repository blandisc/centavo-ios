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
        "Solo se anotan los pagos en los que acercas el iPhone o el reloj a la terminal. Las compras en línea y dentro de apps agrégalas con «+».",
        "Con algunos bancos el aviso de Wallet llega tarde y el atajo no alcanza a correr. Si un pago no aparece, agrégalo con «+».",
        "Un pago rechazado también puede anotarse. Bórralo deslizando hacia la izquierda.",
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
                Section("Bueno saber") {
                    ForEach(notes, id: \.self) { Text($0).font(.callout) }
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
