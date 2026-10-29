import CentavoCore
import SwiftUI

/// The two rules of «Hoy puedes gastar» shown, not told: a toy week of $100 a day, the same
/// spending under both rules. Each column is a day (the outline is what it could spend, the
/// fill what it spent, red past the outline); when a day ends, what it left over or overspent
/// leaves it as a coin and goes to tomorrow («Se acumula») or splits over every day still to
/// come («Se reparte»). It plays on a loop; with «Reducir movimiento» it stands still, done.
struct AllowanceExplainer: View {
    let mode: AllowanceMode
    let currency: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: [Decimal] = Self.start
    @State private var spent: [Bool] = Array(repeating: false, count: Self.count)
    @State private var today: Int?
    @State private var coins: [Coin] = []
    @State private var caption = ""

    private static let count = AllowanceDemo.spending.count
    private static let start = Array(repeating: AllowanceDemo.perDay, count: count)
    private var demo: AllowanceDemo { AllowanceDemo(mode: mode) }

    private struct Coin: Identifiable {
        let id = UUID()
        let amount: Decimal
        let from: Int
        let to: Int
        var arrived = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            GeometryReader { geometry in
                let gap = Theme.Space.xxs
                let width = (geometry.size.width - gap * CGFloat(Self.count - 1)) / CGFloat(Self.count)
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(0..<Self.count, id: \.self) { column($0) }
                    }
                    ForEach(coins) { coin in
                        coinLabel(coin.amount)
                            .position(x: center(coin.arrived ? coin.to : coin.from, width: width, gap: gap),
                                      y: Theme.Size.explainerCoin / 2)
                            .transition(.opacity)
                    }
                }
                // Anchored at the bottom from the first frame: the bars grow up from a floor.
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomLeading)
            }
            .frame(height: Theme.Size.explainerHeight)
            Text(caption)
                .font(.ticket(.detail))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.explainerCaption, alignment: .topLeading)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode == .carry
            ? "Ejemplo: lo que sobra un día pasa completo al día siguiente; lo que te pasas se le quita."
            : "Ejemplo: lo que sobra o falta un día se reparte parejo entre todos los días que quedan.")
        .task(id: mode) { await play() }
    }

    // MARK: Pieces

    private func column(_ index: Int) -> some View {
        let allowance = shown[index]
        let day = demo.days[index]
        let isOver = spent[index] && day.spent > allowance
        return VStack(spacing: Theme.Space.xxxs) {
            Text(whole(allowance))
                .font(.ticket(.micro))
                .foregroundStyle(allowance > AllowanceDemo.perDay ? Theme.good
                                 : allowance < AllowanceDemo.perDay ? Theme.danger : Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(Theme.MinimumScale.figure)
                .contentTransition(.numericText())
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Theme.Radius.tile)
                    .strokeBorder(today == index ? Theme.brass : Theme.brassLow,
                                  style: StrokeStyle(lineWidth: Theme.Stroke.hairline,
                                                     dash: today == index ? [] : Theme.Dash.dotted))
                    .frame(height: height(allowance))
                RoundedRectangle(cornerRadius: Theme.Radius.tile)
                    .fill(isOver ? Theme.danger : Theme.brass)
                    .frame(height: spent[index] ? height(day.spent) : Theme.Space.none)
            }
            .frame(height: max(height(allowance), spent[index] ? height(day.spent) : Theme.Space.none),
                   alignment: .bottom)
            Text("\(index + 1)")
                .font(.ticket(.micro))
                .foregroundStyle(today == index ? Theme.ink : Theme.faint)
        }
        .frame(maxWidth: .infinity)
    }

    private func coinLabel(_ amount: Decimal) -> some View {
        Text((amount >= 0 ? "+" : "−") + whole(amount.magnitude))
            .font(.ticket(.microStrong))
            .foregroundStyle(amount >= 0 ? Theme.onBrass : Theme.ink)
            .padding(.horizontal, Theme.Space.xxs)
            .frame(height: Theme.Size.explainerCoin)
            .background(amount >= 0 ? Theme.good : Theme.danger, in: Capsule())
            .fixedSize()
    }

    private func center(_ index: Int, width: CGFloat, gap: CGFloat) -> CGFloat {
        width / 2 + CGFloat(index) * (width + gap)
    }

    /// Room for the biggest day (the toy week never passes $200).
    private func height(_ amount: Decimal) -> CGFloat {
        let value = CGFloat(NSDecimalNumber(decimal: max(amount, 0)).doubleValue)
        return Theme.Size.explainerBars * value / Theme.Size.explainerScale
    }

    private func whole(_ amount: Decimal) -> String {
        amount.formatted(currencyStyle(currency).precision(.fractionLength(0)))
    }

    // MARK: Playing

    private func reset() {
        shown = Self.start
        spent = Array(repeating: false, count: Self.count)
        today = nil
        coins = []
        caption = "Una semana de ejemplo con \(whole(AllowanceDemo.perDay)) por día."
    }

    private func play() async {
        reset()
        if reduceMotion {
            // Still and finished: every day spent and every move already made.
            for move in demo.moves { for target in move.to { shown[target] += move.each } }
            spent = Array(repeating: true, count: Self.count)
            caption = mode == .carry
                ? "Cada día recibe completo lo que sobró o faltó el anterior."
                : "Lo que sobra o falta se reparte entre los días que quedan."
            return
        }
        while !Task.isCancelled {
            guard await pause(Theme.Motion.Explainer.start) else { return }
            for index in 0..<Self.count {
                let day = demo.days[index]
                withAnimation(Theme.Motion.Explainer.fill) {
                    today = index
                    spent[index] = true
                }
                let result = day.left >= 0 ? "sobraron \(whole(day.left))" : "te pasaste \(whole(-day.left))"
                caption = "Día \(index + 1): podías \(whole(day.allowance)), gastaste \(whole(day.spent)); \(result)."
                guard await pause(Theme.Motion.Explainer.dayBeat) else { return }
                guard let move = demo.moves.first(where: { $0.from == index }) else { continue }
                coins = move.to.map { Coin(amount: move.each, from: index, to: $0) }
                guard await pause(Theme.Motion.Explainer.coinWait) else { return }
                withAnimation(Theme.Motion.Explainer.travel) {
                    for position in coins.indices { coins[position].arrived = true }
                }
                guard await pause(Theme.Motion.Explainer.travelTime) else { return }
                withAnimation(Theme.Motion.Explainer.fill) {
                    for target in move.to { shown[target] += move.each }
                    coins = []
                }
                caption = mode == .carry
                    ? "Día \(index + 1): \(result) → mañana tienes \(whole(shown[index + 1]))."
                    : "Día \(index + 1): \(result) → \(move.each >= 0 ? "+" : "−")\(whole(move.each.magnitude)) a cada uno de los \(move.to.count) días que quedan."
                guard await pause(Theme.Motion.Explainer.dayBeat) else { return }
            }
            guard await pause(Theme.Motion.Explainer.end) else { return }
            withAnimation(Theme.Motion.Explainer.fill) { reset() }
        }
    }

    /// Waits, and says whether to go on: a switch of rule cancels this run, and a sleep that
    /// ended just as it was cancelled must not take one more step over the new run (it once
    /// filled day 5 of «Se reparte» while it was on day 2).
    private func pause(_ seconds: Double) async -> Bool {
        (try? await Task.sleep(for: .seconds(seconds))) != nil && !Task.isCancelled
    }
}

#Preview("Se acumula y se reparte") {
    VStack(spacing: Theme.Space.xxl) {
        AllowanceExplainer(mode: .carry, currency: "MXN")
        AllowanceExplainer(mode: .spread, currency: "MXN")
    }
    .padding(Theme.Space.screen)
    .ticketPreview()
}
