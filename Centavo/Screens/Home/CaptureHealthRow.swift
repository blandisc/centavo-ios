import CentavoCore
import SwiftUI

/// One quiet line under the carousel: when the last Wallet payment arrived, or that it is
/// worth checking the automation. Tapping it opens the setup guide.
struct CaptureHealthRow: View {
    let health: CaptureHealth
    /// A small note under the «Hoy» divider instead of a row of its own.
    var compact = false
    let openGuide: () -> Void

    private var text: String {
        switch health {
        case .never:
            "Wallet sin conectar · Configurar"
        case .recent(let date):
            "Wallet · último pago " + date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        case .quiet(let days):
            "Wallet · sin pagos desde hace \(days) días · Revisar"
        }
    }

    private var needsAttention: Bool { !health.isRecent }

    var body: some View {
        Button(action: openGuide) {
            HStack(spacing: 8) {
                Image(systemName: needsAttention ? "exclamationmark.circle" : "wave.3.right")
                    .imageScale(.small)
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
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("salud-captura")
        .accessibilityHint("Abre la guía del atajo")
    }
}
