import SwiftUI
import UIKit

/// One moment of the iOS 27 walkthrough: a real screenshot of Atajos with a brass ring on
/// the one thing to tap, and a line saying what to do.
///
/// Taken by `GuideScreenshotsTests` (iOS 27, es-MX and, when the English set ships, en-US).
struct GuideFrame: Identifiable {
    let id = UUID()
    let caption: String
    let screen: Screen
    /// «Así debe verse»: what it looks like once done, not something to tap.
    var isResult = false
    /// The part of the screenshot the floating guide shows, in fractions of its width and
    /// height (so it holds at any export size): the ring and what tells the place apart,
    /// without the empty stretches of black around them. The whole screenshot when nil.
    /// Set by eye; retaking a screenshot means looking at its crop again.
    var focus: CGRect?

    /// Whether every screenshot of the guide is in the app's language: Spanish always; in
    /// English once the English set ships (`Tools/guia-aros.py … en`). Until then, or for a
    /// picture missing from it, the Spanish one shows and the guide says so above them.
    static var photosMatchLanguage: Bool {
        guard let language = photoLanguage else { return true }
        return allFrames.allSatisfy { frame in
            if case .photo(let name) = frame.screen { return name.hasSuffix("-" + language) }
            return true
        }
    }

    /// The suffix of the screenshots in the app's language («en»), or nil in Spanish.
    private static var photoLanguage: String? {
        let language = Bundle.main.preferredLocalizations.first ?? "es"
        return language.hasPrefix("en") ? "en" : nil
    }

    /// «guia27-…-en» when the app shows in English and that picture ships; the Spanish one
    /// otherwise, so a build without the English set (or with part of it) still has every picture.
    static func photoName(_ name: String) -> String {
        guard let language = photoLanguage else { return name }
        let localized = name + "-" + language
        return UIImage(named: localized) == nil ? name : localized
    }

    enum Screen {
        /// A real screenshot of Atajos (iOS 27), taken by `GuideScreenshotsTests`, with the
        /// ring already drawn on it: the asset's name as it ships (`shot` picks the language).
        case photo(String)

        /// The picture `name` (the Spanish asset) in the app's language when there is one.
        static func shot(_ name: String) -> Screen { .photo(GuideFrame.photoName(name)) }
    }
}

/// A step's pictures, one under the other, each with its instruction right above it: a
/// still picture per action reads better than a loop that moves on before you are done.
struct GuideFrameSequence: View {
    let frames: [GuideFrame]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if frame.isResult {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.brass)
                                .accessibilityHidden(true)
                        } else if frames.filter({ !$0.isResult }).count > 1 {
                            Text("\(index + 1)")
                                .font(.ticket(15, weight: .semibold, relativeTo: .body))
                                .foregroundStyle(Theme.onBrass)
                                .frame(minWidth: 26, minHeight: 26)
                                .background(Theme.brass, in: Circle())
                                .accessibilityHidden(true)
                        }
                        // Ink for results too: gray read poorly in the research (2026-10-29).
                        Text(frame.caption)
                            .font(.ticket(15, weight: frame.isResult ? .regular : .semibold, relativeTo: .body))
                            .foregroundStyle(Theme.ink)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // A picture of another app: it grows a little with the text, then stops.
                    FrameView(frame: frame)
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

private struct FrameView: View {
    let frame: GuideFrame

    var body: some View {
        if case .photo(let name) = frame.screen {
            Image(name)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1) }
        }
    }
}

// MARK: - The «Notificación» automation, frame by frame (iOS 27)

extension GuideFrame {
    /// Every frame of the guide, to know whether all of them have their picture in English.
    static var allFrames: [GuideFrame] {
        // One list of lists: a chain of `+` is slow to type-check (the CI's compiler gives up).
        let steps: [[GuideFrame]] = [newShortcut, pickNotification, pickWalletApp, addNoticeAction,
                                     connectNotice, connectSubtitle, saveNotice]
        return steps.flatMap { $0 }
    }

    // iOS 27, from real screenshots (see GuideScreenshotsTests).
    static let newShortcut: [GuideFrame] = [
        GuideFrame(caption: String(localized: "Abre la app Atajos y toca el botón «+» de abajo. Si antes aparece «Novedades de Atajos», toca «Continuar»."), screen: .shot("guia27-01-mas"),
                   focus: CGRect(x: 0.167, y: 0.673, width: 0.667, height: 0.327)),
        GuideFrame(caption: String(localized: "Si se abre «Describir un atajo», no escribas nada: toca «Editar», arriba a la derecha."),
                   screen: .shot("guia27-01b-editar"),
                   focus: CGRect(x: 0, y: 0, width: 1, height: 0.746)),
    ]
    static let pickNotification: [GuideFrame] = [
        GuideFrame(caption: String(localized: "Abajo, toca «Automatización»."), screen: .shot("guia27-02-automatizacion"),
                   focus: CGRect(x: 0, y: 0.106, width: 0.689, height: 0.638)),
        // «No elijas Wallet» read as the opposite of the next step's title (research, 2026-10-29).
        GuideFrame(caption: String(localized: "En «Apps», toca «Notificación», la de la campana roja. Wallet va en el siguiente paso."), screen: .shot("guia27-03-notificacion"),
                   focus: CGRect(x: 0, y: 0.407, width: 1, height: 0.568)),
    ]
    static let pickWalletApp: [GuideFrame] = [
        GuideFrame(caption: String(localized: "Toca la palabra «App», en azul tenue, justo debajo de «Al recibir una notificación de»."),
                   screen: .shot("guia27-04-app"),
                   focus: CGRect(x: 0, y: 0.172, width: 1, height: 0.815)),
        GuideFrame(caption: String(localized: "Baja casi hasta el final de la lista y toca «Wallet»."), screen: .shot("guia27-05-wallet"),
                   focus: CGRect(x: 0, y: 0.262, width: 1, height: 0.738)),
        GuideFrame(caption: String(localized: "Así debe verse: «Al recibir una notificación de Wallet»."),
                   screen: .shot("guia27-06-con-wallet"), isResult: true),
    ]
    static let addNoticeAction: [GuideFrame] = [
        GuideFrame(caption: String(localized: "Abajo, toca «Buscar», escribe «Registrar aviso» y toca «Registrar aviso de Wallet». (Si sale un aviso del teclado, toca «Continuar».)"),
                   screen: .shot("guia27-07-accion")),
    ]
    // One action per frame and the words on screen, not Atajos' own («burbuja», «variable»):
    // every person in the 2026-10-29 research got lost here.
    static let connectNotice: [GuideFrame] = [
        GuideFrame(caption: String(localized: "Junto a «Registrar», toca la palabra «Notificación» en azul tenue. Es solo de ejemplo: todavía no está conectada."),
                   screen: .shot("guia27-08-campo"),
                   focus: CGRect(x: 0, y: 0.163, width: 1, height: 0.837)),
        // The row starts on «Seleccionar variable»: say it is not that one, or people stop there.
        GuideFrame(caption: String(localized: "Arriba del teclado sale una fila que empieza con «Seleccionar variable». No es esa: deslízala hacia la izquierda hasta que aparezca la campana."), screen: .shot("guia27-09a-barra"),
                   focus: CGRect(x: 0.022, y: 0.671, width: 0.844, height: 0.324)),
        GuideFrame(caption: String(localized: "Ahí está: toca la campana «Notificación». Después toca ✓ en el teclado para cerrarlo."),
                   screen: .shot("guia27-09-variable"),
                   focus: CGRect(x: 0, y: 0.79, width: 1, height: 0.206)),
        GuideFrame(caption: String(localized: "Así debe verse: junto a «Registrar» dice «Notificación» en azul, con su campana."),
                   screen: .shot("guia27-15-accion-lista"), isResult: true,
                   focus: CGRect(x: 0, y: 0, width: 1, height: 0.43)),
    ]
    /// Atajos leaves the notification's subtitle out, and Wallet puts the merchant there
    /// (owner's iPhone, 2026-10-21): «Comercio» takes it apart.
    static let connectSubtitle: [GuideFrame] = [
        GuideFrame(caption: String(localized: "Toca la flechita junto a «Notificación». Abajo aparece «Comercio»."),
                   screen: .shot("guia27-12-flechita"),
                   focus: CGRect(x: 0.344, y: 0, width: 0.656, height: 1)),
        GuideFrame(caption: String(localized: "Toca «Comercio». En la fila de arriba del teclado, busca otra vez «Notificación», la de la campana, y tócala."), screen: .shot("guia27-09a-barra"),
                   focus: CGRect(x: 0.022, y: 0.671, width: 0.844, height: 0.324)),
        GuideFrame(caption: String(localized: "En «Comercio» quedó «Notificación» en azul. Tócala una vez más y, en la lista, elige «Subtítulo»: ahí pone Wallet el nombre de la tienda."), screen: .shot("guia27-13-subtitulo"),
                   focus: CGRect(x: 0, y: 0.112, width: 1, height: 0.847)),
        GuideFrame(caption: String(localized: "Apaga «Mostrar al ejecutar»: así no te sale un aviso con cada pago. Se anota igual."),
                   screen: .shot("guia27-14-mostrar")),
        GuideFrame(caption: String(localized: "Así debe verse: «Registrar» con «Notificación» y «Comercio» con «Subtítulo». Si junto a «Registrar» dice «Subtítulo», no se anotará nada: tócalo y elige «Notificación»."),
                   screen: .shot("guia27-15-accion-lista"), isResult: true),
    ]
    static let saveNotice: [GuideFrame] = [
        GuideFrame(caption: String(localized: "No hay botón de guardar: toca la flecha de arriba a la izquierda y ya queda guardado."),
                   screen: .shot("guia27-10-guardar")),
        GuideFrame(caption: String(localized: "Así debe verse: en «Todos los atajos» queda «Registrar aviso de Wallet» (el color de la tarjeta puede ser otro). No tienes que activar nada más."),
                   screen: .shot("guia27-11-listo"), isResult: true,
                   focus: CGRect(x: 0, y: 0.028, width: 1, height: 0.972)),
    ]
}
