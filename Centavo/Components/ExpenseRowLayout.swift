import SwiftUI

/// One expense as a row, the same wherever an expense is listed (the month's list, «Gastos
/// fijos»): its category's tile, the name as it arrives, in uppercase, on one line, over a
/// quieter line in lowercase, and the amount on the right. Two levels, so the eye reads the
/// name first (owner, 2026-10-29: the list read as a wall of capitals). With accessibility
/// text sizes it stacks and the name wraps, so nothing is cut.
struct ExpenseRowLayout<Meta: View, Amount: View>: View {
    let name: String
    let tile: CategoryIconTile
    @ViewBuilder let meta: Meta
    @ViewBuilder let amount: Amount

    @Environment(\.dynamicTypeSize) private var typeSize

    private var nameText: some View {
        // One line, as the bank sends it; the full name is in the expense sheet.
        Text(name)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .truncationMode(.tail)
            .font(.ticket(.bodyMedium))
            .tracking(Theme.Tracking.name)
            .textCase(.uppercase)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.leading)
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    nameText
                    meta
                    amount
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    tile
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                        VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                            nameText
                            meta
                        }
                        Spacer(minLength: Theme.Space.s)
                        amount
                    }
                }
            }
        }
        .padding(.vertical, Theme.Space.s)
        .frame(minHeight: Theme.Size.tallRow)
        .contentShape(Rectangle())
    }
}

/// The quiet line under an expense's name: small, grey and in lowercase, one step under the
/// name. Wraps when it must, never shrinks.
struct ExpenseMetaText: View {
    let text: Text

    init(_ text: Text) { self.text = text }
    init(_ string: String) { self.text = Text(string) }

    var body: some View {
        text
            .font(.ticket(.hint))
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.leading)
    }
}

/// A category's icon on a small tile, in the category's own color; grey with `color == nil`
/// (no category, or an expense that does not count).
struct CategoryIconTile: View {
    let icon: String
    var color: Color?
    /// Behind a grey one: `surface` on the paper, `raised` inside a card.
    var background: Color = Theme.surface

    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = Theme.Size.rowTile
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = Theme.Size.rowTileSymbol

    var body: some View {
        Image(systemName: icon)
            .resizable()
            .scaledToFit()
            .fontWeight(.medium)
            .foregroundStyle(color ?? Theme.muted)
            .frame(width: iconSize, height: iconSize)
            .frame(width: tileSize, height: tileSize)
            .background(color.map { $0.opacity(Theme.Opacity.tagFill) } ?? background,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .accessibilityHidden(true)
    }
}
