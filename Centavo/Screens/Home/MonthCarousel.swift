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
    /// or by a tapped dot alike. Kept in an object so only what reads it redraws while it moves
    /// (the dots always; the height only when the pages differ), not the pages themselves.
    @State private var scroll = ScrollProgress()
    /// The page the carousel last came to rest on, to answer with a tick when it lands elsewhere.
    @State private var restingPage = 0
    @State private var landings = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Each page is as wide as the screen: measured by the list, not `containerRelativeFrame`,
    /// which stayed at the landscape width when the phone turned back upright.
    @Environment(\.listWidth) private var listWidth

    /// Pages of different heights (no «En qué se va»): the carousel's height is the one between
    /// them that the swipe has reached, so the calendar comes out like a ticket from the printer,
    /// row by row with the finger, and is whole the moment it lands. An eased height that ran on
    /// its own clock ended after the page and left the last row cut for a moment (owner, 2026-10-26).
    private var height: CGFloat? {
        guard let budget = heights[0], let calendar = heights[1] else { return heights.values.max() }
        return budget + (calendar - budget) * scroll.value
    }

    /// How much of the bottom edge fades while the height moves: none at rest, the most halfway.
    private var fold: CGFloat {
        equalHeights ? Theme.Space.none : Theme.Size.carouselFold * min(scroll.value, 1 - scroll.value) * 2
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
                        .frame(width: listWidth)
                        .id(0)
                    // Today's ring sits 3 pt outside its cell; the page margin leaves it room.
                    CalendarPage(model: calendarModel, selectedDay: selectedDay, onSelectDay: onSelectDay,
                                 currency: currency)
                        .padding(.horizontal, Theme.Space.screen)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[1] = $0 }
                        .frame(width: listWidth)
                        .id(1)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self, of: Self.progress) { _, value in scroll.value = value }
            // A light tick when the page lands on the other one, like a ticket torn off; none while
            // it moves, none if it springs back.
            .onScrollPhaseChange { _, phase in
                guard phase == .idle else { return }
                let landed = scroll.value < 0.5 ? 0 : 1
                if landed != restingPage { restingPage = landed; landings += 1 }
            }
            .sensoryFeedback(.selection, trigger: landings)
            // With both pages about as tall, the row of pages is as tall as the taller one by itself
            // and the carousel takes that: no height measured and set back, which on the owner's
            // iPhone settled on the calendar's and cut «En qué se va». Otherwise each page keeps
            // its own height and the carousel goes from one to the other with the swipe.
            .frame(height: equalHeights ? nil : height, alignment: .top)
            // While it grows or shrinks, the bottom edge fades like paper coming out, not a cut (the
            // owner preferred it to a perforated edge).
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

            PageDots(names: pageNames, scroll: scroll) { index in
                // The height follows the scroll, so it comes along with the page.
                withAnimation(reduceMotion ? nil : Theme.Motion.page) { page = index }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Where the carousel is between its two pages, written on every frame of a swipe.
@MainActor @Observable
private final class ScrollProgress {
    var value: CGFloat = 0
}

/// The two page dots. The lit pill travels with the swipe: it narrows on the page being left and
/// widens on the one coming, and the pair slides by the same fraction, instead of jumping when the
/// page lands.
private struct PageDots: View {
    let names: [String]
    let scroll: ScrollProgress
    let onTap: (Int) -> Void

    /// How lit each dot is: 1 on the page shown, 0 on the other, in between while it moves.
    private func lit(_ index: Int) -> CGFloat { index == 0 ? 1 - scroll.value : scroll.value }

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
