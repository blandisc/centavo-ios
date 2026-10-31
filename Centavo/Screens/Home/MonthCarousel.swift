import CentavoCore
import SwiftUI

/// The swipeable middle of the main screen, in every view (owner, 2026-10-30): on the left the
/// month's barcode with «En qué se va» under it (Lista or Mosaico; alone in Mínima), on the right
/// the calendar. The bar stays above, out of the carousel.
struct MonthCarousel: View {
    let calendarModel: MonthCalendar
    var selectedDay: Int?
    var onSelectDay: (Int?) -> Void = { _ in }
    let spent: MoneyTotal
    let pace: BudgetPace?
    let isCurrentMonth: Bool
    /// What was left out of the budget this month (`MonthSummary.outside`).
    var outside: Decimal = 0
    var shares: [CategoryShare] = []
    var returned: Decimal = 0
    var note: String?
    var selectedCategory: CategoryShare?
    var onSelectCategory: (CategoryShare?) -> Void = { _ in }
    /// What of the screen's entrance has played (`Entrance`).
    var entrance = Entrance()
    /// Whether both pages are as tall as the taller one: true while «En qué se va» fills the
    /// budget page, which is about as tall as the calendar, so a swipe moves nothing below. A
    /// short budget page (no chart) keeps its own height, or it would leave a hole above the list.
    var equalHeights = false
    let onSetBudget: () -> Void
    var currency = CurrencyPreference.fallback
    /// At the top of the first page: the month's barcode.
    var budgetHeader: AnyView?
    var now = Date.now

    /// Where the pages stand; the swipe over the whole top of the screen moves it.
    let motion: CarouselMotion

    @AppStorage(WhereItGoesStyle.key) private var storedStyle = WhereItGoesStyle.bar.rawValue
    /// Each page's own height.
    @State private var heights: [Int: CGFloat] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Each page is as wide as the screen: measured by the list, not `containerRelativeFrame`,
    /// which stayed at the landscape width when the phone turned back upright.
    @Environment(\.listWidth) private var listWidth

    private let pageNames = ["Presupuesto", "Calendario"]

    var body: some View { pages }

    private var calendarPage: some View {
        CalendarPage(model: calendarModel, selectedDay: selectedDay, onSelectDay: onSelectDay, currency: currency)
    }

    private var pages: some View {
        VStack(alignment: .leading, spacing: Theme.Space.none) {
            // One heading for both pages, outside the scroll: it stays still while the boleto
            // turns into the calendar, and both start on the same line under it (owner, 2026-10-30).
            Text("Cada día del mes").ticketCaption()
                .padding(.horizontal, Theme.Space.screen)
                // The air the boleto had under the figure, now over the heading.
                .padding(.top, Theme.Space.m)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: Theme.Space.none) {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    budgetHeader
                    if BudgetPage.hasBottom(shares: shares, note: note, style: storedStyle) {
                        BudgetPage(spent: spent, pace: pace, isCurrentMonth: isCurrentMonth, outside: outside,
                                   shares: shares, returned: returned, note: note, selectedCategory: selectedCategory,
                                   onSelectCategory: onSelectCategory, entrance: entrance, onSetBudget: onSetBudget,
                                   currency: currency, now: now, part: .bottom)
                    }
                }
                .padding(.horizontal, Theme.Space.screen)
                // More room to swipe on, above and below the boleto (owner, 2026-10-30: in
                // «Mínima» it was a thin strip, hard to hit).
                .padding(.vertical, Theme.Space.m)
                .contentShape(Rectangle())
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[0] = $0 }
                .frame(width: listWidth)
                .modifier(PageFade(index: 0, motion: motion, reduceMotion: reduceMotion))
                // Today's ring sits 3 pt outside its cell; the page margin leaves it room.
                calendarPage
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.vertical, Theme.Space.m)
                    .contentShape(Rectangle())
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[1] = $0 }
                    .frame(width: listWidth)
                    .modifier(PageFade(index: 1, motion: motion, reduceMotion: reduceMotion))
            }
            // The row of two pages is twice the screen; the carousel shows one page's width of it,
            // slid by where the pages stand (`CarouselMotion`). No scroll view: the swipe over the
            // whole top of the screen moves them, so one thing moves them.
            .modifier(PageSlide(motion: motion))
            .frame(width: listWidth, alignment: .leading)
            // One page's width, measured where the pages show: the swipe counts in it.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { motion.width = $0 }
            // The height and the fading edge follow the pages frame by frame. They read them in a
            // modifier of their own, so each frame redraws them and not the pages.
            .modifier(CarouselFold(motion: motion, heights: heights, equalHeights: equalHeights))
            // Keeps the other page out at the sides, and the list out below while the height
            // moves. Room over the top for the boleto's day card, which rises over the line above
            // (2026-10-30), and below for a pressed mosaic block, which iOS lifts a little larger.
            .mask {
                Rectangle()
                    .padding(.top, -Theme.Size.monthCodeCardRoom)
                    .padding(.bottom, equalHeights ? -Theme.Space.xxl : Theme.Space.none)
            }
            // A page that changes height in place (choosing «Mínima» in «···») eases too.
            .animation(reduceMotion ? nil : Theme.Motion.restyle, value: heights)
            // A light tick when the pages land on the other one, like a ticket torn off.
            .sensoryFeedback(.selection, trigger: motion.landings)

            PageDots(names: pageNames, motion: motion) { index in
                motion.go(to: index, reduceMotion: reduceMotion)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// The row of pages slid to where they stand. Its own modifier: each frame of a swipe redraws
/// this offset, not the pages.
private struct PageSlide: ViewModifier {
    let motion: CarouselMotion

    func body(content: Content) -> some View {
        content.offset(x: -motion.progress * motion.width)
    }
}

/// A page fading as it leaves and coming in as it arrives, with the finger: the two never show
/// whole side by side, so the boleto reads as turning into the calendar (owner, 2026-10-30).
/// Squared, so each page stays mostly there until the other has come halfway and the middle of
/// the swipe is not two half-dim pages. Only the page the carousel rests on takes touches and
/// VoiceOver.
private struct PageFade: ViewModifier {
    let index: Int
    let motion: CarouselMotion
    let reduceMotion: Bool

    private var opacity: Double {
        let away = min(abs(motion.progress - CGFloat(index)), 1)
        return reduceMotion ? Theme.Opacity.visible : Theme.Opacity.visible - away * away
    }

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .allowsHitTesting(motion.page == index)
            .accessibilityHidden(motion.page != index)
    }
}

/// The carousel's height and its fading bottom edge, which follow the swipe.
///
/// The only part of the carousel that reads `motion` frame by frame besides the slide and the
/// dots: as a modifier, redrawing it on each frame of a swipe leaves the pages it wraps as they are.
private struct CarouselFold: ViewModifier {
    let motion: CarouselMotion
    /// Each page's own height.
    let heights: [Int: CGFloat]
    let equalHeights: Bool

    /// Pages of different heights (no «En qué se va»): the carousel's height is the one between
    /// them that the swipe has reached, so the calendar comes out like a ticket from the printer,
    /// row by row with the finger, and is whole the moment it lands. An eased height that ran on
    /// its own clock ended after the page and left the last row cut for a moment (owner, 2026-10-26).
    private var height: CGFloat? {
        guard let budget = heights[0], let calendar = heights[1] else { return heights.values.max() }
        return budget + (calendar - budget) * min(max(motion.progress, 0), 1)
    }

    /// How much of the bottom edge fades while the height moves: none at rest, the most halfway.
    private var fold: CGFloat {
        equalHeights ? Theme.Space.none : Theme.Size.carouselFold * max(min(motion.progress, 1 - motion.progress), 0) * 2
    }

    func body(content: Content) -> some View {
        content
            // With both pages about as tall, the row of pages is as tall as the taller one by itself
            // and the carousel takes that: no height measured and set back, which on the owner's
            // iPhone settled on the calendar's and cut «En qué se va». Otherwise each page keeps
            // its own height and the carousel goes from one to the other with the swipe.
            .frame(height: equalHeights ? nil : height, alignment: .top)
            // While it grows or shrinks, the bottom edge fades like paper coming out, not a cut (the
            // owner preferred it to a perforated edge).
            .mask(alignment: .top) {
                if equalHeights {
                    // Nothing moves; room above and below for a pressed mosaic block to lift (see
                    // below). Not to the sides: in landscape the next page showed there, in the
                    // strip kept clear for the Dynamic Island.
                    Rectangle()
                        .padding(.top, -Theme.Size.monthCodeCardRoom)
                        .padding(.bottom, -Theme.Space.xxl)
                } else {
                    VStack(spacing: Theme.Space.none) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: fold)
                    }
                    // Room over the top for the boleto's day card (2026-10-30).
                    .padding(.top, -Theme.Size.monthCodeCardRoom)
                }
            }
    }
}

/// The two page dots. The lit pill travels with the swipe: it narrows on the page being left and
/// widens on the one coming, and the pair slides by the same fraction, instead of jumping when the
/// page lands.
private struct PageDots: View {
    let names: [String]
    let motion: CarouselMotion
    let onTap: (Int) -> Void

    /// How lit each dot is: 1 on the page shown, 0 on the other, in between while it moves.
    private func lit(_ index: Int) -> CGFloat {
        let calendar = min(max(motion.progress, 0), 1)
        return index == 0 ? 1 - calendar : calendar
    }

    /// Toward the lit side: all the way on either page, none halfway.
    private var shift: CGFloat {
        let budget = lit(0), calendar = lit(1)
        return Theme.Size.pageDotShift * (budget - calendar)
    }

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            ForEach(names.indices, id: \.self) { index in
                Button { onTap(index) } label: {
                    Capsule()
                        .fill(Theme.dimmed)
                        .overlay { Capsule().fill(Theme.ink).opacity(lit(index)) }
                        .frame(width: Theme.Size.pageDot + (Theme.Size.pageDotCurrent - Theme.Size.pageDot) * lit(index),
                               height: Theme.Size.pageDot)
                        .frame(width: Theme.Size.tapTarget, height: Theme.Size.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[index])
                .accessibilityAddTraits(lit(index) > 0.5 ? .isSelected : [])
            }
        }
        // The lit pill is 12 pt wider than the dot, so centering the two 44 pt slots left the
        // ink 3 pt off the middle (measured): shift it back toward the lit dot's side, by as much
        // as the swipe has gone.
        .offset(x: shift)
    }
}
