import SwiftUI

// «Mi dinero»'s first time (2026-11-01): the drawings of the welcome, Face ID and «Primera
// cuenta», and how long their loops last. Everything else comes from the shared tokens.

extension Theme.Size {
    /// The welcome's boleto of months, over the dashed ticket.
    static let moneyHeroBoleto: CGFloat = 72
    /// Gap between two months of that boleto.
    static let moneyHeroCellGap: CGFloat = 4
    /// A kind's little drawing on its card («Cuenta», «Tarjeta»…).
    static let moneyKindArt: CGFloat = 62
    /// The Face ID drawing before iOS asks for permission.
    static let moneyFaceArt: CGFloat = 150
    /// The success ring at the end of «Primera cuenta».
    static let moneySuccessArt: CGFloat = 132
    /// One part of the four-step bar.
    static let moneyStepBar: CGFloat = 3
    /// Width of a currency in the currency carousel.
    static let moneyCurrencyTile: CGFloat = 66
    /// A color swatch beside an account's name.
    static let moneySwatch: CGFloat = 8
    /// The empty «Hoy»'s step cards: their drawing.
    static let emptyStepArt: CGFloat = 52
    /// The empty «Hoy»'s month strip.
    static let emptyStrip: CGFloat = 30
    /// The Excel button's little drawing.
    static let moneyExcelArt: CGFloat = 92
    /// How wide the step bar's sheen is, as a share of its part.
    static let moneySheenShare: CGFloat = 0.5
}

extension Theme.Motion {
    /// The looping drawings: one full turn of each, in seconds. Long, so nothing feels busy.
    enum Money {
        static let heroCycle: Double = 6.4
        /// Where the hero stands with reduced motion: full and still.
        static let heroRest: Double = 0.6
        /// The sheen stays hidden with reduced motion.
        static let sheenRest: Double = 0
        static let kindCycle: Double = 4.4
        static let faceCycle: Double = 5
        /// How many turns a looping drawing makes before it rests on its still frame.
        static let loops = 3
        /// The success plays once and stays.
        static let success: Double = 2.2
        /// The step bar's light, crossing the current part once.
        static let sheen: Animation = .smooth(duration: 1.2).delay(0.2)
        /// A row of «Primera cuenta» opening or closing: the app's one fold (second audit,
        /// 2026-11-02), with `.unfold` for what it shows.
        static var row: Animation { Theme.Motion.fold }
        /// The running total counting to its new figure.
        static let total: Animation = .smooth(duration: 0.7)
        /// Frames per second the drawings ask for: smooth enough, light on the battery.
        static let frameInterval: Double = 1.0 / 30
        /// The empty «Hoy» plays once: the ghost row, then the budget card, then Wallet's.
        enum Empty {
            static let ghost: ClosedRange<Double> = 0...1
            static let budget: ClosedRange<Double> = 1...2.5
            static let wallet: ClosedRange<Double> = 2.5...4
            static let end: Double = 4
            /// Today's cell breathes this many times, then rests.
            static let breaths = 3
            /// Each half of a breath (down, or back up).
            static let breathSeconds: Double = 1.4
        }
        /// The final figure starts counting once the ring has mostly closed.
        static let countUpDelay: Double = 0.9
    }
}

extension Theme.Opacity {
    /// The faint ground under a kind's drawing.
    static let moneyArtWash: Double = 0.03
    /// A chosen kind's card, washed with brass.
    static let moneyChosen: Double = 0.08
    /// The chosen currency's tile.
    static let moneyCurrency: Double = 0.12
}
