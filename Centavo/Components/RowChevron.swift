import SwiftUI

/// The arrow at the end of a row: small and faint, so the row's words lead and brass stays for
/// what's chosen and the main figure (owner, 2026-11-16, D6-A). The one arrow for rows; an
/// arrow that is part of a phrase («Ver 6 más ⌄», «MXN ⌄») takes that phrase's color.
struct RowChevron: View {
    enum Kind {
        /// Opens another screen or sheet: ›.
        case opens
        /// Shows more right below, in place: › turning to ⌄ when open.
        case discloses(Bool)
        /// Folds a block that starts open or closed: ⌄, turning to ⌃ when open.
        case folds(Bool)
    }

    var kind: Kind = .opens

    init(_ kind: Kind = .opens) {
        self.kind = kind
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.ticket(.footnote))
            .foregroundStyle(Theme.faint)
            .rotationEffect(.degrees(angle))
            .accessibilityHidden(true)
    }

    private var symbol: String {
        if case .folds = kind { return "chevron.down" }
        return "chevron.right"
    }

    private var angle: Double {
        switch kind {
        case .opens: 0
        case .discloses(let open): open ? 90 : 0
        case .folds(let open): open ? 180 : 0
        }
    }
}
