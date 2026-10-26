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
    /// Each page's own height. The carousel is as tall as the page it is going to, so a
    /// short budget page (no «En qué se va») leaves no empty band above the list.
    @State private var heights: [Int: CGFloat] = [:]
    /// What each page needs, before it is stretched to match the other.
    @State private var needs: [Int: CGFloat] = [:]
    /// The page the carousel is sized for. It changes once per swipe, as soon as the finger
    /// says where it is going, and the height eases there in one animation while the page
    /// slides in. A height that followed the finger frame by frame relaid the whole list
    /// below on every frame and felt rough (#77); one that changed when the page settled
    /// leapt (before #74).
    @State private var sizedFor = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var onBudgetPage: Bool { (page ?? 0) == 0 }

    private var height: CGFloat? { heights[sizedFor] ?? heights.values.max() }

    /// The height both pages share, when they share one. An exact height, not a least one: a least
    /// height took the carousel's own (the scroll view proposes it) and never came back down.
    private var sharedHeight: CGFloat? { equalHeights ? needs.values.max() : nil }

    /// How far a swipe is from the budget (0) to the calendar (1), in tenths: only the
    /// tenths cross into `resize`, not every frame.
    private static func stage(_ geometry: ScrollGeometry) -> Int {
        guard geometry.containerSize.width > 0 else { return 0 }
        let progress = geometry.contentOffset.x / geometry.containerSize.width
        return Int((min(max(progress, 0), 1) * 10).rounded())
    }

    /// The stage the last swipe step reached, to know which way the finger is going.
    @State private var lastStage = 0

    /// Heading for a taller page, the height starts growing a tenth of the way, so the page
    /// lands whole; heading for a shorter one, it starts shrinking halfway, while the page is
    /// still moving, so the list below rises with the swipe instead of after it. The way is
    /// read from the swipe itself, not from the scroll position: that one names the other
    /// page halfway and made the list go down, up and down.
    private func resize(for stage: Int) {
        defer { lastStage = stage }
        let target: Int
        if stage == 0 || stage == 10 {
            target = stage == 0 ? 0 : 1
        } else if stage == lastStage {
            return
        } else {
            let heading = stage > lastStage ? 1 : 0
            let travel = Double(heading == 1 ? stage : 10 - stage) / 10
            let grows = (heights[heading] ?? 0) >= (heights[1 - heading] ?? 0)
            target = travel >= (grows ? 0.1 : 0.5) ? heading : 1 - heading
        }
        guard target != sizedFor else { return }
        withAnimation(reduceMotion ? nil : Theme.Motion.resize) { sizedFor = target }
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
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { needs[0] = $0 }
                        .frame(height: sharedHeight, alignment: .top)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[0] = $0 }
                        .containerRelativeFrame(.horizontal)
                        .id(0)
                    // Today's ring sits 3 pt outside its cell; the page margin leaves it room.
                    CalendarPage(model: calendarModel, selectedDay: selectedDay, onSelectDay: onSelectDay,
                                 currency: currency)
                        .padding(.horizontal, Theme.Space.screen)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { needs[1] = $0 }
                        .frame(height: sharedHeight, alignment: .top)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[1] = $0 }
                        .containerRelativeFrame(.horizontal)
                        .id(1)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .scrollIndicators(.hidden)
            // Only crossing a stage reaches `resize`: the swipe itself changes no state.
            .onScrollGeometryChange(for: Int.self, of: Self.stage) { _, stage in resize(for: stage) }
            .frame(height: height, alignment: .top)
            // While the height eases, nothing of the taller page draws over the list.
            .clipped()
            // A page that changes height in place (choosing «No mostrar» in «Más») eases too.
            .animation(reduceMotion ? nil : Theme.Motion.restyle, value: heights[sizedFor])

            HStack(spacing: Theme.Space.xxs) {
                ForEach(pageNames.indices, id: \.self) { index in
                    Button {
                        withAnimation { page = index }
                        withAnimation(reduceMotion ? nil : Theme.Motion.restyle) { sizedFor = index }
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
