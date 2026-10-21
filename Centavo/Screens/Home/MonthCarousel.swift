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
    var shares: [CategoryShare] = []
    var note: String?
    let onSetBudget: () -> Void
    var currency = CurrencyPreference.fallback

    @State private var page: Int? = 0
    /// Each page's own height. The carousel keeps the taller one's, always: a height that
    /// changed while swiping made the list below leap or stutter, and clipped the calendar.
    /// Only the pages move sideways; nothing else on the screen moves.
    @State private var heights: [Int: CGFloat] = [:]

    private var height: CGFloat? { heights.values.max() }

    private let pageNames = ["Presupuesto", "Calendario"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    BudgetPage(spent: spent, pace: pace, isCurrentMonth: isCurrentMonth,
                               shares: shares, note: note, onSetBudget: onSetBudget)
                        .padding(.horizontal, Theme.horizontalPadding)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[0] = $0 }
                        .containerRelativeFrame(.horizontal)
                        .id(0)
                    // Today's ring sits 3 pt outside its cell; the page margin leaves it room.
                    CalendarPage(model: calendarModel, selectedDay: selectedDay, onSelectDay: onSelectDay,
                                 currency: currency)
                        .padding(.horizontal, Theme.horizontalPadding)
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
            .frame(height: height, alignment: .top)

            HStack(spacing: 4) {
                ForEach(pageNames.indices, id: \.self) { index in
                    Button {
                        withAnimation { page = index }
                    } label: {
                        Capsule()
                            .fill(page == index ? Theme.ink : Theme.dimmed)
                            .frame(width: page == index ? 18 : 6, height: 6)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pageNames[index])
                    .accessibilityAddTraits(page == index ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
