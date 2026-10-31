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

    /// A page asked from outside (a swipe on the figure); and whether a finger reading the boleto
    /// holds the carousel still.
    var request = CarouselRequest()
    var scrollLocked = false

    @AppStorage(WhereItGoesStyle.key) private var storedStyle = WhereItGoesStyle.bar.rawValue
    @State private var position = ScrollPosition(idType: Int.self)
    /// The page shown or on its way, by finger or by dot, to put the carousel back on it when
    /// the phone turns.
    @State private var page = 0
    /// Each page's own height.
    @State private var heights: [Int: CGFloat] = [:]
    /// How far the carousel is from the budget (0) to the calendar (1), frame by frame, by finger
    /// or by a tapped dot alike. Kept in an object so only what reads it redraws while it moves
    /// (the dots always; the height only when the pages differ), not the pages themselves.
    @State private var scroll = ScrollProgress()
    /// The page the carousel last came to rest on, to answer with a tick when it lands elsewhere.
    @State private var restingPage = 0
    @State private var landings = 0
    /// True while a finger drags the pages or they glide to rest. The page swipe over the header
    /// then leaves them alone: a second animation on top of iOS's own stopped the glide dead and
    /// started it again, which the owner felt as a jolt (2026-10-30).
    @State private var moving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Each page is as wide as the screen: measured by the list, not `containerRelativeFrame`,
    /// which stayed at the landscape width when the phone turned back upright.
    @Environment(\.listWidth) private var listWidth

    /// Measured against a page's width (half the row of two) and counting the inset: in landscape
    /// the scroll view also spans the strip kept clear for the Dynamic Island and starts the pages
    /// past it, so the calendar never got past 0.93 and its height, which follows this, left the
    /// last row cut (measured, 2026-10-27).
    private static func progress(_ geometry: ScrollGeometry) -> CGFloat {
        let page = geometry.contentSize.width / 2
        guard page > 0 else { return 0 }
        return min(max((geometry.contentOffset.x + geometry.contentInsets.leading) / page, 0), 1)
    }

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
            ScrollView(.horizontal) {
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
                        .id(0)
                        .modifier(PageFade(reduceMotion: reduceMotion))
                    // Today's ring sits 3 pt outside its cell; the page margin leaves it room.
                    calendarPage
                        .padding(.horizontal, Theme.Space.screen)
                        .padding(.vertical, Theme.Space.m)
                        .contentShape(Rectangle())
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[1] = $0 }
                        .frame(width: listWidth)
                        .id(1)
                        .modifier(PageFade(reduceMotion: reduceMotion))
                }
                .scrollTargetLayout()
            }
            // iOS glides the page to rest with the finger's own momentum; this only picks the page,
            // with less travel than a half page (see `EasyPaging`).
            .scrollTargetBehavior(EasyPaging(page: page))
            .scrollPosition($position, anchor: .leading)
            .scrollDisabled(scrollLocked)
            .onChange(of: request) { _, asked in
                // The finger is on the pages: iOS is already taking them there.
                guard !moving else { return }
                page = asked.page
                withAnimation(reduceMotion ? nil : Theme.Motion.pageTurn) { position.scrollTo(id: asked.page, anchor: .leading) }
            }
            // Turning the phone changes the pages' width but not where the scroll stands, so it
            // was left between two pages: the other one peeking in and, with the height following
            // the scroll, the calendar cut short. Back square on the page it rested on.
            .onChange(of: listWidth) { _, _ in
                Theme.Motion.instantly { position.scrollTo(id: page, anchor: .leading) }
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self, of: Self.progress) { _, value in scroll.value = value }
            // A light tick when the page lands on the other one, like a ticket torn off; none while
            // it moves, none if it springs back.
            .onScrollPhaseChange { _, phase in
                moving = phase != .idle
                guard phase == .idle else { return }
                let landed = scroll.value < 0.5 ? 0 : 1
                page = landed
                if landed != restingPage { restingPage = landed; landings += 1 }
            }
            .sensoryFeedback(.selection, trigger: landings)
            // The height and the fading edge follow the swipe frame by frame. They read it in a
            // modifier of their own, so each frame redraws them and not the pages.
            .modifier(CarouselFold(scroll: scroll, heights: heights, equalHeights: equalHeights))
            // While the height moves, nothing of the taller page draws over the list. With both pages
            // the same height nothing moves, and a pressed mosaic block, which iOS lifts a little
            // larger before its detail opens, must not be cut at the carousel's edge (owner's iPhone).
            // Not clipped by the scroll view: the boleto's day card rises over the line above the
            // carousel. The mask below still keeps the next page and the list out.
            .scrollClipDisabled()
            .mask {
                Rectangle()
                    // Room over the top for the boleto's day card (2026-10-30).
                    .padding(.top, -Theme.Size.monthCodeCardRoom)
                    .padding(.bottom, equalHeights ? -Theme.Space.xxl : Theme.Space.none)
            }
            // A page that changes height in place (choosing «No mostrar» in «Más») eases too. Keyed
            // on the pages' heights, not the current one's: that one also changes on a page change,
            // and this slow ease then won over the page's own and the calendar's last row stayed cut.
            .animation(reduceMotion ? nil : Theme.Motion.restyle, value: heights)

            PageDots(names: pageNames, scroll: scroll) { index in
                // The height follows the scroll, so it comes along with the page.
                page = index
                withAnimation(reduceMotion ? nil : Theme.Motion.pageTurn) { position.scrollTo(id: index, anchor: .leading) }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Paging for the carousel's two pages that turns with a short swipe: the page goes over once the
/// finger, with its momentum, would carry it `pageSwipeDistance` past where it rested, not half a
/// page as `.paging` asks. Where it lands is all this decides; the glide there is iOS's own.
private struct EasyPaging: ScrollTargetBehavior {
    /// The page the carousel rested on when the finger came down.
    let page: Int

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let width = context.containerSize.width
        guard width > 0 else { return }
        let lastPage = max(Int((context.contentSize.width / width).rounded()) - 1, 0)
        let travel = context.originalTarget.rect.minX - CGFloat(page) * width
        var next = page
        if travel >= Theme.Size.pageSwipeDistance { next += 1 }
        if travel <= -Theme.Size.pageSwipeDistance { next -= 1 }
        target.rect.origin.x = CGFloat(min(max(next, 0), lastPage)) * width
    }
}

/// A page fading as it leaves and coming in as it arrives, with the finger: the two never show
/// whole side by side, so the boleto reads as turning into the calendar (owner, 2026-10-30).
private struct PageFade: ViewModifier {
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content.scrollTransition(axis: .horizontal) { page, phase in
            // Squared: each page stays mostly there until the other has come halfway, so the middle
            // of the swipe is not two half-dim pages.
            page.opacity(reduceMotion ? Theme.Opacity.visible : Theme.Opacity.visible - phase.value * phase.value)
        }
    }
}

/// The carousel's height and its fading bottom edge, which follow the swipe.
///
/// The only part of the carousel that reads `scroll` frame by frame besides the dots: as a
/// modifier, redrawing it on each frame of a swipe leaves the pages it wraps as they are.
private struct CarouselFold: ViewModifier {
    let scroll: ScrollProgress
    /// Each page's own height.
    let heights: [Int: CGFloat]
    let equalHeights: Bool

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
