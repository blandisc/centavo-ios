import CentavoCore
import SwiftUI
import WidgetKit

/// Where the month stands, as every widget tells it (the same four cases as the app).
enum DayState {
    /// The app never wrote a snapshot (never opened, or no App Group nor shared Keychain): there
    /// is nothing to show, and «Sin presupuesto» would be a lie.
    case neverOpened
    /// No budget: the month's total and today's, and an invitation to set one.
    case noBudget(spent: Decimal, today: Decimal)
    /// The month went past its budget: «Te pasaste $430».
    case overBudget(BudgetPace)
    /// Today went past its share, the month did not: «Hoy te pasaste $300».
    case overToday(BudgetPace)
    /// The month's fixed expenses take the whole budget: «Tus fijos pasan por $3,000» (second
    /// audit, 2026-11-02). Nothing was overspent, so it isn't said in red.
    case fixedOverBudget(BudgetPace)
    case normal(BudgetPace)

    init(_ entry: DayEntry) {
        let month = entry.month
        if entry.snapshot == nil {
            self = .neverOpened
        } else if let pace = entry.pace {
            // The same rule as the screen and Siri (`BudgetPace.isOverspent`).
            self = pace.isOverspent ? .overBudget(pace) : pace.isFixedOverBudget ? .fixedOverBudget(pace)
                : pace.isOverToday ? .overToday(pace) : .normal(pace)
        } else {
            self = .noBudget(spent: month?.spent ?? 0, today: month?.spentToday ?? 0)
        }
    }

    var pace: BudgetPace? {
        switch self {
        case .neverOpened, .noBudget: nil
        case .overBudget(let pace), .overToday(let pace), .fixedOverBudget(let pace), .normal(let pace): pace
        }
    }

    /// Where a tap on the whole widget goes: the budget sheet without a budget, else the app.
    var tapURL: URL? {
        if case .noBudget = self { return .setBudget }
        return nil
    }

    var isNeverOpened: Bool {
        if case .neverOpened = self { return true }
        return false
    }

    /// The widget in one sentence, for VoiceOver: the lock screen and the home screen alike.
    func spoken(_ money: Money) -> String {
        let amount = money.whole(figure)
        switch self {
        case .neverOpened:
            return String(localized: "Abre Al día una vez para ver cuánto puedes gastar hoy")
        case .noBudget(let spent, let today):
            let month = money.whole(spent)
            let day = money.whole(today)
            return String(localized: "Llevas \(month) este mes, hoy \(day)")
        case .overBudget:
            return String(localized: "Te pasaste del presupuesto por \(amount)")
        case .overToday:
            return String(localized: "Hoy te pasaste por \(amount)")
        case .fixedOverBudget:
            if figure > 0 { return String(localized: "Tus fijos pasan el presupuesto por \(amount)") }
            return String(localized: "Tus fijos se llevan todo el presupuesto")
        case .normal:
            return String(localized: "Hoy puedes gastar \(amount)")
        }
    }

    /// The caption over the big figure.
    var caption: String {
        switch self {
        case .neverOpened:
            return String(localized: "Al día")
        case .noBudget:
            let month = Date.now.formatted(.dateTime.month(.wide).locale(Locale.current))
            return String(localized: "Llevas en \(month)")
        case .overBudget:
            return String(localized: "Te pasaste")
        case .overToday:
            return String(localized: "Hoy te pasaste")
        case .fixedOverBudget:
            if figure > 0 { return String(localized: "Tus fijos pasan por") }
            return String(localized: "Hoy puedes gastar")
        case .normal:
            return String(localized: "Hoy puedes gastar")
        }
    }

    /// The big figure's amount, always positive: the caption says which way it goes.
    var figure: Decimal {
        switch self {
        case .neverOpened: 0
        case .noBudget(let spent, _): spent
        // Rounded up: «Te pasaste $0» over a few centavos said nothing (second audit).
        case .overBudget(let pace): pace.overspentShown
        case .fixedOverBudget(let pace): pace.fixedOverBudgetShown ?? 0
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
    /// One line that still ends «del ritmo»: «Vas $665 abajo del ritmo», under the medium's boleto.
    var endsWithRhythm = false

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
        switch state {
        case .neverOpened:
            return nil
        case .noBudget(_, let today):
            return Text("hoy \(money.whole(today))").foregroundStyle(ink.muted)
        case .overBudget:
            return Text("del presupuesto").foregroundStyle(ink.muted)
        case .fixedOverBudget(let pace):
            if (pace.fixedOverBudgetShown ?? 0) > 0 { return Text("el presupuesto").foregroundStyle(ink.muted) }
            return Text("tus fijos se llevan todo").foregroundStyle(ink.muted)
        case .overToday(let pace), .normal(let pace):
            guard let rhythm = pace.rhythm else {
                if twoLines { return nil }
                let expected = money.whole(pace.expectedToDate)
                let line: KeyLine = pace.isAheadOfPace ? .shouldBe : .couldBe
                return keyText(line, expected, ink: ink)
            }
            if rhythm.magnitude < 1 { return Text("Vas al ritmo").foregroundStyle(ink.muted) }
            return rhythmText(rhythm)
        }
    }

    /// «Vas $200 abajo del ritmo», one sentence per key, with «$200 abajo» in green (or
    /// «arriba», in red) wherever the language puts it.
    private func rhythmText(_ rhythm: Decimal) -> Text {
        let amount = money.whole(rhythm.magnitude)
        if rhythm > 0 {
            let gap = String(localized: "\(amount) abajo")
            return tinted(underSentence(amount), ink.muted, [Tint(text: gap, color: ink.good)])
        }
        let gap = String(localized: "\(amount) arriba")
        return tinted(overSentence(amount), ink.muted, [Tint(text: gap, color: ink.danger)])
    }

    private func underSentence(_ amount: String) -> String {
        if endsWithRhythm { return String(localized: "Vas \(amount) abajo del ritmo") }
        if twoLines { return String(localized: "Vas \(amount) abajo\ndel ritmo") }
        return String(localized: "Vas \(amount) abajo")
    }

    private func overSentence(_ amount: String) -> String {
        if endsWithRhythm { return String(localized: "Vas \(amount) arriba del ritmo") }
        if twoLines { return String(localized: "Vas \(amount) arriba\ndel ritmo") }
        return String(localized: "Vas \(amount) arriba")
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
            let over = pace.isOverspent
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

/// The boleto, as on the main screen (2026-10-30): one cell per day of the month, as tall as
/// what a day may spend. Brass rises with what went that day, what was left over keeps the
/// green hatch, a day past it is red; today is outlined and the days to come are dashed.
struct DayTicket: View {
    /// What went each day outside the fixed expenses, from the 1st (`WidgetSnapshot.days`).
    let days: [Decimal]
    let pace: BudgetPace
    let ink: Ink
    var height = Theme.Size.widgetTicket

    /// The budget, less the month's fixed expenses, over its days: the same in either rule.
    private var limit: Decimal {
        max((pace.budget - pace.fixedMonth) / Decimal(max(pace.daysInMonth, 1)), 0)
    }

    var body: some View {
        HStack(spacing: Theme.Size.widgetStripGap) {
            ForEach(1...max(pace.daysInMonth, 1), id: \.self) { day in
                cell(day)
            }
        }
        .frame(height: height)
    }

    @ViewBuilder private func cell(_ day: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.widgetTile)
        let spent = day <= days.count ? days[day - 1] : 0
        if day > pace.day {
            shape.strokeBorder(ink.hairline, style: StrokeStyle(lineWidth: Theme.Stroke.hairline,
                                                                dash: Theme.Dash.widgetReserved))
        } else if limit > 0, spent > limit {
            shape.fill(ink.danger).widgetAccentable()
                // The red cap over the day, as on the main screen's boleto.
                .overlay(alignment: .top) {
                    Capsule().fill(ink.danger)
                        .frame(height: Theme.Size.widgetCap)
                        .offset(y: -(Theme.Size.widgetCap + Theme.Size.widgetStripGap))
                        .widgetAccentable()
                }
        } else {
            // How much of the day's limit went, held to the cell.
            let share = limit > 0 ? min(max(CGFloat(NSDecimalNumber(decimal: spent / limit).doubleValue), .zero), 1) : .zero
            ZStack(alignment: .bottom) {
                shape.fill(ink.track)
                if limit > 0 {
                    WidgetHatch()
                        .stroke(ink.good, lineWidth: Theme.Stroke.mark)
                        .opacity(Theme.Opacity.paceBehind)
                        .clipShape(shape)
                }
                shape.fill(ink.brass)
                    .frame(height: height * share)
                    .widgetAccentable()
            }
            .overlay {
                if day == pace.day { shape.strokeBorder(ink.primary, lineWidth: Theme.Stroke.hairline) }
            }
        }
    }
}

/// Thin diagonal lines, like the shading on a printed form (the app's `Hatch`).
struct WidgetHatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += Theme.Size.hatchSpacing
        }
        return path
    }
}

/// «LLEVAS $8,140»: the whole sentence in grey and its figure in ink (one key per sentence).
func keyText(_ line: KeyLine, _ value: String, ink: Ink) -> Text {
    let sentence: String
    switch line {
    case .spent: sentence = String(localized: "Llevas \(value)")
    case .fixed: sentence = String(localized: "Fijos \(value)")
    case .budget: sentence = String(localized: "Presupuesto \(value)")
    case .shouldBe: sentence = String(localized: "Deberías llevar \(value)")
    case .couldBe: sentence = String(localized: "Podrías llevar \(value)")
    }
    return tinted(sentence, ink.muted, [Tint(text: value, color: ink.primary)])
}

/// Which `keyText` line: each one is a whole sentence in the catalog («Llevas $8,140»).
enum KeyLine {
    case spent, fixed, budget, shouldBe, couldBe
}

/// One part of a sentence drawn in its own color (`tinted`).
struct Tint {
    let text: String
    let color: Color
    /// Look for it from the end: for a second figure that may print the same as the first.
    var fromEnd = false
}

/// A whole sentence from the catalog in `base`, with each of `tints` (which come from inside
/// it) in its color, wherever the language put them. A tint that isn't found stays in `base`.
func tinted(_ sentence: String, _ base: Color, _ tints: [Tint]) -> Text {
    var attributed = AttributedString(sentence)
    attributed.foregroundColor = base
    for tint in tints {
        let options: String.CompareOptions = tint.fromEnd ? [.backwards] : []
        if let range = attributed.range(of: tint.text, options: options) {
            attributed[range].foregroundColor = tint.color
        }
    }
    return Text(attributed)
}

/// The brass «+» that opens «Anotar gasto» in the app.
///
/// The medium one is a `Link`. A small widget has no links (only the tap on the whole widget),
/// so its smaller «+» is a button that runs `OpenAddExpenseIntent`, which opens the app on the sheet.
struct AddButton: View {
    let ink: Ink
    var compact = false

    var body: some View {
        if compact {
            Button(intent: OpenAddExpenseIntent()) { circle }
                .buttonStyle(.plain)
                .accessibilityLabel("Anotar gasto")
        } else {
            Link(destination: .addExpense) { circle }
                .accessibilityLabel("Anotar gasto")
        }
    }

    private var circle: some View {
        let side = compact ? Theme.Size.widgetAddButtonSmall : Theme.Size.widgetAddButton
        return Image(systemName: "plus")
            .font(compact ? Theme.Symbol.widgetAddSmall : Theme.Symbol.widgetAdd)
            .foregroundStyle(ink.onAdd)
            .frame(width: side, height: side)
            .background(ink.addBackground, in: Circle())
            .widgetAccentable()
    }
}

/// «Actualizado hace 2 días»: the app has not written the widgets in a day or more.
struct StaleNote: View {
    let text: String
    let ink: Ink

    var body: some View {
        Text(text)
            .font(.widget(.verdict))
            .foregroundStyle(ink.muted)
            .lineLimit(1)
            .minimumScaleFactor(Theme.MinimumScale.figure)
    }
}

extension DayEntry {
    /// «Actualizado hace X», only once what the app left is a day old or more.
    var staleNote: String? {
        guard let days = snapshot?.daysOld(at: date) else { return nil }
        if days == 1 { return String(localized: "Actualizado hace 1 día") }
        return String(localized: "Actualizado hace \(days) días")
    }

    /// The widget in one sentence for VoiceOver, with how old it is when it is old.
    func spoken(_ state: DayState, _ money: Money) -> String {
        [state.spoken(money), staleNote].compactMap { $0 }.joined(separator: ". ")
    }
}

/// «ABRE AL DÍA UNA VEZ»: the widget before the app ever wrote to it. A tap opens the app.
struct NeverOpenedBox: View {
    let ink: Ink
    var subtitle = false

    var body: some View {
        let detail: String? = subtitle ? String(localized: "Para ver cuánto puedes gastar hoy") : nil
        return TicketBox(title: String(localized: "Abre Al día una vez"), detail: detail, ink: ink)
    }
}

/// «FIJAR PRESUPUESTO», dashed like the app's blank ticket. Opens the budget sheet.
struct SetBudgetBox: View {
    let ink: Ink
    var subtitle = false

    var body: some View {
        let detail: String? = subtitle ? String(localized: "Para ver cuánto te queda") : nil
        return TicketBox(title: String(localized: "Fijar presupuesto"), detail: detail, ink: ink)
    }
}

/// A brass caption in a dashed box, like the app's blank ticket, with an optional line under it.
struct TicketBox: View {
    let title: String
    let detail: String?
    let ink: Ink

    var body: some View {
        VStack(spacing: Theme.Space.widgetCaptionGap) {
            Caption(text: title, color: ink.brass, style: detail != nil ? .caption : .captionSmall)
            if let detail {
                Caption(text: detail, color: ink.muted, style: .captionTiny)
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
    static let addExpense = URL(string: "centavo://anotar")!
}
