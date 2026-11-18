import SwiftUI

/// A category or a way of paying as a small tile: its icon in its own color over its name.
/// The same tile in the expense sheet (pick one) and in «Pagos y categorías» (manage them).
///
/// - `selected` fills it in brass (the one chosen for this expense).
/// - `isAction` («Nueva», «Agregar») is outlined with the ticket's dashes, in brass.
/// - `badge` marks a corner (★ the default card, a crossed eye a hidden category); `dimmed`
///   fades a hidden one.
/// - `twoLines` lets a name of two words wrap («American / Express»); every tile in a grid
///   keeps the same height either way.
struct CategoryTile: View {
    let name: String
    let icon: String
    var color: Color = Theme.brass
    var selected = false
    var isAction = false
    var badge: String?
    var dimmed = false
    var twoLines = false

    @ScaledMetric(relativeTo: .body) private var symbolBox = Theme.Size.categorySymbol
    @ScaledMetric(relativeTo: .body) private var tallHeight = Theme.Size.catalogTileHeight
    @ScaledMetric(relativeTo: .body) private var shortHeight = Theme.Size.categoryTile

    @Environment(\.dynamicTypeSize) private var typeSize

    private var symbolColor: Color { selected ? Theme.onBrass : isAction ? Theme.brass : color }
    private var nameColor: Color { selected ? Theme.onBrass : isAction ? Theme.brass : Theme.ink }

    private var symbol: some View {
        Image(systemName: icon)
            .font(Theme.Symbol.regular)
            .foregroundStyle(symbolColor)
            .frame(height: symbolBox)
            .accessibilityHidden(true)
    }

    /// Icon over the name, the size of a square in the grid.
    private var stacked: some View {
        VStack(spacing: Theme.Space.xs) {
            symbol
            // One word stays on one line and shrinks a little rather than break («Suscripcione/s»).
            Text(name)
                .font(.ticket(.detail))
                .foregroundStyle(nameColor)
                .multilineTextAlignment(.center)
                .lineLimit(twoLines && name.contains(" ") ? 2 : 1)
                .minimumScaleFactor(Theme.MinimumScale.figure)
        }
    }

    /// With accessibility sizes, one tile per row: the icon beside the whole name, which wraps
    /// instead of shrinking (2026-11-18: «Transporte» was cut to «Transp…»).
    private var wide: some View {
        HStack(spacing: Theme.Space.m) {
            symbol
                .frame(minWidth: symbolBox)
            Text(name)
                .font(.ticket(.detail))
                .foregroundStyle(nameColor)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.Space.xs)
    }

    var body: some View {
        let height = twoLines ? tallHeight : shortHeight
        let large = typeSize.isAccessibilitySize
        Group {
            if large { wide } else { stacked }
        }
        .padding(.horizontal, large ? Theme.Space.m : Theme.Space.xs)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: large ? nil : height)
        .background(selected ? Theme.brass : isAction ? Color.clear : Theme.raised,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .overlay {
            if !selected {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(isAction ? Theme.brassLow : Theme.hairline,
                                  style: StrokeStyle(lineWidth: Theme.Stroke.hairline,
                                                     dash: isAction ? Theme.Dash.ticket : []))
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge {
                Image(systemName: badge)
                    .font(.ticket(.micro))
                    .foregroundStyle(badge == "star.fill" ? Theme.brass : Theme.faint)
                    .padding(Theme.Space.xs)
                    .accessibilityHidden(true)
            }
        }
        .opacity(dimmed ? Theme.Opacity.unselected : Theme.Opacity.visible)
        .contentShape(Rectangle())
    }
}

extension CategoryTile {
    /// The grid the tiles go in, in the expense sheet and in «Pagos y categorías»: squares
    /// side by side, or one per row with accessibility sizes, where a name needs the width.
    static func columns(for typeSize: DynamicTypeSize) -> [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: Theme.Space.s)]
            : [GridItem(.adaptive(minimum: Theme.Size.categoryGridMinimum), spacing: Theme.Space.s)]
    }
}

#Preview("Mosaicos") {
    HStack(spacing: Theme.Space.s) {
        CategoryTile(name: "Despensa", icon: "cart", color: Theme.categories[0])
        CategoryTile(name: "Comida", icon: "fork.knife", color: Theme.categories[1], selected: true)
        CategoryTile(name: "Nueva", icon: "plus", isAction: true)
    }
    .padding(Theme.Space.screen)
    .ticketPreview()
}
