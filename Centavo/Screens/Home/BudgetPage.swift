import CentavoCore
import SwiftUI

/// First page of the carousel, what the main screen opens on: the budget as a blank ticket that fills up as the month is spent.
///
/// Brass is what you have spent, the white line is where an even spend would be today,
/// and what is still dashed is what remains.
struct BudgetPage: View {
    let spent: MoneyTotal
    let pace: BudgetPace?
    /// A month that is over has no "today": the whole budget was due, so the marker goes.
    let isCurrentMonth: Bool
    /// Where the month's money went, biggest first. Empty when nothing is filed.
    var shares: [CategoryShare] = []
    /// What came back this month, which `shares` leave out (`CategoryShare.returned`).
    var returned: Decimal = 0
    /// One thing worth knowing about the month (see `MonthNote`), this month only.
    var note: String?
    /// The category whose expenses the list shows, if one was tapped in the mosaic.
    var selectedCategory: CategoryShare?
    var onSelectCategory: (CategoryShare?) -> Void = { _ in }
    let onSetBudget: () -> Void

    @ScaledMetric(relativeTo: .body) private var scaledBarHeight: CGFloat = 84
    /// The big figure's point size at the current Dynamic Type setting, to estimate its width.
    @ScaledMetric(relativeTo: .title2) private var figureSize: CGFloat = 22
    @State private var barWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(WhereItGoesStyle.key) private var storedStyle = WhereItGoesStyle.bar.rawValue

    /// Grows a little with the text, but a bar the size of the screen helps nobody.
    private var barHeight: CGFloat { min(scaledBarHeight, 132) }

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
        // What was spent is already the big total right above; this page only says how it
        // measures against the budget.
        VStack(alignment: .leading, spacing: 24) {
            if let pace {
                ticket(pace)
            } else {
                invitation
            }
            if !shares.isEmpty, storedStyle != WhereItGoesStyle.hidden.rawValue {
                whereItGoes
                    .transition(.opacity)
            }
            if let note {
                noteLine(note)
            }
        }
        // Choosing a view of «En qué se va» in «Más» fades it, while the carousel eases its
        // height and the list below follows.
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: storedStyle)
    }

    // MARK: Note

    /// «Nota · Comida va 40 % arriba de lo normal…», the last line of the ticket.
    private func noteLine(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nota")
                .font(.ticket(10, relativeTo: .caption2))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.brass)
            Text(text)
                .font(.ticket(12, relativeTo: .footnote))
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

    private var invitation: some View {
        Button(action: onSetBudget) {
            VStack(spacing: 6) {
                Text("Fijar presupuesto")
                    .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.brass)
                Text("Para ver cuánto te queda")
                    .font(.ticket(11, relativeTo: .caption))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: barHeight)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.outline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fijar-presupuesto")
    }

    // MARK: With a budget

    private func ticket(_ pace: BudgetPace) -> some View {
        let isOver = pace.remaining < 0
        // A month where more came back than went out is 0 %, not "-5 %".
        let share = max(0, NSDecimalNumber(decimal: pace.spent / pace.budget).doubleValue)
        return MonthBar(pace: pace, isCurrentMonth: isCurrentMonth, money: money, wholeMoney: wholeMoney,
                        carriesTotal: isCurrentMonth && !isOver)
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
            parts.append("Te pasaste por \(remainingText).")
        } else {
            parts.append((isCurrentMonth ? "Te quedan " : "Te quedaron ") + "\(remainingText).")
        }
        if isCurrentMonth {
            parts.append("A hoy podrías llevar \(money(pace.expectedToDate)).")
            if pace.reserved > 0 { parts.append("Se apartan \(money(pace.reserved)) de gastos fijos por venir.") }
            if !isOver { parts.append("Hoy puedes gastar \(wholeMoney(pace.dailyAllowance)).") }
        }
        return parts.joined(separator: " ")
    }

    private func remainingBlock(_ label: String, _ amount: String,
                                alignment: HorizontalAlignment = .trailing) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(label)
                .font(.ticket(10, relativeTo: .caption2))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
            Text(amount)
                .contentTransition(.numericText())
                .font(.ticket(22, relativeTo: .title2))
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
                // A huge figure shrinks instead of widening the page (it shifted the carousel).
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
    }
}

