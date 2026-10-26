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
            if family == .systemMedium { medium } else { small }
        }
        .widgetURL(state.pace == nil ? .setBudget : nil)
    }

    private var figureColor: Color {
        switch state {
        case .noBudget: ink.primary
        case .overBudget, .overToday: ink.danger
        case .normal: ink.brass
        }
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
            Caption(text: state.caption, color: ink.muted)
            Figure(text: money.whole(state.figure), color: figureColor)
            Verdict(state: state, money: money, ink: ink)
            Spacer(minLength: Theme.Space.xs)
            if let pace = state.pace {
                MonthStrip(pace: pace, ink: ink)
                // Only «Llevas $X» under the bar, in full (the budget is in the medium one).
                keyText("Llevas", money.whole(pace.spent), ink: ink)
                    .font(.widget(.spent))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(Theme.MinimumScale.widgetLabel)
                    .padding(.top, Theme.Space.xs)
            } else {
                SetBudgetBox(ink: ink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Medium

    private var medium: some View {
        VStack(alignment: .leading, spacing: Theme.Space.none) {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    Caption(text: state.caption, color: ink.muted)
                    HStack(alignment: .lastTextBaseline, spacing: Theme.Space.s) {
                        Figure(text: money.whole(state.figure), color: figureColor, style: .figureLarge)
                        if case .overBudget = state {
                            Verdict(state: state, money: money, ink: ink).fixedSize()
                        }
                    }
                }
                Spacer(minLength: Theme.Space.xxs)
                if state.pace != nil, !isOverBudget {
                    Verdict(state: state, money: money, ink: ink, twoLines: true)
                        .padding(.top, Theme.Space.xxxs)
                }
                AddButton(ink: ink)
            }
            Spacer(minLength: Theme.Space.xs)
            if let pace = state.pace {
                if !pace.isOverBudget {
                    annotation(pace)
                }
                MonthStrip(pace: pace, ink: ink, height: Theme.Size.widgetStripTall, tiles: true)
                keys(pace)
                    .padding(.top, Theme.Space.xs)
            } else {
                Link(destination: .setBudget) { SetBudgetBox(ink: ink, subtitle: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var isOverBudget: Bool {
        if case .overBudget = state { return true }
        return false
    }

    /// «PODRÍAS LLEVAR $8,516», over the rule it names; «Deberías» once past it.
    private func annotation(_ pace: BudgetPace) -> some View {
        GeometryReader { proxy in
            let share = min(max(NSDecimalNumber(decimal: pace.expectedToDate / pace.budget).doubleValue, 0), 1)
            let text = keyText(pace.isAheadOfPace ? "Deberías llevar" : "Podrías llevar", money.whole(pace.expectedToDate), ink: ink)
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

    private func keys(_ pace: BudgetPace) -> some View {
        HStack(spacing: Theme.Space.xs) {
            RoundedRectangle(cornerRadius: Theme.Radius.widgetTile)
                .fill(pace.isOverBudget ? ink.danger : ink.brass)
                .frame(width: Theme.Size.widgetKeySquare, height: Theme.Size.widgetKeySquare)
                .widgetAccentable()
            keyText("Llevas", money.whole(pace.spent), ink: ink)
            Spacer(minLength: Theme.Space.xxs)
            if pace.fixedMonth > 0, !pace.isOverBudget {
                keyText("Fijos", money.whole(pace.fixedMonth), ink: ink)
                Spacer(minLength: Theme.Space.xxs)
            }
            keyText("Presupuesto", money.whole(pace.budget), ink: ink)
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
        .widgetURL(state.pace == nil ? .setBudget : nil)
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
            Caption(text: state.caption, color: ink.muted)
            Figure(text: money.whole(state.figure),
                   color: state.pace == nil ? ink.primary : state.isBad ? ink.danger : ink.brass, style: .figureCompact)
            Verdict(state: state, money: money, ink: ink)
            Spacer(minLength: Theme.Space.xxs)
            if let pace = state.pace {
                MonthStrip(pace: pace, ink: ink)
                keyText("Llevas", money.whole(pace.spent), ink: ink)
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
        ink.category(index, isRest: slice.isRest)
    }

    private var whereItGoes: some View {
        let total = slices.reduce(Decimal(0)) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: Theme.Space.widgetRowGap) {
            Caption(text: "En qué se va", color: ink.muted)
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
            Text(slice.isRest ? "Otras" : slice.name ?? "Sin categoría")
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
