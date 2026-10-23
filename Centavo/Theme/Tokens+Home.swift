import SwiftUI

// Chart and geometry values of the main screen (month bar, «En qué se va», calendar, carousel).

extension Theme.Size {
    /// Scaled. Height of the month bar's track.
    static let monthBarTrack: CGFloat = 20
    /// Gap between the pieces of the month bar.
    static let monthBarGap: CGFloat = 3
    /// The narrowest a day tile of the month bar may be drawn.
    static let minimumDayTile: CGFloat = 2
    /// Bars start this tall and grow to full: the full scale.
    static let barFullScale: CGFloat = 1
    /// How much taller than the track the «today» mark is, in all.
    static let todayMarkExtra: CGFloat = 8
    /// How far the «today» mark sticks out above the track.
    static let todayMarkInset: CGFloat = 4
    /// Half of `todayMarkWidth`: centers the mark on its x.
    static let todayMarkHalf: CGFloat = 1
    /// Distance between the hatch's diagonal lines.
    static let hatchSpacing: CGFloat = 5

    /// Scaled. Height of the split bar in «En qué se va».
    static let shareBar: CGFloat = 10
    /// The narrowest a category piece of the split bar may be (1 % still shows).
    static let minimumBarWidth: CGFloat = 3
    /// Scaled. Width of a category's icon column under the bar.
    static let shareIconColumn: CGFloat = 20
    /// Scaled. Least width of the share column under the bar.
    static let sharePercentColumn: CGFloat = 40
    /// Scaled. Least height of a category line under the bar.
    static let shareRow: CGFloat = 24
    /// Scaled. Height of the mosaic.
    static let mosaicHeight: CGFloat = 156
    /// The tallest the mosaic may grow with Dynamic Type.
    static let mosaicMaxHeight: CGFloat = 260
    /// Scaled. Text size the mosaic estimates its fit with.
    static let mosaicText: CGFloat = 12
    /// The gap between mosaic blocks.
    static let mosaicGap: CGFloat = 3
    /// Line height of a mosaic block's text, as a multiple of its size.
    static let mosaicLineHeightRatio: CGFloat = 1.35
    /// Width of a character of a mosaic block's text, as a multiple of its size.
    static let mosaicCharWidthRatio: CGFloat = 0.66

    /// Scaled. Height of the budget page's blank ticket.
    static let budgetBar: CGFloat = 84
    /// The tallest the budget page's blank ticket may grow with Dynamic Type.
    static let budgetBarMaxHeight: CGFloat = 132
    /// Scaled. The big figure's point size, to estimate its width.
    static let figureText: CGFloat = 22

    /// How far the page dots shift toward the dot's side to look centered.
    static let pageDotShift: CGFloat = 3
}

extension Theme.Opacity {
    /// 0.65: the dimmest breath of today's tile.
    static let tileBreath: Double = 0.65
}

extension Theme.Space {
    /// −10 pt. Pulls a 44 pt row into the air around it.
    static let tuck: CGFloat = -10
}
