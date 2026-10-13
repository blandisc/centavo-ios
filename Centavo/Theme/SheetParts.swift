import SwiftUI

/// The top row of a sheet: "CANCELAR   NUEVO GASTO   GUARDAR".
struct SheetBar<Leading: View, Trailing: View>: View {
    let title: String
    private let leading: Leading
    private let trailing: Trailing

    init(title: String, @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            leading.frame(maxWidth: .infinity, alignment: .leading)
            Text(title)
                .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                .tracking(2)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            trailing.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 52)
    }
}

/// A text button for a sheet bar. Brass when it is the main action, muted otherwise.
struct SheetAction: View {
    let title: String
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ticket(13, weight: prominent ? .semibold : .regular, relativeTo: .footnote))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(isEnabled ? (prominent ? Theme.brass : Theme.muted) : Theme.faint)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// The look every sheet shares: ticket paper, drag handle, soft corners.
    func ticketSheet() -> some View {
        self
            .padding(.horizontal, Theme.horizontalPadding)
            .background(Theme.background.ignoresSafeArea())
            .presentationBackground(Theme.background)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(14)
    }
}
