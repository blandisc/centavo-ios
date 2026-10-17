import CentavoCore
import SwiftUI

/// One quiet line under the carousel: when the last Wallet payment arrived, or that it is
/// worth checking the automation. Tapping it opens the setup guide.
struct CaptureHealthRow: View {
    let health: CaptureHealth
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

    private var needsAttention: Bool {
        if case .recent = health { return false }
        return true
    }

    var body: some View {
        Button(action: openGuide) {
            HStack(spacing: 8) {
                Image(systemName: needsAttention ? "exclamationmark.circle" : "wave.3.right")
                    .imageScale(.small)
                Text(text)
                    .font(.ticket(11, relativeTo: .caption))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(needsAttention ? Theme.brass : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("salud-captura")
        .accessibilityHint("Abre la guía del atajo")
    }
}
