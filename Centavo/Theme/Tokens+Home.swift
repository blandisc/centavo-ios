import SwiftUI

// Chart and geometry values of the main screen (month bar, «En qué se va», calendar, carousel).

extension Theme.Size {
    /// Scaled. Height of the month bar's track.
    static let monthBarTrack: CGFloat = 20
    /// Gap between the pieces of the month bar.
    static let monthBarGap: CGFloat = 3
    /// Gap between two days' cells of the month bar (it is cut by days, 2026-10-29).
    static let monthBarCellGap: CGFloat = 2
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
    /// Scaled. Width of a category's icon column under the bar: the same as `Size.glyph`, so
    /// the names start on the line of the Wallet row and the day headers.
    static let shareIconColumn: CGFloat = 14
    /// Scaled. Least width of the share column under the bar.
    static let sharePercentColumn: CGFloat = 40
    /// Scaled. Least height of a category line under the bar.
    static let shareRow: CGFloat = 29
    /// Scaled. Height of «En qué se va», the bar's and the mosaic's the same, so choosing one or the
    /// other in «Más» moves nothing below it: the bar (10) and its gap (12) over five lines of 29.
    /// As tall as the calendar page, so the space over the page dots is the same on both.
    static let shareChartHeight: CGFloat = 167
    /// The tallest the chart may grow with Dynamic Type.
    static let shareChartMaxHeight: CGFloat = 260
    /// The gap between mosaic blocks.
    static let mosaicGap: CGFloat = 3
    /// Width of the card a mosaic block opens when pressed and held: wide enough for a long name
    /// and a large amount, which the block itself may have had no room for.
    static let mosaicPreviewWidth: CGFloat = 260

    /// Scaled. Height of the budget page's blank ticket.
    static let budgetBar: CGFloat = 84
    /// The tallest the budget page's blank ticket may grow with Dynamic Type.
    static let budgetBarMaxHeight: CGFloat = 132
    /// Scaled. The big figure's point size, to estimate its width.
    static let figureText: CGFloat = 22

    /// The most of the carousel's bottom edge that fades while its height follows a swipe
    /// (halfway through it; none at rest).
    static let carouselFold: CGFloat = 28

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
    /// −4 pt, above and below. The hero figure's line is taller than its digits (about 18 pt of
    /// air over them and 15 under, measured): trimmed so the caption and the verdict sit a breath
    /// from the figure (about 14 pt, ink to ink, measured on the simulator), closer than one
    /// section is to the next (about 26 pt).
    static let heroTrim: CGFloat = -4
}

extension Theme.Motion {
    /// Seconds «Deshacer» stays after a delete; longer with VoiceOver, to reach it.
    static let undoSeconds: Double = 6
    static let undoLongSeconds: Double = 15
    /// A panel folding or unfolding in place: slow enough to follow, no bounce.
    static let fold: Animation = .smooth(duration: 0.42)
    /// What unfolds shows once there is room for it, so it never draws over what is moving
    /// down below; folding, it goes first and the room closes after (owner, 2026-10-29).
    static let revealIn: Animation = .easeOut(duration: 0.22).delay(0.2)
    static let revealOut: Animation = .easeIn(duration: 0.12)
}

extension AnyTransition {
    /// What a panel shows when it unfolds (`Theme.Motion.fold`): fades in after the room
    /// opens, fades out before it closes. Use it for every fold, so they all move alike.
    static var unfold: AnyTransition {
        .asymmetric(insertion: .opacity.animation(Theme.Motion.revealIn),
                    removal: .opacity.animation(Theme.Motion.revealOut))
    }
}


// The month's barcode under the budget bar (`MonthCodeView`).
extension Theme.Size {
    /// Scaled. Height of the barcode's bars at their tallest.
    static let monthCode: CGFloat = 40
    /// The shortest a day's bar is drawn, so a quiet day still reads as a bar.
    static let monthCodeFloor: CGFloat = 0.1
    /// Gap between two days' bars.
    static let monthCodeGap: CGFloat = 2
    /// The scanner's light that crosses the code now and then.
    static let monthCodeScan: CGFloat = 2
    /// How far the scanner's light glows.
    static let monthCodeGlow: CGFloat = 6
    /// Width of the card a day opens while the finger is on it.
    static let monthCodeCard: CGFloat = 210
}

extension Theme.Opacity {
    /// 0.5: a plain day's bar, so the brass and red days stand out.
    static let codeBar: Double = 0.5
    /// 0.22: the other days while one is picked.
    static let codeBarAside: Double = 0.22
}

extension Theme.Motion {
    /// The scanner's light crosses the code once every this many seconds…
    static let scanEvery: Duration = .seconds(9)
    /// …taking this long.
    static let scan: Animation = .easeInOut(duration: 1.4)
    /// …and is gone this long after it set off (the crossing plus a beat).
    static let scanShown: Duration = .seconds(1.3)
    /// …then fades out (`settle`) before going back to the left, unseen.
    static let scanFade: Duration = .seconds(0.4)
    /// Today's bar breathes, like a cursor waiting.
    static let todayBreath: Animation = .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
}
