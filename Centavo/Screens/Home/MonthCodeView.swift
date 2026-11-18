import CentavoCore
import SwiftUI

/// The month as a boleto, one cell per day (see `bars`): the carousel's first page, swapping places
/// with the calendar (owner, 2026-10-30).
///
/// A finger on it reads the day under it in a card above (what went, how many payments, the
/// biggest, against the day's limit), with a tick at each new day. Let go on a day and the list
/// shows only that day, the same as tapping it in the calendar, and the day's card stays until
/// the day is let go (tapped again, or a tap anywhere else on the screen, 2026-10-30).
struct MonthCodeView: View {
    let code: MonthCode
    let selectedDay: Int?
    let onSelectDay: (Int?) -> Void
    /// A finger holding the boleto to read its days, or letting go: the carousel holds still meanwhile.
    var onScrubbing: (Bool) -> Void = { _ in }
    /// "$846": whole money in the month's currency.
    let wholeMoney: (Decimal) -> String
    /// The viewed month, to name a day («MIÉ 28 OCT»).
    let month: Date
    /// The screen's entrance: the boleto comes in once when the app opens, and not again when
    /// the row is rebuilt.
    var entrance = Entrance()

    @State private var drawn = false
    /// A boleto rebuilt (closing a search) is already there: it came in once, when the app
    /// opened, with or without a budget (2026-11-18: without one it faded in again).
    private var shown: Bool { drawn || entrance.barShown || entrance.codeShown }
    /// Whether today breathes on this boleto: only the first one the app shows, so a rebuilt one
    /// rests at full (2026-11-18). Settled when it appears.
    @State private var breathesToday: Bool?

    @State private var touched: Int?
    /// This touch held and read the days: its lift is not also a tap.
    @State private var didScrub = false
    @State private var width = Theme.Space.none
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var height = Theme.Size.monthCode

    private var shownDay: Int? { touched ?? selectedDay }
    /// Today, or the month's last day that came: what a double tap picks with VoiceOver.
    private var lastDay: Int? { code.days.last { $0.kind != .future }?.number }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            bars
                .frame(height: height)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .overlay(alignment: .bottomLeading) { card }
                // Over the card too, which comes and goes with the dimming of the other days
                // instead of popping in (2026-11-18).
                .animation(Theme.Motion.animation(Theme.Motion.select, reduceMotion: reduceMotion), value: shownDay)
                .contentShape(Rectangle())
                // A swipe is always the carousel's (owner, 2026-10-30, twice: it was hard to get to
                // the calendar). A tap picks a day; holding a moment and sliding reads the days, and
                // only then is the carousel held still. Neither gesture claims the swipe: the tap
                // and the hold fail as soon as the finger travels.
                .onTapGesture(coordinateSpace: .local) { location in
                    if didScrub { didScrub = false; return }
                    pick(day(at: location.x))
                }
                .gesture(scrub)
                .sensoryFeedback(.selection, trigger: touched) { _, new in new != nil }
        }
        .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
        .onAppear {
            if breathesToday == nil {
                breathesToday = !entrance.todayBreathed
                entrance.todayBreathed = true
            }
            guard !drawn else { return }
            withAnimation(reduceMotion ? nil : Theme.Motion.Entrance.code) { drawn = true }
            entrance.codeShown = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gasto de cada día")
        .accessibilityValue(spoken(shownDay ?? code.days.last { $0.kind == .today }?.number ?? code.days.count))
        .accessibilityAdjustableAction { direction in
            let last = code.days.last { $0.kind != .future }?.number ?? code.days.count
            let current = shownDay ?? code.days.last { $0.kind == .today }?.number ?? last
            let next = direction == .increment ? min(current + 1, last) : max(current - 1, 1)
            onSelectDay(next)
        }
        // A double tap is not a tap in the middle of the boleto, on whatever day is there
        // (2026-11-18): it shows today, or the whole month again.
        .accessibilityAction(.default) { onSelectDay(selectedDay == nil ? lastDay : nil) }
        .accessibilityActions {
            if selectedDay != nil {
                Button("Ver todo el mes") { onSelectDay(nil) }
            }
        }
        .accessibilityHint("Desliza hacia arriba o hacia abajo para cambiar de día")
        .accessibilityIdentifier("codigo-del-mes")
    }

    // MARK: The bars

    /// The boleto (owner's choice, 2026-10-30): one cell per day, as tall as what a day may spend.
    /// Brass rises with what went that day; what was left over keeps the old bar's green hatch;
    /// a day past it is red, with a tick over it. Today is outlined; the days to come are dashed.
    /// Without a budget there is no limit: each day is measured against the month's biggest.
    private var bars: some View {
        HStack(alignment: .bottom, spacing: Theme.Size.monthBarCellGap) {
            ForEach(code.days, id: \.number) { day in
                cell(day)
                    .opacity(opacity(day))
                    // Today breathes a few times once the boleto has come in, then rests at full
                    // (audit 2026-11-02: it breathed forever, and began before it could be seen).
                    .breathes(day.kind == .today && shownDay == nil && breathesToday == true,
                              times: Theme.Motion.todayBreaths,
                              seconds: Theme.Motion.todayBreathSeconds, low: Theme.Opacity.tileBreath,
                              begins: shown, after: Theme.Motion.todayBreathAfter)
            }
        }
    }

    private func cell(_ day: MonthCode.Day) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.bar)
        return ZStack(alignment: .bottom) {
            if day.kind == .future {
                shape.strokeBorder(Theme.dimmed, style: StrokeStyle(lineWidth: Theme.Stroke.hairline,
                                                                    dash: Theme.Dash.dotted))
            } else if isOver(day) {
                shape.fill(Theme.danger)
            } else {
                shape.fill(Theme.raised)
                if code.limitPerDay != nil {
                    Hatch()
                        .stroke(Theme.good, lineWidth: Theme.Stroke.mark)
                        .opacity(Theme.Opacity.paceBehind)
                        .clipShape(shape)
                }
                shape.fill(Theme.brass)
                    .frame(height: height * fill(day))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay(alignment: .top) {
            if isOver(day) {
                // Past the day's limit: a tick over the cell, like a mark on the ticket.
                RoundedRectangle(cornerRadius: Theme.Radius.bar)
                    .fill(Theme.danger)
                    .frame(height: Theme.Size.monthCodeTick)
                    .offset(y: -(Theme.Size.monthCodeTick + Theme.Size.monthBarCellGap))
            }
        }
        .overlay {
            if day.kind == .today {
                RoundedRectangle(cornerRadius: Theme.Radius.bar)
                    .strokeBorder(Theme.ink, lineWidth: Theme.Stroke.emphasis)
            }
        }
    }

    /// Past the day's limit, today included (today is outlined, and red too once over it).
    private func isOver(_ day: MonthCode.Day) -> Bool {
        if day.kind == .over { return true }
        guard day.kind == .today, let limit = code.limitPerDay else { return false }
        return day.input.variable > limit
    }

    /// How much of the cell what went that day fills: against the day's limit, or against the
    /// month's biggest day without a budget. Never all of it unless it is past the limit.
    private func fill(_ day: MonthCode.Day) -> CGFloat {
        guard day.input.payments > 0 else { return Theme.Space.none }
        if let limit = code.limitPerDay, limit > 0 {
            let share = NSDecimalNumber(decimal: day.input.variable / limit).doubleValue
            return CGFloat(min(max(share, 0), 1))
        }
        return CGFloat(day.height)
    }

    private func opacity(_ day: MonthCode.Day) -> Double {
        if day.kind == .future { return Theme.Opacity.visible }
        if let shownDay { return day.number == shownDay ? Theme.Opacity.visible : Theme.Opacity.codeBarAside }
        return Theme.Opacity.visible
    }

    // MARK: The finger

    /// Hold a moment, then slide: the day under the finger, and on letting go, that day picked.
    /// UIKit's long press (`HoldAndSlide`): a swipe up that starts here still scrolls the screen.
    private var scrub: HoldAndSlide {
        HoldAndSlide(hold: Theme.Motion.scrubHold, slop: Theme.Size.scrubSlop) { location in
            didScrub = true
            onScrubbing(true)
            touched = day(at: location.x)
        } moved: { location in
            touched = day(at: location.x)
        } ended: { location in
            defer { touched = nil; onScrubbing(false) }
            // Cancelled (a call, the app going away): no lift will come to be taken for a tap,
            // so the next tap is one (2026-11-18: it was swallowed).
            guard let location else { didScrub = false; return }
            pick(day(at: location.x))
            // The lift that ends a scrub is not also a tap; a later touch is a tap again.
            Task { @MainActor in didScrub = false }
        }
    }

    private func pick(_ day: Int?) {
        guard let day, code.days[day - 1].kind != .future else { return }
        onSelectDay(selectedDay == day ? nil : day)
    }

    private func day(at x: CGFloat) -> Int? {
        guard width > 0, !code.days.isEmpty else { return nil }
        let index = Int((min(max(x, 0), width - 1) / width) * CGFloat(code.days.count))
        return min(index, code.days.count - 1) + 1
    }

    /// The card over the day under the finger, or over the day picked: kept inside the code's width.
    @ViewBuilder private var card: some View {
        if let shownDay, let day = code.days.first(where: { $0.number == shownDay }) {
            let center = width * (CGFloat(shownDay) - 0.5) / CGFloat(max(code.days.count, 1))
            // Never wider than the boleto itself.
            let cardWidth = min(Theme.Size.monthCodeCard, width)
            let left = min(max(center - cardWidth / 2, Theme.Space.none), max(width - cardWidth, Theme.Space.none))
            DayCard(day: day, title: title(shownDay), limit: code.limitPerDay, wholeMoney: wholeMoney)
                .frame(width: cardWidth, alignment: .leading)
                // As tall as what it says: the overlay offers it the boleto's height, and its
                // last line was cut to «$43 arriba de tu cifra p…».
                .fixedSize(horizontal: false, vertical: true)
                // Right over the boleto, on «Cada día del mes»: it stays under the hero's figure,
                // which is what is looked at most (owner, 2026-11-11).
                .offset(x: left, y: -(height + Theme.Size.monthBarCellGap))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func title(_ number: Int) -> String {
        var parts = Calendar.current.dateComponents([.year, .month], from: month)
        parts.day = number
        let date = Calendar.current.date(from: parts) ?? month
        let text = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            .locale(Locale.current))
            .replacingOccurrences(of: ".", with: "")
        guard code.days[number - 1].kind == .today else { return text }
        return String(localized: "Hoy · \(text)")
    }

    private func spoken(_ number: Int) -> String {
        guard number >= 1, number <= code.days.count else { return "" }
        let day = code.days[number - 1]
        if day.kind == .future { return String(localized: "Día \(number): todavía no llega") }
        let amount = wholeMoney(day.input.total)
        let name = title(number)
        let payments = day.input.payments
        if payments == 1 { return String(localized: "\(name): \(amount), 1 pago") }
        return String(localized: "\(name): \(amount), \(payments) pagos")
    }
}

/// One day under the finger, in two lines so it stays under the hero's figure: the day and what
/// went; then how many payments, the biggest, and how far from the day's limit, in a sentence
/// that wraps instead of being cut (owner, 2026-11-11).
private struct DayCard: View {
    let day: MonthCode.Day
    let title: String
    let limit: Decimal?
    let wholeMoney: (Decimal) -> String

    private var hasPayments: Bool { day.kind != .future && day.input.payments > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.none) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(title)
                    .font(.ticket(.microStrong))
                    .tracking(Theme.Tracking.label)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.brass)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Space.none)
                if day.kind != .future {
                    Text(wholeMoney(hasPayments ? day.input.total : 0))
                        .font(.ticket(.label))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            sentence
                .font(.ticket(.detail))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, Theme.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.panel).strokeBorder(Theme.dimmed) }
        .shadow(color: Theme.background, radius: Theme.Size.monthCodeGlow)
    }

    /// «1 pago · $43 arriba del tope del día»: only the judgement in color.
    private var sentence: Text {
        if day.kind == .future { return Text("Todavía no llega.").foregroundStyle(Theme.muted) }
        guard hasPayments else { return Text("Día sin gastos").foregroundStyle(Theme.good) }
        let said = Text(details).foregroundStyle(Theme.muted)
        guard let limit else { return said }
        let over = day.input.variable - limit
        let judged = Text(judgement(over))
            .foregroundStyle(over > 0 ? Theme.danger : Theme.good)
        // A no-break space before the dot: a wrapped line never starts with «·».
        let dot = Text(verbatim: "\u{00A0}· ").foregroundStyle(Theme.muted)
        return Text("\(said)\(dot)\(judged)")
    }

    /// «$43 arriba del tope del día», or «abajo».
    private func judgement(_ over: Decimal) -> String {
        if over > 0 {
            let amount = wholeMoney(over)
            return String(localized: "\(amount) arriba del tope del día")
        }
        let amount = wholeMoney(-over)
        return String(localized: "\(amount) abajo del tope del día")
    }

    private var details: String {
        let payments = day.input.payments
        let fixed = day.input.fixedPayments
        var parts: [String] = []
        if payments == 1 {
            parts.append(String(localized: "1 pago"))
        } else {
            parts.append(String(localized: "\(payments) pagos"))
        }
        if fixed == 1 {
            parts.append(String(localized: "1 fijo"))
        } else if fixed > 1 {
            parts.append(String(localized: "\(fixed) fijos"))
        }
        if let biggest = day.input.biggest, payments > 1 {
            let name = biggest.name
            parts.append(String(localized: "el más grande: \(name)"))
        }
        return parts.joined(separator: " · ")
    }
}
