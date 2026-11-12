import CentavoCore
import SwiftUI

/// What goes with the boleto on the carousel's first page, in two halves (`Part`): right under
/// it the month's line and its sum (`MonthBar`), or the invitation to set a budget; and below,
/// «En qué se va» and the month's note.
struct BudgetPage: View {
    let spent: MoneyTotal
    let pace: BudgetPace?
    /// A month that is over has no "today": the whole budget was due, so the marker goes.
    let isCurrentMonth: Bool
    /// What was left out of the budget («No cuenta»): said in the sum, never silently gone.
    var outside: Decimal = 0
    /// Where the month's money went, biggest first. Empty when nothing is filed.
    var shares: [CategoryShare] = []
    /// What came back this month, which `shares` leave out (`CategoryShare.returned`).
    var returned: Decimal = 0
    /// One thing worth knowing about the month (see `MonthNote`), this month only.
    var note: String?
    /// The category whose expenses the list shows, if one was tapped in the mosaic.
    var selectedCategory: CategoryShare?
    var onSelectCategory: (CategoryShare?) -> Void = { _ in }
    /// What of the screen's entrance has played (`Entrance`), handed to the month's line.
    var entrance = Entrance()
    let onSetBudget: () -> Void
    /// Which half to draw: the screen puts the boleto between the two.
    let part: Part

    enum Part {
        /// The month's line and its sum, or the invitation to set a budget.
        case top
        /// «En qué se va» and the month's note.
        case bottom
    }

    /// Whether `.bottom` has anything to draw.
    static func hasBottom(shares: [CategoryShare], note: String?, style: String) -> Bool {
        (!shares.isEmpty && style != WhereItGoesStyle.hidden.rawValue) || note != nil
    }

    @ScaledMetric(relativeTo: .body) private var scaledBarHeight: CGFloat = Theme.Size.budgetBar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(WhereItGoesStyle.key) private var storedStyle = WhereItGoesStyle.bar.rawValue
    /// Today's budget: a month that is over and had none doesn't invite to set one that exists.
    @AppStorage(BudgetStore.key) private var storedBudget = ""

    /// Grows a little with the text, but a bar the size of the screen helps nobody.
    private var barHeight: CGFloat { min(scaledBarHeight, Theme.Size.budgetBarMaxHeight) }

    private func money(_ amount: Decimal) -> String {
        formatMoney(amount, isoCode: spent.isoCode, label: spent.label)
    }

    /// "$3,871": a rough mark, so no cents, but still money like every other figure.
    private func wholeMoney(_ amount: Decimal) -> String {
        if let isoCode = spent.isoCode {
            return amount.formatted(currencyStyle(isoCode).precision(.fractionLength(0)))
        }
        return spent.label + amount.formatted(.number.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            switch part {
            case .top:
                if let pace {
                    ticket(pace)
                } else if !isCurrentMonth, BudgetStore.amount(from: storedBudget) != nil {
                    noBudgetThen
                } else {
                    invitation
                }
            case .bottom:
                if !shares.isEmpty, storedStyle != WhereItGoesStyle.hidden.rawValue {
                    whereItGoes
                        .transition(.opacity)
                }
                if let note {
                    noteLine(note)
                }
            }
        }
        // Choosing a view of «En qué se va» in «Más» fades it, while the carousel eases its
        // height and the list below follows.
        .animation(reduceMotion ? nil : Theme.Motion.restyle, value: storedStyle)
    }

    // MARK: Note

    /// «Nota · Comida va 40 % arriba de lo normal…», the last line of the ticket.
    private func noteLine(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text("Nota").ticketKey()
            Text(text)
                .font(.ticket(.detail))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nota-del-mes")
    }

    // MARK: Where it goes

    private var whereItGoes: some View {
        WhereItGoes(shares: shares, style: WhereItGoesStyle(rawValue: storedStyle) ?? .bar, money: money,
                    returned: returned, selected: selectedCategory, onSelect: onSelectCategory)
    }

    // MARK: Without a budget

    /// A month that closed with no budget (it was set later, or had been taken off): nothing to
    /// judge it with, so only its total, and why (`BudgetHistory`, 2026-11-11).
    private var noBudgetThen: some View {
        Text("Este mes no tenías presupuesto.")
            .font(.ticket(.detail))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("sin-presupuesto-ese-mes")
    }

    private var invitation: some View {
        Button(action: onSetBudget) {
            VStack(spacing: Theme.Space.xs) {
                Text("Fijar presupuesto")
                    .font(.ticket(.footnoteStrong))
                    .tracking(Theme.Tracking.action)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.brass)
                Text("Para ver cuánto te queda")
                    .font(.ticket(.caption))
                    .tracking(Theme.Tracking.detail)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: barHeight)
            .ticketOutline(.emphasis)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fijar-presupuesto")
    }

    // MARK: With a budget

    private func ticket(_ pace: BudgetPace) -> some View {
        let isOver = pace.isOverspent
        // A month where more came back than went out is 0 %, not "-5 %".
        let share = max(0, NSDecimalNumber(decimal: pace.spent / pace.budget).doubleValue)
        return MonthBar(pace: pace, isCurrentMonth: isCurrentMonth, money: money, wholeMoney: wholeMoney,
                        outside: outside, entrance: entrance)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("presupuesto-ticket")
            .accessibilityLabel(spokenTicket(pace, share: share, isOver: isOver,
                                             remainingText: money(pace.remaining.magnitude)))
    }

    /// What VoiceOver reads for the ticket, sentence by sentence (one expression was too much
    /// for the compiler).
    private func spokenTicket(_ pace: BudgetPace, share: Double, isOver: Bool, remainingText: String) -> String {
        var parts = ["Presupuesto de \(money(pace.budget)). Has gastado \(money(pace.spent)), "
                     + "el \(share.formatted(.percent.precision(.fractionLength(0))))."]
        if isOver {
            parts.append("Te pasaste por \(wholeMoney(pace.overspentShown)).")
        } else if pace.remaining >= 0 {
            // Fixed expenses past the budget, charged: below zero without overspending; the
            // fixed sentence below says it.
            parts.append((isCurrentMonth ? "Te quedan " : "Te quedaron ") + "\(remainingText).")
        }
        if isCurrentMonth {
            parts.append("A hoy \(pace.isAheadOfPace ? "deberías" : "podrías") llevar \(wholeMoney(pace.expectedShown)).")
            if pace.reserved > 0 { parts.append("Se apartan \(money(pace.reserved)) de gastos fijos por venir.") }
            if let start = pace.countsFrom {
                let day = start.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es_MX")))
                parts.append("Tu presupuesto cuenta desde el \(day).")
            }
            if pace.rhythm != nil, case let rhythm = pace.gapShown, rhythm != 0 {
                parts.append("Vas \(wholeMoney(rhythm.magnitude)) " + (rhythm > 0 ? "abajo" : "arriba") + " del ritmo.")
            }
            if !isOver, let excess = pace.fixedOverBudgetShown {
                parts.append(excess > 0 ? "Tus fijos pasan el presupuesto por \(wholeMoney(excess))."
                             : "Tus fijos se llevan todo el presupuesto.")
            } else if !isOver {
                parts.append(pace.isOverToday ? "Hoy te pasaste por \(wholeMoney(pace.dailyAllowance.magnitude))."
                             : "Hoy puedes gastar \(wholeMoney(pace.dailyAllowance)).")
            }
        }
        if outside != 0 { parts.append("Fuera del presupuesto, \(money(outside)).") }
        return parts.joined(separator: " ")
    }
}
