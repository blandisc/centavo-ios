import CentavoCore
import SwiftUI

/// The month as one bar that answers the five questions at a glance: the whole bar is the
/// budget, brass is what went, the white rule is what an even month would have spent by
/// today (the stretch between the two is hatched), and what is left is cut into one tile per
/// day still to come, today's lit. Tapping it unfolds the sum behind «Hoy puedes gastar».
/// No capsules: everything is said with type and the bar itself, like a printed ticket.
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

            // Each figure where what it measures is: «Llevas» under the brass, «Presupuesto» at
            // the bar's end, «Podrías llevar» over the rule (owner's choice, 2026-10-22).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { spentKey; Spacer(minLength: 8); budgetKey }
                VStack(alignment: .leading, spacing: 4) { spentKey; budgetKey }
            }
            .font(.ticket(12, relativeTo: .footnote))


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
        let reservedW = isCurrentMonth && !isOver ? width * fraction(pace.reserved) : 0
        let freeW = max(0, width - spentW - reservedW - (reservedW > 0 ? gap : 0) - (spentW > 0 ? gap : 0))
        let slotW = days > 0 ? (freeW - gap * CGFloat(days - 1)) / CGFloat(days) : 0
        let tilesX = width - freeW
        let markX = snapped(width * CGFloat(pace.paceFraction), tilesX: tilesX, slotW: slotW)

        return VStack(alignment: .leading, spacing: 8) {
            if isCurrentMonth {
                annotation(at: markX)
            }
            Color.clear
                .frame(height: trackHeight)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .overlay(alignment: .leading) {
                    HStack(spacing: gap) {
                        // What went: grows in from nothing, with a little bounce.
                        RoundedRectangle(cornerRadius: 3)
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
                                DayTile(isToday: index == 0, animate: !reduceMotion)
                                    .frame(width: slotW)
                                    .opacity(shown ? 1 : 0)
                                    .scaleEffect(y: shown ? 1 : 0.3, anchor: .bottom)
                                    .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.3)
                                        .delay(0.45 + Double(index) * 0.035), value: shown)
                            }
                        } else if !isOver {
                            RoundedRectangle(cornerRadius: 3).fill(Theme.raised)
                        }
                    }
                    // Only the bar as a whole is rounded; every piece inside is cut the same.
                    .clipShape(Capsule())
                }
                .overlay(alignment: .leading) {
                    if isCurrentMonth, !isOver, width > 0 {
                        // The stretch between what went and what was expected: under it is
                        // money you have not spent yet (green), over it is money ahead of time.
                        let spent = width * fraction(pace.spent)
                        let ahead = spent > markX
                        Hatch()
                            .stroke(ahead ? Theme.danger : Theme.good, lineWidth: 1.2)
                            .opacity(ahead ? 0.8 : 0.55)
                            .frame(width: abs(markX - spent), height: trackHeight)
                            .clipShape(Rectangle())
                            .offset(x: min(spent, markX))
                            .opacity(shown ? 1 : 0)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.8), value: shown)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .leading) {
                    if isCurrentMonth {
                        // Where an even month would be by today.
                        Capsule()
                            .fill(Theme.ink)
                            .frame(width: 2, height: trackHeight + 8)
                            .offset(x: markX - 1, y: -4)
                            .opacity(shown ? 1 : 0)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.35).delay(0.7), value: shown)
                    }
                }
        }
        .contentShape(Rectangle())
    }

    /// The expected mark, set in the gap between two day tiles rather than on a tile's edge.
    private func snapped(_ x: CGFloat, tilesX: CGFloat, slotW: CGFloat) -> CGFloat {
        guard slotW >= 2, x > tilesX else { return x }
        let step = slotW + gap
        let k = ((x - tilesX + gap / 2) / step).rounded()
        return min(tilesX + k * step - gap / 2, width)
    }

    /// «ESPERADO HOY $3,871», printed over its rule like a note on a ticket, kept inside the bar.
    private func annotation(at x: CGFloat) -> some View {
        (Text("Podrías llevar ").foregroundStyle(Theme.muted)
            + Text(wholeMoney(pace.expectedToDate)).foregroundStyle(Theme.ink))
            .font(.ticket(10, relativeTo: .caption2))
            .tracking(1)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            // Never wider than the bar it sits on (large text made it push the page aside).
            .frame(maxWidth: width > 0 ? width : nil)
            .fixedSize(horizontal: width == 0, vertical: false)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { annotationWidth = $0 }
            .offset(x: min(max(x - annotationWidth / 2, 0), max(0, width - annotationWidth)))
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.75), value: shown)
    }
    @State private var annotationWidth: CGFloat = 0

    // MARK: Words

    private var spentKey: some View {
        HStack(spacing: 6) {
            swatch(isOver ? Theme.danger : Theme.brass)
            Text("Llevas").foregroundStyle(Theme.muted)
            totalText
        }
        .fixedSize()
    }

    /// «Presupuesto $8,000», at the end of the bar it measures.
    private var budgetKey: some View {
        (Text("Presupuesto ").foregroundStyle(Theme.muted)
            + Text(wholeMoney(pace.budget)).foregroundStyle(Theme.ink))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// The key's little square, the same shape as the bar's pieces.
    private func swatch(_ color: Color, outlined: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .overlay { if outlined { RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.dimmed, lineWidth: 0.5) } }
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var totalText: some View {
        Text(wholeMoney(pace.spent))
            .foregroundStyle(Theme.ink)
            .contentTransition(.numericText())
            .accessibilityLabel(money(pace.spent))
            .accessibilityIdentifier(carriesTotal ? "total-mes" : "llevas")
    }

    /// «Vas $2,537 abajo de lo esperado»: a plain sentence, only the judgement in color.
    private var verdict: some View {
        let difference = pace.expectedToDate - pace.spent
        let (before, colored, after, good): (String, String, String, Bool) = {
            if isOver {
                return ("Te pasaste ", wholeMoney(pace.remaining.magnitude), " del presupuesto", false)
            }
            if !isCurrentMonth { return ("Cerraste con ", wholeMoney(pace.remaining), " de sobra", true) }
            if difference >= 0 { return ("Vas ", "\(wholeMoney(difference)) abajo", " de lo que podrías llevar", true) }
            return ("Vas ", "\(wholeMoney(-difference)) arriba", " de lo que podrías llevar", false)
        }()
        return (Text(before).foregroundStyle(Theme.muted)
            + Text(colored).foregroundStyle(good ? Theme.good : Theme.danger)
            + Text(after).foregroundStyle(Theme.muted))
            .font(.ticket(12, relativeTo: .footnote))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("veredicto")
    }

    /// The sum behind «Hoy puedes gastar», like a ticket's lines.
    private var sum: some View {
        VStack(spacing: 6) {
            sumLine("Presupuesto", wholeMoney(pace.budget))
            sumLine("− Llevas", wholeMoney(pace.spent))
            sumLine(isOver ? "= Te pasaste" : "= Te quedan", wholeMoney(pace.remaining.magnitude))
            // What today spent comes off today alone: it goes back in before sharing the
            // days, and comes off today's share at the end.
            let spentToday = pace.spentToday != 0
            if days > 0, pace.reserved > 0 {
                sumLine("− Fijos por venir", wholeMoney(pace.reserved))
                sumLine(spentToday ? "= Libres" : "= Para tus días", wholeMoney(pace.free))
            }
            if days > 0, spentToday {
                sumLine(pace.spentToday > 0 ? "+ Gastado hoy" : "− Devuelto hoy", wholeMoney(pace.spentToday.magnitude))
                sumLine("= Para tus días", wholeMoney(pace.todayShare * Decimal(days)))
            }
            if days > 0 {
                sumLine("÷ Días que faltan", "\(days)")
                if spentToday {
                    sumLine("= Para hoy", wholeMoney(pace.todayShare))
                    sumLine(pace.spentToday > 0 ? "− Gastado hoy" : "+ Devuelto hoy", wholeMoney(pace.spentToday.magnitude))
                }
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
    let animate: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3)
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

/// Thin diagonal lines, like the shading on a printed form.
private struct Hatch: Shape {
    var spacing: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
