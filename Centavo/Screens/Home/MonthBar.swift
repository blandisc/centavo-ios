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
    /// What was left out of the budget («No cuenta»), shown under the sum so nothing goes
    /// missing without a word. Zero shows nothing.
    var outside: Decimal = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var trackHeight: CGFloat = Theme.Size.monthBarTrack
    @State private var width: CGFloat = Theme.Space.none
    @State private var shown = false
    @State private var showsSum = false

    private let gap: CGFloat = Theme.Size.monthBarGap
    /// Whether the bar has been measured yet.
    private var hasWidth: Bool { width > 0 }
    private var isOver: Bool { pace.remaining < 0 }
    private var days: Int { isCurrentMonth && !isOver ? min(max(pace.daysLeft, 1), 31) : 0 }

    private func fraction(_ part: Decimal) -> CGFloat {
        guard pace.budget > 0 else { return 0 }
        return CGFloat(min(max(NSDecimalNumber(decimal: part / pace.budget).doubleValue, 0), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            // Right under «Hoy puedes gastar», the one sentence that judges the month.
            verdict
                .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
                .animation(reduceMotion ? nil : Theme.Motion.Entrance.legend, value: shown)
                .padding(.bottom, isCurrentMonth ? Theme.Space.l : Theme.Space.s)

            Button {
                withAnimation(reduceMotion ? nil : Theme.Motion.toggle) { showsSum.toggle() }
            } label: {
                bar
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: showsSum)
            .accessibilityHint(showsSum ? "Oculta la cuenta" : "Muestra la cuenta")
            .accessibilityIdentifier("barra-del-mes")

            // Each figure where what it measures is: «Llevas» under the brass, «Presupuesto» at
            // the bar's end, «Podrías llevar» over the rule (owner's choice, 2026-10-22).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { spentKey; Spacer(minLength: Theme.Space.s); budgetKey }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) { spentKey; budgetKey }
            }
            .font(.ticket(.detail))


            if showsSum {
                sum
                    .padding(.top, Theme.Space.s)
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
        // «Podrías llevar»: the fixed expenses already charged plus every day's amount so far.
        let markX = snapped(width * fraction(pace.expectedToDate), tilesX: tilesX, slotW: slotW)

        return VStack(alignment: .leading, spacing: Theme.Space.s) {
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
                        RoundedRectangle(cornerRadius: Theme.Radius.tile)
                            .fill(isOver ? Theme.danger : Theme.brass)
                            .frame(width: shown ? spentW : Theme.Space.none)
                            .animation(reduceMotion ? nil : Theme.Motion.Entrance.fill, value: shown)
                            .animation(reduceMotion ? nil : Theme.Motion.Entrance.refill, value: spentW)
                        if reservedW > 0 {
                            RoundedRectangle(cornerRadius: Theme.Radius.tile)
                                .strokeBorder(Theme.brassLow, style: StrokeStyle(lineWidth: Theme.Stroke.emphasis, dash: Theme.Dash.dotted))
                                .frame(width: reservedW)
                                .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
                                .animation(reduceMotion ? nil : Theme.Motion.Entrance.markers, value: shown)
                        }
                        if slotW >= Theme.Size.minimumDayTile {
                            ForEach(0..<days, id: \.self) { index in
                                DayTile(isToday: index == 0, animate: !reduceMotion)
                                    .frame(width: slotW)
                                    .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
                                    .scaleEffect(y: shown ? Theme.Size.barFullScale : Theme.Motion.Entrance.barStart, anchor: .bottom)
                                    .animation(reduceMotion ? nil : Theme.Motion.Entrance.bar(index), value: shown)
                            }
                        } else if !isOver {
                            RoundedRectangle(cornerRadius: Theme.Radius.tile).fill(Theme.raised)
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
                            .stroke(ahead ? Theme.danger : Theme.good, lineWidth: Theme.Stroke.mark)
                            .opacity(ahead ? Theme.Opacity.paceAhead : Theme.Opacity.paceBehind)
                            .frame(width: abs(markX - spent), height: trackHeight)
                            .clipShape(Rectangle())
                            .offset(x: min(spent, markX))
                            .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
                            .animation(reduceMotion ? nil : Theme.Motion.Entrance.pace, value: shown)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .leading) {
                    if isCurrentMonth {
                        // Where an even month would be by today.
                        Capsule()
                            .fill(Theme.ink)
                            .frame(width: Theme.Size.todayMarkWidth, height: trackHeight + Theme.Size.todayMarkExtra)
                            .offset(x: markX - Theme.Size.todayMarkHalf, y: -Theme.Size.todayMarkInset)
                            .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
                            .animation(reduceMotion ? nil : Theme.Motion.Entrance.today, value: shown)
                    }
                }
        }
        .contentShape(Rectangle())
    }

    /// The expected mark, set in the gap between two day tiles rather than on a tile's edge.
    private func snapped(_ x: CGFloat, tilesX: CGFloat, slotW: CGFloat) -> CGFloat {
        guard slotW >= Theme.Size.minimumDayTile, x > tilesX else { return x }
        let step = slotW + gap
        let k = ((x - tilesX + gap / 2) / step).rounded()
        return min(tilesX + k * step - gap / 2, width)
    }

    /// «PODRÍAS LLEVAR $3,871», printed over its rule like a note on a ticket, kept inside the bar.
    /// Past the rule it is «Deberías llevar»: it is no longer room to spend.
    private func annotation(at x: CGFloat) -> some View {
        (Text(pace.isAheadOfPace ? "Deberías llevar " : "Podrías llevar ").foregroundStyle(Theme.muted)
            + Text(wholeMoney(pace.expectedToDate)).foregroundStyle(Theme.ink))
            .font(.ticket(.micro))
            .tracking(Theme.Tracking.tag)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(Theme.MinimumScale.figure)
            // Never wider than the bar it sits on (large text made it push the page aside).
            .frame(maxWidth: hasWidth ? width : nil)
            .fixedSize(horizontal: width == 0, vertical: false)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { annotationWidth = $0 }
            .offset(x: annotationX(centeredOn: x))
            .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
            .animation(reduceMotion ? nil : Theme.Motion.Entrance.annotation, value: shown)
    }
    @State private var annotationWidth: CGFloat = 0

    /// Where the note starts so it is centered on the mark, without leaving the bar.
    private func annotationX(centeredOn x: CGFloat) -> CGFloat {
        min(max(x - annotationWidth / 2, 0), max(0, width - annotationWidth))
    }

    // MARK: Words

    private var spentKey: some View {
        HStack(spacing: Theme.Space.xs) {
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
            .minimumScaleFactor(Theme.MinimumScale.figure)
    }

    /// The key's little square, the same shape as the bar's pieces.
    private func swatch(_ color: Color, outlined: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.bar)
            .fill(color)
            .overlay { if outlined { RoundedRectangle(cornerRadius: Theme.Radius.bar).strokeBorder(Theme.dimmed, lineWidth: Theme.Stroke.fine) } }
            .frame(width: Theme.Size.legendDot, height: Theme.Size.legendDot)
            .accessibilityHidden(true)
    }

    private var totalText: some View {
        Text(wholeMoney(pace.spent))
            .foregroundStyle(Theme.ink)
            .contentTransition(.numericText())
            .accessibilityLabel(money(pace.spent))
            .accessibilityIdentifier(carriesTotal ? "total-mes" : "llevas")
    }

    /// «Vas $400 abajo del ritmo»: what the days before today left over (or overspent), which
    /// today gets on top of its own amount. A plain sentence, only the judgement in color.
    private var verdict: some View {
        let carried = pace.carriedOver
        let (before, colored, after, good): (String, String, String, Bool) = {
            if isOver {
                return ("Te pasaste ", wholeMoney(pace.remaining.magnitude), " del presupuesto", false)
            }
            if !isCurrentMonth { return ("Cerraste con ", wholeMoney(pace.remaining), " de sobra", true) }
            if carried.magnitude >= 1 {
                return carried > 0 ? ("Vas ", "\(wholeMoney(carried)) abajo", " del ritmo", true)
                    : ("Vas ", "\(wholeMoney(-carried)) arriba", " del ritmo", false)
            }
            if pace.day == 1 { return ("Día 1 de \(pace.daysInMonth)", "", " · mes nuevo", true) }
            return ("Vas ", "justo", " al ritmo", true)
        }()
        return (Text(before).foregroundStyle(Theme.muted)
            + Text(colored).foregroundStyle(good ? Theme.good : Theme.danger)
            + Text(after).foregroundStyle(Theme.muted))
            .font(.ticket(.detail))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("veredicto")
    }

    /// The sum behind «Hoy puedes gastar», like a ticket's lines: what is left of the month,
    /// then the day's amount, what the days before left over or overspent, and today.
    private var sum: some View {
        VStack(spacing: Theme.Space.xs) {
            sumLine("Presupuesto", wholeMoney(pace.budget))
            sumLine("− Llevas", wholeMoney(pace.spent))
            sumLine(isOver ? "= Te pasaste" : "= Te quedan", wholeMoney(pace.remaining.magnitude))
            if days > 0, pace.mode == .spread {
                // «Repartir»: what was left when the day began, shared over the days left.
                Divider().overlay(Theme.hairline)
                sumLine("Presupuesto", wholeMoney(pace.budget))
                sumLine("− Llevas antes de hoy", wholeMoney(pace.spent - pace.variableToday))
                if pace.reserved > 0 {
                    sumLine("− Fijos por venir", wholeMoney(pace.reserved))
                }
                sumLine("÷ Días que faltan", "\(pace.daysLeft)")
                sumLine("= Para hoy", wholeMoney(pace.todayShare))
                if pace.variableToday != 0 {
                    sumLine(pace.variableToday > 0 ? "− Gastado hoy" : "+ Devuelto hoy",
                            wholeMoney(pace.variableToday.magnitude))
                }
                Divider().overlay(Theme.hairline)
                sumLine("= Hoy puedes gastar", wholeMoney(pace.dailyAllowance), strong: true)
            } else if days > 0 {
                Divider().overlay(Theme.hairline)
                if pace.fixedMonth > 0 {
                    sumLine("Presupuesto", wholeMoney(pace.budget))
                    sumLine("− Fijos del mes", wholeMoney(pace.fixedMonth))
                }
                sumLine("÷ Días del mes", "\(pace.daysInMonth)")
                sumLine("= Por día", wholeMoney(pace.dailyBase))
                if pace.day > 1 {
                    sumLine(pace.carriedOver >= 0 ? "+ Sobró de otros días" : "− Te pasaste otros días",
                            wholeMoney(pace.carriedOver.magnitude))
                }
                if pace.variableToday != 0 {
                    sumLine(pace.variableToday > 0 ? "− Gastado hoy" : "+ Devuelto hoy",
                            wholeMoney(pace.variableToday.magnitude))
                }
                Divider().overlay(Theme.hairline)
                sumLine(pace.isOverToday ? "= Hoy te pasaste" : "= Hoy puedes gastar",
                        wholeMoney(pace.dailyAllowance.magnitude), strong: true)
            }
            if outside != 0 {
                // Not part of the sum: what was spent but doesn't count, said apart.
                Divider().overlay(Theme.hairline)
                sumLine("Fuera del presupuesto", wholeMoney(outside))
                    .accessibilityIdentifier("fuera-del-presupuesto")
            }
        }
        .font(.ticket(.detail))
        .padding(Theme.Space.m)
        .ticketPanel()
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
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile)
        if isToday {
            shape
                .fill(Theme.brass.opacity(Theme.Opacity.glow))
                .overlay(shape.strokeBorder(Theme.brass, lineWidth: Theme.Stroke.emphasis))
                .phaseAnimator(animate ? [Theme.Opacity.tileBreath, Theme.Opacity.visible] : [Theme.Opacity.visible]) { tile, phase in
                    tile.opacity(phase)
                } animation: { _ in Theme.Motion.pulse }
        } else {
            shape.fill(Theme.raised)
        }
    }
}

/// Thin diagonal lines, like the shading on a printed form.
private struct Hatch: Shape {
    var spacing: CGFloat = Theme.Size.hatchSpacing

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
