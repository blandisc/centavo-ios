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
                Text("Hoy puedes gastar").ticketCaption()
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
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ticketPanel()
        .sensoryFeedback(.impact(weight: .light), trigger: landings)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ejemplo: llega un pago de Wallet, se anota solo y baja lo que puedes gastar hoy.")
        .task { await play() }
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
            Text("−" + money(payment.amount))
                .font(.ticket(.footnote))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(currencyStyle(currency).precision(.fractionLength(2)))
    }

    private func play() async {
        if reduceMotion {
            rows.insert(Self.coming[0], at: 0)
            left -= Self.coming[0].amount
            return
        }
        var index = 0
        while !Task.isCancelled {
            let payment = Self.coming[index % Self.coming.count]
            guard await pause(Theme.Motion.Onboarding.beforeNotice) else { return }
            withAnimation(Theme.Motion.Onboarding.noticeIn) { notice = payment }
            guard await pause(Theme.Motion.Onboarding.noticeShown) else { return }
            withAnimation(Theme.Motion.Onboarding.land) {
                notice = nil
                rows.insert(payment, at: 0)
                left -= payment.amount
            }
            landings += 1
            guard await pause(Theme.Motion.Onboarding.afterLanding) else { return }
            index += 1
            if index % Self.coming.count == 0 {
                withAnimation(Theme.Motion.restyle) {
                    rows = [Self.first]
                    left = Self.start
                }
            }
        }
    }

    private func pause(_ seconds: Double) async -> Bool {
        (try? await Task.sleep(for: .seconds(seconds))) != nil
    }
}

/// How a payment reaches Al día, lit one node after the other: you pay, Atajos tells
/// Al día, Al día writes it down. Still and fully lit with «Reducir movimiento».
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
                        .symbolEffect(.bounce, value: lit == index)
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
            guard !reduceMotion else { lit = nodes.count - 1; return }
            while !Task.isCancelled {
                for index in 0...nodes.count {
                    guard (try? await Task.sleep(for: .seconds(Theme.Motion.Onboarding.chainBeat))) != nil
                    else { return }
                    withAnimation(Theme.Motion.Onboarding.light) { lit = index == nodes.count ? -1 : index }
                }
            }
        }
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
            .opacity(shown || reduceMotion ? Theme.Opacity.visible : Theme.Opacity.hidden)
            .offset(y: shown || reduceMotion ? Theme.Space.none : Theme.Size.entranceRise)
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
