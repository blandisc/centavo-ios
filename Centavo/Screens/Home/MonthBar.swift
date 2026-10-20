import CentavoCore
import SwiftUI

/// The month as one bar that answers the five questions at a glance: the whole bar is the
/// budget, brass is what went, the white flag is what an even month would have spent by
/// today, and what is left is cut into one tile per day still to come, today's lit.
/// Tapping it unfolds the sum behind «Hoy puedes gastar».
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

    private let gap: CGFloat = 3
    private var isOver: Bool { pace.remaining < 0 }
    /// What the day tiles share: what is left, minus the fixed expenses still to come.
    private var toShare: Decimal { max(0, pace.remaining - (isCurrentMonth ? pace.reserved : 0)) }
    private var days: Int { isCurrentMonth && !isOver ? min(max(pace.daysLeft, 1), 31) : 0 }

    private func fraction(_ part: Decimal) -> CGFloat {
        guard pace.budget > 0 else { return 0 }
        return CGFloat(min(max(NSDecimalNumber(decimal: part / pace.budget).doubleValue, 0), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.2)) { showsSum.toggle() }
            } label: {
                bar
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: showsSum)
            .accessibilityHint(showsSum ? "Oculta la cuenta" : "Muestra la cuenta")

            // Side by side; stacked when the text is large.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { spentKey; Spacer(minLength: 8); leftKey }
                VStack(alignment: .leading, spacing: 4) { spentKey; leftKey }
            }
            .font(.ticket(12, relativeTo: .footnote))

            // The dashed piece of the bar: money already set aside for what is coming.
            if isCurrentMonth, !isOver, pace.reserved > 0 {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Theme.brassLow, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .frame(width: 14, height: 8)
                    Text("Apartado para fijos por venir ").foregroundStyle(Theme.muted)
                    + Text(wholeMoney(pace.reserved)).foregroundStyle(Theme.ink)
                }
                .font(.ticket(11, relativeTo: .caption))
            }

            if showsSum { sum.transition(.move(edge: .top).combined(with: .opacity)) }

            verdict
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.92, anchor: .leading)
                .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.3).delay(0.9), value: shown)
        }
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation { shown = true } }
        }
    }

    // MARK: The bar

    private var bar: some View {
        let spentW = width * (isOver ? 1 : fraction(pace.spent))
        let reservedW = isCurrentMonth && !isOver ? width * fraction(pace.reserved) : 0
        let freeW = max(0, width - spentW - reservedW - (reservedW > 0 ? gap : 0) - (spentW > 0 ? gap : 0))
        let slotW = days > 0 ? (freeW - gap * CGFloat(days - 1)) / CGFloat(days) : 0
        let markX = width * CGFloat(pace.paceFraction)

        return VStack(alignment: .leading, spacing: 6) {
            if isCurrentMonth {
                flag(at: markX)
            }
            Color.clear
                .frame(height: trackHeight)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .overlay(alignment: .leading) {
                    HStack(spacing: gap) {
                        // What went: grows in from nothing, with a little bounce.
                        UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10,
                                               bottomTrailingRadius: isOver ? 10 : 3,
                                               topTrailingRadius: isOver ? 10 : 3)
                            .fill(isOver ? Theme.danger : Theme.brass)
                            .frame(width: shown ? spentW : 0)
                            .animation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.18).delay(0.1), value: shown)
                            .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.15), value: spentW)
                        if reservedW > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Theme.brassLow, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                                .frame(width: reservedW)
                                .opacity(shown ? 1 : 0)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.5), value: shown)
                        }
                        if slotW >= 2 {
                            ForEach(0..<days, id: \.self) { index in
                                DayTile(isToday: index == 0, isLast: index == days - 1, animate: !reduceMotion)
                                    .frame(width: slotW)
                                    .opacity(shown ? 1 : 0)
                                    .scaleEffect(y: shown ? 1 : 0.3, anchor: .bottom)
                                    .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.3)
                                        .delay(0.45 + Double(index) * 0.035), value: shown)
                            }
                        } else if !isOver {
                            UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3,
                                                   bottomTrailingRadius: 10, topTrailingRadius: 10)
                                .fill(Theme.raised)
                        }
                    }
                }
                .overlay(alignment: .leading) {
                    if isCurrentMonth {
                        // Where an even month would be by today.
                        Capsule()
                            .fill(Theme.ink)
                            .frame(width: 2.5, height: trackHeight + 10)
                            .offset(x: markX - 1.25, y: -5)
                            .opacity(shown ? 1 : 0)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.35).delay(0.7), value: shown)
                    }
                }
        }
        .contentShape(Rectangle())
    }

    /// «Lo esperado a hoy $4,903», as a small white flag over its line, kept inside the bar.
    private func flag(at x: CGFloat) -> some View {
        let text = "Lo esperado a hoy " + wholeMoney(pace.expectedToDate)
        return Text(text)
            .font(.ticket(10, weight: .medium, relativeTo: .caption2))
            .foregroundStyle(Theme.background)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.ink, in: Capsule())
            // Never wider than the bar it sits on (large text made it push the page aside).
            .frame(maxWidth: width > 0 ? width : nil)
            .fixedSize(horizontal: width == 0, vertical: false)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { flagWidth = $0 }
            .offset(x: min(max(x - flagWidth / 2, 0), max(0, width - flagWidth)))
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : -6)
            .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.35).delay(0.75), value: shown)
    }
    @State private var flagWidth: CGFloat = 0

    // MARK: Words

    private var spentKey: some View {
        HStack(spacing: 6) {
            Circle().fill(isOver ? Theme.danger : Theme.brass).frame(width: 8, height: 8)
            Text("Llevas").foregroundStyle(Theme.muted)
            totalText
        }
        .fixedSize()
    }

    private var leftKey: some View {
        (Text(isOver ? "Te pasaste " : (isCurrentMonth ? "Te quedan " : "Te quedaron "))
            .foregroundStyle(Theme.muted)
        + Text(money(pace.remaining.magnitude)).foregroundStyle(Theme.ink)
        + Text(" de ").foregroundStyle(Theme.muted)
        + Text(wholeMoney(pace.budget)).foregroundStyle(Theme.ink))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var totalText: some View {
        Text(money(pace.spent))
            .foregroundStyle(Theme.ink)
            .contentTransition(.numericText())
            .accessibilityIdentifier(carriesTotal ? "total-mes" : "llevas")
    }

    /// «Vas bien · $2,537 menos de lo esperado», «Vas $697 arriba de lo esperado».
    private var verdict: some View {
        let difference = pace.expectedToDate - pace.spent
        let (text, good): (String, Bool) = {
            if isOver { return ("Te pasaste \(wholeMoney(pace.remaining.magnitude)) del presupuesto", false) }
            if !isCurrentMonth { return ("Cerraste con \(wholeMoney(pace.remaining)) de sobra", true) }
            if difference >= 0 { return ("Vas bien · \(wholeMoney(difference)) menos de lo esperado", true) }
            return ("Vas \(wholeMoney(-difference)) arriba de lo esperado", false)
        }()
        return Text(text)
            .font(.ticket(12, weight: .medium, relativeTo: .footnote))
            .foregroundStyle(good ? Theme.good : Theme.danger)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background((good ? Theme.good : Theme.danger).opacity(0.14), in: Capsule())
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

/// One day still to come; today's is lit and breathes softly.
private struct DayTile: View {
    let isToday: Bool
    let isLast: Bool
    let animate: Bool

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3,
                                           bottomTrailingRadius: isLast ? 10 : 3,
                                           topTrailingRadius: isLast ? 10 : 3)
        if isToday {
            shape
                .fill(Theme.brass.opacity(0.35))
                .overlay(shape.strokeBorder(Theme.brass, lineWidth: 1.5))
                .phaseAnimator(animate ? [0.65, 1.0] : [1.0]) { tile, phase in
                    tile.opacity(phase)
                } animation: { _ in .easeInOut(duration: 1.4) }
        } else {
            shape.fill(Theme.raised)
        }
    }
}
