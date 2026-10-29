import SwiftUI

extension Theme.Space {
    /// 3 pt. Extra gap between the lines of a paragraph in the Wallet guide (`lineSpacing`).
    static let guideLine: CGFloat = 3
}

extension Theme.Size {
    /// The narrowest a tile of «Tarjetas y categorías» gets: four across on an iPhone.
    static let catalogTile: CGFloat = 76
    /// Scaled. The height of every tile there: a symbol and two lines of name.
    static let catalogTileHeight: CGFloat = 78
}

extension Theme.Size {
    /// The budget sheet's drawing of «Se acumula» / «Se reparte» (`AllowanceExplainer`): its
    /// whole height, the tallest bar, the amount that bar stands for, a coin, the caption.
    static let explainerHeight: CGFloat = 124
    static let explainerBars: CGFloat = 76
    static let explainerScale: CGFloat = 200
    static let explainerCoin: CGFloat = 16
    static let explainerCaption: CGFloat = 34
}

extension Theme.Motion {
    /// The toy week of the budget sheet, one day after another.
    enum Explainer {
        /// Seconds before the week starts, each day's beat, before a coin leaves, while it
        /// travels, and at the end before it starts over.
        static let start: Double = 0.8
        static let dayBeat: Double = 1.0
        static let coinWait: Double = 0.05
        static let travelTime: Double = 0.95
        static let end: Double = 2.4
        /// A day filling or an outline growing.
        static let fill: Animation = .smooth(duration: 0.6)
        /// A coin going to its day: smooth, no bounce.
        static let travel: Animation = .smooth(duration: 0.9)
    }
}

