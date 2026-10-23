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

/// Colors that hold in every rendering mode: the app's own in full color, and the system's
/// one tone with opacities when iOS tints the widget, makes it clear or puts it on the
/// lock screen (the shape still says what each piece is).
struct Ink {
    let mode: WidgetRenderingMode
    var full: Bool { mode == .fullColor }

    var primary: Color { full ? Theme.ink : .primary }
    var muted: Color { full ? Theme.muted : .primary.opacity(0.7) }
    var brass: Color { full ? Theme.brass : .primary }
    var good: Color { full ? Theme.good : .primary }
    var danger: Color { full ? Theme.danger : .primary }
    var track: Color { full ? Theme.raised : .primary.opacity(0.22) }
    var reserved: Color { full ? Theme.brassLow : .primary.opacity(0.55) }
    var hairline: Color { full ? Theme.hairline : .primary.opacity(0.3) }
}

/// «HOY PUEDES GASTAR»: small tracked capitals, like the app's captions.
struct Caption: View {
    let text: String
    var color: Color
    var size: CGFloat = 10

    var body: some View {
        Text(text)
            .font(.ticket(size, weight: .semibold, relativeTo: .caption2))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// The big figure.
struct Figure: View {
    let text: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Text(text)
            .font(.ticket(size, weight: .medium, relativeTo: .largeTitle))
            .tracking(-1)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .widgetAccentable()
            .padding(.leading, -2)
    }
}

/// «Vas $376 abajo» under the figure: what the days before today left over or overspent.
struct Verdict: View {
    let state: DayState
    let money: Money
    let ink: Ink
    var size: CGFloat = 11
    /// The medium widget's top right corner says it in two lines: «Vas $376 abajo / del ritmo».
    var twoLines = false

    var body: some View {
        content
            .font(.ticket(size, relativeTo: .footnote))
            .lineLimit(twoLines ? 2 : 1)
            .minimumScaleFactor(0.6)
            .multilineTextAlignment(twoLines ? .trailing : .leading)
    }

    private var content: Text {
        let tail = twoLines ? "\ndel ritmo" : ""
        switch state {
        case .noBudget(_, let today):
            return Text("hoy \(money.whole(today))").foregroundStyle(ink.muted)
        case .overBudget:
            return Text("del presupuesto").foregroundStyle(ink.muted)
        case .overToday(let pace), .normal(let pace):
            let carried = pace.carriedOver
            if carried.magnitude >= 1 {
                return Text("Vas ").foregroundStyle(ink.muted)
                    + Text("\(money.whole(carried.magnitude)) \(carried > 0 ? "abajo" : "arriba")")
                        .foregroundStyle(carried > 0 ? ink.good : ink.danger)
                    + Text(tail).foregroundStyle(ink.muted)
            }
            if pace.day == 1 {
                return Text("Día 1 de \(pace.daysInMonth)" + (twoLines ? "\nmes nuevo" : "")).foregroundStyle(ink.muted)
            }
            return Text("Vas al ritmo").foregroundStyle(ink.muted)
        }
    }
}

/// The month's bar in small: brass is what went, the dashed stretch the fixed expenses still
/// to come, then one tile per day left (or a plain track), and the white rule is «Podrías
/// llevar». Past the budget, all of it in red.
struct MonthStrip: View {
    let pace: BudgetPace
    let ink: Ink
    var height: CGFloat = 8
    var tiles = false

    private let gap: CGFloat = 2

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
            let days = over ? 0 : min(max(pace.daysLeft, 1), 31)
            let slotW = days > 0 ? (freeW - gap * CGFloat(days - 1)) / CGFloat(days) : 0
            let markX = width * fraction(pace.expectedToDate)
            ZStack(alignment: .leading) {
                HStack(spacing: gap) {
                    if spentW > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(over ? ink.danger : ink.brass)
                            .frame(width: spentW)
                            .widgetAccentable()
                    }
                    if reservedW > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(ink.reserved, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                            .frame(width: reservedW)
                    }
                    if tiles, slotW >= 2 {
                        ForEach(0..<days, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(index == 0 ? ink.brass.opacity(0.45) : ink.track)
                                .frame(width: slotW)
                        }
                    } else if !over, freeW > 0 {
                        RoundedRectangle(cornerRadius: 2).fill(ink.track)
                    }
                }
                .clipShape(Capsule())
                if !over {
                    Capsule()
                        .fill(ink.primary)
                        .frame(width: 2, height: height + 4)
                        .offset(x: min(max(markX - 1, 0), width - 2))
                }
            }
            .frame(height: height)
        }
        .frame(height: height + 4)
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
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(ink.full ? Theme.onBrass : Color.primary)
                .frame(width: 36, height: 36)
                .background(ink.full ? Theme.brass : Color.primary.opacity(0.2), in: Circle())
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
        VStack(spacing: 3) {
            Caption(text: "Fijar presupuesto", color: ink.brass, size: subtitle ? 10 : 9)
            if subtitle {
                Caption(text: "Para ver cuánto te queda", color: ink.muted, size: 8)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(ink.full ? Theme.outline : .primary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

extension URL {
    static let setBudget = URL(string: "centavo://presupuesto")!
}
