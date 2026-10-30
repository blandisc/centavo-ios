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
    /// What came back this month (`CategoryShare.returned`): the shares leave it out, so the
    /// figure on top, the same as «Llevas», is the lines minus this.
    var returned: Decimal = 0
    var selected: CategoryShare?
    var onSelect: (CategoryShare?) -> Void = { _ in }

    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @AppStorage(UserCatalog.categoryColorsKey) private var storedColors = ""
    @Environment(\.dynamicTypeSize) private var typeSize

    private var total: Decimal { shares.reduce(0) { $0 + $1.amount } - returned }

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
                            // Letter spacing trails the last digit too: give it back, so the
                            // figure ends on the bar's edge.
                            .padding(.trailing, -Theme.Tracking.caption)
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
            // The same section caption as «Cada día del mes», the page beside it.
            .ticketCaption()
            .accessibilityElement(children: .combine)
            switch style {
            case .bar:
                ShareBarChart(lines: lines, money: money, selected: selected, onSelect: onSelect)
            case .mosaic:
                ShareMosaicChart(lines: lines, money: money, selected: selected, onSelect: onSelect)
            case .hidden:
                EmptyView()
            }
            if returned > 0 {
                HStack {
                    Text("Menos devoluciones")
                    Spacer(minLength: Theme.Space.s)
                    Text("−" + money(returned))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(Theme.MinimumScale.figure)
                }
                .font(.ticket(.detail))
                .foregroundStyle(Theme.muted)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("en-que-se-va-devoluciones")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("en-que-se-va")
    }

    private var lines: [CategoryLine] {
        let custom = UserCatalog.decode(storedCategories)
        let colors = CatalogColors(categories: storedColors, sources: "")
        return shares.map { share in
            CategoryLine(
                share: share,
                name: share.isRest ? "Otras" : share.category ?? "Sin categoría",
                icon: share.isRest ? "ellipsis"
                    : share.category.map { CategoryStyle.icon(for: $0, custom: custom) } ?? "questionmark",
                // Each category keeps its own color all month and every month; «Otras» and
                // what has no category are grey.
                color: share.isRest ? Theme.categoryRest
                    : share.category.map(colors.category) ?? Theme.categoryRest
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
    /// Tapping a line shows only its expenses in the list, as a block of the mosaic does.
    let selected: CategoryShare?
    let onSelect: (CategoryShare?) -> Void

    private func isSelected(_ line: CategoryLine) -> Bool {
        selected.map { line.share.isSameLine(as: $0) } ?? false
    }

    @ScaledMetric(relativeTo: .footnote) private var barHeight: CGFloat = Theme.Size.shareBar
    @ScaledMetric(relativeTo: .footnote) private var scaledHeight: CGFloat = Theme.Size.shareChartHeight

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
                        .opacity(selected == nil || isSelected(line) ? Theme.Opacity.visible : Theme.Opacity.unselected)
                        .onTapGesture {
                            let wasSelected = isSelected(line)
                            Theme.Motion.instantly { onSelect(wasSelected ? nil : line.share) }
                        }
                        .accessibilityLabel(line.spoken(money))
                        .accessibilityAddTraits(isSelected(line) ? [.isButton, .isSelected] : .isButton)
                        .accessibilityHint("Muestra solo sus gastos")
                }
            }
        }
        // As tall as the mosaic, however many categories there are.
        .frame(minHeight: min(scaledHeight, Theme.Size.shareChartMaxHeight), alignment: .top)
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
                        // The same for the spacing after the «%».
                        .padding(.trailing, -Theme.Tracking.detail)
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
        .accessibilityIdentifier("parte-\(line.name)")
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

    @ScaledMetric(relativeTo: .footnote) private var scaledHeight: CGFloat = Theme.Size.shareChartHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Grows a little with the text, but stays a part of the screen.
    private var height: CGFloat { min(scaledHeight, Theme.Size.shareChartMaxHeight) }

    private func isSelected(_ line: CategoryLine) -> Bool {
        selected.map { line.share.isSameLine(as: $0) } ?? false
    }

    private func toggle(_ line: CategoryLine) {
        let wasSelected = isSelected(line)
        // The list under the chart changes at once; only the blocks' ring and dimming ease.
        Theme.Motion.instantly { onSelect(wasSelected ? nil : line.share) }
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
                                              anySelected: selected != nil, money: money,
                                              onToggle: { toggle(line) }))
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
                        MosaicTile(line: line, amount: money(line.share.amount))
                    }
                    .buttonStyle(.plain)
                    .frame(width: tile.width - Theme.Size.mosaicGap, height: tile.height - Theme.Size.mosaicGap)
                    .modifier(MosaicTileDress(line: line, isSelected: isSelected(line),
                                              anySelected: selected != nil, money: money,
                                              onToggle: { toggle(line) }))
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
    let onToggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(line.color, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(Theme.ink, lineWidth: Theme.Stroke.strong)
                }
            }
            // Pressed and held, a block shows all of it: its name in full, its amount and its share,
            // which the block may have had no room for.
            .contextMenu {
                Button(isSelected ? "Ver todo el mes" : "Ver sus gastos",
                       systemImage: isSelected ? "xmark" : "list.bullet", action: onToggle)
            } preview: {
                MosaicDetail(line: line, amount: money(line.share.amount))
            }
            .opacity(!anySelected || isSelected ? Theme.Opacity.visible : Theme.Opacity.unselected)
            .animation(Theme.Motion.animation(Theme.Motion.select, reduceMotion: reduceMotion),
                       value: isSelected || anySelected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.spoken(money))
            .accessibilityHint(isSelected ? "Muestra todo el mes" : "Muestra sus gastos")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("parte-\(line.name)")
    }
}

/// What pressing and holding a mosaic block shows: the whole category, nothing cut.
private struct MosaicDetail: View {
    let line: CategoryLine
    let amount: String

    @ScaledMetric(relativeTo: .footnote) private var iconSize: CGFloat = Theme.Size.glyph

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
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
            if line.share.isRest {
                Text("\(line.share.restCount) categorías")
                    .font(.ticket(.detail))
                    .opacity(Theme.Opacity.onTileSecondary)
            }
            Text(amount)
                .font(.ticket(.display))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(Theme.MinimumScale.figure)
            Text("\(line.percent) de lo gastado")
                .font(.ticket(.detail))
                .monospacedDigit()
                .opacity(Theme.Opacity.onTileSecondary)
        }
        .foregroundStyle(line.textColor)
        .padding(Theme.Space.l)
        .frame(width: Theme.Size.mosaicPreviewWidth, alignment: .leading)
        .background(line.color)
        .accessibilityHidden(true)
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

/// A mosaic block: as much of the category as really fits, never cut. It tries, roomiest first,
/// icon + name over amount + share, then one line of icon, name and amount, then the name alone,
/// then the name running up the block (a tall, narrow one) with or without its icon, and last the icon. Each candidate is
/// measured at its own size by `ViewThatFits` (no estimate of the text's width), so a name that
/// does not fit across is not truncated: the next candidate is tried.
private struct MosaicTile: View {
    let line: CategoryLine
    let amount: String

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
            .fixedSize()
    }

    private var nameRow: some View {
        HStack(spacing: Theme.Space.xs) { icon; name }
    }

    var body: some View {
        ViewThatFits(in: [.horizontal, .vertical]) {
            // Icon and name on top, amount and share below.
            VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                nameRow
                Spacer(minLength: Theme.Space.xxs)
                Text(amount)
                    .font(.ticket(.bodyStrong))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                Text(line.percent)
                    .font(.ticket(.micro))
                    .monospacedDigit()
                    .opacity(Theme.Opacity.onTileSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Short and wide: all on one line.
            HStack(spacing: Theme.Space.xs) {
                nameRow
                Spacer(minLength: Theme.Space.xxs)
                Text(amount)
                    .font(.ticket(.label))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            // No room for the amount: the name is still worth more than a bare icon.
            nameRow
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Tall and narrow: the name runs up the block, as on a book's spine.
            VStack(spacing: Theme.Space.none) {
                icon
                Spacer(minLength: Theme.Space.xs)
                Sideways { name }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // A long name, tall room but not enough for the icon too: the name wins.
            Sideways { name }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            icon.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(line.textColor)
        .padding(Theme.Space.s)
        .contentShape(Rectangle())
    }
}

/// Lays its one subview out turned a quarter to the left, taking the room the turned view takes
/// (`rotationEffect` alone would keep the room of the unturned one).
private struct Sideways<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        SidewaysLayout { content.rotationEffect(.degrees(-90)) }
    }
}

private struct SidewaysLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let size = view.sizeThatFits(.unspecified)
        return CGSize(width: size.height, height: size.width)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        view.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                   proposal: ProposedViewSize(view.sizeThatFits(.unspecified)))
    }
}
