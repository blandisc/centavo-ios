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

    enum Screen {
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
    }

    enum Token: Equatable {
        case placeholder(String)
        case bubble(String)
    }

    enum Ring { case importe, comercio }
}

/// Plays a step's frames one after another, on a loop, like a short video. With Reduce
/// Motion it shows them all, one under the other, so nothing is lost.
struct GuideFrameAnimation: View {
    let frames: [GuideFrame]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let interval: TimeInterval = 2.6

    var body: some View {
        if reduceMotion {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(frames) { frame in FrameView(frame: frame) }
            }
        } else {
            TimelineView(.periodic(from: .now, by: interval)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate / interval) % frames.count
                FrameView(frame: frames[index])
                    .id(index)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: index)
            }
        }
    }
}

private struct FrameView: View {
    let frame: GuideFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(frame.caption)
                .font(.ticket(12, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Theme.brass)
                .fixedSize(horizontal: false, vertical: true)
            screen
                .font(.subheadline)
                .foregroundStyle(Theme.Shortcuts.text)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .background(Theme.Shortcuts.screen, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.hairline, lineWidth: 1) }
    }

    @ViewBuilder private var screen: some View {
        switch frame.screen {
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
    static let openAutomation: [GuideFrame] = [
        GuideFrame(caption: "1 · En Atajos, toca la flecha de arriba", screen: .allShortcuts),
        GuideFrame(caption: "2 · Toca «Automatización»", screen: .library),
        GuideFrame(caption: "3 · Toca el «+» de abajo", screen: .automationEmpty),
    ]
    static let openEditor: [GuideFrame] = [
        GuideFrame(caption: "No escribas nada: toca «Editor» arriba a la derecha", screen: .describe),
    ]
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
