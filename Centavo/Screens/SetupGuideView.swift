import SwiftData
import SwiftUI

/// Walks the person through the Wallet automation in Atajos, one screen per step.
///
/// Apple does not let an app create that automation, so the next best thing is drawing each
/// Atajos screen as it will look and showing where to tap. Connecting the amount is two taps
/// in a row that nobody guesses, so that step plays them out on a loop, like a short video.
///
/// Each step reads like the welcome: a «Paso X de 8» caption with the brass emblem beside the
/// title, a short lead and the content; the dots between the bottom-bar buttons show where the
/// person is.
struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Payments the automation saved (only it keeps the raw Wallet text): proof that it works.
    @Query(Self.latestCapture) private var captured: [Expense]

    /// Only the newest capture is ever shown.
    private static var latestCapture: FetchDescriptor<Expense> {
        var descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.rawAmount != nil },
                                                  sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }
    @State private var step = GuideDebug.firstStep
    /// iOS 27 starts on adding the ready-made automation (`ShortcutInstallView`); the
    /// step-by-step guide is the way back if that fails.
    @State private var stepByStep = !ShortcutsVersion.isIOS27 || GuideDebug.opensOnStep
    /// The floating guide that goes into Atajos with the person (Picture in Picture).
    @State private var companion = GuideCompanion()
    @ScaledMetric(relativeTo: .body) private var stepNumberWidth = Theme.Size.stepNumber
    @ScaledMetric(relativeTo: .body) private var thumbWidth = Theme.Size.companionThumbWidth
    @ScaledMetric(relativeTo: .body) private var thumbHeight = Theme.Size.companionThumbHeight

    private let steps = ShortcutsVersion.isIOS27 ? GuideStep.ios27 : GuideStep.all
    private var isLast: Bool { step == steps.count - 1 }

    var body: some View {
        if stepByStep {
            guide
        } else {
            NavigationStack {
                ShortcutInstallView(latest: captured.first) {
                    withAnimation(Theme.Motion.settle) { stepByStep = true }
                }
                .background(Theme.background.ignoresSafeArea())
                .presentationBackground(Theme.background)
                .navigationBarTitleDisplayMode(.inline)
                .ticketBarTitle("Configurar atajo")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") { dismiss() }
                            .font(.ticket(.footnoteStrong))
                            .accessibilityIdentifier("hoja-listo")
                    }
                }
            }
        }
    }

    private var guide: some View {
        NavigationStack {
            TabView(selection: $step) {
                ForEach(steps.indices, id: \.self) { index in
                    page(steps[index], number: index + 1).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .bottom) {
                if steps[step].opensShortcuts { launcher }
            }
            .animation(Theme.Motion.settle, value: steps[step].opensShortcuts)
            .task { companion.load(companionPages) }
            // While the window floats over Atajos, the guide follows it: coming back to Al día
            // lands on the step the person was on.
            .onChange(of: companion.step) { _, value in
                if companion.isFloating { step = value }
            }
            .onChange(of: captured.first?.persistentModelID) { _, _ in
                if companion.isFloating { companion.stop() }
            }
            .onDisappear { companion.stop() }
            .background(Theme.background.ignoresSafeArea())
            .presentationBackground(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Configurar atajo")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .font(.ticket(.footnoteStrong))
                        .accessibilityIdentifier("hoja-listo")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Paso anterior", systemImage: "chevron.left") {
                        withAnimation { step -= 1 }
                    }
                    .disabled(step == 0)
                    .accessibilityIdentifier("guia-anterior")
                    Spacer()
                    StepDots(current: step, of: steps.count)
                        // The «Paso X de 8» caption above each title carries the progress.
                        .accessibilityHidden(true)
                        // Room inside the bar's glass: shifted toward a side, the last dot was
                        // cut by the capsule's edge (owner, 2026-10-29).
                        .padding(.horizontal, Theme.Space.s)
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
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                StepHeader(step: number, of: steps.count, title: guide.title, systemImage: guide.symbol)

                if let lead = guide.lead {
                    Text(lead)
                        .font(.ticket(.body))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if case .frames(let frames) = guide.scene {
                    // One real screenshot per action, its instruction right above it.
                    GuideFrameSequence(frames: frames)
                        .id(number)
                } else {
                    // A picture of another app: it grows a little with the text, then stops. The
                    // numbered steps under it carry the words and scale all the way.
                    ShortcutsDrawing(scene: guide.scene)
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .accessibilityHidden(true)
                }

                if !guide.taps.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        ForEach(Array(guide.taps.enumerated()), id: \.offset) { index, tap in
                            instruction("\(index + 1)", text: tap)
                        }
                    }
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ticketPanel()
                }

                if let warning = guide.warning {
                    warningBlock(warning)
                }

                if let note = guide.note {
                    noteRow(note)
                }

                if number == steps.count {
                    CaptureCheck(latest: captured.first)
                    goodToKnow
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.xxl)
        }
    }

    /// The dock above the bottom bar on every step done in Atajos: one button that floats the
    /// guide and opens Atajos under it, the guide already playing. Without Picture in Picture,
    /// a plain «Abrir Atajos».
    private var launcher: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if GuideCompanion.isSupported {
                Text(companion.isFloating
                     ? "La guía flota sobre Atajos. Avanza con ⏩."
                     : "Esta guía te acompaña en una ventanita sobre Atajos.")
                    .font(.ticket(.detail))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                let url = URL(string: "shortcuts://")!
                if GuideCompanion.isSupported {
                    companion.float(from: step, thenOpen: url)
                } else {
                    openURL(url)
                }
            } label: {
                PrimaryButtonLabel("Abrir Atajos", systemImage: GuideCompanion.isSupported
                                   ? "pip.enter" : "arrow.up.forward.app")
            }
            .ticketProminent()
            .accessibilityIdentifier("guia-abrir-atajos")
        }
        .padding(.horizontal, Theme.Space.screen)
        // Room above the bar's step buttons: the dock sat right on them (owner, 2026-10-29).
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.xxl)
        .background(Theme.surface)
        // The layer the window floats from, hidden behind the dock: it has to be on screen,
        // but no thumbnail beside the button (owner, 2026-10-29).
        .background {
            if GuideCompanion.isSupported {
                CompanionLayerView(companion: companion)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .top) { Divider().overlay(Theme.hairline) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Every picture of the guide, in order, for the floating window.
    private var companionPages: [GuideCompanion.Page] {
        steps.indices.flatMap { index -> [GuideCompanion.Page] in
            let guide = steps[index]
            if case .frames(let frames) = guide.scene, !frames.isEmpty {
                return frames.map { frame in
                    var photo: String?
                    if case .photo(let name) = frame.screen { photo = name }
                    return GuideCompanion.Page(step: index, stepTitle: guide.title, symbol: guide.symbol,
                                               caption: frame.caption, photo: photo, focus: frame.focus,
                                               isResult: frame.isResult)
                }
            }
            let lines = guide.taps.isEmpty ? [guide.lead ?? guide.title] : guide.taps
            return lines.map { GuideCompanion.Page(step: index, stepTitle: guide.title, symbol: guide.symbol,
                                                 caption: $0) }
        }
    }

    /// One numbered instruction of a step: the number in brass, then what to do.
    private func instruction(_ number: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
            Text(number)
                .foregroundStyle(Theme.brass)
                .monospacedDigit()
                .frame(minWidth: stepNumberWidth, alignment: .leading)
            Text(text)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.ticket(.body))
        .lineSpacing(Theme.Space.guideLine)
        .accessibilityElement(children: .combine)
    }

    /// The trap of a step told as a warning, not a quiet note: a triangle, brass, first lines.
    private func warningBlock(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.brass)
                .accessibilityHidden(true)
            Text(text)
                .font(.ticket(.callout))
                .foregroundStyle(Theme.ink)
                .lineSpacing(Theme.Space.guideLine)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ticketPanel()
        .accessibilityElement(children: .combine)
    }

    /// A quiet secondary block: an info mark under a step or inside «Bueno saber».
    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.faint)
                .accessibilityHidden(true)
            Text(text)
                .font(.ticket(.detail))
                .foregroundStyle(Theme.muted)
                .lineSpacing(Theme.Space.guideLine)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The last step's side panel: what the automation will and won't capture.
    private var goodToKnow: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Bueno saber").ticketCaption()
            ForEach(GuideStep.notes, id: \.self) { note in
                noteRow(note)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ticketPanel()
    }
}

/// Debug only: `-centavo-guia-paso N` opens the guide on step N when the app starts, for
/// screenshots of each step.
enum GuideDebug {
    static var firstStep: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let at = args.firstIndex(of: "-centavo-guia-paso"), at + 1 < args.count {
            return Int(args[at + 1]) ?? 0
        }
        #endif
        return 0
    }

    /// `-centavo-guia-paso N` or `-centavo-atajo` (the ready-made automation, iOS 27).
    static var opensAtLaunch: Bool {
        #if DEBUG
        opensOnStep || ProcessInfo.processInfo.arguments.contains("-centavo-atajo")
        #else
        false
        #endif
    }

    static var opensOnStep: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-centavo-guia-paso")
        #else
        false
        #endif
    }
}

// MARK: - The steps

private struct GuideStep {
    let title: String
    /// The symbol of the step's brass emblem.
    let symbol: String
    var lead: String? = nil
    let taps: [String]
    var warning: String? = nil
    var note: String? = nil
    var opensShortcuts = false
    let scene: ShortcutsScene

    // Labels checked against Atajos in iOS 26 (es-MX): «Automatización», «Nueva automatización»,
    // «Wallet», «Ejecutar de inmediato», «Notificar al ejecutar», «Crear nuevo atajo».
    static let all: [GuideStep] = [
        GuideStep(
            title: "Abre Atajos",
            symbol: "square.2.layers.3d",
            lead: "Apple no deja que Al día la cree por ti. Son unos 5 minutos, una sola vez.",
            taps: ["Abre la app Atajos (viene con el iPhone).",
                   "Abajo, al centro, toca «Automatización»."],
            opensShortcuts: true,
            scene: .tabs
        ),
        GuideStep(
            title: "Elige «Wallet»",
            symbol: "wallet.pass",
            lead: "Atajos se dispara con el pago sin contacto de Wallet.",
            taps: ["Toca «Nueva automatización» (o «+» arriba, si ya tienes otras).",
                   "En el buscador de abajo escribe «Wallet».",
                   "Toca «Wallet»: «Al realizar un pago sin contacto…»."],
            note: "En versiones anteriores de iOS se llamaba «Transacción».",
            scene: .wallet
        ),
        GuideStep(
            title: "Que corra sola",
            symbol: "play.fill",
            taps: ["Elige las tarjetas con las que pagas.",
                   "Marca «Ejecutar de inmediato».",
                   "Activa «Notificar al ejecutar»: después de cada pago te dirá cuánto te queda.",
                   "Toca «Siguiente»."],
            scene: .runOptions
        ),
        GuideStep(
            title: "Toca «Crear nuevo atajo»",
            symbol: "plus.square",
            taps: ["Arriba, en «Empezar», toca «Crear nuevo atajo»."],
            warning: "Ojo: no toques Al día en la lista de apps. Así la automatización se crea "
                + "sin el importe del pago y no anota nada. Si ya lo hiciste, ve a "
                + "«Automatización», desliza esa automatización a la izquierda, bórrala y "
                + "empieza de nuevo.",
            scene: .newShortcut
        ),
        GuideStep(
            title: "Agrega «Registrar gasto»",
            symbol: "magnifyingglass",
            lead: "La acción de Al día que guarda cada pago.",
            taps: ["Toca «Buscar acciones» y escribe «Registrar gasto».",
                   "Toca «Registrar gasto», la de Al día."],
            scene: .addAction
        ),
        GuideStep(
            title: "Conecta el importe",
            symbol: "dollarsign.circle",
            lead: "Dos datos del pago se conectan en la acción: el importe y el comercio.",
            taps: ["En la acción, toca la palabra azul «Importe».",
                   "Arriba del teclado aparece «Entrada del atajo». Tócala.",
                   "En la acción quedó una burbuja azul. Tócala otra vez.",
                   "Se abre una lista: elige «Importe»."],
            note: "Este es el paso que nadie adivina: hay que tocar la burbuja una segunda vez "
                + "para elegir qué dato del pago va en cada lugar.",
            scene: .connect(field: "Importe", done: [])
        ),
        GuideStep(
            title: "Conecta el comercio",
            symbol: "bag",
            lead: "Así cada pago llega con el lugar donde lo hiciste.",
            taps: ["Toca la palabra azul «Comercio».",
                   "Toca «Entrada del atajo» arriba del teclado.",
                   "Toca la burbuja y elige «Comercio».",
                   "Arriba a la derecha, toca la palomita azul para guardar."],
            note: "La tarjeta es opcional. Si la quieres, toca la flechita de la acción para "
                + "ver «Tarjeta» y conéctala igual, eligiendo la tarjeta en la lista.",
            scene: .connect(field: "Comercio", done: ["Importe"])
        ),
        GuideStep(
            title: "Pruébalo",
            symbol: "creditcard",
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
    // iOS 27: one «Notificación» automation on Wallet's notifications catches every purchase,
    // online or contactless (Wallet notifies each one once). Checked in the iOS 27 simulator
    // (es-MX, 2026-10-17): «Al recibir una notificación de [App]», pick Wallet; the action's
    // «Notificación» field does not connect by itself.
    static let ios27: [GuideStep] = [
        GuideStep(
            title: "Crea un atajo nuevo",
            symbol: "plus.square",
            lead: "Apple no deja que Al día lo cree por ti. Son unos 5 minutos, una sola vez.",
            taps: [],
            opensShortcuts: true,
            scene: .frames(GuideFrame.newShortcut)
        ),
        GuideStep(
            title: "Que se active con una notificación",
            symbol: "bell.badge.fill",
            lead: "Cubre tus compras en línea y acercando el teléfono.",
            taps: [],
            opensShortcuts: true,
            scene: .frames(GuideFrame.pickNotification)
        ),
        GuideStep(
            title: "Que sea la de Wallet",
            symbol: "wallet.pass",
            lead: "Solo las notificaciones de Wallet abren este atajo.",
            taps: [],
            opensShortcuts: true,
            scene: .frames(GuideFrame.pickWalletApp)
        ),
        GuideStep(
            title: "Agrega a Al día",
            symbol: "magnifyingglass",
            lead: "La acción de Al día que guarda cada aviso de Wallet.",
            taps: [],
            note: "Si no aparece, abre Al día una vez y vuelve a buscar: Atajos solo conoce "
                + "las apps que ya abriste.",
            opensShortcuts: true,
            scene: .frames(GuideFrame.addNoticeAction)
        ),
        GuideStep(
            title: "Conecta el aviso",
            symbol: "link",
            lead: "Así Al día recibe cada aviso de Wallet con el monto y la tarjeta. Son tres toques.",
            taps: [],
            opensShortcuts: true,
            scene: .frames(GuideFrame.connectNotice)
        ),
        // Atajos hands the notification over without its subtitle, which is where Wallet puts
        // the merchant (seen on the owner's iPhone, 2026-10-21): it has to be connected apart.
        GuideStep(
            title: "Conecta el comercio",
            symbol: "bag",
            lead: "Wallet manda el nombre de la tienda aparte. Se conecta casi igual que el paso anterior.",
            taps: [],
            opensShortcuts: true,
            scene: .frames(GuideFrame.connectSubtitle)
        ),
        GuideStep(
            title: "Guárdalo",
            symbol: "checkmark.circle",
            taps: [],
            opensShortcuts: true,
            scene: .frames(GuideFrame.saveNotice)
        ),
        GuideStep(
            title: "Pruébalo",
            symbol: "creditcard",
            taps: ["Compra algo, en línea o acercando el teléfono.",
                   "Vuelve aquí: en cuanto llegue el pago, esta pantalla te lo dice."],
            scene: .frames([])
        ),
    ]

    static let notes = [
        ShortcutsVersion.isIOS27
            ? "Se anota todo lo que Wallet te avisa: compras en línea y acercando el teléfono. "
                + "El efectivo y las tarjetas que no están en Wallet anótalos tú con «+»."
            : "Solo se anotan los pagos en los que acercas el iPhone o el reloj a la terminal. "
                + "Las compras en línea y dentro de apps anótalas tú con «+».",
        "Con algunos bancos el aviso de Wallet llega tarde y el atajo no alcanza a correr. "
            + "Si un pago no aparece, anótalo tú.",
        "Un pago rechazado también puede anotarse. Deslízalo hacia la izquierda y bórralo.",
        "Para el efectivo, di «Oye Siri, anotar gasto en Al día». También puedes ponerlo en el "
            + "botón de Acción (Ajustes › Botón de Acción › Atajo) o en el Centro de control.",
    ]
}

// MARK: - Is it working?

/// The last step's answer: the first payment the automation saved, or that it is still waiting.
struct CaptureCheck: View {
    let latest: Expense?

    /// Proof only if it is recent: a capture from days ago says nothing about the automation
    /// someone came here to fix.
    private var recent: Expense? {
        guard let latest, Date.now.timeIntervalSince(latest.date) < 3 * 24 * 3600 else { return nil }
        return latest
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            if let latest = recent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.brass)
                    .font(Theme.Symbol.large)
                    .symbolEffect(.bounce, value: latest.persistentModelID)
                    .transition(.scale.combined(with: .opacity))
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Ya funciona")
                        .font(.ticket(.button))
                        .foregroundStyle(Theme.ink)
                    Text("Llegó \(latest.rawAmount ?? "") en \(latest.merchant), "
                         + latest.date.formatted(.relative(presentation: .named)) + ".")
                        .font(.ticket(.detail))
                        .foregroundStyle(Theme.muted)
                }
            } else {
                ProgressView()
                    .tint(Theme.brass)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Esperando tu primer pago")
                        .font(.ticket(.button))
                        .foregroundStyle(Theme.ink)
                    Text(ShortcutsVersion.isIOS27
                         ? "Si pagaste y no llega en un par de minutos, revisa el paso 5: la acción debe decir "
                           + "«Registrar» y «Notificación» con campana, en azul."
                         : "Si pagaste y no llega en un par de minutos, revisa los pasos 4, 6 y 7.")
                        .font(.ticket(.detail))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ticketPanel()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guia-comprobacion")
        .animation(Theme.Motion.toggle, value: recent?.persistentModelID)
        .sensoryFeedback(.success, trigger: recent?.persistentModelID) { old, new in old == nil && new != nil }
    }
}

#Preview { SetupGuideView().ticketPreview() }
