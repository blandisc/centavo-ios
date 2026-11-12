import SwiftUI

/// The welcome's first promise, shown instead of told: a small ticket with «Hoy puedes gastar»,
/// a Wallet notice drops in, folds into the list as a new row and the figure goes down. It
/// loops over a few payments; with «Reducir movimiento» it stays still on the first one landed.
struct WelcomeDemo: View {
    let currency: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        Payment(merchant: "Farmacia", symbol: "cross.case", amount: 120),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            noticeSlot
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                // It moves by itself: say it is an example, or it reads as something you did
                // (user research, 2026-10-29).
                HStack(alignment: .firstTextBaseline) {
                    Text("Hoy puedes gastar").ticketCaption()
                    Spacer(minLength: Theme.Space.s)
                    Text("Ejemplo").ticketCaption()
                }
                Text(left.formatted(currencyStyle(currency).precision(.fractionLength(0))))
                    .font(.ticket(.display))
                    .tracking(Theme.Tracking.figure)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: NSDecimalNumber(decimal: left).doubleValue))
                    .monospacedDigit()
            }
            Perforation()
            VStack(spacing: Theme.Space.s) {
                ForEach(rows.prefix(3)) { row($0) }
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
                            let fill: CGFloat = day < today ? Theme.Size.welcomeDayGone : day == today ? todayFill : 0
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
    private var noticeSlot: some View {
        ZStack {
            row(Self.first).hidden()
            if let notice {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "wallet.pass.fill").foregroundStyle(Theme.brass)
                    VStack(alignment: .leading, spacing: Theme.Space.none) {
                        Text("Wallet · ahora").font(.ticket(.caption)).foregroundStyle(Theme.muted)
                        Text("\(notice.merchant) · \(money(notice.amount))")
                            .font(.ticket(.footnoteStrong)).foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.none)
                }
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
                .transition(.asymmetric(
                    insertion: .offset(y: -Theme.Size.noticeDrop).combined(with: .opacity),
                    removal: .scale(scale: Theme.Size.noticeFold, anchor: .bottom).combined(with: .opacity)))
            }
        }
    }

    private func row(_ payment: Payment) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: payment.symbol)
                .foregroundStyle(Theme.brass)
                .frame(width: Theme.Size.iconColumnNarrow)
            Text(payment.merchant.uppercased())
                .font(.ticket(.footnote))
                .tracking(Theme.Tracking.name)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.s)
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
    @ScaledMetric(relativeTo: .body) private var node = Theme.Size.chainNode
    @State private var lit = 0

    private let nodes = [("wallet.pass", "Pagas"), ("square.2.layers.3d", "Atajos avisa"),
                         ("checkmark", "Al día lo anota")]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.none) {
            ForEach(nodes.indices, id: \.self) { index in
                if index > 0 {
                    Capsule()
                        .fill(lit >= index ? Theme.brass : Theme.dimmed)
                        .frame(height: Theme.Size.chainLink)
                        .padding(.top, node / 2) // ds-allow: the link runs through the middle of the node
                }
                VStack(spacing: Theme.Space.s) {
                    Image(systemName: nodes[index].0)
                        .font(Theme.Symbol.large)
                        .foregroundStyle(lit >= index ? Theme.brass : Theme.faint)
                        .frame(width: node, height: node)
                        .background(lit >= index ? Theme.brass.opacity(Theme.Opacity.wash) : Theme.raised,
                                    in: Circle())
                        .overlay { Circle().strokeBorder(lit >= index ? Theme.brass : Theme.hairline) }
                    Text(nodes[index].1)
                        .font(.ticket(.caption))
                        .foregroundStyle(lit >= index ? Theme.ink : Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: node)
            }
        }
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
                                .frame(height: filled && shown ? proxy.size.height * Theme.Size.welcomeDayGone : Theme.Space.none)
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
                .accessibilityLabel(isStamped ? "Día \(day), con un fijo" : "Día \(day)")
                .accessibilityAddTraits(day == chosen ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: chosen)
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
