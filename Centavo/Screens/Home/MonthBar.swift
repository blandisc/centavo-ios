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
    /// Remembers that the bar has drawn itself, so a rebuilt one is already drawn (`Entrance`).
    var entrance = Entrance()
    /// Without its track (owner, 2026-10-30): the days are drawn by the boleto in the carousel, and
    /// this is the one line that stays while it swaps with the calendar: «Llevas $X y deberías llevar
    /// $Y de $Z», and under it the tear line that opens the sum (owner, 2026-11-08: P1).
    var showsTrack = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var trackHeight: CGFloat = Theme.Size.monthBarTrack
    @State private var measuredWidth: CGFloat = Theme.Space.none
    @State private var drawn = false
    @State private var showsSum = false

    /// Whether the bar has been measured yet.
    private var hasWidth: Bool { width > 0 }
    private var width: CGFloat { measuredWidth > Theme.Space.none ? measuredWidth : entrance.barWidth }
    /// Drawn: this view's entrance has played, or the app's has (a rebuilt bar starts drawn).
    private var shown: Bool { drawn || entrance.barShown }
    /// The same rule as the hero, the widgets and Siri: fixed expenses past the budget, charged,
    /// are not «te pasaste» (independent review).
    private var isOver: Bool { pace.isOverspent }
    private var days: Int { isCurrentMonth && !isOver ? min(max(pace.daysLeft, 1), 31) : 0 }

    /// Past the budget, how much of what went the budget was (where the red starts).
    private var overFraction: CGFloat {
        guard pace.spent > 0 else { return 0 }
        return CGFloat(min(max(NSDecimalNumber(decimal: pace.budget / pace.spent).doubleValue, 0), 1))
    }

    private func fraction(_ part: Decimal) -> CGFloat {
        guard pace.budget > 0 else { return 0 }
        return CGFloat(min(max(NSDecimalNumber(decimal: part / pace.budget).doubleValue, 0), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            // Right under «Hoy puedes gastar», the one sentence that judges the month. With
            // «Acumular» there is none (the figure already says it) and the bar moves up into
            // its place; choosing «Repartir» unfolds it from under the figure.
            if let line = verdictLine {
                verdict(line)
                    .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
                    .animation(reduceMotion ? nil : Theme.Motion.Entrance.legend, value: shown)
                    // Over the track it leaves room for the bar's label; over «Llevas» it sits a
                    // little closer, one sentence after another (owner, 2026-11-08).
                    .padding(.bottom, isCurrentMonth && showsTrack ? Theme.Space.l : Theme.Space.s)
                    // It fades in place: sliding down from the top it crossed the figure above it.
                    .transition(.opacity)
            }

            if showsTrack {
                Button {
                    withAnimation(reduceMotion ? nil : Theme.Motion.fold) { showsSum.toggle() }
                } label: {
                    bar
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: showsSum)
                .accessibilityHint(showsSum ? "Oculta la cuenta" : "Muestra la cuenta")
                .accessibilityIdentifier("barra-del-mes")
            }

            if showsTrack {
                keysButton
            } else {
                // Without the track, the line only says; the tear line under it opens the sum, and
                // the sum unfolds from there (owner's choice P1, 2026-11-08).
                spentKey
                    .font(.ticket(.detail))
                tearLine
            }


            if showsSum {
                // It comes out from under the tear line like a receipt while the page grows, and
                // slides back under it as it closes (owner, 2026-11-08; before, a 3D flap).
                sum
                    .padding(.top, Theme.Space.s)
                    .transition(.printOut)
            }
        }
        // Without the sentence the bar would sit flush under the figure; without the track the line
        // sits right under the boleto.
        .padding(.top, verdictLine == nil && showsTrack ? Theme.Space.s : Theme.Space.none)
        .animation(reduceMotion ? nil : Theme.Motion.toggle, value: verdictLine == nil)
        .onAppear {
            if reduceMotion { drawn = true } else { withAnimation { drawn = true } }
        }
        // Only once it is drawn: setting it sooner would skip the entrance on a re-render.
        .onChange(of: drawn) { _, isDrawn in
            if isDrawn { entrance.barShown = true }
        }
    }

    /// The keys under the track: each figure where what it measures is, and the whole line opens the sum.
    private var keysButton: some View {
        // Each figure where what it measures is: «Llevas» under the brass, «Presupuesto» at
        // the bar's end, «Podrías llevar» over the rule (owner's choice, 2026-10-22).
        // The whole line opens the sum too, 44 pt tall: the chevron alone was too small a
        // target and was not even the button (owner, 2026-10-29).
        Button {
            withAnimation(reduceMotion ? nil : Theme.Motion.fold) { showsSum.toggle() }
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { spentKey; Spacer(minLength: Theme.Space.s); budgetKey }
                // «Ver cuenta» under the sentence, still at the end it opens from.
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    spentKey
                    HStack { Spacer(minLength: Theme.Space.none); budgetKey }
                }
            }
            .font(.ticket(.detail))
            .frame(minHeight: Theme.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -Theme.Space.ml)
        .accessibilityLabel(showsSum ? "Ocultar cuenta" : "Ver cuenta")
        .accessibilityIdentifier("ver-cuenta")
    }

    /// The boleto's tear line: dots edge to edge and «cuenta» in the middle, the one place the
    /// sum opens from when there is no track (owner's choice P1, 2026-11-08). 44 pt tall.
    private var tearLine: some View {
        Button {
            withAnimation(reduceMotion ? nil : Theme.Motion.fold) { showsSum.toggle() }
        } label: {
            HStack(spacing: Theme.Space.m) {
                Perforation(tear: true)
                HStack(spacing: Theme.Space.xs) {
                    Text("cuenta").foregroundStyle(Theme.brass)
                    Image(systemName: "chevron.down")
                        .foregroundStyle(Theme.faint)
                        .rotationEffect(.degrees(showsSum ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .font(.ticket(.detail))
                .fixedSize()
                Perforation(tear: true)
            }
            .frame(minHeight: Theme.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: showsSum)
        .accessibilityLabel(showsSum ? "Ocultar cuenta" : "Ver cuenta")
        .accessibilityIdentifier("ver-cuenta")
    }

    // MARK: The bar

    private var bar: some View {
        // Past the budget the whole bar is what went: brass up to the budget, red beyond it.
        let budgetW = isOver ? width * overFraction : 0
        let spentW = width * (isOver ? 1 : fraction(pace.spent))
        let reservedW = isCurrentMonth && !isOver ? width * fraction(pace.reserved) : 0
        // «Podrías llevar»: the fixed expenses already charged plus every day's amount so far.
        let markX = isOver ? budgetW : width * fraction(pace.expectedToDate)

        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            if isCurrentMonth, !isOver {
                annotation(at: markX)
            }
            Color.clear
                .frame(height: trackHeight)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                    measuredWidth = $0
                    entrance.barWidth = $0
                }
                .overlay(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        // The days still empty.
                        Rectangle().fill(Theme.raised)
                        HStack(spacing: Theme.Space.none) {
                            // What went: grows in from nothing and settles, no bounce.
                            if isOver {
                                Rectangle()
                                    .fill(Theme.brass)
                                    .frame(width: shown ? budgetW : Theme.Space.none)
                                    .animation(reduceMotion ? nil : Theme.Motion.Entrance.fill, value: shown)
                            }
                            Rectangle()
                                .fill(isOver ? Theme.danger : Theme.brass)
                                .frame(width: shown ? (isOver ? width - budgetW : spentW) : Theme.Space.none)
                                .animation(reduceMotion ? nil : Theme.Motion.Entrance.fill, value: shown)
                                .animation(reduceMotion ? nil : Theme.Motion.Entrance.refill, value: spentW)
                            // The fixed expenses still to come, set apart.
                            if reservedW > 0 {
                                Rectangle()
                                    .fill(Theme.brassLow)
                                    .frame(width: reservedW)
                                    .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
                                    .animation(reduceMotion ? nil : Theme.Motion.Entrance.markers, value: shown)
                            }
                        }
                    }
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
                // The month by days (owner's choice, 2026-10-29): the bar is cut into one cell per
                // day of the month, like a perforated ticket, and what went fills them.
                .mask(alignment: .leading) { DayCells(count: pace.daysInMonth, height: trackHeight) }
                .overlay(alignment: .leading) {
                    if isCurrentMonth, !isOver, width > 0 {
                        // Today's cell, outlined.
                        let cell = DayCells.cellWidth(in: width, count: pace.daysInMonth)
                        let daysBefore = CGFloat(max(pace.day - 1, Int.zero))
                        RoundedRectangle(cornerRadius: Theme.Radius.bar)
                            .strokeBorder(Theme.ink, lineWidth: Theme.Stroke.hairline)
                            .frame(width: cell, height: trackHeight)
                            .offset(x: daysBefore * (cell + Theme.Size.monthBarCellGap))
                            .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
                            .animation(reduceMotion ? nil : Theme.Motion.Entrance.today, value: shown)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .leading) {
                    if isCurrentMonth || isOver {
                        // Where an even month would be by today, reaching up to «Podrías llevar»;
                        // past the budget, where it ended, centered on the bar (nothing above).
                        Capsule()
                            .fill(Theme.ink)
                            .frame(width: Theme.Size.todayMarkWidth, height: trackHeight + Theme.Size.todayMarkExtra)
                            .offset(x: markX - Theme.Size.todayMarkHalf,
                                    y: isOver ? Theme.Space.none : -Theme.Size.todayMarkInset)
                            .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
                            .animation(reduceMotion ? nil : Theme.Motion.Entrance.today, value: shown)
                    }
                }
        }
        .contentShape(Rectangle())
    }

    /// «PODRÍAS LLEVAR $3,871», printed over its rule like a note on a ticket, kept inside the bar.
    /// Past the rule it is «Deberías llevar»: it is no longer room to spend.
    private func annotation(at x: CGFloat) -> some View {
        (Text(pace.isAheadOfPace ? "Deberías llevar " : "Podrías llevar ").foregroundStyle(Theme.muted)
            + Text(wholeMoney(pace.expectedShown)).foregroundStyle(Theme.ink))
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

    /// Without the track, this month and within the budget, the line says where the month should
    /// be by now, the figure the bar's rule used to carry (owner's choice B2, 2026-11-04).
    private var showsExpected: Bool { !showsTrack && isCurrentMonth && !isOver }

    /// Its pieces wrap to a second line when they don't fit (the largest text sizes): kept on
    /// one line, it pushed the whole page past the screen's edge. With `showsExpected`, «Llevas
    /// $3,000 y deberías llevar $2,600 de $8,000» in one line: «podrías» while under it, where it is
    /// room to spend and not a goal (owner's choices B2 and C1, 2026-11-04).
    private var spentKey: some View {
        WrapLayout(spacing: Theme.Space.xs) {
            if showsTrack { swatch(isOver ? Theme.danger : Theme.brass) }
            Text("Llevas").foregroundStyle(Theme.muted)
            totalText
            if showsExpected {
                Text(pace.isAheadOfPace ? "y deberías llevar" : "y podrías llevar").foregroundStyle(Theme.muted)
                Text(wholeMoney(pace.expectedShown))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            // Past it, the budget goes right after what went: «Llevas $2,366 de $2,000». Without
            // the track there is no bar's end to carry it, so it always does.
            if isOver || !showsTrack {
                Text("de").foregroundStyle(Theme.muted)
                Text(wholeMoney(pace.sum.budget)).foregroundStyle(Theme.ink)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// «Presupuesto $8,000», at the end of the bar it measures; past it, «· de más $366».
    private var budgetKeyText: Text {
        // Past it the hero already says how far («Te pasaste $366»), and «Llevas» carries the
        // budget: this end only opens the sum.
        if isOver { return Text(showsSum ? "Ocultar cuenta" : "Ver cuenta").foregroundStyle(Theme.brass) }
        return Text("Presupuesto ").foregroundStyle(Theme.muted)
            + Text(wholeMoney(pace.sum.budget)).foregroundStyle(Theme.ink)
    }

    /// «Presupuesto $8,000», at the end of the bar it measures.
    private var budgetKey: some View {
        HStack(spacing: Theme.Space.xs) {
            budgetKeyText
                .lineLimit(1)
                .minimumScaleFactor(Theme.MinimumScale.figure)
            // Says the bar opens the sum; it turns with it instead of swapping.
            Image(systemName: "chevron.down")
                .foregroundStyle(Theme.faint)
                .rotationEffect(.degrees(showsSum ? 180 : 0))
                .accessibilityHidden(true)
        }
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
        Text(wholeMoney(pace.spentShown))
            // Red past the budget when it stands alone, with no red bar beside it.
            .foregroundStyle(!showsTrack && isOver ? Theme.danger : Theme.ink)
            .contentTransition(.numericText())
            .accessibilityLabel(money(pace.spent))
            .accessibilityIdentifier(carriesTotal ? "total-mes" : "llevas")
    }

    /// The sentence under the figure, in three pieces (only the judgement in color), or `nil`
    /// when there is nothing the figure does not already say.
    private typealias Line = (before: String, colored: String, after: String, good: Bool)

    /// «Te pasaste $X del presupuesto», «Cerraste con $X de sobra» and, with «Repartir», «Vas
    /// $400 abajo del ritmo»: how far from the rule, the same gap the bar shows. With
    /// «Acumular», «Hoy puedes gastar» already is that gap, so no sentence (alternative C).
    private var verdictLine: Line? {
        // This month the hero already says it in big red figures; the bar shows where.
        if isOver { return isCurrentMonth ? nil : ("Te pasaste ", wholeMoney(pace.overspentShown), " del presupuesto", false) }
        if !isCurrentMonth { return ("Cerraste con ", wholeMoney(pace.sum.remaining), " de sobra", true) }
        guard pace.rhythm != nil else { return nil }
        let rhythm = pace.gapShown
        if rhythm == 0 { return ("Vas ", "justo", " al ritmo", true) }
        return rhythm > 0 ? ("Vas ", "\(wholeMoney(rhythm)) abajo", " del ritmo", true)
            : ("Vas ", "\(wholeMoney(-rhythm)) arriba", " del ritmo", false)
    }

    /// What went a day on average so far, after the rhythm: «· $711/día» (owner's choice B1,
    /// 2026-11-08). Only with the rhythm, the sentence it is measured against.
    private var averageText: Text? {
        guard isCurrentMonth, !isOver, pace.rhythm != nil else { return nil }
        return Text(" · ").foregroundStyle(Theme.brass)
            + Text(wholeMoney(pace.spent / Decimal(max(pace.day, 1)))).foregroundStyle(Theme.ink)
            + Text("/día").foregroundStyle(Theme.muted)
    }

    private func verdict(_ line: Line) -> some View {
        (Text(line.before).foregroundStyle(Theme.muted)
            + Text(line.colored).foregroundStyle(line.good ? Theme.good : Theme.danger)
            + Text(line.after).foregroundStyle(Theme.muted)
            + (averageText ?? Text(verbatim: "")))
            .font(.ticket(.detail))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("veredicto")
    }

    /// The sum behind «Hoy puedes gastar», like a ticket's lines: what is left of the month,
    /// then the day's amount, what the days before left over or overspent, and today.
    private var sum: some View {
        let sum = pace.sum
        return VStack(spacing: Theme.Space.xs) {
            sumLine("Presupuesto", wholeMoney(sum.budget))
            sumLine("− Llevas", wholeMoney(sum.spent))
            sumLine(sum.remaining < 0 ? "= Te pasaste" : "= Te quedan", wholeMoney(sum.remaining.magnitude))
            if days > 0, let excess = pace.fixedOverBudgetShown {
                // Fixed expenses past the budget: nothing to cut into days (second audit).
                Perforation(tear: !showsTrack)
                sumLine("Presupuesto", wholeMoney(sum.budget))
                // Whole, so the lines subtract to the peso: the fixed ones are the budget plus
                // the excess, rounded up like it (independent review).
                sumLine("− Fijos del mes", wholeMoney(sum.budget + excess))
                sumLine(excess > 0 ? "= Tus fijos pasan por" : "= Para los días", wholeMoney(excess), strong: true)
            } else if days > 0, pace.mode == .spread {
                // «Repartir»: what was left when the day began, shared over the days left.
                Perforation(tear: !showsTrack)
                sumLine("Presupuesto", wholeMoney(sum.budget))
                sumLine("− Llevas antes de hoy", wholeMoney(sum.spentBeforeToday))
                if pace.reserved > 0 {
                    sumLine("− Fijos por venir", wholeMoney(pace.reserved))
                }
                sumLine("÷ Días que faltan", "\(pace.daysLeft)")
                sumLine("= Para hoy", wholeMoney(sum.forToday))
                if sum.variableToday != 0 {
                    sumLine(sum.variableToday > 0 ? "− Gastado hoy" : "+ Devuelto hoy",
                            wholeMoney(sum.variableToday.magnitude))
                }
                Perforation(tear: !showsTrack)
                sumLine("= Hoy puedes gastar", wholeMoney(pace.dailyAllowance), strong: true)
            } else if days > 0 {
                Perforation(tear: !showsTrack)
                if pace.fixedMonth > 0 {
                    sumLine("Presupuesto", wholeMoney(sum.budget))
                    sumLine("− Fijos del mes", wholeMoney(pace.fixedMonth))
                }
                sumLine("÷ Días del mes", "\(pace.daysInMonth)")
                sumLine("= Por día", wholeMoney(sum.perDay))
                if pace.day > 1 {
                    sumLine(sum.carriedOver >= 0 ? "+ Sobró de otros días" : "− Te pasaste otros días",
                            wholeMoney(sum.carriedOver.magnitude))
                }
                if sum.variableToday != 0 {
                    sumLine(sum.variableToday > 0 ? "− Gastado hoy" : "+ Devuelto hoy",
                            wholeMoney(sum.variableToday.magnitude))
                }
                Perforation(tear: !showsTrack)
                sumLine(pace.isOverToday ? "= Hoy te pasaste" : "= Hoy puedes gastar",
                        wholeMoney(pace.dailyAllowance.magnitude), strong: true)
            }
            if outside != 0 {
                // Not part of the sum: what was spent but doesn't count, said apart.
                Perforation(tear: !showsTrack)
                sumLine("Fuera del presupuesto", wholeMoney(outside))
                    .accessibilityIdentifier("fuera-del-presupuesto")
            }
        }
        .font(.ticket(.detail))
        // Under the tear line it is the same paper, torn open: no panel, only its dots (P1).
        .padding(showsTrack ? Theme.Space.m : Theme.Space.none)
        .background {
            if showsTrack { RoundedRectangle(cornerRadius: Theme.Radius.panel).fill(Theme.surface) }
        }
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

/// One cell per day of the month, the shape the month bar is cut to.
private struct DayCells: View {
    let count: Int
    let height: CGFloat

    static func cellWidth(in width: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return width }
        return max((width - Theme.Size.monthBarCellGap * CGFloat(count - 1)) / CGFloat(count), Theme.Space.none)
    }

    var body: some View {
        HStack(spacing: Theme.Size.monthBarCellGap) {
            ForEach(0..<max(count, 1), id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.Radius.bar).frame(height: height)
            }
        }
    }
}

/// Thin diagonal lines, like the shading on a printed form.
struct Hatch: Shape {
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
