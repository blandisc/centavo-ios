import SwiftUI

/// Which Atajos screen a guide step draws.
/// Atajos changed its layout in iOS 27; the guide draws whichever the phone has.
enum ShortcutsVersion {
    static var isIOS27: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
    }
}

enum ShortcutsScene {
    case tabs
    case wallet
    case runOptions
    case newShortcut
    case addAction
    /// Connecting `field` to the transaction, with `done` fields already connected.
    case connect(field: String, done: [String])
    case finished
    // iOS 27
    case library27
    case editor27
    case wallet27
    /// A step played tap by tap (iOS 27).
    case frames([GuideFrame])
}

/// A simplified drawing of Apple's Shortcuts app in dark mode, with a brass ring on what to
/// tap. Decorative: the numbered steps under it say the same thing in words.
struct ShortcutsDrawing: View {
    let scene: ShortcutsScene

    var body: some View {
        if case .frames(let frames) = scene {
            GuideFrameAnimation(frames: frames)
        } else {
            drawing
        }
    }

    private var drawing: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch scene {
            case .tabs: tabs
            case .wallet: wallet
            case .runOptions: runOptions
            case .newShortcut: newShortcut
            case .addAction: addAction
            case .connect(let field, let done): ConnectAnimation(field: field, done: done)
            case .finished: finished
            case .library27: library27
            case .editor27: editor27
            case .wallet27: wallet27
            case .frames: EmptyView()
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.Shortcuts.text)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(Theme.Shortcuts.screen, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }

    // MARK: Scenes

    private var tabs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Automatización").font(.title2.bold())
            Spacer(minLength: 24)
            Text("Nueva automatización")
                .foregroundStyle(Theme.Shortcuts.text)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.Shortcuts.blue, in: Capsule())
                .frame(maxWidth: .infinity)
            Spacer(minLength: 24)
            HStack {
                tabItem("Biblioteca", "square.stack.fill", selected: false)
                tabItem("Automatización", "checkmark.circle.fill", selected: true)
                    .tapTarget()
                tabItem("Galería", "square.grid.2x2.fill", selected: false)
            }
        }
    }

    private func tabItem(_ title: String, _ icon: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption2)
        }
        .foregroundStyle(selected ? Theme.Shortcuts.blue : Theme.Shortcuts.secondary)
        .frame(maxWidth: .infinity)
    }

    private var wallet: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automatización personal").font(.headline)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wallet.pass.fill").foregroundStyle(Theme.Shortcuts.blue).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallet")
                    Text("«Al realizar un pago sin contacto con mi tarjeta o pase de Wallet»")
                        .font(.caption).foregroundStyle(Theme.Shortcuts.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 10))
            .tapTarget()
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.Shortcuts.secondary)
                Text("Wallet")
                Spacer()
            }
            .padding(10)
            .background(Theme.Shortcuts.card, in: Capsule())
        }
    }

    private var runOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Text("Siguiente")
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.Shortcuts.card, in: Capsule())
                    .tapTarget()
            }
            Text("Cuando use sin contacto").font(.headline)
            VStack(spacing: 10) {
                option("Ejecutar después de confirmar", checked: false)
                option("Ejecutar de inmediato", checked: true).tapTarget()
                HStack {
                    Text("Notificar al ejecutar")
                    Spacer()
                    Capsule().fill(Theme.Shortcuts.blue).frame(width: 40, height: 24)
                        .overlay(alignment: .trailing) {
                            Circle().fill(Theme.Shortcuts.text).frame(width: 20).padding(2)
                        }
                }
                .padding(10)
                .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 10))
                .tapTarget()
            }
        }
    }

    private func option(_ title: String, checked: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if checked { Image(systemName: "checkmark").foregroundStyle(Theme.Shortcuts.blue) }
        }
        .padding(10)
        .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private var newShortcut: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Empezar").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "plus.app")
                Text("Crear nuevo atajo")
            }
            .padding(12)
            .frame(width: 150, alignment: .leading)
            .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 14))
            .tapTarget()
            Spacer(minLength: 6)
            HStack(spacing: 10) {
                AppGlyph()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Al día")
                    Text("Registrar gasto").font(.caption).foregroundStyle(Theme.Shortcuts.secondary)
                }
                Spacer()
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.danger)
            }
            .padding(10)
            .opacity(0.6)
        }
    }

    private var addAction: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.Shortcuts.secondary)
                Text("Registrar gasto")
                Spacer()
            }
            .padding(10)
            .background(Theme.Shortcuts.card, in: Capsule())
            Text("Al día").font(.caption.bold()).foregroundStyle(Theme.Shortcuts.secondary)
            HStack(spacing: 10) {
                AppGlyph()
                Text("Registrar gasto")
                Spacer()
            }
            .padding(10)
            .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 10))
            .tapTarget()
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Wallet").font(.headline)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.headline)
                    .foregroundStyle(Theme.Shortcuts.text)
                    .frame(width: 34, height: 34)
                    .background(Theme.Shortcuts.blue, in: Circle())
            }
            ActionCard(importe: .variable("Importe"), comercio: .variable("Comercio"))
        }
    }

    // MARK: iOS 27

    /// Biblioteca: the sections are rows now, and «+» sits at the bottom.
    private var library27: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").foregroundStyle(Theme.Shortcuts.blue)
                Text("Biblioteca").font(.headline)
            }
            row("Todos los atajos", "square.stack.fill")
            row("Automatización", "checkmark.circle.fill").tapTarget()
            HStack {
                Spacer()
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Theme.Shortcuts.card, in: Circle())
                    .tapTarget()
                Spacer()
            }
            .padding(.top, 6)
        }
    }

    /// «Nuevo atajo» opens «Describir un atajo»; the editor is behind «Editor».
    private var editor27: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nuevo atajo").font(.headline)
                Spacer()
                Text("Editor")
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.Shortcuts.card, in: Capsule())
                    .tapTarget()
            }
            Text("Describir un atajo")
                .foregroundStyle(Theme.Shortcuts.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Shortcuts.card, in: Capsule())
                .opacity(0.6)
        }
    }

    /// In the editor: the «Automatización» category holds «Wallet»; it lands as a block on top.
    private var wallet27: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "creditcard.fill").foregroundStyle(Theme.Shortcuts.blue)
                Text("Cuando se use")
                Text("Cualquier tarjeta").foregroundStyle(Theme.Shortcuts.blue)
            }
            .font(.footnote)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 6) {
                Text("Automatización")
                    .foregroundStyle(Theme.Shortcuts.blue)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.Shortcuts.card, in: Capsule())
                    .tapTarget()
                Text("Scripts").foregroundStyle(Theme.Shortcuts.secondary)
            }
            .font(.footnote)
            row("Wallet", "wallet.pass.fill").tapTarget()
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
}

// MARK: - The two taps, on a loop

/// Plays the taps that connect one field of «Registrar gasto» to the transaction:
/// the blue word, the variable above the keyboard, the bubble again, the property.
private struct ConnectAnimation: View {
    let field: String
    let done: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: CaseIterable {
        case start, tapWord, tapSuggestion, tapBubble, pickProperty, connected
    }

    var body: some View {
        if reduceMotion {
            frame(.pickProperty)
        } else {
            PhaseAnimator(Phase.allCases) { phase in
                frame(phase)
            } animation: { phase in
                .easeInOut(duration: 0.3).delay(phase == .start ? 0.4 : 1.3)
            }
        }
    }

    /// The subtitle under the drawing, numbered like the steps below it.
    private func caption(_ phase: Phase) -> String {
        switch phase {
        case .start, .tapWord: "1 · Toca «\(field)» en azul"
        case .tapSuggestion: ShortcutsVersion.isIOS27
            ? "2 · «Seleccionar variable» y toca el bloque de Wallet"
            : "2 · Toca «Entrada del atajo»"
        case .tapBubble: "3 · Toca la burbuja otra vez"
        case .pickProperty: "4 · Elige «\(field)»"
        case .connected: "Listo: «\(field)» quedó conectado"
        }
    }

    private func frame(_ phase: Phase) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption(phase))
                .font(.ticket(12, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Theme.brass)
                .contentTransition(.opacity)
            ActionCard(
                importe: token("Importe", phase),
                comercio: token("Comercio", phase),
                ring: ringOnField(phase) ? field : nil
            )
            ZStack(alignment: .topLeading) {
                Color.clear.frame(height: 96)
                switch phase {
                case .tapSuggestion:
                    suggestionBar
                case .pickProperty:
                    propertyList
                default:
                    EmptyView()
                }
            }
        }
    }

    private func ringOnField(_ phase: Phase) -> Bool {
        phase == .tapWord || phase == .tapBubble
    }

    private func token(_ name: String, _ phase: Phase) -> ActionCard.Token {
        if done.contains(name) { return .variable(name) }
        guard name == field else { return .placeholder(name) }
        switch phase {
        case .start, .tapWord, .tapSuggestion: return .placeholder(name)
        case .tapBubble, .pickProperty:
            return .variable(ShortcutsVersion.isIOS27 ? "Wallet" : "Entrada del atajo")
        case .connected: return .variable(name)
        }
    }

    private var suggestionBar: some View {
        HStack(spacing: 8) {
            if ShortcutsVersion.isIOS27 {
                Text("Seleccionar variable")
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.Shortcuts.card, in: Capsule())
                    .tapTarget()
                Text("Entrada de atajo")
                    .foregroundStyle(Theme.Shortcuts.secondary)
                    .strikethrough()
                    .padding(.horizontal, 10).padding(.vertical, 6)
            } else {
                Text("Entrada del atajo")
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.Shortcuts.card, in: Capsule())
                    .tapTarget()
                Text("Seleccionar variable")
                    .foregroundStyle(Theme.Shortcuts.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
        }
        .font(.footnote)
    }

    private var propertyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(["Tarjeta", "Comercio", "Importe"], id: \.self) { property in
                Text(property)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tapTarget(property == field)
            }
        }
        .font(.footnote)
        .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 200, alignment: .leading)
    }
}

// MARK: - Pieces

/// «Registrar gasto» as Atajos shows it: "Registrar [Importe] en [Comercio]".
private struct ActionCard: View {
    enum Token {
        case placeholder(String)
        case variable(String)
    }

    let importe: Token
    let comercio: Token
    var ring: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AppGlyph()
                Text("Registrar gasto").font(.footnote.bold())
                Spacer()
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(Theme.Shortcuts.secondary)
            }
            // One line when it fits, as Atajos shows it; two when both bubbles are long.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { first; second }
                VStack(alignment: .leading, spacing: 6) { first; second }
            }
            .font(.footnote)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Shortcuts.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var first: some View {
        HStack(spacing: 6) {
            Text("Registrar").fixedSize()
            tokenView(importe, isRinged: ring == "Importe")
        }
    }

    private var second: some View {
        HStack(spacing: 6) {
            Text("en").fixedSize()
            tokenView(comercio, isRinged: ring == "Comercio")
        }
    }

    @ViewBuilder
    private func tokenView(_ token: Token, isRinged: Bool) -> some View {
        switch token {
        case .placeholder(let text):
            Text(text)
                .fixedSize()
                .foregroundStyle(Theme.Shortcuts.blue)
                .tapTarget(isRinged)
        case .variable(let text):
            Label(text, systemImage: "creditcard.fill")
                .labelStyle(.titleAndIcon)
                .font(.footnote)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.Shortcuts.blue)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.Shortcuts.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                .tapTarget(isRinged)
        }
    }
}

/// A tiny stand-in for Centavo's icon: the brass ticket.
private struct AppGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Theme.background)
            .frame(width: 22, height: 22)
            .overlay {
                // The app icon: days of the month, today in brass.
                Grid(horizontalSpacing: 1.5, verticalSpacing: 1.5) {
                    GridRow { cell(Theme.surface); cell(Theme.brassLow) }
                    GridRow { cell(Theme.brass); cell(Theme.surface) }
                }
            }
    }

    private func cell(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 6, height: 6)
    }
}

private extension View {
    /// The brass ring that says "tap here".
    func tapTarget(_ isOn: Bool = true) -> some View {
        overlay {
            if isOn {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.brass, lineWidth: 2)
                    .padding(-5)
            }
        }
    }
}
