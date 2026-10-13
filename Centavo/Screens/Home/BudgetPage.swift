import CentavoCore
import SwiftUI

/// Second page of the carousel: the budget as a bar that fills up as the month is spent.
///
/// The accent is what you have spent, the line is where an even spend would be today,
/// and what is still empty is what remains.
struct BudgetPage: View {
    let spent: MoneyTotal
    let pace: BudgetPace?
    /// A month that is over has no "today": the whole budget was due, so the marker goes.
    let isCurrentMonth: Bool
    let onSetBudget: () -> Void

    @ScaledMetric(relativeTo: .body) private var scaledBarHeight: CGFloat = 72
    /// The big figure's point size at the current Dynamic Type setting, to estimate its width.
    @ScaledMetric(relativeTo: .title2) private var figureSize: CGFloat = 22
    @State private var barWidth: CGFloat = 0

    /// Grows a little with the text, but a bar the size of the screen helps nobody.
    private var barHeight: CGFloat { min(scaledBarHeight, 132) }

    private func money(_ amount: Decimal) -> String {
        formatMoney(amount, isoCode: spent.isoCode, label: spent.label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gastado")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(money(spent.amount))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tint)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Fija un tope de gasto para ver cuánto te queda.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Fijar presupuesto", systemImage: "target", action: onSetBudget)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("fijar-presupuesto")
        }
        .frame(maxWidth: .infinity, minHeight: barHeight, alignment: .leading)
    }

    // MARK: With a budget

    private func ticket(_ pace: BudgetPace) -> some View {
        let isOver = pace.remaining < 0
        let markerX = barWidth * CGFloat(pace.paceFraction)
        let labelOnLeft = pace.paceFraction < 0.5
        let todayText = "A hoy: " + pace.expectedToDate.formatted(.number.precision(.fractionLength(0)))
        let remainingLabel = isOver ? "Te pasaste" : (isCurrentMonth ? "Te quedan" : "Te quedaron")
        let remainingText = money(pace.remaining.magnitude)
        // The figure is tabular, so its width is predictable. If it would run over the
        // filled part, it goes under the bar instead.
        let neededWidth = CGFloat(remainingText.count) * 0.6 * figureSize + 28
        let remainingInside = barWidth > 0 && barWidth * CGFloat(1 - pace.spentFraction) >= neededWidth

        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .leading) {
                Rectangle().fill(.quaternary)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: barWidth * CGFloat(pace.spentFraction))
                if remainingInside {
                    remainingBlock(remainingLabel, remainingText)
                        .padding(.trailing, 14)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: barHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .leading) {
                if isCurrentMonth {
                    Rectangle()
                        .fill(.primary)
                        .frame(width: 2, height: barHeight + 12)
                        .offset(x: markerX - 1)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }

            if isCurrentMonth {
                Text(todayText)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(labelOnLeft ? .leading : .trailing, labelOnLeft ? markerX + 6 : barWidth - markerX + 6)
                    .frame(maxWidth: .infinity, alignment: labelOnLeft ? .leading : .trailing)
            }
            if !remainingInside {
                remainingBlock(remainingLabel, remainingText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text("Presupuesto: \(money(pace.budget))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("presupuesto-ticket")
        .accessibilityLabel(
            "Presupuesto de \(money(pace.budget)). Has gastado \(money(pace.spent)). "
            + (isOver ? "Te pasaste por \(remainingText). "
                      : (isCurrentMonth ? "Te quedan \(remainingText). " : "Te quedaron \(remainingText). "))
            + (isCurrentMonth ? "A hoy podrías llevar \(money(pace.expectedToDate))." : "")
        )
    }

    private func remainingBlock(_ label: String, _ amount: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(amount)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}
