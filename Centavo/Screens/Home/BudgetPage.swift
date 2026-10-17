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
    let onSetBudget: () -> Void

    @ScaledMetric(relativeTo: .body) private var scaledBarHeight: CGFloat = 84
    /// The big figure's point size at the current Dynamic Type setting, to estimate its width.
    @ScaledMetric(relativeTo: .title2) private var figureSize: CGFloat = 22
    @State private var barWidth: CGFloat = 0

    /// Grows a little with the text, but a bar the size of the screen helps nobody.
    private var barHeight: CGFloat { min(scaledBarHeight, 132) }

    private func money(_ amount: Decimal) -> String {
        formatMoney(amount, isoCode: spent.isoCode, label: spent.label)
    }

    /// "$3,871": a rough mark, so no cents, but still money like every other figure.
    private func wholeMoney(_ amount: Decimal) -> String {
        if let isoCode = spent.isoCode {
            return amount.formatted(.currency(code: isoCode).precision(.fractionLength(0)))
        }
        return spent.label + amount.formatted(.number.precision(.fractionLength(0)))
    }

    var body: some View {
        // What was spent is already the big total right above; this page only says how it
        // measures against the budget.
        VStack(alignment: .leading, spacing: 20) {
            if let pace {
                ticket(pace)
            } else {
                invitation
            }
            if !shares.isEmpty {
                whereItGoes
            }
        }
    }

    // MARK: Where it goes

    /// The biggest categories, each a line of the ticket with a brass rule for its share.
    private var whereItGoes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("En qué se va")
                .font(.ticket(10, relativeTo: .caption2))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
            ForEach(Array(shares.enumerated()), id: \.offset) { _, line in
                let name = line.category ?? "Sin categoría"
                let percent = line.share.formatted(.percent.precision(.fractionLength(0)))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(name)
                            .foregroundStyle(line.category == nil ? Theme.muted : Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Text(percent)
                            .foregroundStyle(Theme.muted)
                            .monospacedDigit()
                    }
                    .font(.ticket(12, relativeTo: .footnote))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    Rectangle()
                        .fill(Theme.brass)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: max(line.share, 0.02), anchor: .leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name): \(percent) de lo gastado")
            }
        }
        .accessibilityIdentifier("en-que-se-va")
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
        let markerX = barWidth * CGFloat(pace.paceFraction)
        let labelOnLeft = pace.paceFraction < 0.5
        let todayText = "Ritmo · " + wholeMoney(pace.expectedToDate)
        // A month where more came back than went out is 0 %, not "-5 %".
        let share = max(0, NSDecimalNumber(decimal: pace.spent / pace.budget).doubleValue)
        let remainingLabel = isOver ? "Te pasaste" : (isCurrentMonth ? "Te quedan" : "Te quedaron")
        let remainingText = money(pace.remaining.magnitude)
        // The type is monospaced (0.6 em a character), so its width is predictable. If the
        // figure would run over the brass, it goes under the bar instead.
        let neededWidth = CGFloat(remainingText.count) * 0.6 * figureSize + 28
        let remainingInside = barWidth > 0 && barWidth * CGFloat(1 - pace.spentFraction) >= neededWidth

        return VStack(alignment: .leading, spacing: 8) {
            // The legend of the brass: what share of the budget is gone, past 100 % if need be.
            Text("Gastado · " + share.formatted(.percent.precision(.fractionLength(0))))
                .font(.ticket(10, relativeTo: .caption2))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.brass)
                .padding(.bottom, 4)
            // The outline alone sets the size. Everything sized from `barWidth` is an overlay,
            // so it can never feed back into the width it was measured from: a full brass bar
            // used to hold the ticket at a stale, wider width and push the page off screen.
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.outline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(maxWidth: .infinity)
                .frame(height: barHeight)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 6,
                        bottomLeadingRadius: 6,
                        bottomTrailingRadius: pace.spentFraction >= 1 ? 6 : 0,
                        topTrailingRadius: pace.spentFraction >= 1 ? 6 : 0
                    )
                    .fill(Theme.brass)
                    .frame(width: barWidth * CGFloat(pace.spentFraction))
                }
                .overlay(alignment: .trailing) {
                    if remainingInside {
                        remainingBlock(remainingLabel, remainingText)
                            .padding(.trailing, 14)
                    }
                }
                .overlay(alignment: .leading) {
                    if isCurrentMonth {
                        Rectangle()
                            .fill(Theme.ink)
                            .frame(width: 2, height: barHeight + 12)
                            .offset(x: markerX - 1)
                    }
                }

            if isCurrentMonth {
                Text(todayText)
                    .font(.ticket(10, relativeTo: .caption2))
                    .tracking(1)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(labelOnLeft ? .leading : .trailing, labelOnLeft ? markerX + 6 : barWidth - markerX + 6)
                    .frame(maxWidth: .infinity, alignment: labelOnLeft ? .leading : .trailing)
            }

            if !remainingInside {
                remainingBlock(remainingLabel, remainingText, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text("Presupuesto · \(money(pace.budget))")
                .font(.ticket(10, relativeTo: .caption2))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
            // The one number to act on today: what is left, spread over the days to come.
            if isCurrentMonth, !isOver {
                Text("Hoy puedes gastar \(wholeMoney(pace.dailyAllowance))")
                    .font(.ticket(12, weight: .semibold, relativeTo: .footnote))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.brass)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("presupuesto-ticket")
        .accessibilityLabel(
            "Presupuesto de \(money(pace.budget)). Has gastado \(money(pace.spent)), "
            + "el \(share.formatted(.percent.precision(.fractionLength(0)))). "
            + (isOver ? "Te pasaste por \(remainingText). "
                      : (isCurrentMonth ? "Te quedan \(remainingText). " : "Te quedaron \(remainingText). "))
            + (isCurrentMonth ? "A hoy podrías llevar \(money(pace.expectedToDate)). " : "")
            + (isCurrentMonth && !isOver ? "Hoy puedes gastar \(wholeMoney(pace.dailyAllowance))." : "")
        )
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
                .font(.ticket(22, relativeTo: .title2))
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
        }
    }
}
