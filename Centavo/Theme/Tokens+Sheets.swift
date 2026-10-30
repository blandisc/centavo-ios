import SwiftUI

extension Theme.Space {
    /// 3 pt. Extra gap between the lines of a paragraph in the Wallet guide (`lineSpacing`).
    static let guideLine: CGFloat = 3
}

extension Theme.Size {
    /// The narrowest a tile of «Pagos y categorías» gets: four across on an iPhone.
    static let catalogTile: CGFloat = 76
    /// Scaled. The height of every tile there: a symbol and two lines of name.
    static let catalogTileHeight: CGFloat = 78
}

extension Theme.Size {
    /// The budget sheet's drawing of «Se acumula» / «Se reparte» (`AllowanceExplainer`): its
    /// whole height, the tallest bar, the amount that bar stands for and a coin.
    static let explainerHeight: CGFloat = 124
    static let explainerBars: CGFloat = 76
    static let explainerScale: CGFloat = 160
    static let explainerCoin: CGFloat = 16
}

extension Theme.Motion {
    /// The toy week of the budget sheet, one day after another.
    enum Explainer {
        /// Seconds before the week starts, each day's beat, before a coin leaves, while it
        /// travels, and at the end before it starts over.
        /// Slow enough to read each line (owner, 2026-10-29).
        static let start: Double = 1.2
        static let dayBeat: Double = 1.8
        static let coinWait: Double = 0.1
        static let travelTime: Double = 1.3
        static let end: Double = 3.6
        /// How often a wait looks whether it was paused or resumed.
        static let tick: Double = 0.1
        /// A day filling or an outline growing.
        static let fill: Animation = .smooth(duration: 0.8)
        /// A coin going to its day: smooth, no bounce.
        static let travel: Animation = .smooth(duration: 1.2)
    }
}

