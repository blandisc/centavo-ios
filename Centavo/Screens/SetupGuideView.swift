import SwiftData
import SwiftUI

/// Walks the person through the Wallet automation in Atajos, one screen per step.
///
/// Apple does not let an app create that automation, so the next best thing is drawing each
/// Atajos screen as it will look and showing where to tap. Connecting the amount is two taps
/// in a row that nobody guesses, so that step plays them out on a loop, like a short video.
struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    /// Payments the automation saved (only it keeps the raw Wallet text): proof that it works.
    @Query(filter: #Predicate<Expense> { $0.rawAmount != nil },
           sort: \Expense.date, order: .reverse)
    private var captured: [Expense]
    @State private var step = 0

    private let steps = ShortcutsVersion.isIOS27 ? GuideStep.ios27 : GuideStep.all
    private var isLast: Bool { step == steps.count - 1 }

    var body: some View {
        NavigationStack {
            TabView(selection: $step) {
                ForEach(steps.indices, id: \.self) { index in
                    page(steps[index], number: index + 1).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Theme.background.ignoresSafeArea())
            .presentationBackground(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Configurar atajo")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                        .accessibilityIdentifier("hoja-listo")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Paso anterior", systemImage: "chevron.left") {
                        withAnimation { step -= 1 }
                    }
                    .disabled(step == 0)
                    .accessibilityIdentifier("guia-anterior")
                    Spacer()
                    Text("\(step + 1) de \(steps.count)")
                        .font(.ticket(13, relativeTo: .footnote))
                        .tracking(2)
                        .textCase(.uppercase)
                        .monospacedDigit()
                        .fixedSize()
                    Spacer()
                    Button("Paso siguiente", systemImage: "chevron.right") {
                        withAnimation { step += 1 }
                    }
                    .disabled(isLast)
                    .accessibilityIdentifier("guia-siguiente")
                }
            }
        }
    }

    private func page(_ guide: GuideStep, number: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paso \(number) de \(steps.count)").ticketCaption()
                    Text(guide.title)
                        .font(.ticket(20, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                }

                // A picture of another app: it grows a little with the text, then stops. The
                // numbered steps under it carry the words and scale all the way.
                ShortcutsDrawing(scene: guide.scene)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(guide.taps.enumerated()), id: \.offset) { index, tap in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .foregroundStyle(Theme.brass)
                                .frame(minWidth: 16, alignment: .leading)
                            Text(tap).foregroundStyle(Theme.ink)
                        }
                        .font(.ticket(14, relativeTo: .body))
                        .lineSpacing(3)
                        .accessibilityElement(children: .combine)
                    }
                }

                if let note = guide.note {
                    Text(note)
                        .font(.ticket(12, relativeTo: .footnote))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.muted)
                }

                if guide.opensShortcuts {
                    Link(destination: URL(string: "shortcuts://")!) {
                        Label("Abrir Atajos", systemImage: "arrow.up.forward.app")
                            .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.onBrass)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brass)
                }

                if number == steps.count {
                    CaptureCheck(latest: captured.first)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Bueno saber").ticketCaption()
                        ForEach(GuideStep.notes, id: \.self) { note in
                            Text(note)
                                .font(.ticket(12, relativeTo: .footnote))
                                .lineSpacing(3)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - The steps

private struct GuideStep {
    let title: String
    let taps: [String]
    var note: String?
    var opensShortcuts = false
    let scene: ShortcutsScene

    // Labels checked against Atajos in iOS 26 (es-MX): «Automatización», «Nueva automatización»,
    // «Wallet», «Ejecutar de inmediato», «Notificar al ejecutar», «Crear nuevo atajo».
    static let all: [GuideStep] = [
        GuideStep(
            title: "Abre Atajos",
            taps: ["Abre la app Atajos (viene con el iPhone).",
                   "Abajo, al centro, toca «Automatización»."],
            note: "Atajos es la que corre una acción cada vez que pagas. Centavo no puede crear "
                + "la automatización por ti: Apple no lo permite. Son 2 minutos y se hace una vez.",
            opensShortcuts: true,
            scene: .tabs
        ),
        GuideStep(
            title: "Elige «Wallet»",
            taps: ["Toca «Nueva automatización» (o «+» arriba, si ya tienes otras).",
                   "En el buscador de abajo escribe «Wallet».",
                   "Toca «Wallet»: «Al realizar un pago sin contacto…»."],
            note: "En versiones anteriores de iOS se llamaba «Transacción».",
            scene: .wallet
        ),
        GuideStep(
            title: "Que corra sola",
            taps: ["Elige las tarjetas con las que pagas.",
                   "Marca «Ejecutar de inmediato».",
                   "Activa «Notificar al ejecutar»: después de cada pago te dirá cuánto te queda.",
                   "Toca «Siguiente»."],
            scene: .runOptions
        ),
        GuideStep(
            title: "Toca «Crear nuevo atajo»",
            taps: ["Arriba, en «Empezar», toca «Crear nuevo atajo»."],
            note: "Ojo: no toques Centavo en la lista de apps. Así la automatización se crea "
                + "sin el importe del pago y no anota nada. Si ya lo hiciste, ve a «Automatización», "
                + "desliza esa automatización a la izquierda, bórrala y empieza de nuevo.",
            scene: .newShortcut
        ),
        GuideStep(
            title: "Agrega «Registrar gasto»",
            taps: ["Toca «Buscar acciones» y escribe «Registrar gasto».",
                   "Toca «Registrar gasto», la de Centavo."],
            scene: .addAction
        ),
        GuideStep(
            title: "Conecta el importe",
            taps: ["En la acción, toca la palabra azul «Importe».",
                   "Arriba del teclado aparece «Entrada del atajo». Tócala.",
                   "En la acción quedó una burbuja azul. Tócala otra vez.",
                   "Se abre una lista: elige «Importe»."],
            note: "Este es el paso que nadie adivina: hay que tocar la burbuja una segunda vez para "
                + "elegir qué dato del pago va en cada lugar.",
            scene: .connect(field: "Importe", done: [])
        ),
        GuideStep(
            title: "Conecta el comercio",
            taps: ["Toca la palabra azul «Comercio».",
                   "Toca «Entrada del atajo» arriba del teclado.",
                   "Toca la burbuja y elige «Comercio».",
                   "Arriba a la derecha, toca la palomita azul para guardar."],
            note: "La tarjeta es opcional. Si la quieres, toca la flechita de la acción para ver "
                + "«Tarjeta» y conéctala igual, eligiendo la tarjeta en la lista.",
            scene: .connect(field: "Comercio", done: ["Importe"])
        ),
        GuideStep(
            title: "Pruébalo",
            taps: ["Paga algo acercando el iPhone o el reloj a la terminal.",
                   "Vuelve aquí: en cuanto llegue el pago, esta pantalla te lo dice."],
            scene: .finished
        ),
    ]

    // Checked against Atajos in iOS 27.0 (es-MX, simulator, 2026-10-15): Biblioteca →
    // Automatización → «Nuevo atajo» opens «Describir un atajo»; «Editor» shows the action
    // list with an «Automatización» category holding «Wallet» («Cuando se use»). «Entrada de
    // atajo» is NOT the payment there: inserting it adds «Recibir… de Ningún lado».
    // Not verifiable without cards in Wallet: the variable picked from the Wallet block.
    static let ios27: [GuideStep] = [
        GuideStep(
            title: "Abre Atajos",
            taps: ["Abre la app Atajos.",
                   "Toca la flecha de arriba a la izquierda.",
                   "Toca «Automatización» y luego el «+» de abajo."],
            note: "Centavo no puede crear la automatización por ti: Apple no lo permite. "
                + "Son 2 minutos y se hace una vez.",
            opensShortcuts: true,
            scene: .frames(GuideFrame.openAutomation)
        ),
        GuideStep(
            title: "Abre el editor",
            taps: ["Se abre «Describir un atajo». No escribas nada.",
                   "Toca «Editor» arriba a la derecha."],
            scene: .frames(GuideFrame.openEditor)
        ),
        GuideStep(
            title: "Agrega «Wallet»",
            taps: ["Abajo, toca la categoría «Automatización».",
                   "Toca «Wallet». Arriba queda «Cuando se use Cualquier tarjeta»."],
            scene: .frames(GuideFrame.addWallet)
        ),
        GuideStep(
            title: "Agrega «Registrar gasto»",
            taps: ["Toca «Buscar» y escribe «Registrar gasto».",
                   "Toca «Registrar gasto», la de Centavo."],
            scene: .frames(GuideFrame.addAction)
        ),
        GuideStep(
            title: "Conecta la cantidad",
            taps: ["Toca «Importe».",
                   "Arriba del teclado toca «Transacción».",
                   "Toca la burbuja «Transacción» otra vez.",
                   "En «Obtener», elige «Cantidad»."],
            note: "Si ves «Cantidad» con palomita, ya quedó. Si en «Importe» dice «Transacción» y no "
                + "«Cantidad», el gasto no se anota: toca la burbuja y elige «Cantidad».",
            scene: .frames(GuideFrame.connectAmount)
        ),
        GuideStep(
            title: "Conecta el comercio",
            taps: ["Toca «Comercio».",
                   "Arriba del teclado toca «Transacción».",
                   "Toca la burbuja otra vez y elige «Comercio»."],
            scene: .frames(GuideFrame.connectMerchant)
        ),
        GuideStep(
            title: "Guárdala",
            taps: ["Toca la flecha de arriba a la izquierda. Se guarda sola y aparece en "
                   + "«Automatización», en «Personal»."],
            note: "Si al pagar Atajos te pide confirmar, abre esa automatización y elige "
                + "«Ejecutar de inmediato».",
            scene: .frames(GuideFrame.save)
        ),
        GuideStep(
            title: "Pruébalo",
            taps: ["Paga algo acercando el iPhone o el reloj a la terminal.",
                   "Vuelve aquí: en cuanto llegue el pago, esta pantalla te lo dice."],
            scene: .finished
        ),
    ]

    static let notes = [
        "Solo se anotan los pagos en los que acercas el iPhone o el reloj a la terminal. "
            + "Las compras en línea y dentro de apps anótalas tú con «+».",
        "Con algunos bancos el aviso de Wallet llega tarde y el atajo no alcanza a correr. "
            + "Si un pago no aparece, anótalo tú.",
        "Un pago rechazado también puede anotarse. Deslízalo hacia la izquierda y bórralo.",
        "Para el efectivo, di «Oye Siri, anotar gasto en Centavo». También puedes ponerlo en el "
            + "botón de Acción (Ajustes › Botón de Acción › Atajo) o en el Centro de control.",
    ]
}

// MARK: - Is it working?

/// The last step's answer: the first payment the automation saved, or that it is still waiting.
private struct CaptureCheck: View {
    let latest: Expense?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let latest {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.brass)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ya funciona")
                        .font(.ticket(14, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.ink)
                    Text("Llegó \(latest.rawAmount ?? "") en \(latest.merchant), "
                         + latest.date.formatted(.relative(presentation: .named)) + ".")
                        .font(.ticket(12, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                }
            } else {
                ProgressView()
                    .tint(Theme.brass)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Esperando tu primer pago")
                        .font(.ticket(14, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.ink)
                    Text(ShortcutsVersion.isIOS27
                         ? "Si pagaste y no llega en un par de minutos, revisa los pasos 5 y 6."
                         : "Si pagaste y no llega en un par de minutos, revisa los pasos 4, 6 y 7.")
                        .font(.ticket(12, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guia-comprobacion")
    }
}

#Preview { SetupGuideView().preferredColorScheme(.dark) }
