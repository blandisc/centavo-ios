import CentavoCore
import SwiftUI

/// The swipeable middle of the main screen: budget first, then the calendar.
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

    @State private var page: Int? = 0
    /// Each page's own height.
    @State private var heights: [Int: CGFloat] = [:]
    /// How far the carousel is from the budget (0) to the calendar (1), frame by frame, by finger
    /// or by a tapped dot alike.
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var onBudgetPage: Bool { (page ?? 0) == 0 }

    /// Pages of different heights (no «En qué se va»): the carousel's height is the one between
    /// them that the swipe has reached, so the calendar comes out like a ticket from the printer,
    /// row by row with the finger, and is whole the moment it lands. An eased height that ran on
    /// its own clock ended after the page and left the last row cut for a moment (owner, 2026-10-26).
    private var height: CGFloat? {
        guard let budget = heights[0], let calendar = heights[1] else { return heights.values.max() }
        return budget + (calendar - budget) * progress
    }

    /// How much of the bottom edge fades while the height moves: none at rest, the most halfway.
    private var fold: CGFloat {
        equalHeights ? Theme.Space.none : Theme.Size.carouselFold * min(progress, 1 - progress) * 2
    }

    private static func progress(_ geometry: ScrollGeometry) -> CGFloat {
        guard geometry.containerSize.width > 0 else { return 0 }
        return min(max(geometry.contentOffset.x / geometry.containerSize.width, 0), 1)
    }

    private let pageNames = ["Presupuesto", "Calendario"]

    var body: some View {
        VStack(spacing: Theme.Space.none) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Theme.Space.none) {
                    BudgetPage(spent: spent, pace: pace, isCurrentMonth: isCurrentMonth, outside: outside,
                               shares: shares, returned: returned, note: note, selectedCategory: selectedCategory,
                               onSelectCategory: onSelectCategory, entrance: entrance, onSetBudget: onSetBudget)
                        .padding(.horizontal, Theme.Space.screen)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[0] = $0 }
                        .containerRelativeFrame(.horizontal)
                        .id(0)
                    // Today's ring sits 3 pt outside its cell; the page margin leaves it room.
                    CalendarPage(model: calendarModel, selectedDay: selectedDay, onSelectDay: onSelectDay,
                                 currency: currency)
                        .padding(.horizontal, Theme.Space.screen)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[1] = $0 }
                        .containerRelativeFrame(.horizontal)
                        .id(1)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .scrollIndicators(.hidden)
            // Only pages of different heights need to know where the swipe is.
            .onScrollGeometryChange(for: CGFloat.self, of: Self.progress) { _, value in
                if !equalHeights { progress = value }
            }
            // With both pages about as tall, the row of pages is as tall as the taller one by itself
            // and the carousel takes that: no height measured and set back, which on the owner's
            // iPhone settled on the calendar's and cut «En qué se va». Otherwise each page keeps
            // its own height and the carousel goes from one to the other with the swipe.
            .frame(height: equalHeights ? nil : height, alignment: .top)
            // While it grows or shrinks, the bottom edge fades like paper coming out, not a cut.
            .mask(alignment: .top) {
                if equalHeights {
                    // Nothing moves; room for a pressed mosaic block to lift (see below).
                    Rectangle().padding(-Theme.Space.xxl)
                } else {
                    VStack(spacing: Theme.Space.none) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: fold)
                    }
                }
            }
            // While the height moves, nothing of the taller page draws over the list. With both pages
            // the same height nothing moves, and a pressed mosaic block, which iOS lifts a little
            // larger before its detail opens, must not be cut at the carousel's edge (owner's iPhone).
            .scrollClipDisabled(equalHeights)
            .clipShape(Rectangle().inset(by: equalHeights ? -Theme.Space.xxl : Theme.Space.none))
            // A page that changes height in place (choosing «No mostrar» in «Más») eases too. Keyed
            // on the pages' heights, not the current one's: that one also changes on a page change,
            // and this slow ease then won over the page's own and the calendar's last row stayed cut.
            .animation(reduceMotion ? nil : Theme.Motion.restyle, value: heights)

            HStack(spacing: Theme.Space.xxs) {
                ForEach(pageNames.indices, id: \.self) { index in
                    Button {
                        // The height follows the scroll, so it comes along with the page.
                        withAnimation(reduceMotion ? nil : Theme.Motion.page) { page = index }
                    } label: {
                        Capsule()
                            .fill(page == index ? Theme.ink : Theme.dimmed)
                            .frame(width: page == index ? Theme.Size.pageDotCurrent : Theme.Size.pageDot,
                                   height: Theme.Size.pageDot)
                            .frame(width: Theme.Size.tapTarget, height: Theme.Size.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pageNames[index])
                    .accessibilityAddTraits(page == index ? .isSelected : [])
                }
            }
            // The lit pill is 12 pt wider than the dot, so centering the two 44 pt slots left the
            // ink 3 pt off the middle (measured): shift it back toward the dot's side.
            .offset(x: onBudgetPage ? Theme.Size.pageDotShift : -Theme.Size.pageDotShift)
            .animation(reduceMotion ? nil : Theme.Motion.settle, value: page)
            .frame(maxWidth: .infinity)
        }
    }
}
