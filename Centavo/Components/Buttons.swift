import SwiftUI

/// What a prominent button does: the usual brass, or the one red the app has.
enum TicketButtonKind {
    /// Brass. The main action of a screen or sheet: «Guardar», «Configurar ahora».
    case primary
    /// Red. Only for deleting, after asking (`confirmsDelete`).
    case destructive

    var tint: Color {
        switch self {
        case .primary: Theme.brass
        case .destructive: Theme.danger
        }
    }
}

extension View {
    /// The system's prominent button in the app's color: Liquid Glass on iOS 26, a filled
    /// capsule before. Apply it to a `Button` or a `Link`; it is the only prominent style the
    /// app uses (never `.borderedProminent` by hand: it would skip the glass).
    func ticketProminent(_ kind: TicketButtonKind = .primary) -> some View {
        modifier(TicketProminent(kind: kind))
    }
}

private struct TicketProminent: ViewModifier {
    let kind: TicketButtonKind

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonStyle(.glassProminent).tint(kind.tint)
        } else {
            content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(kind.tint)
        }
    }
}

/// The label of a full-width main action: uppercase, spaced, dark on brass, at least 44 pt.
///
///     Button(action: start) { PrimaryButtonLabel("Configurar ahora", systemImage: "wallet.pass") }
///         .ticketProminent()
struct PrimaryButtonLabel: View {
    let title: String
    var systemImage: String?
    var kind: TicketButtonKind = .primary

    init(_ title: String, systemImage: String? = nil, kind: TicketButtonKind = .primary) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
    }

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.ticket(.footnoteStrong))
        .tracking(Theme.Tracking.action)
        .textCase(.uppercase)
        // Explicit: inside a prominent button the hierarchical styles follow the tint.
        .foregroundStyle(kind == .primary ? Theme.onBrass : Theme.ink)
        .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
    }
}

/// The quiet partner of a main action («Después», «Conservar»): plain text, full tap target.
struct SecondaryButton: View {
    let title: String
    var identifier: String?
    let action: () -> Void

    init(_ title: String, identifier: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ticket(.footnote))
                .foregroundStyle(Theme.muted)
                .frame(minHeight: Theme.Size.tapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// A quiet action written in brass inside a screen («Ajustar presupuesto», «Agregar gasto
/// fijo», «Deshacer»): uppercase and spaced like every action, optionally with a symbol,
/// at least 44 pt tall. Put it in a plain `Button`.
///
///     Button(action: onAdjust) { LinkActionLabel("Ajustar presupuesto", systemImage: "slider.horizontal.3") }
///         .buttonStyle(.plain)
struct LinkActionLabel: View {
    let title: String
    var systemImage: String?
    /// `.center` for a button across a card, `.leading` for one in a list row.
    var alignment: Alignment = .center
    /// `false` for one beside other content (the undo bar), so it only takes its width.
    var fillsWidth = true

    init(_ title: String, systemImage: String? = nil, alignment: Alignment = .center, fillsWidth: Bool = true) {
        self.title = title
        self.systemImage = systemImage
        self.alignment = alignment
        self.fillsWidth = fillsWidth
    }

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.ticket(.footnoteStrong))
        .tracking(Theme.Tracking.action)
        .textCase(.uppercase)
        .foregroundStyle(Theme.brass)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: Theme.Size.tapTarget, alignment: alignment)
        .contentShape(Rectangle())
    }
}

/// The one way to delete or take something away inside a sheet («Borrar gasto», «Quitar
/// presupuesto»): red, uppercase and spaced, centered across its row, at least 44 pt. The
/// confirmation that follows (`DeleteSheet`, a dialog) has the prominent red button.
struct DestructiveRowButton: View {
    let title: String
    var identifier: String?
    let action: () -> Void

    init(_ title: String, identifier: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(role: .destructive, action: action) {
            Text(title)
                .font(.ticket(.footnoteStrong))
                .tracking(Theme.Tracking.action)
                .textCase(.uppercase)
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(identifier ?? "")
    }
}

#Preview("Botones") {
    VStack(spacing: Theme.Space.m) {
        Button {} label: { PrimaryButtonLabel("Configurar ahora", systemImage: "wallet.pass") }
            .ticketProminent()
        Button {} label: { PrimaryButtonLabel("Borrar", kind: .destructive) }
            .ticketProminent(.destructive)
        Button("Sumar en pesos") {}
            .font(.ticket(.label))
            .foregroundStyle(Theme.onBrass)
            .ticketProminent()
        SecondaryButton("Después") {}
        DestructiveRowButton("Borrar gasto") {}
        Button {} label: { LinkActionLabel("Ajustar presupuesto", systemImage: "slider.horizontal.3") }
            .buttonStyle(.plain)
    }
    .padding(Theme.Space.screen)
    .ticketPreview()
}
