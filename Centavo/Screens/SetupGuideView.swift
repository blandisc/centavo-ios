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
        "Un pago rechazado también puede anotarse. Tócalo y bórralo.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(title: "Configurar atajo") {
                EmptyView()
            } trailing: {
                SheetAction(title: "Listo", prominent: true) { dismiss() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String(format: "%02d", index + 1))
                                .foregroundStyle(Theme.brass)
                                .frame(minWidth: 28, alignment: .leading)
                            Text(step).multilineTextAlignment(.leading)
                        }
                        .font(.ticket(13, relativeTo: .footnote))
                        .lineSpacing(4)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Perforation() }
                        .accessibilityElement(children: .combine)
                    }

                    Text("Bueno saber")
                        .ticketCaption()
                        .padding(.top, 20)
                        .padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(notes, id: \.self) { note in
                        Text(note)
                            .font(.ticket(12, relativeTo: .footnote))
                            .lineSpacing(4)
                            .foregroundStyle(Theme.muted)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) { Perforation() }
                    }

                    Link(destination: URL(string: "shortcuts://")!) {
                        Text("Abrir Atajos")
                            .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.brass)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(Capsule().stroke(Theme.brass, lineWidth: 1.5))
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
            }
        }
        .ticketSheet()
    }
}

#Preview { SetupGuideView().preferredColorScheme(.dark) }
