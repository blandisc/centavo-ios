import CentavoCore
import SwiftUI

/// One quiet line under the carousel: when the last Wallet payment arrived, or that it is
/// worth checking the automation. Tapping it opens the setup guide. The payments the capture
/// couldn't write down have their own notice above it (`PendingPaymentsPanel`).
struct CaptureHealthRow: View {
    let health: CaptureHealth
    let openGuide: () -> Void

    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = Theme.Size.glyph

    private var text: String {
        switch health {
        case .never:
            return "Wallet sin conectar · Configurar"
        case .recent(let date):
            return "Wallet · último pago " + AppClock.relative(date, abbreviated: true)
        case .quiet(let days):
            return "Wallet · sin pagos desde hace \(days) días · Revisar"
        }
    }

    private var needsAttention: Bool { !health.isRecent }

    /// When it needs attention it is a short sentence and what to do, not a shouted caption.
    private var warning: (title: String, detail: String) {
        switch health {
        case .quiet(let days):
            return ("Sin pagos de Wallet desde hace \(days) días", "Si sí pagaste, toca para revisar el atajo.")
        default:
            return ("Wallet sin conectar", "Conéctalo una vez y cada pago con Apple Pay se anota solo.")
        }
    }

    var body: some View {
        if needsAttention { attention } else { quiet }
    }

    private var attention: some View {
        Button(action: openGuide) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Theme.brass)
                    .frame(width: glyphWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    Text(warning.title)
                        .font(.ticket(.footnoteStrong))
                        .foregroundStyle(Theme.ink)
                    Text(warning.detail)
                        .font(.ticket(.detail))
                        .foregroundStyle(Theme.muted)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Space.s)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
            .ticketPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, Theme.Space.s)
        .accessibilityIdentifier("salud-captura")
        .accessibilityHint("Abre la guía del atajo")
    }

    private var quiet: some View {
        Button(action: openGuide) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "wave.3.right")
                    .imageScale(.small)
                    // The width of a day divider's dash, so «Wallet» starts where «HOY» does.
                    .frame(width: glyphWidth, alignment: .leading)
                Text(text)
                    .font(.ticket(.caption))
                    .tracking(Theme.Tracking.label)
                    .textCase(.uppercase)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Space.none)
            }
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
            // Still 44 pt to tap, but it takes only its line: the rest overlaps the air above
            // and below instead of adding a band of empty space (owner, 2026-10-22).
            .padding(.vertical, Theme.Space.tuck)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("salud-captura")
        .accessibilityHint("Abre la guía del atajo")
    }
}

/// The payments the capture received and couldn't write down (`UnreadNotice`): how many, and
/// each one with «Anotar» and «Descartar». It stays until the person deals with them; a payment
/// that comes in right after does not take it away (2026-11-11). On «Hoy», with or without
/// expenses. One is shown as it is; several fold under their count and open with a tap.
struct PendingPaymentsPanel: View {
    let pending: [PendingPayment]
    /// «Anotar»: opens the sheet of a new expense for this payment.
    let log: (PendingPayment) -> Void
    let discard: (PendingPayment) -> Void
    let discardAll: () -> Void
    let openGuide: () -> Void

    @State private var expanded = false
    @State private var asking: Discard?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = Theme.Size.glyph

    /// What «Descartar» is asked about: one payment, or all of them.
    private enum Discard: Identifiable {
        case one(PendingPayment)
        case all(count: Int)

        var id: String {
            switch self {
            case .one(let payment): payment.id.uuidString
            case .all: "todos"
            }
        }
    }

    private var folds: Bool { pending.count > 1 }
    private var showsList: Bool { !folds || expanded }
    /// A notice that didn't read usually means the automation is wired wrong.
    private var hasUnread: Bool { pending.contains { $0.kind == .unread } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.none) {
            if folds {
                Button {
                    withAnimation(Theme.Motion.animation(Theme.Motion.toggle, reduceMotion: reduceMotion)) {
                        expanded.toggle()
                    }
                } label: {
                    header
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pagos-pendientes")
                .accessibilityValue(expanded ? "Lista abierta" : "Lista cerrada")
                .accessibilityHint(expanded ? "Oculta los pagos" : "Muestra los pagos para anotarlos o descartarlos")
            } else {
                header
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("pagos-pendientes")
            }
            if showsList {
                ForEach(pending) { row($0) }
                if hasUnread || folds { footer }
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ticketPanel()
        .padding(.vertical, Theme.Space.s)
        .confirmsRemoval(of: $asking, question: question) { asked in
            switch asked {
            case .one(let payment): discard(payment)
            case .all: discardAll()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Theme.brass)
                .frame(width: glyphWidth, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                Text(PendingPayments.title(for: pending))
                    .font(.ticket(.footnoteStrong))
                    .foregroundStyle(Theme.ink)
                Text(lead)
                    .font(.ticket(.detail))
                    .foregroundStyle(Theme.muted)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.s)
            if folds {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Under the count: what to do about them.
    private var lead: String {
        if !folds { return "No está en tus gastos. Anótalo o descártalo." }
        return expanded ? "No están en tus gastos. Anótalos o descártalos." : "No están en tus gastos. Toca para verlos."
    }

    private func row(_ payment: PendingPayment) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.none) {
            VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                Text(Self.name(payment))
                    .font(.ticket(.bodyMedium))
                    .foregroundStyle(Theme.ink)
                Text(Self.detail(payment))
                    .font(.ticket(.detail))
                    .foregroundStyle(Theme.muted)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Theme.Space.m)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spoken(payment))
            AdaptiveStack(spacing: Theme.Space.xl) {
                Button { log(payment) } label: {
                    LinkActionLabel("Anotar", systemImage: "plus", alignment: .leading, fillsWidth: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pendiente-anotar")
                .accessibilityLabel("Anotar \(Self.name(payment))")
                .accessibilityHint("Abre la hoja de gasto nuevo")
                SecondaryButton("Descartar", identifier: "pendiente-descartar") { asking = .one(payment) }
                    .accessibilityLabel("Descartar \(Self.name(payment))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Perforation() }
    }

    /// What goes for all of them: the way to the guide when a notice didn't read, and
    /// «Descartar todos» when there are several.
    private var footer: some View {
        AdaptiveStack(spacing: Theme.Space.xl) {
            if hasUnread {
                Button(action: openGuide) {
                    LinkActionLabel("Revisar el atajo", systemImage: "wallet.pass", alignment: .leading, fillsWidth: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pendientes-revisar-atajo")
                .accessibilityHint("Abre la guía del atajo")
            }
            if folds {
                SecondaryButton("Descartar todos", identifier: "pendientes-descartar-todos") {
                    asking = .all(count: pending.count)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Perforation() }
    }

    private func question(_ asked: Discard) -> TicketQuestion {
        switch asked {
        case .one(let payment):
            TicketQuestion(title: "¿Descartar este pago?", name: payment.text, detail: Self.detail(payment),
                           note: "No se anotará en tus gastos. No se puede deshacer.", verb: "Descartar")
        case .all(let count):
            TicketQuestion(title: "¿Descartar los \(count) pagos?",
                           note: "Ninguno se anotará en tus gastos. No se puede deshacer.", verb: "Descartar todos")
        }
    }

    /// A notice that didn't read is quoted, as it arrived; a payment that did is said plainly.
    static func name(_ payment: PendingPayment) -> String {
        payment.kind == .unread ? "«\(payment.text)»" : payment.text
    }

    /// «Llegó sin monto · hace 2 h», «No se pudo guardar · hace 10 min».
    static func detail(_ payment: PendingPayment) -> String {
        (payment.kind == .unread ? "Llegó sin monto" : "No se pudo guardar")
            + " · " + AppClock.relative(payment.date, abbreviated: true)
    }

    /// The whole row in one sentence, for VoiceOver.
    static func spoken(_ payment: PendingPayment) -> String {
        let when = AppClock.relative(payment.date)
        return payment.kind == .unread
            ? "Aviso de Wallet sin monto: \(payment.text), \(when)."
            : "Pago que no se pudo guardar: \(payment.text), \(when)."
    }
}

#Preview("Pagos pendientes") {
    let now = AppClock.now
    return VStack(spacing: Theme.Space.xl) {
        PendingPaymentsPanel(
            pending: [PendingPayment(kind: .unsaved, text: "$319 en Google", date: now.addingTimeInterval(-600))],
            log: { _ in }, discard: { _ in }, discardAll: {}, openGuide: {})
        PendingPaymentsPanel(
            pending: [PendingPayment(kind: .unread, text: "Google", date: now.addingTimeInterval(-7200)),
                      PendingPayment(kind: .unread, text: "Oxxo", date: now.addingTimeInterval(-86_400))],
            log: { _ in }, discard: { _ in }, discardAll: {}, openGuide: {})
    }
    .padding(Theme.Space.screen)
    .ticketPreview()
}
