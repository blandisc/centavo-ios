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
        /// The success plays once and stays.
        static let success: Double = 2.2
        /// A row of «Primera cuenta» opening or closing.
        static let row: Animation = .smooth(duration: 0.45)
        /// The running total counting to its new figure.
        static let total: Animation = .smooth(duration: 0.7)
        /// Frames per second the drawings ask for: smooth enough, light on the battery.
        static let frameInterval: Double = 1.0 / 30
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
