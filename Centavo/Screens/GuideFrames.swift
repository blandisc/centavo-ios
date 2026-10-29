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
                        Text(frame.caption)
                            .font(.ticket(15, weight: frame.isResult ? .regular : .semibold, relativeTo: .body))
                            .foregroundStyle(frame.isResult ? Theme.muted : Theme.ink)
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
                   + "«Novedades de Atajos», toca «Continuar».", screen: .photo("guia27-01-mas")),
        GuideFrame(caption: "Si se abre «Describir un atajo», no escribas nada: toca «Editar», arriba a la derecha.",
                   screen: .photo("guia27-01b-editar")),
    ]
    static let pickNotification: [GuideFrame] = [
        GuideFrame(caption: "Abajo, toca «Automatización».", screen: .photo("guia27-02-automatizacion")),
        GuideFrame(caption: "Baja hasta la sección «Apps», a media lista, y toca «Notificación», la de la campana roja. "
                   + "No elijas «Wallet».", screen: .photo("guia27-03-notificacion")),
    ]
    static let pickWalletApp: [GuideFrame] = [
        GuideFrame(caption: "Toca la palabra «App», en azul tenue, justo debajo de «Al recibir una notificación de».",
                   screen: .photo("guia27-04-app")),
        GuideFrame(caption: "Baja casi hasta el final de la lista y toca «Wallet».", screen: .photo("guia27-05-wallet")),
        GuideFrame(caption: "Así debe verse: «Al recibir una notificación de Wallet».",
                   screen: .photo("guia27-06-con-wallet"), isResult: true),
    ]
    static let addNoticeAction: [GuideFrame] = [
        GuideFrame(caption: "Abajo, toca «Buscar», escribe «Registrar aviso» y toca «Registrar aviso de Wallet». "
                   + "(Si sale un aviso del teclado, toca «Continuar».)",
                   screen: .photo("guia27-07-accion")),
    ]
    static let connectNotice: [GuideFrame] = [
        GuideFrame(caption: "La palabra «Notificación» en gris es solo un ejemplo: todavía no está conectada. Tócala.",
                   screen: .photo("guia27-08-campo")),
        GuideFrame(caption: "Arriba del teclado sale una barra. Deslízala hacia la izquierda varias veces, hasta "
                   + "que veas «Notificación» con una campana.", screen: .photo("guia27-09a-barra")),
        GuideFrame(caption: "Toca «Notificación», la de la campana. En la acción queda «Notificación» con su "
                   + "campana. Luego toca ✓, la tecla azul del teclado (no la X).", screen: .photo("guia27-09-variable")),
    ]
    /// Atajos leaves the notification's subtitle out, and Wallet puts the merchant there
    /// (owner's iPhone, 2026-10-21): «Comercio» takes it apart.
    static let connectSubtitle: [GuideFrame] = [
        GuideFrame(caption: "Toca la flechita junto a «Notificación»: abajo aparece «Comercio».",
                   screen: .photo("guia27-12-flechita")),
        GuideFrame(caption: "Toca «Comercio», desliza la barra de arriba del teclado y toca «Notificación», la de "
                   + "la campana. Luego toca esa burbuja azul en la acción.", screen: .photo("guia27-09a-barra")),
        GuideFrame(caption: "Elige «Subtítulo»: ahí pone Wallet el comercio. Ojo: solo en «Comercio». Junto a "
                   + "«Registrar» tiene que seguir «Notificación»; si ahí dice «Subtítulo», no llega el monto y "
                   + "no se anota nada.", screen: .photo("guia27-13-subtitulo")),
        GuideFrame(caption: "Apaga «Mostrar al ejecutar»: así no sale un aviso con cada pago. Se anota igual.",
                   screen: .photo("guia27-14-mostrar")),
        GuideFrame(caption: "Así debe verse: «Registrar» con «Notificación», «Comercio» con «Subtítulo» y "
                   + "«Mostrar al ejecutar» apagado.", screen: .photo("guia27-15-accion-lista"), isResult: true),
    ]
    static let saveNotice: [GuideFrame] = [
        GuideFrame(caption: "No hay botón de guardar: toca la flecha de arriba a la izquierda y ya queda guardado.",
                   screen: .photo("guia27-10-guardar")),
        GuideFrame(caption: "Así debe verse: en «Todos los atajos» queda «Registrar aviso de Wallet» (el color "
                   + "de la tarjeta puede ser otro). No tienes que activar nada más.",
                   screen: .photo("guia27-11-listo"), isResult: true),
    ]
}
