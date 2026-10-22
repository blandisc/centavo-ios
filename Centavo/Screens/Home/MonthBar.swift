import CentavoCore
import SwiftUI

/// The month in three things: a verdict in words («Vas bien este mes»), one bar (brass is
/// what went, the rest is what is left, a thin rule is where an even month would be today)
/// and one line («$2,366.00 de $8,000 · faltan 9 días»). The owner found seven figures under
/// «Hoy puedes gastar» too many (2026-10-22): the expected amount, the difference and what is
/// set aside for fixed expenses now live in the sum that unfolds when the bar is tapped.
struct MonthBar: View {
    let pace: BudgetPace
    let isCurrentMonth: Bool
    /// "$2,366.00", as the rest of the app writes it.
    let money: (Decimal) -> String
    /// "$4,903", for marks.
    let wholeMoney: (Decimal) -> String
    /// Whether «Llevas» is the screen's own total (the hero shows «Hoy puedes gastar» instead).
    let carriesTotal: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var trackHeight: CGFloat = 20
    @State private var width: CGFloat = 0
    @State private var shown = false
    @State private var showsSum = false

    private var isOver: Bool { pace.remaining < 0 }
    /// What the day tiles share: what is left, minus the fixed expenses still to come.
    private var toShare: Decimal { max(0, pace.remaining - (isCurrentMonth ? pace.reserved : 0)) }
    private var days: Int { isCurrentMonth && !isOver ? min(max(pace.daysLeft, 1), 31) : 0 }

    private func fraction(_ part: Decimal) -> CGFloat {
        guard pace.budget > 0 else { return 0 }
        return CGFloat(min(max(NSDecimalNumber(decimal: part / pace.budget).doubleValue, 0), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Right under «Hoy puedes gastar», the one sentence that judges the month.
            verdict
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.9), value: shown)
                .padding(.bottom, isCurrentMonth ? 16 : 8)

            Button {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.2)) { showsSum.toggle() }
            } label: {
                bar
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: showsSum)
            .accessibilityHint(showsSum ? "Oculta la cuenta" : "Muestra la cuenta")

            summaryLine

            if showsSum {
                sum
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation { shown = true } }
        }
    }

    // MARK: The bar

    private var bar: some View {
        let spentW = width * (isOver ? 1 : fraction(pace.spent))
        let markX = width * CGFloat(pace.paceFraction)

        return Color.clear
            .frame(height: trackHeight)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background(Theme.raised, in: Capsule())
            .overlay(alignment: .leading) {
                // What went: grows in from nothing, with a little bounce.
                Capsule()
                    .fill(isOver ? Theme.danger : Theme.brass)
                    .frame(width: shown ? max(spentW, spentW > 0 ? trackHeight : 0) : 0)
                    .animation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.18).delay(0.1), value: shown)
                    .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.15), value: spentW)
            }
            .overlay(alignment: .leading) {
                if isCurrentMonth, !isOver, width > 0 {
                    // Where an even month would be by today: a rule, no figure (it is in the sum).
                    Capsule()
                        .fill(Theme.ink)
                        .frame(width: 2, height: trackHeight + 8)
                        .offset(x: min(max(markX - 1, 0), width - 2))
                        .opacity(shown ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.35).delay(0.7), value: shown)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
    }

    // MARK: Words

    /// «$2,366.00 de $8,000 · faltan 9 días»: what went, of what, and how long is left.
    private var summaryLine: some View {
        let tail: String = {
            guard isCurrentMonth, !isOver, pace.daysLeft > 0 else { return "" }
            return pace.daysLeft == 1 ? " · hoy es el último día" : " · faltan \(pace.daysLeft) días"
        }()
        return HStack(spacing: 0) {
            totalText
            (Text(" de ").foregroundStyle(Theme.muted)
                + Text(wholeMoney(pace.budget)).foregroundStyle(Theme.ink)
                + Text(tail).foregroundStyle(Theme.muted))
        }
        .font(.ticket(12, relativeTo: .footnote))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var totalText: some View {
        Text(money(pace.spent))
            .foregroundStyle(Theme.ink)
            .contentTransition(.numericText())
            .accessibilityIdentifier(carriesTotal ? "total-mes" : "llevas")
    }

    /// «Vas bien este mes»: a plain sentence, only the judgement in color.
    private var verdict: some View {
        let difference = pace.expectedToDate - pace.spent
        let (before, colored, after, good): (String, String, String, Bool) = {
            if isOver {
                return ("Te pasaste ", wholeMoney(pace.remaining.magnitude), " del presupuesto", false)
            }
            if !isCurrentMonth { return ("Cerraste con ", wholeMoney(pace.remaining), " de sobra", true) }
            // Words, not a figure: the difference is in the sum, for whoever wants it.
            if difference >= 0 { return ("", "Vas bien", " este mes", true) }
            return ("", "Vas arriba", " de tu ritmo", false)
        }()
        return (Text(before).foregroundStyle(Theme.muted)
            + Text(colored).foregroundStyle(good ? Theme.good : Theme.danger)
            + Text(after).foregroundStyle(Theme.muted))
            .font(.ticket(14, relativeTo: .callout))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("veredicto")
    }

    /// The sum behind «Hoy puedes gastar», like a ticket's lines.
    private var sum: some View {
        VStack(spacing: 6) {
            sumLine("Presupuesto", wholeMoney(pace.budget))
            sumLine("− Llevas", wholeMoney(pace.spent))
            sumLine(isOver ? "= Te pasaste" : "= Te quedan", wholeMoney(pace.remaining.magnitude))
            if days > 0, pace.reserved > 0 {
                sumLine("− Fijos por venir", wholeMoney(pace.reserved))
                sumLine("= Para tus días", wholeMoney(toShare))
            }
            if days > 0 {
                sumLine("÷ Días que faltan", "\(days)")
                Divider().overlay(Theme.hairline)
                sumLine("= Hoy puedes gastar", wholeMoney(pace.dailyAllowance), strong: true)
            }
            if isCurrentMonth, !isOver {
                // What the verdict and the rule on the bar mean, in figures.
                let difference = pace.expectedToDate - pace.spent
                Divider().overlay(Theme.hairline).padding(.top, 4)
                sumLine("Ritmo parejo a hoy", wholeMoney(pace.expectedToDate))
                sumLine(difference >= 0 ? "Vas abajo por" : "Vas arriba por", wholeMoney(difference.magnitude))
            }
        }
        .font(.ticket(12, relativeTo: .footnote))
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("la-cuenta")
    }

    private func sumLine(_ label: String, _ value: String, strong: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(strong ? Theme.brass : Theme.muted)
            Spacer()
            Text(value).foregroundStyle(strong ? Theme.brass : Theme.ink).monospacedDigit()
        }
        .fontWeight(strong ? .semibold : .regular)
    }
}
