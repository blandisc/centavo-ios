import CentavoCore
import SwiftUI

/// Second page of the carousel: the budget as a blank ticket that fills up as the month is spent.
///
/// Brass is what you have spent, the white line is where an even spend would be today,
/// and what is still dashed is what remains.
struct BudgetPage: View {
    let spent: MoneyTotal
    let pace: BudgetPace?
    let onSetBudget: () -> Void

    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 84
    /// The big figure's point size at the current Dynamic Type setting, to estimate its width.
    @ScaledMetric(relativeTo: .title2) private var figureSize: CGFloat = 22
    @State private var barWidth: CGFloat = 0

    private func money(_ amount: Decimal) -> String {
        formatMoney(amount, isoCode: spent.isoCode, label: spent.label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gastado").font(.ticket(10, relativeTo: .caption2)).tracking(1.2)
                    .textCase(.uppercase).foregroundStyle(Theme.muted)
                Text(money(spent.amount))
                    .font(.ticket(22, relativeTo: .title2))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.brass)
            }
            if let pace {
                ticket(pace)
            } else {
                invitation
            }
        }
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
    }

    // MARK: With a budget

    private func ticket(_ pace: BudgetPace) -> some View {
        let isOver = pace.remaining < 0
        let markerX = barWidth * CGFloat(pace.paceFraction)
        let labelOnLeft = pace.paceFraction < 0.5
        let todayText = "Hoy · " + pace.expectedToDate.formatted(.number.precision(.fractionLength(0)))
        let remainingLabel = isOver ? "Te pasaste" : "Te quedan"
        let remainingText = money(pace.remaining.magnitude)
        // The type is monospaced (0.6 em a character), so its width is predictable. If the
        // figure would run over the brass, it goes under the bar instead.
        let neededWidth = CGFloat(remainingText.count) * 0.6 * figureSize + 28
        let remainingInside = barWidth > 0 && barWidth * CGFloat(1 - pace.spentFraction) >= neededWidth

        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.outline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                UnevenRoundedRectangle(
                    topLeadingRadius: 6,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: pace.spentFraction >= 1 ? 6 : 0,
                    topTrailingRadius: pace.spentFraction >= 1 ? 6 : 0
                )
                .fill(Theme.brass)
                .frame(width: barWidth * CGFloat(pace.spentFraction))
                if remainingInside {
                    remainingBlock(remainingLabel, remainingText)
                        .padding(.trailing, 14)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Rectangle()
                    .fill(Theme.ink)
                    .frame(width: 2, height: barHeight + 12)
                    .offset(x: markerX - 1)
            }
            .frame(height: barHeight)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }

            Text(todayText)
                .font(.ticket(10, relativeTo: .caption2))
                .tracking(1)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(labelOnLeft ? .leading : .trailing, labelOnLeft ? markerX + 6 : barWidth - markerX + 6)
                .frame(maxWidth: .infinity, alignment: labelOnLeft ? .leading : .trailing)

            if !remainingInside {
                remainingBlock(remainingLabel, remainingText, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Presupuesto de \(money(pace.budget)). Has gastado \(money(pace.spent)). "
            + (isOver ? "Te pasaste por \(remainingText). " : "Te quedan \(remainingText). ")
            + "A hoy podrías llevar \(money(pace.expectedToDate))."
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
