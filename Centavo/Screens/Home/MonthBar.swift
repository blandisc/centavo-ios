import CentavoCore
import SwiftUI

/// The month's line under the boleto, and the sum behind «Hoy puedes gastar».
///
/// The days are the boleto's (`MonthCodeView`, owner 2026-10-30); this is what stays with it: the
/// one sentence that judges the month («Vas $400 abajo del ritmo»), «Llevas $X de $Y» once the
/// month is over or past its budget, and the tear line «cuenta», which opens the sum (owner,
/// 2026-11-08: P1). The bar with a track it once drew went with the last state that showed it,
/// a budget with nothing spent (owner, 2026-11-11).
struct MonthBar: View {
    let pace: BudgetPace
    let isCurrentMonth: Bool
    /// "$2,366.00", as the rest of the app writes it.
    let money: (Decimal) -> String
    /// "$4,903", for marks.
    let wholeMoney: (Decimal) -> String
    /// What was left out of the budget («No cuenta»), shown under the sum so nothing goes
    /// missing without a word. Zero shows nothing.
    var outside: Decimal = 0
    /// Remembers that the line has come in, so a rebuilt one is already there (`Entrance`).
    var entrance = Entrance()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    @State private var showsSum = false

    /// Drawn: this view's entrance has played, or the app's has (a rebuilt line starts drawn).
    private var shown: Bool { drawn || entrance.barShown }
    /// The same rule as the hero, the widgets and Siri: fixed expenses past the budget, charged,
    /// are not «te pasaste» (independent review).
    private var isOver: Bool { pace.isOverspent }
    private var days: Int { isCurrentMonth && !isOver ? min(max(pace.daysLeft, 1), 31) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            // Right under the boleto, the one sentence that judges the month. With «Acumular»
            // there is none (the figure already says it); choosing «Repartir» fades it in.
            if let line = verdictLine {
                verdict(line)
                    .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
                    .animation(reduceMotion ? nil : Theme.Motion.Entrance.codeLine, value: shown)
                    // Right over the tear line it sits close, the line's own height is room
                    // enough (owner, 2026-11-08).
                    .padding(.bottom, showsExpected ? Theme.Space.none : Theme.Space.s)
                    // It fades in place: sliding down from the top it crossed the figure above it.
                    .transition(.opacity)
            }

            // The line only says; the tear line under it opens the sum, and the sum unfolds from
            // there (owner's choice P1, 2026-11-08). Within the budget this month «Llevas $X y
            // podrías llevar $Y de $Z» lives in the sum (L3, same day).
            if !showsExpected {
                spentKey
                    .font(.ticket(.detail))
            }
            tearLine

            if showsSum {
                // It comes out from under the tear line like a receipt while the page grows, and
                // slides back under it as it closes (owner, 2026-11-08; before, a 3D flap).
                sum
                    .padding(.top, Theme.Space.s)
                    .transition(.printOut)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.toggle, value: verdictLine == nil)
        .onAppear {
            if reduceMotion { drawn = true } else { withAnimation { drawn = true } }
        }
        // Only once it is drawn: setting it sooner would skip the entrance on a re-render.
        .onChange(of: drawn) { _, isDrawn in
            if isDrawn { entrance.barShown = true }
        }
    }

    /// The boleto's tear line: dots edge to edge and «cuenta» in the middle, the one place the
    /// sum opens from (owner's choice P1, 2026-11-08). 44 pt tall.
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
        // The 44 pt target reaches into the gaps over and under it, so the line sits close to the
        // sentence and to «En qué se va» (owner, 2026-11-08).
        .padding(.top, -Theme.Space.s)
        .padding(.bottom, -Theme.Space.m)
        .sensoryFeedback(.selection, trigger: showsSum)
        .accessibilityLabel(showsSum ? "Ocultar cuenta" : "Ver cuenta")
        .accessibilityIdentifier("ver-cuenta")
    }

    // MARK: Words

    /// This month and within the budget: no line under the rhythm, and the sum opens with the
    /// rhythm's own account, where the month should be by now (L3, 2026-11-08).
    private var showsExpected: Bool { isCurrentMonth && !isOver }

    /// Its pieces wrap to a second line when they don't fit (the largest text sizes): kept on
    /// one line, it pushed the whole page past the screen's edge.
    private var spentKey: some View {
        WrapLayout(spacing: Theme.Space.xs) {
            Text("Llevas").foregroundStyle(Theme.muted)
            totalText
            // The budget goes right after what went: «Llevas $2,366 de $2,000».
            Text("de").foregroundStyle(Theme.muted)
            Text(wholeMoney(pace.sum.budget)).foregroundStyle(Theme.ink)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var totalText: some View {
        Text(wholeMoney(pace.spentShown))
            // Red past the budget: it stands alone, with no red bar beside it.
            .foregroundStyle(isOver ? Theme.danger : Theme.ink)
            .contentTransition(.numericText())
            .accessibilityLabel(money(pace.spent))
            // Never the screen's own total: it only shows past the budget or in a month that is
            // over, where the hero has its own figure.
            .accessibilityIdentifier("llevas")
    }

    /// The sentence under the figure, in three pieces (only the judgement in color), or `nil`
    /// when there is nothing the figure does not already say.
    private typealias Line = (before: String, colored: String, after: String, good: Bool)

    /// «Te pasaste $X del presupuesto», «Cerraste con $X de sobra» and, with «Repartir», «Vas
    /// $400 abajo del ritmo»: how far from where an even month would be by today. With
    /// «Acumular», «Hoy puedes gastar» already is that gap, so no sentence (alternative C).
    private var verdictLine: Line? {
        // This month the hero already says it in big red figures.
        if isOver { return isCurrentMonth ? nil : ("Te pasaste ", wholeMoney(pace.overspentShown), " del presupuesto", false) }
        if !isCurrentMonth { return ("Cerraste con ", wholeMoney(pace.sum.remaining), " de sobra", true) }
        guard pace.rhythm != nil else { return nil }
        let rhythm = pace.gapShown
        if rhythm == 0 { return ("Vas ", "justo", " al ritmo", true) }
        return rhythm > 0 ? ("Vas ", "\(wholeMoney(rhythm)) abajo", " del ritmo", true)
            : ("Vas ", "\(wholeMoney(-rhythm)) arriba", " del ritmo", false)
    }

    private func verdict(_ line: Line) -> some View {
        (Text(line.before).foregroundStyle(Theme.muted)
            + Text(line.colored).foregroundStyle(line.good ? Theme.good : Theme.danger)
            + Text(line.after).foregroundStyle(Theme.muted))
            .font(.ticket(.detail))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("veredicto")
    }

    /// The sum behind «Hoy puedes gastar», like a ticket's lines: what is left of the month,
    /// then the day's amount, what the days before left over or overspent, and today.
    private var sum: some View {
        let sum = pace.sum
        // With «Repartir» the day's block starts from the budget and what went: the first block
        // would say it twice right above it (L3).
        let opensWithBudget = !(showsExpected && days > 0 && pace.fixedOverBudgetShown == nil && pace.mode == .spread)
        return VStack(spacing: Theme.Space.xs) {
            if showsExpected {
                // Where «Vas $665 abajo del ritmo» comes from, then where today's figure does (L3).
                sumHeading("El ritmo")
                sumLine(pace.isAheadOfPace ? "A hoy deberías llevar" : "A hoy podrías llevar", wholeMoney(pace.expectedShown))
                sumLine("− Llevas", wholeMoney(pace.spentShown))
                sumLine(pace.gapShown > 0 ? "= Vas abajo del ritmo" : pace.gapShown < 0 ? "= Vas arriba del ritmo" : "= Vas justo al ritmo",
                        wholeMoney(pace.gapShown.magnitude), tint: pace.gapShown < 0 ? Theme.danger : Theme.good)
                Perforation(tear: true)
                sumHeading("Hoy")
            }
            if opensWithBudget {
                sumLine("Presupuesto", wholeMoney(sum.budget))
                sumLine("− Llevas", wholeMoney(sum.spent))
                sumLine(sum.remaining < 0 ? "= Te pasaste" : "= Te quedan", wholeMoney(sum.remaining.magnitude))
            }
            if days > 0, let excess = pace.fixedOverBudgetShown {
                // Fixed expenses past the budget: nothing to cut into days (second audit).
                Perforation(tear: true)
                sumLine("Presupuesto", wholeMoney(sum.budget))
                // Whole, so the lines subtract to the peso: the fixed ones are the budget plus
                // the excess, rounded up like it (independent review).
                sumLine("− Fijos del mes", wholeMoney(sum.budget + excess))
                sumLine(excess > 0 ? "= Tus fijos pasan por" : "= Para los días", wholeMoney(excess), strong: true)
            } else if days > 0, pace.mode == .spread {
                // «Repartir»: what was left when the day began, shared over the days left.
                if opensWithBudget { Perforation(tear: true) }
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
                Perforation(tear: true)
                sumLine("= Hoy puedes gastar", wholeMoney(pace.dailyAllowance), strong: true)
            } else if days > 0 {
                Perforation(tear: true)
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
                Perforation(tear: true)
                sumLine(pace.isOverToday ? "= Hoy te pasaste" : "= Hoy puedes gastar",
                        wholeMoney(pace.dailyAllowance.magnitude), strong: true)
            }
            if outside != 0 {
                // Not part of the sum: what was spent but doesn't count, said apart.
                Perforation(tear: true)
                sumLine("Fuera del presupuesto", wholeMoney(outside))
                    .accessibilityIdentifier("fuera-del-presupuesto")
            }
        }
        .font(.ticket(.detail))
        // Under the tear line it is the same paper, torn open: no panel, only its dots (P1).
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("la-cuenta")
    }

    private func sumLine(_ label: String, _ value: String, strong: Bool = false, tint: Color? = nil) -> some View {
        HStack {
            Text(label).foregroundStyle(strong ? Theme.brass : Theme.muted)
            Spacer()
            Text(value).foregroundStyle(tint ?? (strong ? Theme.brass : Theme.ink)).monospacedDigit()
        }
        .fontWeight(strong ? .semibold : .regular)
    }

    /// «EL RITMO», «HOY»: the two accounts in the sum, named like the page's block captions.
    private func sumHeading(_ title: String) -> some View {
        Text(title)
            .ticketKey(Theme.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
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
