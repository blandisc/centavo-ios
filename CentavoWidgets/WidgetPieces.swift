import CentavoCore
import SwiftUI
import WidgetKit

/// Where the month stands, as every widget tells it (the same four cases as the app).
enum DayState {
    /// No budget: the month's total and today's, and an invitation to set one.
    case noBudget(spent: Decimal, today: Decimal)
    /// The month went past its budget: «Te pasaste $430».
    case overBudget(BudgetPace)
    /// Today went past its share, the month did not: «Hoy te pasaste $300».
    case overToday(BudgetPace)
    case normal(BudgetPace)

    init(_ entry: DayEntry) {
        let month = entry.month
        if let pace = entry.pace {
            self = pace.isOverBudget ? .overBudget(pace) : pace.isOverToday ? .overToday(pace) : .normal(pace)
        } else {
            self = .noBudget(spent: month?.spent ?? 0, today: month?.spentToday ?? 0)
        }
    }

    var pace: BudgetPace? {
        switch self {
        case .noBudget: nil
        case .overBudget(let pace), .overToday(let pace), .normal(let pace): pace
        }
    }

    /// The caption over the big figure.
    var caption: String {
        switch self {
        case .noBudget: "Llevas en " + Date.now.formatted(.dateTime.month(.wide).locale(Locale(identifier: "es_MX")))
        case .overBudget: "Te pasaste"
        case .overToday: "Hoy te pasaste"
        case .normal: "Hoy puedes gastar"
        }
    }

    /// The big figure's amount, always positive: the caption says which way it goes.
    var figure: Decimal {
        switch self {
        case .noBudget(let spent, _): spent
        case .overBudget(let pace): pace.remaining.magnitude
        case .overToday(let pace), .normal(let pace): pace.dailyAllowance.magnitude
        }
    }

    var isBad: Bool {
        switch self {
        case .overBudget, .overToday: true
        default: false
        }
    }
}

/// Money as the app writes it, from the snapshot's currency.
struct Money {
    let isoCode: String?
    let label: String

    init(_ snapshot: WidgetSnapshot?) {
        isoCode = snapshot?.isoCode ?? "MXN"
        label = snapshot?.label ?? "$"
    }

    /// "$8,140": a glance, so no cents.
    func whole(_ amount: Decimal) -> String {
        if let isoCode { return amount.formatted(currencyStyle(isoCode).precision(.fractionLength(0))) }
        return label + amount.formatted(.number.precision(.fractionLength(0)))
    }

    /// "$12K" for a round budget of thousands; otherwise `whole`.
    func short(_ amount: Decimal) -> String {
        let thousands = amount / 1000
        guard amount >= 10_000, thousands == Decimal(Int(truncating: thousands as NSNumber)) else { return whole(amount) }
        let symbol = whole(0).replacingOccurrences(of: "0", with: "")
        return "\(symbol)\(Int(truncating: thousands as NSNumber))K"
    }
}

/// «HOY PUEDES GASTAR»: small tracked capitals, like the app's captions.
struct Caption: View {
    let text: String
    var color: Color
    var style = WidgetTextStyle.caption

    var body: some View {
        Text(text)
            .font(.widget(style))
            .tracking(Theme.Tracking.widgetCaption)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(Theme.MinimumScale.figure)
    }
}

/// The big figure.
struct Figure: View {
    let text: String
    let color: Color
    var style = WidgetTextStyle.figure

    var body: some View {
        Text(text)
            .font(.widget(style))
            .tracking(Theme.Tracking.widgetFigure)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(Theme.MinimumScale.widgetFigure)
            .widgetAccentable()
            .padding(.leading, Theme.Space.widgetOutset)
    }
}

/// The line under the figure. With «Repartir», «Vas $376 abajo»: how far from the rule. With
/// «Acumular» the figure already is that gap (alternative C, 2026-10-25), so the line names the
/// rule instead, «Podrías llevar $3,226», which the small bars draw without a label; the medium
/// one labels its rule over the bar and leaves the corner empty.
struct Verdict: View {
    let state: DayState
    let money: Money
    let ink: Ink
    /// The medium widget's top right corner says it in two lines: «Vas $376 abajo / del ritmo».
    var twoLines = false

    var body: some View {
        if let content {
            content
                .font(.widget(.verdict))
                .lineLimit(twoLines ? 2 : 1)
                .minimumScaleFactor(Theme.MinimumScale.figure)
                .multilineTextAlignment(twoLines ? .trailing : .leading)
        }
    }

    private var content: Text? {
        let tail = twoLines ? "\ndel ritmo" : ""
        switch state {
        case .noBudget(_, let today):
            return Text("hoy \(money.whole(today))").foregroundStyle(ink.muted)
        case .overBudget:
            return Text("del presupuesto").foregroundStyle(ink.muted)
        case .overToday(let pace), .normal(let pace):
            guard let rhythm = pace.rhythm else {
                if twoLines { return nil }
                return Text(pace.isAheadOfPace ? "Deberías llevar " : "Podrías llevar ").foregroundStyle(ink.muted)
                    + Text(money.whole(pace.expectedToDate)).foregroundStyle(ink.primary)
            }
            if rhythm.magnitude < 1 { return Text("Vas al ritmo").foregroundStyle(ink.muted) }
            return Text("Vas ").foregroundStyle(ink.muted)
                + Text("\(money.whole(rhythm.magnitude)) \(rhythm > 0 ? "abajo" : "arriba")")
                    .foregroundStyle(rhythm > 0 ? ink.good : ink.danger)
                + Text(tail).foregroundStyle(ink.muted)
        }
    }
}

/// The month's bar in small: brass is what went, the dashed stretch the fixed expenses still
/// to come, then one tile per day left (or a plain track), and the white rule is «Podrías
/// llevar». Past the budget, all of it in red.
struct MonthStrip: View {
    let pace: BudgetPace
    let ink: Ink
    var height = Theme.Size.widgetStrip
    var tiles = false

    private let gap = Theme.Size.widgetStripGap

    private func fraction(_ part: Decimal) -> CGFloat {
        CGFloat(min(max(NSDecimalNumber(decimal: part / pace.budget).doubleValue, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let over = pace.isOverBudget
            let spentW = width * (over ? 1 : fraction(pace.spent))
            let reservedW = over ? 0 : width * fraction(pace.reserved)
            let freeW = max(0, width - spentW - reservedW - (reservedW > 0 ? gap : 0) - (spentW > 0 ? gap : 0))
            let days = over ? 0 : min(max(pace.daysLeft, 1), Theme.Size.widgetMaxDays)
            let slotW = days > 0 ? (freeW - gap * CGFloat(days - 1)) / CGFloat(days) : 0
            let markX = width * fraction(pace.expectedToDate)
            let markOffset = min(max(markX - Theme.Size.widgetMarkHalf, 0), width - Theme.Size.todayMarkWidth)
            ZStack(alignment: .leading) {
                HStack(spacing: gap) {
                    if spentW > 0 {
                        RoundedRectangle(cornerRadius: Theme.Radius.bar)
                            .fill(over ? ink.danger : ink.brass)
                            .frame(width: spentW)
                            .widgetAccentable()
                    }
                    if reservedW > 0 {
                        RoundedRectangle(cornerRadius: Theme.Radius.bar)
                            .strokeBorder(ink.reserved, style: StrokeStyle(lineWidth: Theme.Stroke.hairline,
                                                                           dash: Theme.Dash.widgetReserved))
                            .frame(width: reservedW)
                    }
                    if tiles, slotW >= gap {
                        ForEach(0..<days, id: \.self) { index in
                            RoundedRectangle(cornerRadius: Theme.Radius.widgetTile)
                                .fill(index == 0 ? ink.brass.opacity(Theme.Opacity.widgetToday) : ink.track)
                                .frame(width: slotW)
                        }
                    } else if !over, freeW > 0 {
                        RoundedRectangle(cornerRadius: Theme.Radius.bar).fill(ink.track)
                    }
                }
                .clipShape(Capsule())
                if !over {
                    Capsule()
                        .fill(ink.primary)
                        .frame(width: Theme.Size.todayMarkWidth, height: height + Theme.Size.widgetMarkExtra)
                        .offset(x: markOffset)
                }
            }
            .frame(height: height)
        }
        .frame(height: height + Theme.Size.widgetMarkExtra)
    }
}

/// «LLEVAS $8,140»: a label in grey and its figure in ink.
func keyText(_ label: String, _ value: String, ink: Ink) -> Text {
    Text(label + " ").foregroundStyle(ink.muted) + Text(value).foregroundStyle(ink.primary)
}

/// The brass «+» that opens «Anotar gasto» in the app.
struct AddButton: View {
    let ink: Ink
    var body: some View {
        Link(destination: URL(string: "centavo://anotar")!) {
            Image(systemName: "plus")
                .font(Theme.Symbol.widgetAdd)
                .foregroundStyle(ink.onAdd)
                .frame(width: Theme.Size.widgetAddButton, height: Theme.Size.widgetAddButton)
                .background(ink.addBackground, in: Circle())
                .widgetAccentable()
        }
        .accessibilityLabel("Anotar gasto")
    }
}

/// «FIJAR PRESUPUESTO», dashed like the app's blank ticket. Opens the budget sheet.
struct SetBudgetBox: View {
    let ink: Ink
    var subtitle = false

    var body: some View {
        VStack(spacing: Theme.Space.widgetCaptionGap) {
            Caption(text: "Fijar presupuesto", color: ink.brass, style: subtitle ? .caption : .captionSmall)
            if subtitle {
                Caption(text: "Para ver cuánto te queda", color: ink.muted, style: .captionTiny)
            }
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.s)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.ticket)
                .strokeBorder(ink.outline, style: StrokeStyle(lineWidth: Theme.Stroke.hairline,
                                                             dash: Theme.Dash.widgetTicket))
        }
    }
}

extension URL {
    static let setBudget = URL(string: "centavo://presupuesto")!
}
