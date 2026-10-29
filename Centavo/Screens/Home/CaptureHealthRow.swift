import CentavoCore
import SwiftUI

/// One quiet line under the carousel: when the last Wallet payment arrived, or that it is
/// worth checking the automation. Tapping it opens the setup guide.
struct CaptureHealthRow: View {
    let health: CaptureHealth
    /// A notice that arrived without an amount after the last capture (see `UnreadNotice`).
    var unread: String?
    /// A small note under the «Hoy» divider instead of a row of its own.
    var compact = false
    let openGuide: () -> Void

    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = Theme.Size.glyph

    private var text: String {
        if let unread {
            return "Wallet · llegó «\(unread)» sin monto · Revisar el atajo"
        }
        switch health {
        case .never:
            return "Wallet sin conectar · Configurar"
        case .recent(let date):
            return "Wallet · último pago " + date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        case .quiet(let days):
            return "Wallet · sin pagos desde hace \(days) días · Revisar"
        }
    }

    private var needsAttention: Bool { unread != nil || !health.isRecent }

    /// When it needs attention it is a short sentence and what to do, not a shouted caption.
    private var warning: (title: String, detail: String) {
        if let unread {
            return ("Llegó un aviso de Wallet sin monto", "«\(unread)». Toca para revisar el atajo.")
        }
        switch health {
        case .quiet(let days):
            return ("Sin pagos de Wallet desde hace \(days) días", "Si sí pagaste, toca para revisar el atajo.")
        default:
            return ("Wallet sin conectar", "Conéctalo una vez y cada compra se anota sola.")
        }
    }

    var body: some View {
        if needsAttention && !compact { attention } else { quiet }
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
                Image(systemName: needsAttention ? "exclamationmark.circle" : "wave.3.right")
                    .imageScale(.small)
                    // The width of a day divider's dash, so «Wallet» starts where «HOY» does.
                    .frame(width: glyphWidth, alignment: .leading)
                Text(text)
                    .font(.ticket(compact ? .micro : .caption))
                    .tracking(compact ? Theme.Tracking.compactLabel : Theme.Tracking.label)
                    .textCase(.uppercase)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Space.none)
            }
            .foregroundStyle(needsAttention ? Theme.brass : Theme.muted)
            // Compact, it lines up with the divider's words, past its brass dash.
            .padding(.leading, compact ? Theme.Space.xlx : Theme.Space.none)
            .frame(maxWidth: .infinity, minHeight: compact ? Theme.Size.compactRow : Theme.Size.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
            // Still 44 pt to tap, but it takes only its line: the rest overlaps the air above
            // and below instead of adding a band of empty space (owner, 2026-10-22).
            .padding(.vertical, compact ? Theme.Space.none : Theme.Space.tuck)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("salud-captura")
        .accessibilityHint("Abre la guía del atajo")
    }
}
