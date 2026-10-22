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

    var body: some View {
        Button(action: openGuide) {
            HStack(spacing: 8) {
                Image(systemName: needsAttention ? "exclamationmark.circle" : "wave.3.right")
                    .imageScale(.small)
                    // The width of a day divider's dash, so «Wallet» starts where «HOY» does.
                    .frame(width: 14, alignment: .leading)
                Text(text)
                    .font(.ticket(compact ? 10 : 11, relativeTo: compact ? .caption2 : .caption))
                    .tracking(compact ? 0.8 : 1.2)
                    .textCase(.uppercase)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(needsAttention ? Theme.brass : Theme.muted)
            // Compact, it lines up with the divider's words, past its brass dash.
            .padding(.leading, compact ? 22 : 0)
            .frame(maxWidth: .infinity, minHeight: compact ? 28 : 44, alignment: .leading)
            .contentShape(Rectangle())
            // Still 44 pt to tap, but it takes only its line: the rest overlaps the air above
            // and below instead of adding a band of empty space (owner, 2026-10-22).
            .padding(.vertical, compact ? 0 : -10)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("salud-captura")
        .accessibilityHint("Abre la guía del atajo")
    }
}
