import CentavoCore
import SwiftUI

/// The welcome's first promise, shown instead of told: a small ticket with «Hoy puedes gastar»,
/// a Wallet notice drops in, folds into the list as a new row and the figure goes down. It
/// loops over a few payments; with «Reducir movimiento» it stays still on the first one landed.
struct WelcomeDemo: View {
    let currency: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The symbol's column grows with the text (2026-11-18): at 22 pt fixed, the symbol ran over
    /// the name with accessibility text.
    @ScaledMetric(relativeTo: .footnote) private var iconWidth = Theme.Size.iconColumnNarrow
    @State private var left: Decimal = Self.start
    @State private var rows: [Payment] = [Self.first]
    @State private var notice: Payment?
    @State private var landings = 0
    /// How much of today's cell is spent, 0…1: each payment fills a bit more.
    @State private var todayFill: CGFloat = 0

    private struct Payment: Identifiable, Equatable {
        let id = UUID()
        let merchant: String
        let symbol: String
        let amount: Decimal
    }

    private static let start: Decimal = 420
    private static let first = Payment(merchant: "Oxxo", symbol: "cart", amount: 47.5)
    private static let coming = [
        Payment(merchant: "Café del Sol", symbol: "cup.and.saucer", amount: 65),
        Payment(merchant: "Uber", symbol: "car", amount: 89),
        Payment(merchant: String(localized: "Farmacia"), symbol: "cross.case", amount: 120),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if !still || notice != nil { noticeSlot }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                // It moves by itself: say it is an example, or it reads as something you did
                // (user research, 2026-10-29).
                header
                Text(shownLeft.formatted(currencyStyle(currency).precision(.fractionLength(0))))
                    .font(.ticket(.display))
                    .tracking(Theme.Tracking.figure)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: NSDecimalNumber(decimal: shownLeft).doubleValue))
                    .monospacedDigit()
            }
            Perforation()
            VStack(spacing: Theme.Space.s) {
                ForEach(shownRows.prefix(3)) { row($0) }
            }
            monthStrip
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ticketPanel()
        .sensoryFeedback(.impact(weight: .light), trigger: landings)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ejemplo: llega un pago de Wallet, se anota solo y baja lo que puedes gastar hoy.")
        .task { await play() }
    }

    /// «Hoy puedes gastar» and «Ejemplo», one under the other with accessibility text
    /// (2026-11-18): side by side they cut each other.
    @ViewBuilder private var header: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Space.none) {
                Text("Hoy puedes gastar").ticketCaption()
                Text("Ejemplo").ticketCaption()
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text("Hoy puedes gastar").ticketCaption()
                Spacer(minLength: Theme.Space.s)
                Text("Ejemplo").ticketCaption()
            }
        }
    }

    /// The month as the main screen's boleto: the days gone, filled; today, outlined, filling
    /// with each payment; the days to come, empty.
    private var monthStrip: some View {
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: AppClock.now)?.count ?? 30
        let today = calendar.component(.day, from: AppClock.now)
        return HStack(spacing: Theme.Size.monthBarCellGap) {
            ForEach(1...days, id: \.self) { day in
                RoundedRectangle(cornerRadius: Theme.Radius.bar)
                    .strokeBorder(day == today ? Theme.ink : Theme.hairline, lineWidth: Theme.Stroke.hairline)
                    .background(alignment: .bottom) {
                        GeometryReader { proxy in
                            let fill: CGFloat = day < today ? Theme.Size.welcomeDayGone : day == today ? shownFill : 0
                            Rectangle().fill(Theme.brass)
                                .frame(height: proxy.size.height * fill)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.bar))
            }
        }
        .frame(height: Theme.Size.welcomeStrip)
        .accessibilityHidden(true)
    }

    /// Room for the notice is always kept, so the ticket does not jump when it comes and goes.
    /// The room is the notice itself, hidden (2026-11-18): a row kept one line where the notice
    /// takes two, and the ticket jumped with each payment.
    /// Still (Reducir movimiento, Bajo consumo), no notice ever comes: no room is kept. With
    /// accessibility text that room filled the screen and the example read as an empty box
    /// (fourth QA round, 2026-11-19).
    private var noticeSlot: some View {
        ZStack {
            noticeCard(Self.longest).hidden()
            if let notice {
                noticeCard(notice)
                    .transition(.asymmetric(
                        insertion: .offset(y: -Theme.Size.noticeDrop).combined(with: .opacity),
                        removal: .scale(scale: Theme.Size.noticeFold, anchor: .bottom).combined(with: .opacity)))
            }
        }
    }

    /// The payment whose notice takes the most room, for the room kept.
    private static let longest = coming.max { $0.merchant.count < $1.merchant.count } ?? first

    private func noticeCard(_ payment: Payment) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "wallet.pass.fill")
                .foregroundStyle(Theme.brass)
                .frame(width: iconWidth)
            VStack(alignment: .leading, spacing: Theme.Space.none) {
                Text("Wallet · ahora").font(.ticket(.caption)).foregroundStyle(Theme.muted)
                // The amount is the point of the demo: on its own line with accessibility text,
                // never cut off (2026-11-18).
                if typeSize.isAccessibilitySize {
                    Text(payment.merchant)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(money(payment.amount))
                } else {
                    Text("\(payment.merchant) · \(money(payment.amount))")
                        .lineLimit(1)
                }
            }
            .font(.ticket(.footnoteStrong))
            .foregroundStyle(Theme.ink)
            Spacer(minLength: Theme.Space.none)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
    }

    private func row(_ payment: Payment) -> some View {
        AdaptiveStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: payment.symbol)
                    .foregroundStyle(Theme.brass)
                    .frame(width: iconWidth)
                Text(payment.merchant.uppercased())
                    .font(.ticket(.footnote))
                    .tracking(Theme.Tracking.name)
                    .foregroundStyle(Theme.ink)
                    // Whole, on more lines, with accessibility text (2026-11-18).
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: Theme.Space.s) }
            Text(money(payment.amount))
                .font(.ticket(.footnote))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
        }
        // A new row fades in where it lands while the others make room; it doesn't slide down
        // across the perforation and the figure (audit 2026-11-02). The one pushed off the
        // bottom just fades.
        .transition(.opacity)
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(currencyStyle(currency).precision(.fractionLength(2)))
    }

    /// A few payments, one after the other, then still on the last: a loop forever would tire
    /// (and keep the phone busy). Still from the start with reduced motion or Low Power Mode.
    private func play() async {
        if MotionPolicy.isStill(reduceMotion: reduceMotion) {
            guard rows.count == 1 else { return }
            rows.insert(Self.coming[0], at: 0)
            left -= Self.coming[0].amount
            todayFill = Theme.Size.welcomeTodayStep
            return
        }
        let payments = Array(Self.coming.prefix(Theme.Motion.Onboarding.loops))
        for (index, payment) in payments.enumerated() {
            // Low Power Mode or reduced motion turned on midway: straight to the end, still.
            guard await pause(Theme.Motion.Onboarding.beforeNotice) else { return }
            guard !still else { return land(payments[index...]) }
            withAnimation(Theme.Motion.Onboarding.noticeIn) { notice = payment }
            guard await pause(Theme.Motion.Onboarding.noticeShown) else { return }
            guard !still else { return land(payments[index...]) }
            withAnimation(Theme.Motion.Onboarding.land) {
                notice = nil
                rows.insert(payment, at: 0)
                left -= payment.amount
            }
            withAnimation(Theme.Motion.Onboarding.land.delay(Theme.Motion.Onboarding.fillDelay)) {
                todayFill = min(1, todayFill + Theme.Size.welcomeTodayStep)
            }
            landings += 1
            guard await pause(Theme.Motion.Onboarding.afterLanding) else { return }
        }
    }

    private var still: Bool { MotionPolicy.isStill(reduceMotion: reduceMotion) }

    /// Still and nothing played yet: the first frame already shows where it stays (2026-11-19).
    /// Set only in `.task`, the payment landed a frame after the page was drawn.
    private var startsStill: Bool { still && rows.count == 1 && notice == nil }
    private var shownLeft: Decimal { startsStill ? Self.start - Self.coming[0].amount : left }
    private var shownRows: [Payment] { startsStill ? [Self.coming[0]] + rows : rows }
    private var shownFill: CGFloat { startsStill ? Theme.Size.welcomeTodayStep : todayFill }

    /// What is left to come, all at once and with no animation: where the demo ends.
    private func land(_ payments: ArraySlice<Payment>) {
        var instantly = Transaction(animation: nil)
        instantly.disablesAnimations = true
        withTransaction(instantly) {
            notice = nil
            for payment in payments {
                rows.insert(payment, at: 0)
                left -= payment.amount
                todayFill = min(1, todayFill + Theme.Size.welcomeTodayStep)
            }
        }
    }

    private func pause(_ seconds: Double) async -> Bool {
        (try? await Task.sleep(for: .seconds(seconds))) != nil
    }
}

/// How a payment reaches Al día, lit one node after the other: you pay, Atajos tells
/// Al día, Al día writes it down. It lights once and stays fully lit (audit 2026-11-02: it went
/// dark and started over forever). Fully lit from the start with `MotionPolicy` still.
struct WalletChain: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var node = Theme.Size.chainNode
    @State private var lit = 0

    /// Fully lit from the first frame when still (2026-11-19), not a frame later from `.task`.
    private var shownLit: Int { MotionPolicy.isStill(reduceMotion: reduceMotion) ? nodes.count - 1 : lit }

    private let nodes: [(String, String)] = [
        ("wallet.pass", String(localized: "Pagas")),
        ("square.2.layers.3d", String(localized: "Atajos avisa")),
        ("checkmark", String(localized: "Al día lo anota")),
    ]

    var body: some View {
        chain
            .padding(Theme.Space.l)
        .frame(maxWidth: .infinity)
        .ticketPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pagas con Wallet, Atajos le avisa a Al día y Al día lo anota.")
        .task {
            guard !MotionPolicy.isStill(reduceMotion: reduceMotion) else { lit = nodes.count - 1; return }
            for index in lit.advanced(by: 1)..<nodes.count {
                // Cancelled, or still since (Low Power Mode midway): fully lit at once.
                guard (try? await Task.sleep(for: .seconds(Theme.Motion.Onboarding.chainBeat))) != nil,
                      !MotionPolicy.isStill(reduceMotion: reduceMotion) else {
                    lit = nodes.count - 1
                    return
                }
                withAnimation(Theme.Motion.Onboarding.light) { lit = index }
            }
        }
    }

    /// Across, or down with accessibility text (2026-11-18): three nodes side by side ran off
    /// both edges of the panel, and the page only scrolls up and down.
    @ViewBuilder private var chain: some View {
        if typeSize.isAccessibilitySize {
            let side = min(node, Theme.Size.chainNodeMax)
            VStack(alignment: .leading, spacing: Theme.Space.none) {
                ForEach(nodes.indices, id: \.self) { index in
                    if index > 0 {
                        link(index)
                            .frame(width: Theme.Size.chainLink, height: Theme.Size.chainLinkRun)
                            .frame(width: side) // the link runs under the middle of the node
                    }
                    HStack(spacing: Theme.Space.m) {
                        circle(index, side: side)
                        name(index)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: Theme.Space.none) {
                ForEach(nodes.indices, id: \.self) { index in
                    if index > 0 {
                        link(index)
                            .frame(height: Theme.Size.chainLink)
                            .padding(.top, node / 2) // ds-allow: the link runs through the middle of the node
                    }
                    VStack(spacing: Theme.Space.s) {
                        circle(index, side: node)
                        name(index)
                            .multilineTextAlignment(.center)
                    }
                    .frame(minWidth: node)
                }
            }
        }
    }

    private func link(_ index: Int) -> some View {
        Capsule().fill(shownLit >= index ? Theme.brass : Theme.dimmed)
    }

    private func circle(_ index: Int, side: CGFloat) -> some View {
        Image(systemName: nodes[index].0)
            .font(Theme.Symbol.large)
            .foregroundStyle(shownLit >= index ? Theme.brass : Theme.faint)
            .frame(width: side, height: side)
            .background(shownLit >= index ? Theme.brass.opacity(Theme.Opacity.wash) : Theme.raised,
                        in: Circle())
            .overlay { Circle().strokeBorder(shownLit >= index ? Theme.brass : Theme.hairline) }
    }

    private func name(_ index: Int) -> some View {
        Text(nodes[index].1)
            .font(.ticket(.caption))
            .foregroundStyle(shownLit >= index ? Theme.ink : Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The month split into its days, as the main screen's boleto: equal cells that fill when there
/// is a budget (once, as it's typed), empty dashed ones while there isn't.
struct WelcomeDaysStrip: View {
    let days: Int
    let filled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        HStack(spacing: Theme.Size.monthBarCellGap) {
            ForEach(0..<days, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.Radius.bar)
                    .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: Theme.Stroke.hairline,
                                                                    dash: filled ? [] : Theme.Dash.dotted))
                    .background(alignment: .bottom) {
                        GeometryReader { proxy in
                            Rectangle().fill(Theme.brass)
                                .frame(height: filled && (shown || still) ? proxy.size.height * Theme.Size.welcomeDayGone : Theme.Space.none)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.bar))
            }
        }
        .frame(height: Theme.Size.welcomeStrip)
        .accessibilityHidden(true)
        .onAppear { fill() }
        .onChange(of: filled) { fill() }
    }

    /// Filled from the first frame when still (2026-11-19), not a frame later from `onAppear`.
    private var still: Bool { MotionPolicy.isStill(reduceMotion: reduceMotion) }

    private func fill() {
        withAnimation(Theme.Motion.animation(Theme.Motion.Money.total, reduceMotion: MotionPolicy.isStill(reduceMotion: reduceMotion))) {
            shown = filled
        }
    }
}

/// The month as a calendar for the fixed expenses: tap a day to choose it, and each one added is
/// stamped on its day in brass, once (not in a loop). A day 31 in a shorter month lands on the last.
struct WelcomeFixedCalendar: View {
    let stamped: Set<Int>
    @Binding var chosen: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let days = Calendar.current.range(of: .day, in: .month, for: AppClock.now)?.count ?? 30
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.xxs), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Space.xxs) {
            ForEach(1...days, id: \.self) { day in
                let isStamped = stamped.contains(where: { min($0, days) == day })
                Button { chosen = day } label: {
                    Text("\(day)")
                        .font(.ticket(.micro))
                        .foregroundStyle(isStamped ? Theme.onBrass : day == chosen ? Theme.brass : Theme.muted)
                        // A whole touch target tall: at 28 pt the finger landed on the day above
                        // or below (UX review, 2026-11-11).
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.tile)
                                .fill(isStamped ? Theme.brass : .clear)
                                .scaleEffect(isStamped ? Theme.Size.barFullScale : Theme.Size.stampFrom)
                                .opacity(isStamped ? Theme.Opacity.visible : Theme.Opacity.hidden)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.tile)
                                .strokeBorder(day == chosen ? Theme.brass : Theme.hairline, lineWidth: Theme.Stroke.hairline)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(Theme.Motion.animation(Theme.Motion.settle, reduceMotion: reduceMotion), value: isStamped)
                .accessibilityLabel(spokenCell(day, stamped: isStamped))
                .accessibilityAddTraits(day == chosen ? .isSelected : [])
            }
        }
        // One control for VoiceOver (2026-11-18): up to 31 buttons «Día N» to swipe through,
        // with nothing saying they choose the charge's day. Swipe up or down to change it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Día del cobro")
        .accessibilityValue(spokenDay)
        .accessibilityAdjustableAction { direction in
            chosen = direction == .increment ? min(chosen + 1, days) : max(chosen - 1, 1)
        }
        .sensoryFeedback(.selection, trigger: chosen)
    }

    private var spokenDay: String {
        let taken = stamped.contains { min($0, days) == chosen }
        let day = chosen
        if day >= RepeatRule.lastDayOfMonth {
            if taken { return String(localized: "el último día del mes, con un fijo") }
            return String(localized: "el último día del mes")
        }
        if taken { return String(localized: "el día \(day), con un fijo") }
        return String(localized: "el día \(day)")
    }

    private func spokenCell(_ day: Int, stamped: Bool) -> String {
        if stamped { return String(localized: "Día \(day), con un fijo") }
        return String(localized: "Día \(day)")
    }
}

/// Each block of an onboarding page rises in after the one above it, the first time the page
/// shows. With «Reducir movimiento» it is simply there.
struct OnboardingRise: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || MotionPolicy.isStill(reduceMotion: reduceMotion) ? Theme.Opacity.visible : Theme.Opacity.hidden)
            .offset(y: shown || MotionPolicy.isStill(reduceMotion: reduceMotion) ? Theme.Space.none : Theme.Size.entranceRise)
            .onAppear {
                guard !shown else { return }
                withAnimation(Theme.Motion.Onboarding.rise(index)) { shown = true }
            }
    }
}

extension View {
    /// Rises in as block `index` of an onboarding page (see `OnboardingRise`).
    func onboardingRise(_ index: Int) -> some View { modifier(OnboardingRise(index: index)) }
}

#Preview("Demo de bienvenida") {
    VStack(spacing: Theme.Space.xl) {
        WelcomeDemo(currency: "MXN")
        WalletChain()
    }
    .padding(Theme.Space.screen)
    .ticketPreview()
}
