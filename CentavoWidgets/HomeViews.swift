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
        VStack(alignment: .leading, spacing: 2) {
            Caption(text: state.caption, color: ink.muted)
            Figure(text: money.whole(state.figure), color: figureColor)
            Verdict(state: state, money: money, ink: ink)
            Spacer(minLength: 6)
            if let pace = state.pace {
                MonthStrip(pace: pace, ink: ink)
                // Same type for both; «Llevas» gets the width first, so when the row is
                // tight it keeps its size and «de $X» is the one that shrinks.
                HStack(spacing: 4) {
                    keyText("Llevas", money.whole(pace.spent), ink: ink)
                        .layoutPriority(1)
                    Spacer(minLength: 2)
                    keyText("de", money.short(pace.budget), ink: ink)
                }
                .font(.ticket(9, relativeTo: .caption2))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 4)
            } else {
                SetBudgetBox(ink: ink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Medium

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Caption(text: state.caption, color: ink.muted)
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Figure(text: money.whole(state.figure), color: figureColor, size: 38)
                        if case .overBudget = state {
                            Verdict(state: state, money: money, ink: ink).fixedSize()
                        }
                    }
                }
                Spacer(minLength: 4)
                if state.pace != nil, !isOverBudget {
                    Verdict(state: state, money: money, ink: ink, twoLines: true)
                        .padding(.top, 2)
                }
                AddButton(ink: ink)
            }
            Spacer(minLength: 6)
            if let pace = state.pace {
                if !pace.isOverBudget {
                    annotation(pace)
                }
                MonthStrip(pace: pace, ink: ink, height: 12, tiles: true)
                keys(pace)
                    .padding(.top, 6)
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

    /// «PODRÍAS LLEVAR $8,516», over the rule it names.
    private func annotation(_ pace: BudgetPace) -> some View {
        GeometryReader { proxy in
            let share = min(max(NSDecimalNumber(decimal: pace.expectedToDate / pace.budget).doubleValue, 0), 1)
            let text = keyText("Podrías llevar", money.whole(pace.expectedToDate), ink: ink)
                .font(.ticket(9, relativeTo: .caption2))
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
            text
                .frame(width: proxy.size.width, alignment: share > 0.5 ? .trailing : .leading)
                .padding(share > 0.5 ? .trailing : .leading,
                         share > 0.5 ? max(0, proxy.size.width * (1 - share) - 2) : max(0, proxy.size.width * share - 2))
        }
        .frame(height: 12)
        .padding(.bottom, 8)
    }

    private func keys(_ pace: BudgetPace) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(pace.isOverBudget ? ink.danger : ink.brass)
                .frame(width: 7, height: 7)
                .widgetAccentable()
            keyText("Llevas", money.whole(pace.spent), ink: ink)
            Spacer(minLength: 4)
            if pace.fixedMonth > 0, !pace.isOverBudget {
                keyText("Fijos", money.whole(pace.fixedMonth), ink: ink)
                Spacer(minLength: 4)
            }
            keyText("Presupuesto", money.whole(pace.budget), ink: ink)
        }
        .font(.ticket(9, relativeTo: .caption2))
        .textCase(.uppercase)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
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
        HStack(alignment: .top, spacing: 14) {
            today
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle()
                .fill(.clear)
                .frame(width: 1)
                .overlay(Rectangle().stroke(ink.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            whereItGoes
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .widgetURL(state.pace == nil ? .setBudget : nil)
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 2) {
            Caption(text: state.caption, color: ink.muted)
            Figure(text: money.whole(state.figure),
                   color: state.pace == nil ? ink.primary : state.isBad ? ink.danger : ink.brass, size: 32)
            Verdict(state: state, money: money, ink: ink)
            Spacer(minLength: 4)
            if let pace = state.pace {
                MonthStrip(pace: pace, ink: ink)
                keyText("Llevas", money.whole(pace.spent), ink: ink)
                    .font(.ticket(9, relativeTo: .caption2))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 4)
            } else {
                SetBudgetBox(ink: ink)
            }
        }
    }

    private func color(_ index: Int, _ slice: WidgetSnapshot.Slice) -> Color {
        guard ink.full else { return .primary.opacity([1, 0.75, 0.5, 0.3][min(index, 3)]) }
        return slice.isRest ? Theme.categoryRest : Theme.categories[min(index, Theme.categories.count - 1)]
    }

    private var whereItGoes: some View {
        let total = slices.reduce(Decimal(0)) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 5) {
            Caption(text: "En qué se va", color: ink.muted)
            if slices.isEmpty || total <= 0 {
                Spacer()
                Text("Sin categorías este mes")
                    .font(.ticket(10, relativeTo: .caption))
                    .foregroundStyle(ink.muted)
                Spacer()
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(color(index, slice))
                                .frame(width: max(2, (proxy.size.width - 2 * CGFloat(slices.count - 1))
                                    * CGFloat(NSDecimalNumber(decimal: slice.amount / total).doubleValue)))
                        }
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
                .widgetAccentable()
                .padding(.bottom, 2)
                ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                    row(slice, color: color(index, slice), share: NSDecimalNumber(decimal: slice.amount / total).doubleValue)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ slice: WidgetSnapshot.Slice, color: Color, share: Double) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 7, height: 7)
            Text(slice.isRest ? "Otras" : slice.name ?? "Sin categoría")
                .foregroundStyle(ink.primary)
                .textCase(.uppercase)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 2)
            Text(money.whole(slice.amount)).foregroundStyle(ink.primary)
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .foregroundStyle(ink.muted)
                .frame(minWidth: 26, alignment: .trailing)
        }
        .font(.ticket(9, relativeTo: .caption2))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
