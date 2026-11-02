import SwiftUI

/// The welcome's picture (2026-11-01): an example net worth, the boleto of months growing,
/// and the figure counting with it. Fills left to right, holds, drains; still with reduced motion.
struct MoneyGrowthHero: View {
    static let example: Double = 412_380
    static let grew: Double = 234_000
    let currency: String

    private func amount(_ value: Double) -> String {
        Decimal(value.rounded()).formatted(currencyStyle(currency).precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Así crece tu patrimonio").ticketCaption(strong: true)
                Spacer(minLength: Theme.Space.s)
                MoneyLoopClock(cycle: Theme.Motion.Money.heroCycle, rest: Theme.Motion.Money.heroRest) { t in
                    Text(amount(Self.example * Self.shown(t)))
                        .font(.ticket(.display))
                        .tracking(Theme.Tracking.figure)
                        .foregroundStyle(Theme.brass)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(Theme.MinimumScale.figure)
                }
            }
            MoneyLoopClock(cycle: Theme.Motion.Money.heroCycle, rest: Theme.Motion.Money.heroRest) { t in
                MoneyGrowthBars(t: t)
            }
            .frame(height: Theme.Size.moneyHeroBoleto)
            HStack {
                Text("hace un año")
                Spacer()
                Text("+\(amount(Self.grew)) · ejemplo")
                Spacer()
                Text("hoy")
            }
            .font(.ticket(.micro))
            .foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ejemplo: un patrimonio que crece mes a mes durante un año.")
    }

    /// How far the figure has counted at `t`, in step with the bars.
    static func shown(_ t: Double) -> Double { moneyRise(t, 0.05, 0.40, 0.80, 0.96) }
}
