import SwiftUI

// Chart and geometry values of the main screen (boleto, «En qué se va», calendar, carousel).

extension Theme.Size {
    /// Gap between two days' cells of the boleto, and of the empty screen's strip of days.
    static let monthBarCellGap: CGFloat = 2
    /// Bars start this tall and grow to full: the full scale.
    static let barFullScale: CGFloat = 1
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
    /// Scaled. Least height of a category line under the bar. 29 pt on purpose, not the 44 pt
    /// of a row that is tapped (owner's decision, 2026-11-11): five lines fit without scrolling
    /// and they sit flush against each other, so a touch near a line still lands on its category.
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

    /// The most of the carousel's bottom edge that fades while its height follows a swipe
    /// (halfway through it; none at rest).
    static let carouselFold: CGFloat = 28

    /// How far the page dots shift toward the dot's side to look centered.
    static let pageDotShift: CGFloat = 3

    /// Scaled. Height of «Menos devoluciones», the line under «En qué se va»: the chart gives
    /// it up, with the gap over it, so the page is as tall with money returned as without.
    static let shareReturnedLine: CGFloat = 16
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
    static let fold: Animation = .smooth(duration: foldSeconds)
    static let foldSeconds: Double = 0.42
    /// What unfolds shows once there is room for it, so it never draws over what is moving
    /// down below; folding, it goes first and the room closes after (owner, 2026-10-29).
    static let revealIn: Animation = .easeOut(duration: 0.22).delay(0.2)
    static let revealOut: Animation = .easeIn(duration: revealOutSeconds)
    static let revealOutSeconds: Double = 0.12
}

extension AnyTransition {
    /// What a panel shows when it unfolds (`Theme.Motion.fold`): fades in after the room
    /// opens, fades out before it closes. Use it for every fold, so they all move alike.
    static var unfold: AnyTransition {
        .asymmetric(insertion: .opacity.animation(Theme.Motion.revealIn),
                    removal: .opacity.animation(Theme.Motion.revealOut))
    }
}

extension AnyTransition {
    /// The sum behind the tear line (owner, 2026-11-08): it slides down out from under the cut
    /// like a receipt coming out of the printer, its last line moving with the page below it
    /// (`Theme.Motion.fold`), and slides back up under it as it closes. Straight down, no turn,
    /// no fade, no bounce. It replaces the flap of 2026-11-04, which read as a sheet falling forward.
    static var printOut: AnyTransition {
        .modifier(active: PrintOut(tucked: true), identity: PrintOut(tucked: false))
    }
}

private struct PrintOut: ViewModifier {
    let tucked: Bool

    func body(content: Content) -> some View {
        content
            .visualEffect { [tucked] effect, proxy in
                effect.offset(y: tucked ? -proxy.size.height : .zero)
            }
            // Only what has come out from under the cut shows.
            .clipped()
    }
}


// The «+» beside the tabs (`RootView`, owner 2026-11-14): a circle as tall as the tab bar.
extension Theme.Size {
    /// Side of the «+» inside its glass, which adds about 7 pt around it: together as tall as the
    /// system's floating tab bar, 59 pt (measured, iOS 27).
    static let addCircle: CGFloat = 45
}


extension Theme.Space {
    /// How far the tab bar sits under the bottom safe area (measured, iOS 27): the «+» goes as
    /// low, so its middle lines up with the bar's.
    static let tabBarDrop: CGFloat = -13
}

// The boleto (`MonthCodeView`).
extension Theme.Size {
    /// Scaled. Height of the boleto's cells: what a day may spend.
    static let monthCode: CGFloat = 34
    /// How far a finger may drift while it holds the boleto before the hold fails and the swipe
    /// is the carousel's.
    static let scrubSlop: CGFloat = 8
    /// How much more sideways than vertical a finger must go for a sideways pan to begin: 1.3
    /// for a row's «Borrar»; just more sideways than vertical to turn the carousel's page.
    static let sidewaysRatio: CGFloat = 1.3
    static let pageSwipeRatio: CGFloat = 1
    /// A quick sideways flick turns the page even if short.
    static let pageSwipeVelocity: CGFloat = 300
    /// A swipe turns the carousel's page once it went this far sideways.
    static let pageSwipeDistance: CGFloat = 36
    /// Past the first or the last page the pages follow the finger at this fraction, like the
    /// edge of any iOS scroll.
    static let pageEdgeResistance: CGFloat = 0.3
    /// The red tick over a day past its limit.
    static let monthCodeTick: CGFloat = 3
    /// Room the carousel leaves over its top for the boleto's day card, which rises over the
    /// line above it.
    static let monthCodeCardRoom: CGFloat = 140
    /// How far the day card's shadow spreads.
    static let monthCodeGlow: CGFloat = 6
    /// Width of the card a day opens while the finger is on it: wide enough for the day and its
    /// amount on one line and its sentence on the next, so the card is two lines tall and stays
    /// under the hero's figure (2026-11-11; it was 210 and four lines, over the figure).
    static let monthCodeCard: CGFloat = 300
}

extension Theme.Opacity {
    /// 0.22: the other days while one is picked.
    static let codeBarAside: Double = 0.22
}

extension Theme.Motion {
    /// How long a finger rests on the boleto before sliding reads the days; a quicker swipe goes
    /// to the calendar.
    static let scrubHold: Double = 0.25
    /// Today's cell breathes, like a cursor waiting: this many times, each half this long, then
    /// it rests at full (`breathes`).
    static let todayBreaths = 3
    static let todayBreathSeconds: Double = 0.8
    /// The boleto's entrance (`Entrance.code`: 0.1 s late, 0.3 s long) is over before today
    /// starts breathing.
    static let todayBreathAfter: Double = 0.5
}
