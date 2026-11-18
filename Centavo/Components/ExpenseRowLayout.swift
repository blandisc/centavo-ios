import SwiftUI

/// One expense as a row, the same wherever an expense is listed (the month's list, «Gastos
/// fijos»): its category's tile, the name as it arrives, in uppercase, on one line, over a
/// quieter line in lowercase, and the amount on the right. Two levels, so the eye reads the
/// name first (owner, 2026-10-29: the list read as a wall of capitals). With accessibility
/// text sizes it stacks: the name with the amount beside it, or right under it when they don't
/// fit, then the quiet line; the name wraps, so nothing is cut.
struct ExpenseRowLayout<Meta: View, Amount: View>: View {
    let name: String
    let tile: CategoryIconTile
    @ViewBuilder let meta: Meta
    @ViewBuilder let amount: Amount

    @Environment(\.dynamicTypeSize) private var typeSize

    /// A literal name: looked up in the catalog.
    init(name: LocalizedStringResource, tile: CategoryIconTile,
         @ViewBuilder meta: () -> Meta, @ViewBuilder amount: () -> Amount) {
        self.init(name: String(localized: name), tile: tile, meta: meta, amount: amount)
    }

    /// The name as it arrives (the bank's, the person's), shown as it is.
    @_disfavoredOverload
    init<S: StringProtocol>(name: S, tile: CategoryIconTile,
                            @ViewBuilder meta: () -> Meta, @ViewBuilder amount: () -> Amount) {
        self.name = String(name)
        self.tile = tile
        self.meta = meta()
        self.amount = amount()
    }

    /// One line, as the bank sends it (the full name is in the expense sheet); with an
    /// accessibility text size, as many as it takes.
    private func nameText(lines: Int?) -> some View {
        Text(name)
            .lineLimit(lines)
            .truncationMode(.tail)
            .rowName()
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.leading)
    }

    /// The most the quiet line grows with an accessibility text size (2026-11-18): bigger, and
    /// on an iPhone SE the card's icon at its end fell alone onto a line of its own.
    static var largestMetaType: DynamicTypeSize { .accessibility2 }

    /// With an accessibility text size: the name and the amount on one line while they fit
    /// (the amount still at the right edge); otherwise the amount on its own line right under
    /// the name, never under the quiet line. The quiet line goes last.
    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                    nameText(lines: 1)
                    Spacer(minLength: Theme.Space.s)
                    amount
                }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    nameText(lines: nil)
                    amount
                }
            }
            meta
                .dynamicTypeSize(...Self.largestMetaType)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var row: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            tile
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    nameText(lines: 1)
                    meta
                }
                Spacer(minLength: Theme.Space.s)
                amount
            }
        }
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { stackedRow } else { row }
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
    /// A literal: looked up in the catalog.
    init(_ string: LocalizedStringResource) { self.text = Text(String(localized: string)) }
    /// Text made at run time, shown as it is.
    @_disfavoredOverload
    init<S: StringProtocol>(_ string: S) { self.text = Text(String(string)) }

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
