import SwiftUI

/// A quiet line under the Wallet one when the daily backup failed or is days late (2026-11-02).
/// Only once the backup is set up; it goes away by itself with the next backup that works.
struct BackupWarningRow: View {
    let text: String
    let open: () -> Void

    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = Theme.Size.glyph

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Image(systemName: "exclamationmark.icloud")
                    .imageScale(.small)
                    .frame(width: glyphWidth, alignment: .leading)
                Text(text)
                    .font(.ticket(.detail))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Space.none)
            }
            .foregroundStyle(Theme.brass)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("aviso-respaldo")
        .accessibilityHint("Abre Ajustes")
    }
}
