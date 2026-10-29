import SwiftUI

/// iOS 27: the Wallet automation comes ready inside the app, so connecting it is adding it.
///
/// The file (`Registrar aviso de Wallet.shortcut`, see Tools/atajo) is the whole automation,
/// trigger and wired action, exported from the owner's iPhone and signed by Apple for anyone.
/// Atajos only imports files through the share sheet: its `import-shortcut` URL takes links,
/// not files. It arrives with its automation off; the person turns it on while adding it.
/// Every person in the user research got lost wiring steps 5 and 6 by hand (2026-10-29);
/// the step-by-step guide stays one tap away.
struct ShortcutInstallView: View {
    let latest: Expense?
    let stepByStep: () -> Void

    private static let file = Bundle.main.url(forResource: "Registrar aviso de Wallet", withExtension: "shortcut")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(spacing: Theme.Space.m) {
                        StepEmblem(systemImage: "wallet.pass")
                        Text("Conecta Wallet")
                            .font(.ticket(.pageTitle))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Text("El atajo ya viene armado. Solo hay que agregarlo a Atajos, una vez.")
                        .font(.ticket(.body))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    // Seen in the iOS 27 simulator (2026-10-29): Atajos opens the added shortcut
                    // with «Automation is turned off» on top; turning it on is not verified yet.
                    instruction("1", "Toca «Agregar a Atajos» y, en la hoja que se abre, elige Atajos.")
                    instruction("2", "Toca «Agregar atajo». Si ya tenías uno con ese nombre, elige «Reemplazar».")
                    instruction("3", "Arriba del atajo dice que la automatización está apagada: tócalo y enciéndela.")
                    instruction("4", "Compra algo, en línea o acercando el teléfono, y vuelve aquí.")
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ticketPanel()

                if let file = Self.file {
                    ShareLink(item: file, preview: SharePreview("Registrar aviso de Wallet")) {
                        PrimaryButtonLabel("Agregar a Atajos", systemImage: "plus.square.on.square")
                    }
                    .ticketProminent()
                    .accessibilityIdentifier("atajo-agregar")
                }

                CaptureCheck(latest: latest)

                SecondaryButton("Prefiero hacerlo paso a paso", identifier: "atajo-paso-a-paso", action: stepByStep)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.xxl)
        }
    }

    private func instruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
            Text(number)
                .foregroundStyle(Theme.brass)
                .monospacedDigit()
            Text(text)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.ticket(.body))
        .lineSpacing(Theme.Space.guideLine)
        .accessibilityElement(children: .combine)
    }
}
