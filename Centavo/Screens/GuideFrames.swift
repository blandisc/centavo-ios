import SwiftUI

/// One moment of the iOS 27 walkthrough: a real screenshot of Atajos with a brass ring on
/// the one thing to tap, and a line saying what to do.
///
/// Taken on the owner's own iPhone (iOS 27, es-MX).
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

    enum Screen {
        /// A real screenshot of Atajos (iOS 27, es-MX), taken by `GuideScreenshotsTests`,
        /// with the ring already drawn on it.
        case photo(String)
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
    // iOS 27, from real screenshots (see GuideScreenshotsTests).
    static let newShortcut: [GuideFrame] = [
        GuideFrame(caption: "Abre la app Atajos y toca el botón «+» de abajo. Si antes aparece "
                   + "«Novedades de Atajos», toca «Continuar».", screen: .photo("guia27-01-mas"),
                   focus: CGRect(x: 0.167, y: 0.673, width: 0.667, height: 0.327)),
        GuideFrame(caption: "Si se abre «Describir un atajo», no escribas nada: toca «Editar», arriba a la derecha.",
                   screen: .photo("guia27-01b-editar"),
                   focus: CGRect(x: 0, y: 0, width: 1, height: 0.746)),
    ]
    static let pickNotification: [GuideFrame] = [
        GuideFrame(caption: "Abajo, toca «Automatización».", screen: .photo("guia27-02-automatizacion"),
                   focus: CGRect(x: 0, y: 0.106, width: 0.689, height: 0.638)),
        // «No elijas Wallet» read as the opposite of the next step's title (research, 2026-10-29).
        GuideFrame(caption: "En «Apps», toca «Notificación», la de la campana roja. "
                   + "Wallet va en el siguiente paso.", screen: .photo("guia27-03-notificacion"),
                   focus: CGRect(x: 0, y: 0.407, width: 1, height: 0.568)),
    ]
    static let pickWalletApp: [GuideFrame] = [
        GuideFrame(caption: "Toca la palabra «App», en azul tenue, justo debajo de «Al recibir una notificación de».",
                   screen: .photo("guia27-04-app"),
                   focus: CGRect(x: 0, y: 0.172, width: 1, height: 0.815)),
        GuideFrame(caption: "Baja casi hasta el final de la lista y toca «Wallet».", screen: .photo("guia27-05-wallet"),
                   focus: CGRect(x: 0, y: 0.262, width: 1, height: 0.738)),
        GuideFrame(caption: "Así debe verse: «Al recibir una notificación de Wallet».",
                   screen: .photo("guia27-06-con-wallet"), isResult: true),
    ]
    static let addNoticeAction: [GuideFrame] = [
        GuideFrame(caption: "Abajo, toca «Buscar», escribe «Registrar aviso» y toca «Registrar aviso de Wallet». "
                   + "(Si sale un aviso del teclado, toca «Continuar».)",
                   screen: .photo("guia27-07-accion")),
    ]
    // One action per frame and the words on screen, not Atajos' own («burbuja», «variable»):
    // every person in the 2026-10-29 research got lost here.
    static let connectNotice: [GuideFrame] = [
        GuideFrame(caption: "Junto a «Registrar», toca la palabra «Notificación» en azul tenue. Es solo de ejemplo: "
                   + "todavía no está conectada.",
                   screen: .photo("guia27-08-campo"),
                   focus: CGRect(x: 0, y: 0.163, width: 1, height: 0.837)),
        // The row starts on «Seleccionar variable»: say it is not that one, or people stop there.
        GuideFrame(caption: "Arriba del teclado sale una fila que empieza con «Seleccionar variable». No es esa: "
                   + "deslízala hacia la izquierda hasta que aparezca la campana.", screen: .photo("guia27-09a-barra"),
                   focus: CGRect(x: 0.022, y: 0.671, width: 0.844, height: 0.324)),
        GuideFrame(caption: "Ahí está: toca la campana «Notificación». Después toca ✓ en el teclado para cerrarlo.",
                   screen: .photo("guia27-09-variable"),
                   focus: CGRect(x: 0, y: 0.79, width: 1, height: 0.206)),
        GuideFrame(caption: "Así debe verse: junto a «Registrar» dice «Notificación» en azul, con su campana.",
                   screen: .photo("guia27-15-accion-lista"), isResult: true,
                   focus: CGRect(x: 0, y: 0, width: 1, height: 0.43)),
    ]
    /// Atajos leaves the notification's subtitle out, and Wallet puts the merchant there
    /// (owner's iPhone, 2026-10-21): «Comercio» takes it apart.
    static let connectSubtitle: [GuideFrame] = [
        GuideFrame(caption: "Toca la flechita junto a «Notificación». Abajo aparece «Comercio».",
                   screen: .photo("guia27-12-flechita"),
                   focus: CGRect(x: 0.344, y: 0, width: 0.656, height: 1)),
        GuideFrame(caption: "Toca «Comercio». En la fila de arriba del teclado, busca otra vez «Notificación», la "
                   + "de la campana, y tócala.", screen: .photo("guia27-09a-barra"),
                   focus: CGRect(x: 0.022, y: 0.671, width: 0.844, height: 0.324)),
        GuideFrame(caption: "En «Comercio» quedó «Notificación» en azul. Tócala una vez más y, en la lista, elige "
                   + "«Subtítulo»: ahí pone Wallet el nombre de la tienda.", screen: .photo("guia27-13-subtitulo"),
                   focus: CGRect(x: 0, y: 0.112, width: 1, height: 0.847)),
        GuideFrame(caption: "Apaga «Mostrar al ejecutar»: así no te sale un aviso con cada pago. Se anota igual.",
                   screen: .photo("guia27-14-mostrar")),
        GuideFrame(caption: "Así debe verse: «Registrar» con «Notificación» y «Comercio» con «Subtítulo». Si junto "
                   + "a «Registrar» dice «Subtítulo», no se anotará nada: tócalo y elige «Notificación».",
                   screen: .photo("guia27-15-accion-lista"), isResult: true),
    ]
    static let saveNotice: [GuideFrame] = [
        GuideFrame(caption: "No hay botón de guardar: toca la flecha de arriba a la izquierda y ya queda guardado.",
                   screen: .photo("guia27-10-guardar")),
        GuideFrame(caption: "Así debe verse: en «Todos los atajos» queda «Registrar aviso de Wallet» (el color "
                   + "de la tarjeta puede ser otro). No tienes que activar nada más.",
                   screen: .photo("guia27-11-listo"), isResult: true,
                   focus: CGRect(x: 0, y: 0.028, width: 1, height: 0.972)),
    ]
}
