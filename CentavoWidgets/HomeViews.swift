import CentavoCore
import SwiftUI
import WidgetKit

/// «Hoy puedes gastar» on the home screen: small and medium (proposal A of both).
struct HoyView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    private var state: DayState { DayState(entry) }
    private var money: Money { Money(entry.snapshot) }
    private var ink: Ink { Ink(mode: mode) }

    var body: some View {
        Group {
            if state.isNeverOpened {
                neverOpened
            } else if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .widgetURL(state.tapURL)
    }

    /// One sentence for VoiceOver over what the widget shows; the «+» and «Fijar presupuesto»
    /// stay buttons of their own.
    private var spoken: String { entry.spoken(state, money) }

    private var figureColor: Color {
        switch state {
        case .neverOpened, .noBudget: ink.primary
        case .overBudget, .overToday: ink.danger
        case .normal, .fixedOverBudget: ink.brass
        }
    }

    // MARK: Never opened

    /// Before the app ever wrote to the widgets: no numbers, just what to do. A tap opens the app.
    private var neverOpened: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
            Caption(text: state.caption, color: ink.muted)
            Spacer(minLength: Theme.Space.xs)
            NeverOpenedBox(ink: ink, subtitle: true)
            Spacer(minLength: Theme.Space.none)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
            // VoiceOver reads the caption as the whole widget in one sentence, then the «+».
            Caption(text: state.caption, color: ink.muted)
                .accessibilityLabel(spoken)
            // The «+» beside the figure: the corner that opens «Anotar gasto». The rest of the
            // widget still opens the app (or the budget sheet) as before.
            HStack(alignment: .center, spacing: Theme.Space.xxs) {
                Figure(text: money.whole(state.figure), color: figureColor)
                    .accessibilityHidden(true)
                Spacer(minLength: Theme.Space.none)
                AddButton(ink: ink, compact: true)
            }
            Group {
                if let note = entry.staleNote {
                    StaleNote(text: note, ink: ink)
                } else {
                    Verdict(state: state, money: money, ink: ink)
                }
            }
            .accessibilityHidden(true)
            Spacer(minLength: Theme.Space.xs)
            if let pace = state.pace {
                Group {
                    if let days = entry.month?.days {
                        DayTicket(days: days, pace: pace, ink: ink)
                    } else {
                        MonthStrip(pace: pace, ink: ink)
                    }
                    // Only «Llevas $X» under the bar, in full (the budget is in the medium one).
                    keyText(.spent, money.whole(pace.spent), ink: ink)
                        .font(.widget(.spent))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(Theme.MinimumScale.widgetLabel)
                        .padding(.top, Theme.Space.xs)
                }
                .accessibilityHidden(true)
            } else {
                SetBudgetBox(ink: ink)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Medium

    private var medium: some View {
        VStack(alignment: .leading, spacing: Theme.Space.none) {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    // VoiceOver reads the caption as the whole widget in one sentence.
                    Caption(text: state.caption, color: ink.muted)
                        .accessibilityLabel(spoken)
                    HStack(alignment: .lastTextBaseline, spacing: Theme.Space.s) {
                        Figure(text: money.whole(state.figure), color: figureColor, style: .figureLarge)
                        if isOverBudget {
                            Verdict(state: state, money: money, ink: ink).fixedSize()
                        }
                    }
                    .accessibilityHidden(true)
                    if let note = entry.staleNote {
                        StaleNote(text: note, ink: ink)
                            .accessibilityHidden(true)
                    }
                }
                Spacer(minLength: Theme.Space.xxs)
                // With the boleto the rhythm goes under it, as on the main screen (W2).
                if state.pace != nil, !isOverBudget, entry.staleNote == nil, !hasDays {
                    Verdict(state: state, money: money, ink: ink, twoLines: true)
                        .padding(.top, Theme.Space.xxxs)
                        .accessibilityHidden(true)
                }
                AddButton(ink: ink)
            }
            Spacer(minLength: Theme.Space.xs)
            if let pace = state.pace {
                Group {
                    if let days = entry.month?.days {
                        // As on the main screen: the boleto and, under it, the rhythm alone (owner,
                        // 2026-11-08: no «Llevas … y podrías llevar …» and no average a day).
                        // Past the budget, «Llevas $X de $Y» in its place.
                        DayTicket(days: days, pace: pace, ink: ink, height: Theme.Size.widgetTicketTall)
                        Group {
                            if !isOverBudget, entry.staleNote == nil {
                                Verdict(state: state, money: money, ink: ink, endsWithRhythm: true)
                            } else {
                                dataLine(pace)
                            }
                        }
                        .padding(.top, Theme.Space.s)
                    } else {
                        if !pace.isOverspent {
                            annotation(pace)
                        }
                        MonthStrip(pace: pace, ink: ink, height: Theme.Size.widgetStripTall, tiles: true)
                        keys(pace)
                            .padding(.top, Theme.Space.xs)
                    }
                }
                .accessibilityHidden(true)
            } else {
                Link(destination: .setBudget) { SetBudgetBox(ink: ink, subtitle: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The medium draws the app's boleto (the days are in the snapshot).
    private var hasDays: Bool { entry.month?.days != nil }

    /// Past the budget, or fixed expenses past it: the verdict rides beside the figure.
    private var isOverBudget: Bool {
        switch state {
        case .overBudget, .fixedOverBudget: true
        default: false
        }
    }

    /// «PODRÍAS LLEVAR $8,516», over the rule it names; «Deberías» once past it.
    private func annotation(_ pace: BudgetPace) -> some View {
        GeometryReader { proxy in
            let share = min(max(NSDecimalNumber(decimal: pace.expectedToDate / pace.budget).doubleValue, 0), 1)
            let line: KeyLine = pace.isAheadOfPace ? .shouldBe : .couldBe
            let text = keyText(line, money.whole(pace.expectedToDate), ink: ink)
                .font(.widget(.key))
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
            let inset = Theme.Size.widgetAnnotationInset
            // Past half the bar, the text ends at the rule; before it, it starts there.
            let fromRight = share > 0.5
            let edge: Edge.Set = fromRight ? .trailing : .leading
            let distance = max(0, proxy.size.width * (fromRight ? 1 - share : share) - inset)
            text
                .frame(width: proxy.size.width, alignment: fromRight ? .trailing : .leading)
                .padding(edge, distance)
        }
        .frame(height: Theme.Size.widgetAnnotation)
        .padding(.bottom, Theme.Space.s)
    }

    /// «Llevas $24,518 de $24,180» under the boleto where there is no rhythm to say (past the
    /// budget, or a stale snapshot); what went in red past the budget.
    private func dataLine(_ pace: BudgetPace) -> some View {
        let spent = money.whole(pace.spentShown)
        let budget = money.whole(pace.budget)
        let spentColor = pace.isOverspent ? ink.danger : ink.primary
        let sentence = String(localized: "Llevas \(spent) de \(budget)")
        let tints = [Tint(text: spent, color: spentColor), Tint(text: budget, color: ink.primary, fromEnd: true)]
        return tinted(sentence, ink.muted, tints)
            .font(.widget(.verdict))
            .lineLimit(1)
            .minimumScaleFactor(Theme.MinimumScale.figure)
    }

    private func keys(_ pace: BudgetPace) -> some View {
        HStack(spacing: Theme.Space.xs) {
            RoundedRectangle(cornerRadius: Theme.Radius.widgetTile)
                .fill(pace.isOverspent ? ink.danger : ink.brass)
                .frame(width: Theme.Size.widgetKeySquare, height: Theme.Size.widgetKeySquare)
                .widgetAccentable()
            keyText(.spent, money.whole(pace.spent), ink: ink)
            Spacer(minLength: Theme.Space.xxs)
            if pace.fixedMonth > 0, !pace.isOverspent {
                keyText(.fixed, money.whole(pace.fixedMonth), ink: ink)
                Spacer(minLength: Theme.Space.xxs)
            }
            keyText(.budget, money.whole(pace.budget), ink: ink)
        }
        .font(.widget(.key))
        .textCase(.uppercase)
        .lineLimit(1)
        .minimumScaleFactor(Theme.MinimumScale.figure)
    }
}

/// «Hoy puedes gastar» on the left, «En qué se va» on the right (medium, proposal B).
struct WhereItGoesView: View {
    let entry: DayEntry
    @Environment(\.widgetRenderingMode) private var mode

    private var state: DayState { DayState(entry) }
    private var money: Money { Money(entry.snapshot) }
    private var ink: Ink { Ink(mode: mode) }
    private var slices: [WidgetSnapshot.Slice] { entry.month?.slices ?? [] }

    var body: some View {
        if state.isNeverOpened {
            // Nothing to split yet: the same «Abre Al día una vez» as the other layout.
            HoyView(entry: entry)
        } else {
            HStack(alignment: .top, spacing: Theme.Space.ml) {
                today
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Rectangle()
                    .fill(.clear)
                    .frame(width: Theme.Size.widgetDivider)
                    .overlay(Rectangle().stroke(ink.hairline, style: StrokeStyle(lineWidth: Theme.Stroke.hairline,
                                                                                 dash: Theme.Dash.perforation)))
                whereItGoes
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .widgetURL(state.tapURL)
            // No buttons here: VoiceOver reads it all as one sentence.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
        }
    }

    /// «Hoy puedes gastar $290. En qué se va: Comida $2,450, Despensa $1,980 y Otras $2,390».
    private var spoken: String {
        let total = slices.reduce(Decimal(0)) { $0 + $1.amount }
        guard !slices.isEmpty, total > 0 else { return entry.spoken(state, money) }
        let parts = slices.map { "\(Self.name(of: $0)) \(money.said($0.amount))" }
        let said = entry.spoken(state, money)
        let list = parts.formatted(.list(type: .and).locale(Locale.current))
        return String(localized: "\(said). En qué se va: \(list)")
    }

    /// The name a slice prints: «Otras» for the rest, «Sin categoría» for one without.
    private static func name(of slice: WidgetSnapshot.Slice) -> String {
        if slice.isRest { return String(localized: "Otras") }
        // The snapshot keeps the stored name; the app's own are shown in the iPhone's language
        // (2026-11-18).
        return slice.name.map { BuiltInName.shown($0) } ?? String(localized: "Sin categoría")
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
            Caption(text: state.caption, color: ink.muted)
            Figure(text: money.whole(state.figure),
                   color: state.pace == nil ? ink.primary : state.isBad ? ink.danger : ink.brass, style: .figureCompact)
            if let note = entry.staleNote {
                StaleNote(text: note, ink: ink)
            } else {
                Verdict(state: state, money: money, ink: ink)
            }
            Spacer(minLength: Theme.Space.xxs)
            if let pace = state.pace {
                if let days = entry.month?.days {
                    DayTicket(days: days, pace: pace, ink: ink)
                } else {
                    MonthStrip(pace: pace, ink: ink)
                }
                keyText(.spent, money.whole(pace.spent), ink: ink)
                    .font(.widget(.key))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(Theme.MinimumScale.figure)
                    .padding(.top, Theme.Space.xxs)
            } else {
                SetBudgetBox(ink: ink)
            }
        }
    }

    private func color(_ index: Int, _ slice: WidgetSnapshot.Slice) -> Color {
        ink.category(index, isRest: slice.isRest, color: slice.color)
    }

    private var whereItGoes: some View {
        let total = slices.reduce(Decimal(0)) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: Theme.Space.widgetRowGap) {
            Caption(text: String(localized: "En qué se va"), color: ink.muted)
            if slices.isEmpty || total <= 0 {
                Spacer()
                Text("Sin categorías este mes")
                    .font(.widget(.note))
                    .foregroundStyle(ink.muted)
                Spacer()
            } else {
                GeometryReader { proxy in
                    let gap = Theme.Size.widgetStripGap
                    let room = proxy.size.width - gap * CGFloat(slices.count - 1)
                    HStack(spacing: gap) {
                        ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                            let share = CGFloat(NSDecimalNumber(decimal: slice.amount / total).doubleValue)
                            RoundedRectangle(cornerRadius: Theme.Radius.widgetTile)
                                .fill(color(index, slice))
                                .frame(width: max(gap, room * share))
                        }
                    }
                }
                .frame(height: Theme.Size.widgetStripThin)
                .clipShape(Capsule())
                .widgetAccentable()
                .padding(.bottom, Theme.Space.xxxs)
                ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                    row(slice, color: color(index, slice), share: NSDecimalNumber(decimal: slice.amount / total).doubleValue)
                }
                Spacer(minLength: Theme.Space.none)
            }
        }
    }

    private func row(_ slice: WidgetSnapshot.Slice, color: Color, share: Double) -> some View {
        HStack(spacing: Theme.Space.widgetRowGap) {
            RoundedRectangle(cornerRadius: Theme.Radius.widgetTile).fill(color)
                .frame(width: Theme.Size.widgetKeySquare, height: Theme.Size.widgetKeySquare)
            Text(Self.name(of: slice))
                .foregroundStyle(ink.primary)
                .textCase(.uppercase)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.Space.xxxs)
            Text(money.whole(slice.amount)).foregroundStyle(ink.primary)
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .foregroundStyle(ink.muted)
                .frame(minWidth: Theme.Size.widgetPercentColumn, alignment: .trailing)
        }
        .font(.widget(.key))
        .lineLimit(1)
        .minimumScaleFactor(Theme.MinimumScale.widgetRow)
    }
}
