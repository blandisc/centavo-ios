import SwiftUI

/// One moment of the iOS 27 walkthrough: the Atajos screen as it looks right then, with a
/// brass ring on the one thing to tap and a line saying what to do.
///
/// Drawn from the owner's own iPhone (iOS 27, es-MX, 2026-10-17): the payment's bubble is
/// «Transacción», and tapping it opens «Obtener» with Transacción, Tarjeta o pase, Comercio,
/// Cantidad, Nombre. The amount is «Cantidad» there.
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
        case allShortcuts
        case library
        case automationEmpty
        case describe
        case categories
        case walletBlock
        case search
        case action(importe: Token, comercio: Token, ring: Ring?)
        case keyboardBar(field: String)
        case obtain(pick: String)
        case saved
        // The «Notificación» automation (iOS 27)
        case triggerList(pick: String)
        case noticeTrigger(app: String?)
        case appPicker
        case noticeSearch
        case noticeAction(token: Token, ring: Bool)
        case noticeKeyboardBar
        case savedNotice
    }

    enum Token: Equatable {
        case placeholder(String)
        case bubble(String)
    }

    enum Ring { case importe, comercio }
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
        } else {
            drawn
        }
    }

    private var drawn: some View {
        VStack(alignment: .leading, spacing: 12) {
            screen
                .font(.subheadline)
                .foregroundStyle(Theme.Shortcuts.text)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.Shortcuts.screen, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.hairline, lineWidth: 1) }
    }

    @ViewBuilder private var screen: some View {
        switch frame.screen {
        case .photo: EmptyView()
        case .allShortcuts:
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .background(Theme.Shortcuts.card, in: Circle())
                    .ring()
                Text("Todos los atajos").font(.title3.bold())
            }
        case .library:
            VStack(alignment: .leading, spacing: 8) {
                Text("Biblioteca").font(.title3.bold())
                row("Todos los atajos", "square.stack.fill")
                row("Galería", "square.grid.2x2.fill")
                row("Automatización", "checkmark.circle.fill").ring()
            }
        case .automationEmpty:
            VStack(spacing: 10) {
                Text("Automatización").font(.title3.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Sin automatizaciones").foregroundStyle(Theme.Shortcuts.secondary)
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(Theme.Shortcuts.card, in: Circle())
                    .ring()
            }
        case .describe:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Nuevo atajo").font(.headline)
                    Spacer()
                    Text("Editor")
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.Shortcuts.card, in: Capsule())
                        .ring()
                }
                Text("Describir un atajo")
                    .foregroundStyle(Theme.Shortcuts.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Shortcuts.card, in: Capsule())
                    .opacity(0.5)
            }
        case .categories:
            VStack(alignment: .leading, spacing: 10) {
                searchField("Buscar")
                HStack(spacing: 6) {
                    chip("Automatización").ring()
                    chip("Scripts")
                    chip("Controles")
                }
            }
        case .walletBlock:
            VStack(alignment: .leading, spacing: 8) {
                row("Notificación", "bell.fill")
                row("Wallet", "wallet.pass.fill").ring()
                row("Captura de pantalla", "camera.viewfinder")
            }
        case .search:
            VStack(alignment: .leading, spacing: 10) {
                walletTrigger
                searchField("Registrar gasto")
                HStack(spacing: 10) {
                    AppGlyph27()
                    Text("Registrar gasto")
                    Spacer()
                }
                .padding(10)
                .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 12))
                .ring()
            }
        case .action(let importe, let comercio, let ring):
            VStack(alignment: .leading, spacing: 10) {
                walletTrigger
                actionCard(importe: importe, comercio: comercio, ring: ring)
            }
        case .keyboardBar(let field):
            VStack(alignment: .leading, spacing: 10) {
                actionCard(importe: field == "Importe" ? .placeholder("Importe") : .bubble("Cantidad"),
                           comercio: .placeholder("Comercio"), ring: nil)
                HStack(spacing: 6) {
                    chip("Transacción", icon: "creditcard").ring()
                    chip("Seleccionar variable")
                }
                Text("Si no ves «Transacción», toca «Seleccionar variable» y luego el bloque de "
                     + "Wallet de arriba.")
                    .font(.caption)
                    .foregroundStyle(Theme.Shortcuts.secondary)
            }
        case .obtain(let pick):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "creditcard")
                    Text("Transacción").font(.headline)
                }
                HStack(spacing: 8) {
                    ForEach([("delete.left.fill", "Borrar variable"), ("keyboard", "Regresar")],
                            id: \.1) { icon, title in
                        VStack(spacing: 4) {
                            Image(systemName: icon)
                            Text(title).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                Text("Obtener").font(.caption).foregroundStyle(Theme.Shortcuts.secondary)
                VStack(spacing: 0) {
                    ForEach(["Transacción", "Tarjeta o pase", "Comercio", "Cantidad", "Nombre"],
                            id: \.self) { option in
                        Text(option)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .trailing) {
                                if option == pick {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Shortcuts.blue)
                                        .padding(.trailing, 12)
                                }
                            }
                            .ring(option == pick)
                    }
                }
                .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 12))
            }
        case .triggerList(let pick):
            VStack(alignment: .leading, spacing: 8) {
                row("Wallet", "wallet.pass.fill").ring(pick == "Wallet")
                row("Captura de pantalla", "camera.viewfinder")
                row("Notificación", "bell.badge.fill").ring(pick == "Notificación")
            }
        case .noticeTrigger(let app):
            VStack(alignment: .leading, spacing: 10) {
                noticeTrigger(app: app, ringApp: app == nil)
            }
        case .appPicker:
            VStack(alignment: .leading, spacing: 10) {
                Text("App").font(.headline)
                searchField("Wallet")
                row("Wallet", "wallet.pass.fill").ring()
            }
        case .noticeSearch:
            VStack(alignment: .leading, spacing: 10) {
                noticeTrigger(app: "Wallet", ringApp: false)
                searchField("Registrar aviso")
                HStack(spacing: 10) {
                    AppGlyph27()
                    Text("Registrar aviso de Wallet")
                    Spacer()
                }
                .padding(10)
                .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 12))
                .ring()
            }
        case .noticeAction(let token, let ring):
            VStack(alignment: .leading, spacing: 10) {
                noticeTrigger(app: "Wallet", ringApp: false)
                HStack(spacing: 6) {
                    AppGlyph27()
                    Text("Registrar").fixedSize()
                    self.token(token).ring(ring)
                    Spacer()
                }
                .font(.footnote)
                .padding(10)
                .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 12))
            }
        case .noticeKeyboardBar:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    AppGlyph27()
                    Text("Registrar").fixedSize()
                    token(.placeholder("Notificación"))
                    Spacer()
                }
                .font(.footnote)
                .padding(10)
                .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 6) {
                    chip("Notificación", icon: "bell.badge").ring()
                    chip("Seleccionar variable")
                }
                Text("Si no ves «Notificación», toca «Seleccionar variable» y luego el bloque "
                     + "«Al recibir una notificación» de arriba.")
                    .font(.caption)
                    .foregroundStyle(Theme.Shortcuts.secondary)
            }
        case .savedNotice:
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .background(Theme.Shortcuts.card, in: Circle())
                    .ring()
                Text("Personal").font(.headline)
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge.fill").foregroundStyle(Theme.Shortcuts.blue)
                    Text("Al recibir una notificación de Wallet").font(.caption)
                }
                .padding(10)
                .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 12))
            }
        case .saved:
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .background(Theme.Shortcuts.card, in: Circle())
                    .ring()
                Text("Personal").font(.headline)
                HStack(spacing: 10) {
                    Image(systemName: "wallet.pass.fill").foregroundStyle(Theme.Shortcuts.blue)
                    Text("Cuando use un pase o tarjeta de pago de Wallet sin contacto")
                        .font(.caption)
                }
                .padding(10)
                .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: Pieces

    private func noticeTrigger(app: String?, ringApp: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill").foregroundStyle(.red)
                Text("Al recibir una notificación de")
            }
            Group {
                if let app {
                    Label(app, systemImage: "wallet.pass.fill").foregroundStyle(Theme.Shortcuts.blue)
                } else {
                    Text("App")
                        .foregroundStyle(Theme.Shortcuts.text)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.Shortcuts.blue, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .ring(ringApp)
        }
        .font(.footnote)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var walletTrigger: some View {
        HStack(spacing: 6) {
            Image(systemName: "creditcard.fill").foregroundStyle(Theme.Shortcuts.blue)
            Text("Cuando se use")
            Text("Cualquier tarjeta").foregroundStyle(Theme.Shortcuts.blue)
        }
        .font(.footnote)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func actionCard(importe: GuideFrame.Token, comercio: GuideFrame.Token,
                            ring: GuideFrame.Ring?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AppGlyph27()
                Text("Registrar").fixedSize()
                token(importe).ring(ring == .importe)
            }
            HStack(spacing: 6) {
                Text("en").fixedSize()
                token(comercio).ring(ring == .comercio)
            }
        }
        .font(.footnote)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func token(_ token: GuideFrame.Token) -> some View {
        switch token {
        case .placeholder(let text):
            Text(text).foregroundStyle(Theme.Shortcuts.blue).fixedSize()
        case .bubble(let text):
            Label(text, systemImage: "creditcard")
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.Shortcuts.text)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.Shortcuts.blue, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func row(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.Shortcuts.blue).frame(width: 22)
            Text(title)
            Spacer()
        }
        .padding(10)
        .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private func chip(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(title)
        }
        .font(.footnote)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.Shortcuts.card, in: Capsule())
    }

    private func searchField(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Shortcuts.secondary)
            Text(text).foregroundStyle(text == "Buscar" ? Theme.Shortcuts.secondary : Theme.Shortcuts.text)
            Spacer()
        }
        .padding(10)
        .background(Theme.Shortcuts.card, in: Capsule())
    }
}

/// Centavo's icon in miniature.
private struct AppGlyph27: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Theme.background)
            .frame(width: 20, height: 20)
            .overlay {
                // The app icon: days of the month, today in brass.
                Grid(horizontalSpacing: 1.5, verticalSpacing: 1.5) {
                    GridRow { cell(Theme.surface); cell(Theme.brassLow) }
                    GridRow { cell(Theme.brass); cell(Theme.surface) }
                }
            }
    }

    private func cell(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 5.5, height: 5.5)
    }
}

private extension View {
    /// The brass ring that says "tap here".
    func ring(_ isOn: Bool = true) -> some View {
        overlay {
            if isOn {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.brass, lineWidth: 2.5)
                    .padding(-5)
            }
        }
    }
}

// MARK: - The iOS 27 steps, frame by frame

extension GuideFrame {
    static let addWallet: [GuideFrame] = [
        GuideFrame(caption: "1 · Abajo, toca la categoría «Automatización»", screen: .categories),
        GuideFrame(caption: "2 · Toca «Wallet»", screen: .walletBlock),
    ]
    static let addAction: [GuideFrame] = [
        GuideFrame(caption: "Busca «Registrar gasto» y tócalo", screen: .search),
        GuideFrame(caption: "Queda debajo del bloque de Wallet",
                   screen: .action(importe: .placeholder("Importe"),
                                   comercio: .placeholder("Comercio"), ring: nil)),
    ]
    static let connectAmount: [GuideFrame] = [
        GuideFrame(caption: "1 · Toca «Importe»",
                   screen: .action(importe: .placeholder("Importe"),
                                   comercio: .placeholder("Comercio"), ring: .importe)),
        GuideFrame(caption: "2 · Arriba del teclado, toca «Transacción»",
                   screen: .keyboardBar(field: "Importe")),
        GuideFrame(caption: "3 · Quedó la burbuja «Transacción». Tócala otra vez",
                   screen: .action(importe: .bubble("Transacción"),
                                   comercio: .placeholder("Comercio"), ring: .importe)),
        GuideFrame(caption: "4 · En «Obtener», elige «Cantidad»", screen: .obtain(pick: "Cantidad")),
        GuideFrame(caption: "Listo: dice «Cantidad»",
                   screen: .action(importe: .bubble("Cantidad"),
                                   comercio: .placeholder("Comercio"), ring: nil)),
    ]
    static let connectMerchant: [GuideFrame] = [
        GuideFrame(caption: "1 · Toca «Comercio»",
                   screen: .action(importe: .bubble("Cantidad"),
                                   comercio: .placeholder("Comercio"), ring: .comercio)),
        GuideFrame(caption: "2 · Arriba del teclado, toca «Transacción»",
                   screen: .keyboardBar(field: "Comercio")),
        GuideFrame(caption: "3 · Toca la burbuja «Transacción» otra vez",
                   screen: .action(importe: .bubble("Cantidad"),
                                   comercio: .bubble("Transacción"), ring: .comercio)),
        GuideFrame(caption: "4 · En «Obtener», elige «Comercio»", screen: .obtain(pick: "Comercio")),
        GuideFrame(caption: "Listo: «Cantidad» en «Comercio»",
                   screen: .action(importe: .bubble("Cantidad"),
                                   comercio: .bubble("Comercio"), ring: nil)),
    ]
    static let save: [GuideFrame] = [
        GuideFrame(caption: "Toca la flecha de arriba a la izquierda: se guarda sola", screen: .saved),
    ]
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
    static let saveNotice: [GuideFrame] = [
        GuideFrame(caption: "No hay botón de guardar: toca la flecha de arriba a la izquierda y ya queda guardado.",
                   screen: .photo("guia27-10-guardar")),
        GuideFrame(caption: "Así debe verse: en «Todos los atajos» queda «Registrar aviso de Wallet» (el color "
                   + "de la tarjeta puede ser otro). No tienes que activar nada más.",
                   screen: .photo("guia27-11-listo"), isResult: true),
    ]
}
