import CentavoCore
import SwiftUI

/// How «En qué se va» is drawn, chosen in «Más».
enum WhereItGoesStyle: String, CaseIterable, Identifiable {
    /// One bar split by category, with a line per category under it.
    case bar
    /// One block per category, as big as what was spent there; tapping one filters the list.
    case mosaic
    /// Not shown: the budget page is only the month's bar.
    case hidden

    static let key = "whereItGoesStyle"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bar: "Barra"
        case .mosaic: "Mosaico"
        case .hidden: "No mostrar"
        }
    }

    var icon: String {
        switch self {
        case .bar: "chart.bar.doc.horizontal"
        case .mosaic: "square.grid.2x2"
        case .hidden: "eye.slash"
        }
    }
}

/// Where the month's money went, in the primary currency: each category in its own color
/// with its own icon, biggest first; past four, the rest go together in grey as «Otras».
struct WhereItGoes: View {
    let shares: [CategoryShare]
    var style: WhereItGoesStyle = .bar
    let money: (Decimal) -> String
    /// The category whose expenses the list shows, if one was tapped.
    var selected: CategoryShare?
    var onSelect: (CategoryShare?) -> Void = { _ in }

    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @Environment(\.dynamicTypeSize) private var typeSize

    private var total: Decimal { shares.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Group {
                if typeSize.isAccessibilitySize {
                    // Side by side the total got cut («$2,3…»): the title goes above it.
                    VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                        Text("En qué se va")
                            .fixedSize(horizontal: false, vertical: true)
                        Text(money(total))
                            .foregroundStyle(Theme.ink)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(Theme.MinimumScale.figure)
                    }
                } else {
                    HStack {
                        Text("En qué se va")
                            .lineLimit(1)
                            .layoutPriority(1)
                        Spacer(minLength: Theme.Space.s)
                        // Shrinks with large text rather than breaking «$2,366.00» in two.
                        Text(money(total))
                            .foregroundStyle(Theme.ink)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(Theme.MinimumScale.figure)
                    }
                }
            }
            .font(.ticket(.micro))
            .tracking(Theme.Tracking.label)
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)
            .accessibilityElement(children: .combine)
            switch style {
            case .bar:
                ShareBarChart(lines: lines, money: money)
            case .mosaic:
                ShareMosaicChart(lines: lines, money: money, selected: selected, onSelect: onSelect)
            case .hidden:
                EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("en-que-se-va")
    }

    private var lines: [CategoryLine] {
        let custom = UserCatalog.decode(storedCategories)
        return shares.enumerated().map { index, share in
            CategoryLine(
                share: share,
                name: share.isRest ? "Otras" : share.category ?? "Sin categoría",
                icon: share.isRest ? "ellipsis"
                    : share.category.map { CategoryStyle.icon(for: $0, custom: custom) } ?? "questionmark",
                color: share.isRest || index >= Theme.categories.count ? Theme.categoryRest : Theme.categories[index]
            )
        }
    }
}

/// One category as drawn: its name, icon and color.
private struct CategoryLine: Identifiable {
    let share: CategoryShare
    let name: String
    let icon: String
    let color: Color
    var id: String { name }

    var percent: String { share.share.formatted(.percent.precision(.fractionLength(0))) }
    /// Text on a block of this color: dark on the bright ones, light on the grey.
    var textColor: Color { share.isRest ? Theme.ink : Theme.onBrass }

    func spoken(_ money: (Decimal) -> String) -> String {
        share.isRest
            ? "Otras \(share.restCount) categorías: \(money(share.amount)), \(percent) de lo gastado"
            : "\(name): \(money(share.amount)), \(percent) de lo gastado"
    }
}

// MARK: - Bar

/// The month as one bar, a piece per category as wide as its share, and a line per
/// category under it: its icon in its color, the amount and the share.
private struct ShareBarChart: View {
    let lines: [CategoryLine]
    let money: (Decimal) -> String

    @ScaledMetric(relativeTo: .footnote) private var barHeight: CGFloat = Theme.Size.shareBar

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            GeometryReader { proxy in
                let gap: CGFloat = Theme.Space.xxxs
                let usable = max(proxy.size.width - gap * CGFloat(max(lines.count - 1, 0)), 0)
                HStack(spacing: gap) {
                    ForEach(lines) { line in
                        // A sliver still shows: 1 % of the month is still somewhere.
                        Rectangle().fill(line.color).frame(width: max(usable * line.share.share, Theme.Size.minimumBarWidth))
                    }
                }
                .frame(width: proxy.size.width, alignment: .leading)
                .clipShape(Capsule())
            }
            .frame(height: barHeight)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Space.none) {
                ForEach(lines) { line in
                    ShareBarLine(line: line, amount: money(line.share.amount))
                        .accessibilityLabel(line.spoken(money))
                }
            }
        }
    }
}

/// A category under the bar: its icon in its color, the name, the amount and the share.
/// With accessibility text sizes the name goes on its own line and the amount under it,
/// whole: side by side the names disappeared and the amounts were cut («$2,3…»).
private struct ShareBarLine: View {
    let line: CategoryLine
    let amount: String

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var iconWidth: CGFloat = Theme.Size.shareIconColumn
    @ScaledMetric(relativeTo: .footnote) private var iconSize: CGFloat = Theme.Size.glyph
    @ScaledMetric(relativeTo: .footnote) private var percentWidth: CGFloat = Theme.Size.sharePercentColumn
    @ScaledMetric(relativeTo: .footnote) private var rowHeight: CGFloat = Theme.Size.shareRow

    private var icon: some View {
        Image(systemName: line.icon)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(line.color)
            // Narrow glyphs (a bolt, a glass) would sit centered in the square.
            .frame(width: iconSize, height: iconSize, alignment: .leading)
            // Flush with the margin, like every other line (centered, they
            // started anywhere from 27 to 30 pt).
            .frame(width: iconWidth, alignment: .leading)
    }

    private var name: some View {
        Text(line.name)
            .foregroundStyle(line.share.category == nil && !line.share.isRest ? Theme.muted : Theme.ink)
    }

    private var amountText: some View {
        Text(amount)
            .foregroundStyle(Theme.ink)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var percent: some View {
        Text(line.percent)
            .foregroundStyle(Theme.muted)
            .monospacedDigit()
            .lineLimit(1)
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    HStack(spacing: Theme.Space.s) {
                        icon
                        name.fixedSize(horizontal: false, vertical: true)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Space.s) {
                            amountText.fixedSize()
                            Spacer(minLength: Theme.Space.s)
                            percent
                        }
                        VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                            amountText.minimumScaleFactor(Theme.MinimumScale.figure)
                            percent
                        }
                    }
                }
                .padding(.vertical, Theme.Space.xxs)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: Theme.Space.s) {
                    icon
                    name.lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    amountText.layoutPriority(1)
                    percent.frame(minWidth: percentWidth, alignment: .trailing)
                }
            }
        }
        .font(.ticket(.detail))
        .textCase(.uppercase)
        .tracking(Theme.Tracking.detail)
        // A line of 16 pt read as a target too small for the accessibility audit.
        .frame(minHeight: rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("categoria-\(line.name)")
    }
}

// MARK: - Mosaic

/// One block per category, as big as what was spent there, with its icon and as much of
/// its name and amount as fits. Tapping a block shows its expenses in the list.
private struct ShareMosaicChart: View {
    let lines: [CategoryLine]
    let money: (Decimal) -> String
    let selected: CategoryShare?
    let onSelect: (CategoryShare?) -> Void

    @ScaledMetric(relativeTo: .footnote) private var scaledHeight: CGFloat = Theme.Size.mosaicHeight
    @ScaledMetric(relativeTo: .footnote) private var textSize: CGFloat = Theme.Size.mosaicText
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Grows a little with the text, but stays a part of the screen.
    private var height: CGFloat { min(scaledHeight, Theme.Size.mosaicMaxHeight) }

    private func isSelected(_ line: CategoryLine) -> Bool {
        selected.map { line.share.isSameLine(as: $0) } ?? false
    }

    private func toggle(_ line: CategoryLine) {
        let wasSelected = isSelected(line)
        withAnimation(reduceMotion ? nil : Theme.Motion.quick) { onSelect(wasSelected ? nil : line.share) }
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            // With the largest text no name or amount fits in a block sized by its share (they
            // were cut or left only the icon): one full-width block per category, biggest
            // first, as tall as its text, in the same colors and still a filter.
            VStack(spacing: Theme.Space.xxs) {
                ForEach(lines) { line in
                    Button { toggle(line) } label: {
                        MosaicStackedTile(line: line, amount: money(line.share.amount))
                    }
                    .buttonStyle(.plain)
                    .modifier(MosaicTileDress(line: line, isSelected: isSelected(line),
                                              anySelected: selected != nil, money: money))
                }
            }
        } else {
            tiled
        }
    }

    private var tiled: some View {
        GeometryReader { proxy in
            // Laid out 3 pt wider and taller, then pulled back by the half gap: the outer blocks
            // touch the margins (they sat 1.5 pt inside, measured) and the gaps stay 3 pt.
            let tiles = ShareMosaic.layout(lines.map(\.share.share), width: proxy.size.width + Theme.Size.mosaicGap,
                                           height: proxy.size.height + Theme.Size.mosaicGap)
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(lines, tiles)), id: \.0.id) { line, tile in
                    Button { toggle(line) } label: {
                        MosaicTile(line: line, amount: money(line.share.amount),
                                   fit: ShareMosaic.fit(width: tile.width - Theme.Size.mosaicGap,
                                                        height: tile.height - Theme.Size.mosaicGap,
                                                        name: line.name,
                                                        lineHeight: textSize * Theme.Size.mosaicLineHeightRatio,
                                                        charWidth: textSize * Theme.Size.mosaicCharWidthRatio))
                    }
                    .buttonStyle(.plain)
                    .frame(width: tile.width - Theme.Size.mosaicGap, height: tile.height - Theme.Size.mosaicGap)
                    .modifier(MosaicTileDress(line: line, isSelected: isSelected(line),
                                              anySelected: selected != nil, money: money))
                    .offset(x: tile.x, y: tile.y)
                }
            }
        }
        .frame(height: height)
    }
}

/// A mosaic block's color, selection ring, dimming and what VoiceOver says: the same tiled
/// or stacked.
private struct MosaicTileDress: ViewModifier {
    let line: CategoryLine
    let isSelected: Bool
    let anySelected: Bool
    let money: (Decimal) -> String

    func body(content: Content) -> some View {
        content
            .background(line.color, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(Theme.ink, lineWidth: Theme.Stroke.strong)
                }
            }
            .opacity(!anySelected || isSelected ? Theme.Opacity.visible : Theme.Opacity.unselected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.spoken(money))
            .accessibilityHint(isSelected ? "Muestra todo el mes" : "Muestra sus gastos")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("categoria-\(line.name)")
    }
}

/// A mosaic block in accessibility text sizes: icon and name over the amount and its share,
/// all wrapping instead of shrinking.
private struct MosaicStackedTile: View {
    let line: CategoryLine
    let amount: String

    @ScaledMetric(relativeTo: .footnote) private var iconSize: CGFloat = Theme.Size.glyph

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Image(systemName: line.icon)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .frame(width: iconSize, height: iconSize)
                Text(line.name)
                    .font(.ticket(.label))
                    .textCase(.uppercase)
                    .tracking(Theme.Tracking.detail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(amount)
                .font(.ticket(.bodyStrong))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(line.percent)
                .font(.ticket(.micro))
                .monospacedDigit()
                .opacity(Theme.Opacity.onTileSecondary)
        }
        .foregroundStyle(line.textColor)
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct MosaicTile: View {
    let line: CategoryLine
    let amount: String
    let fit: ShareMosaic.Fit

    @ScaledMetric(relativeTo: .footnote) private var iconSize: CGFloat = Theme.Size.glyph

    private var icon: some View {
        Image(systemName: line.icon)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .frame(width: iconSize, height: iconSize)
    }

    private var name: some View {
        Text(line.name)
            .font(.ticket(.label))
            .textCase(.uppercase)
            .tracking(Theme.Tracking.detail)
            .lineLimit(1)
    }

    var body: some View {
        Group {
            switch fit {
            case .full:
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    HStack(spacing: Theme.Space.xs) { icon; name }
                    Spacer(minLength: Theme.Space.xxs)
                    Text(amount)
                        .font(.ticket(.bodyStrong))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(Theme.MinimumScale.figure)
                    Text(line.percent)
                        .font(.ticket(.micro))
                        .monospacedDigit()
                        .opacity(Theme.Opacity.onTileSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .line:
                HStack(spacing: Theme.Space.xs) {
                    icon
                    name
                    Spacer(minLength: Theme.Space.xxs)
                    Text(amount)
                        .font(.ticket(.label))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .vertical:
                // Too narrow for the name across: it runs up the block, as on a book's spine.
                GeometryReader { proxy in
                    VStack(spacing: Theme.Space.xs) {
                        icon
                        let room = max(proxy.size.height - iconSize - Theme.Space.xs, 0)
                        name
                            .frame(width: room, alignment: .leading)
                            .rotationEffect(.degrees(-90))
                            .frame(width: proxy.size.width, height: room)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                }
            case .icon:
                icon.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(line.textColor)
        .padding(Theme.Space.s)
        .contentShape(Rectangle())
    }
}
