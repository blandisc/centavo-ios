import CentavoCore
import SwiftUI

/// What the capture promises, in one place for «Hoy» and its empty screen (2026-11-18). iOS 26's
/// automation («Wallet») fires only for payments made by holding the iPhone up, so there it says
/// that, as the welcome does: «cada pago con Apple Pay» sent people who bought online to blame
/// the shortcut. iOS 27 catches every Apple Pay payment.
enum CaptureCopy {
    private static var catchesAll: Bool { ShortcutsVersion.isIOS27 }

    /// `.waiting`: the guide was opened and no payment came yet. Opening the guide is all it
    /// knows (iOS doesn't say whether the automation was made), so it offers a way back to it
    /// for whoever stopped halfway (QA, 2026-11-18). «Abrir la guía», not «seguir»: the guide
    /// opens on its first step, it doesn't remember where the person was (QA, 2026-11-18).
    static var waiting: String {
        if catchesAll {
            return String(localized: "Paga algo con Apple Pay y aparecerá aquí solo. ¿Te quedaste a medias? Toca para abrir la guía.")
        }
        return String(localized: "Paga acercando el iPhone y aparecerá aquí solo. ¿Te quedaste a medias? Toca para abrir la guía.")
    }

    /// `.quiet`: days without a Wallet payment. In iOS 26 days of online purchases look the
    /// same, so it says those don't come in by themselves (QA, 2026-11-18).
    static var quiet: String {
        if catchesAll { return String(localized: "Si sí pagaste, toca para revisar el atajo.") }
        return String(localized: "Si pagaste acercando el iPhone, toca para revisar el atajo. Las compras en línea no se anotan solas.")
    }

    /// The guide's check, when a payment from before the guide was opened is all there is.
    static var proveIt: String {
        if catchesAll { return String(localized: "Paga algo con Apple Pay para comprobar.") }
        return String(localized: "Paga algo acercando el iPhone para comprobar.")
    }

    /// «Se anota solo», in «Cómo funciona».
    static var tutorial: String {
        if catchesAll {
            return String(localized: "Cada pago con Apple Pay llega por Atajos y se anota. El efectivo, con «+».")
        }
        return String(localized: "Cada pago que haces acercando el iPhone llega por Atajos y se anota. Lo demás, con «+».")
    }

    /// `.silent`: days after the guide, still nothing.
    static var silent: String {
        if catchesAll { return String(localized: "Si ya pagaste con Apple Pay, toca para revisarlo.") }
        return String(localized: "Si ya pagaste acercando el iPhone, toca para revisarlo.")
    }

    /// The empty screen's card, before connecting.
    static var connect: String {
        if catchesAll { return String(localized: "Cada pago con Apple Pay se anota solo.") }
        return String(localized: "Cada pago que haces acercando el iPhone se anota solo.")
    }

    /// «Wallet sin conectar», on «Hoy».
    static var connectOnce: String {
        if catchesAll { return String(localized: "Conéctalo una vez y cada pago con Apple Pay se anota solo.") }
        return String(localized: "Conéctalo una vez y cada pago que hagas acercando el iPhone se anota solo.")
    }

    /// The empty screen's first line.
    static var emptyLead: String {
        if catchesAll {
            return String(localized: "Anota un gasto, o conecta Wallet y cada pago con Apple Pay se anotará solo.")
        }
        return String(localized: "Anota un gasto, o conecta Wallet y cada pago que hagas acercando el iPhone se anotará solo.")
    }
}

/// One quiet line under the carousel: when the last Wallet payment arrived, or that it is
/// worth checking the automation. Tapping it opens the setup guide. The payments the capture
/// couldn't write down have their own notice above it (`PendingPaymentsPanel`).
struct CaptureHealthRow: View {
    let health: CaptureHealth
    let openGuide: () -> Void

    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = Theme.Size.glyph

    private var text: String {
        switch health {
        case .never, .waiting, .silent:
            return String(localized: "Wallet sin conectar · Configurar")
        case .recent(let date), .first(let date):
            let when = AppClock.relative(date, abbreviated: true)
            return String(localized: "Wallet · último pago \(when)")
        case .quiet(let days):
            return String(localized: "Wallet · sin pagos desde hace \(days) días · Revisar")
        }
    }

    /// What VoiceOver reads for the quiet line: «hace 3 horas», not «hace 3 h» (2026-11-18).
    private var spokenText: String {
        if case .recent(let date) = health {
            let when = AppClock.relative(date)
            return String(localized: "Wallet, último pago \(when)")
        }
        return text
    }

    private var needsAttention: Bool { !health.isRecent }

    /// When it needs attention it is a short sentence and what to do, not a shouted caption.
    private var warning: (title: String, detail: String, icon: String) {
        switch health {
        case .quiet(let days):
            let title = String(localized: "Sin pagos de Wallet desde hace \(days) días")
            return (title, CaptureCopy.quiet, "exclamationmark.circle")
        case .waiting:
            return (String(localized: "Esperando tu primer pago"), CaptureCopy.waiting, "hourglass")
        case .silent:
            return (String(localized: "El atajo no ha anotado nada"), CaptureCopy.silent, "exclamationmark.circle")
        case .first:
            return (firstTitle, String(localized: "Así se anotará cada uno."), "checkmark.circle")
        default:
            return (String(localized: "Wallet sin conectar"), CaptureCopy.connectOnce, "exclamationmark.circle")
        }
    }

    /// «Llegó tu primer pago solo: $47.50 en Oxxo», from what the automation saved with the
    /// first one, not the latest (a refund later that day read as the first payment). A first
    /// payment from before that was kept apart has no text: the title goes alone.
    private var firstTitle: String {
        let text = UserDefaults.standard.string(forKey: CaptureArrival.firstTextKey) ?? ""
        if text.isEmpty { return String(localized: "Llegó tu primer pago solo") }
        return String(localized: "Llegó tu primer pago solo: \(text)")
    }

    /// The first payment is said in the panel too, once: so the person sees that it worked.
    private var showsPanel: Bool {
        if case .first = health { return true }
        return needsAttention
    }

    var body: some View {
        if showsPanel { attention } else { quiet }
    }

    private var attention: some View {
        Button(action: openGuide) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Image(systemName: warning.icon)
                    .foregroundStyle(Theme.brass)
                    .frame(width: glyphWidth, alignment: .leading)
                    .accessibilityHidden(true)
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
                RowChevron()
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
                    // Only a mark: VoiceOver read its name before the line (2026-11-18).
                    .accessibilityHidden(true)
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
        .accessibilityLabel(spokenText)
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
                .accessibilityValue(listState)
                .accessibilityHint(listHint)
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
                RowChevron(.folds(expanded))
            }
        }
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Under the count: what to do about them.
    private var lead: String {
        if !folds { return String(localized: "No está en tus gastos. Anótalo o descártalo.") }
        if expanded { return String(localized: "No están en tus gastos. Anótalos o descártalos.") }
        return String(localized: "No están en tus gastos. Toca para verlos.")
    }

    /// Whether the folded list is open, for VoiceOver.
    private var listState: String {
        if expanded { return String(localized: "Lista abierta") }
        return String(localized: "Lista cerrada")
    }

    /// What a tap on the folded header does, for VoiceOver.
    private var listHint: String {
        if expanded { return String(localized: "Oculta los pagos") }
        return String(localized: "Muestra los pagos para anotarlos o descartarlos")
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
            TicketQuestion(title: String(localized: "¿Descartar este pago?"), name: payment.text,
                           detail: Self.detail(payment),
                           note: String(localized: "No se anotará en tus gastos. No se puede deshacer."),
                           verb: String(localized: "Descartar"))
        case .all(let count):
            TicketQuestion(title: String(localized: "¿Descartar los \(count) pagos?"),
                           note: String(localized: "Ninguno se anotará en tus gastos. No se puede deshacer."),
                           verb: String(localized: "Descartar todos"))
        }
    }

    /// A notice that didn't read is quoted, as it arrived; a payment that did is said plainly.
    static func name(_ payment: PendingPayment) -> String {
        let text = payment.text
        if payment.kind == .unread { return String(localized: "«\(text)»", comment: "A Wallet notice quoted as it arrived") }
        return text
    }

    /// «Llegó sin monto · hace 2 h», «No se pudo guardar · hace 10 min».
    static func detail(_ payment: PendingPayment) -> String {
        let when = AppClock.relative(payment.date, abbreviated: true)
        if payment.kind == .unread { return String(localized: "Llegó sin monto · \(when)") }
        return String(localized: "No se pudo guardar · \(when)")
    }

    /// The whole row in one sentence, for VoiceOver.
    static func spoken(_ payment: PendingPayment) -> String {
        let when = AppClock.relative(payment.date)
        let text = payment.text
        if payment.kind == .unread { return String(localized: "Aviso de Wallet sin monto: \(text), \(when).") }
        return String(localized: "Pago que no se pudo guardar: \(text), \(when).")
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
