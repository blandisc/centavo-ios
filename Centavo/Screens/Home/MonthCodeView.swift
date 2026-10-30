import CentavoCore
import SwiftUI

/// The month as a ticket's barcode, under the budget bar (owner's choice, 2026-10-29): one bar
/// per day, as tall as what went that day. Brass, a day with a fixed charge; red, a day past what
/// a day may spend; today breathes; the days to come are blank. Now and then a scanner's light
/// crosses it, the one thing on the screen that moves by itself.
///
/// A finger on it reads the day under it in a card above (what went, how many payments, the
/// biggest, against the day's limit), with a tick at each new day; let go on a day and the list
/// shows only that day, the same as tapping it in the calendar. Under it, where a barcode prints
/// its digits, the month's: payments, the average a day and the limit a day.
struct MonthCodeView: View {
    let code: MonthCode
    let selectedDay: Int?
    let onSelectDay: (Int?) -> Void
    /// "$846": whole money in the month's currency.
    let wholeMoney: (Decimal) -> String
    /// The viewed month, to name a day («MIÉ 28 OCT»).
    let month: Date
    /// The screen's entrance: the code comes in after the bar has drawn itself, the way its
    /// legend does, and not again when the row is rebuilt.
    var entrance = Entrance()

    @State private var drawn = false
    private var shown: Bool { drawn || entrance.barShown }

    @State private var touched: Int?
    /// Where the scanner's light is (0 at the left edge, 1 at the right) and whether it shows.
    @State private var scanned = false
    @State private var scanLit = false
    @State private var breathing = false
    @State private var width = Theme.Space.none
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var height = Theme.Size.monthCode

    private var shownDay: Int? { touched ?? selectedDay }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            bars
                .frame(height: height)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .overlay(alignment: .leading) { scanner }
                .overlay(alignment: .bottomLeading) { card }
                .contentShape(Rectangle())
                .gesture(scrub)
                .sensoryFeedback(.selection, trigger: touched) { _, new in new != nil }
            digits
        }
        .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
        .onAppear {
            guard !drawn else { return }
            withAnimation(reduceMotion ? nil : Theme.Motion.Entrance.legend) { drawn = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gasto de cada día")
        .accessibilityValue(spoken(shownDay ?? code.days.last { $0.kind == .today }?.number ?? code.days.count))
        .accessibilityAdjustableAction { direction in
            let current = shownDay ?? code.days.count
            let next = direction == .increment ? min(current + 1, code.days.count) : max(current - 1, 1)
            onSelectDay(next)
        }
        .accessibilityIdentifier("codigo-del-mes")
        .task(id: reduceMotion) { await scanNowAndThen() }
        .onAppear { breathing = !reduceMotion }
    }

    // MARK: The bars

    private var bars: some View {
        HStack(alignment: .bottom, spacing: Theme.Size.monthCodeGap) {
            ForEach(code.days, id: \.number) { day in
                RoundedRectangle(cornerRadius: Theme.Radius.bar)
                    .fill(color(day))
                    .opacity(opacity(day))
                    .frame(maxWidth: .infinity)
                    .frame(height: height * barHeight(day))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .animation(Theme.Motion.animation(Theme.Motion.select, reduceMotion: reduceMotion), value: shownDay)
    }

    private func barHeight(_ day: MonthCode.Day) -> CGFloat {
        // A day still to come keeps a short blank stub, like the end of a code.
        day.kind == .future ? Theme.Size.monthCodeFloor * 2
            : Theme.Size.monthCodeFloor + (1 - Theme.Size.monthCodeFloor) * day.height
    }

    private func color(_ day: MonthCode.Day) -> Color {
        switch day.kind {
        case .fixed: Theme.brass
        case .over: Theme.danger
        case .future: Theme.raised
        case .today, .plain: Theme.ink
        }
    }

    private func opacity(_ day: MonthCode.Day) -> Double {
        if day.kind == .future { return Theme.Opacity.visible }
        if let shownDay { return day.number == shownDay ? Theme.Opacity.visible : Theme.Opacity.codeBarAside }
        switch day.kind {
        case .today: return breathing ? Theme.Opacity.paceBehind : Theme.Opacity.visible
        case .plain: return Theme.Opacity.codeBar
        default: return Theme.Opacity.visible
        }
    }

    // MARK: The scanner

    @ViewBuilder private var scanner: some View {
        if !reduceMotion, shownDay == nil {
            Rectangle()
                .fill(Theme.danger)
                .frame(width: Theme.Size.monthCodeScan)
                .shadow(color: Theme.danger, radius: Theme.Size.monthCodeGlow)
                .offset(x: scanned ? max(width - Theme.Size.monthCodeScan, Theme.Space.none) : Theme.Space.none)
                .opacity(scanLit ? Theme.Opacity.visible : Theme.Opacity.hidden)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Every few seconds the light crosses once, left to right, then is gone until the next time.
    private func scanNowAndThen() async {
        guard !reduceMotion else { breathing = false; return }
        withAnimation(Theme.Motion.todayBreath) { breathing = true }
        while !Task.isCancelled {
            try? await Task.sleep(for: Theme.Motion.scanEvery)
            guard !Task.isCancelled else { return }
            // It lights up as it sets off, crosses, and fades out at the far edge before going back.
            withAnimation(Theme.Motion.select) { scanLit = true }
            withAnimation(Theme.Motion.scan) { scanned = true }
            try? await Task.sleep(for: Theme.Motion.scanShown)
            withAnimation(Theme.Motion.settle) { scanLit = false }
            try? await Task.sleep(for: Theme.Motion.scanFade)
            Theme.Motion.instantly { scanned = false }
        }
    }

    // MARK: The finger

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in touched = day(at: value.location.x) }
            .onEnded { value in
                let day = day(at: value.location.x)
                touched = nil
                guard let day, code.days[day - 1].kind != .future else { return }
                onSelectDay(selectedDay == day ? nil : day)
            }
    }

    private func day(at x: CGFloat) -> Int? {
        guard width > 0, !code.days.isEmpty else { return nil }
        let index = Int((min(max(x, 0), width - 1) / width) * CGFloat(code.days.count))
        return min(index, code.days.count - 1) + 1
    }

    /// The card over the day under the finger, kept inside the code's width.
    @ViewBuilder private var card: some View {
        if let touched, let day = code.days.first(where: { $0.number == touched }) {
            let center = width * (CGFloat(touched) - 0.5) / CGFloat(max(code.days.count, 1))
            let half = Theme.Size.monthCodeCard / 2
            let left = min(max(center - half, Theme.Space.none), max(width - Theme.Size.monthCodeCard, Theme.Space.none))
            DayCard(day: day, title: title(touched), limit: code.limitPerDay, wholeMoney: wholeMoney)
                .frame(width: Theme.Size.monthCodeCard, alignment: .leading)
                .offset(x: left, y: -(height + Theme.Space.s))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func title(_ number: Int) -> String {
        var parts = Calendar.current.dateComponents([.year, .month], from: month)
        parts.day = number
        let date = Calendar.current.date(from: parts) ?? month
        let text = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            .locale(Locale(identifier: "es_MX")))
        let isToday = code.days[number - 1].kind == .today
        return (isToday ? "Hoy · " : "") + text.replacingOccurrences(of: ".", with: "")
    }

    // MARK: The digits

    private var digits: some View {
        HStack(spacing: Theme.Space.xs) {
            digit("\(code.payments)", code.payments == 1 ? "pago" : "pagos")
            if let average = code.averagePerDay {
                Separator()
                digit(wholeMoney(average), "promedio/día", valueFirst: false)
            }
            if let limit = code.limitPerDay {
                Separator()
                digit(wholeMoney(max(limit, 0)), "tope/día", valueFirst: false)
            } else if code.hasNoMargin {
                // The fixed charges take the whole budget: no «tope $0», which read as broken.
                Separator()
                Text("sin margen").foregroundStyle(Theme.danger)
            }
        }
        .font(.ticket(.micro))
        .tracking(Theme.Tracking.tag)
        .textCase(.uppercase)
        .foregroundStyle(Theme.faint)
        .lineLimit(1)
        .minimumScaleFactor(Theme.MinimumScale.figure)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func digit(_ value: String, _ label: String, valueFirst: Bool = true) -> some View {
        let figure = Text(value).foregroundStyle(Theme.ink)
        return valueFirst ? Text("\(figure) \(label)") : Text("\(label.replacingOccurrences(of: "/día", with: "")) \(figure)/día")
    }

    private func spoken(_ number: Int) -> String {
        guard number >= 1, number <= code.days.count else { return "" }
        let day = code.days[number - 1]
        if day.kind == .future { return "\(number): todavía no llega" }
        let amount = wholeMoney(day.input.total)
        let payments = day.input.payments == 1 ? "1 pago" : "\(day.input.payments) pagos"
        return "\(title(number)): \(amount), \(payments)"
    }
}

/// The brass dot between two figures, like the ones in the list.
struct Separator: View {
    var body: some View {
        Text("·").foregroundStyle(Theme.brass).accessibilityHidden(true)
    }
}

/// One day under the finger: what went, how many payments, the biggest, and against the limit.
private struct DayCard: View {
    let day: MonthCode.Day
    let title: String
    let limit: Decimal?
    let wholeMoney: (Decimal) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
            Text(title)
                .font(.ticket(.microStrong))
                .tracking(Theme.Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(Theme.brass)
            if day.kind == .future {
                Text("Todavía no llega.").font(.ticket(.detail)).foregroundStyle(Theme.muted)
            } else if day.input.payments == 0 {
                Text(wholeMoney(0)).font(.ticket(.headline)).foregroundStyle(Theme.ink)
                Text("Día sin gastos").font(.ticket(.detail)).foregroundStyle(Theme.good)
            } else {
                Text(wholeMoney(day.input.total))
                    .font(.ticket(.headline))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(details)
                    .font(.ticket(.detail))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let limit {
                    let over = day.input.variable - limit
                    Text(over > 0 ? "\(wholeMoney(over)) arriba de tu tope" : "\(wholeMoney(-over)) abajo de tu tope")
                        .font(.ticket(.detail))
                        .foregroundStyle(over > 0 ? Theme.danger : Theme.good)
                }
            }
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.panel).strokeBorder(Theme.dimmed) }
        .shadow(color: Theme.background, radius: Theme.Size.monthCodeGlow)
    }

    private var details: String {
        var parts = [day.input.payments == 1 ? "1 pago" : "\(day.input.payments) pagos"]
        if day.input.fixedPayments > 0 { parts.append(day.input.fixedPayments == 1 ? "1 fijo" : "\(day.input.fixedPayments) fijos") }
        if let biggest = day.input.biggest, day.input.payments > 1 { parts.append("el más grande: \(biggest.name)") }
        return parts.joined(separator: " · ")
    }
}
