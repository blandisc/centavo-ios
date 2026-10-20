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

    private let pageNames = ["Presupuesto", "Calendario"]

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    BudgetPage(spent: spent, pace: pace, isCurrentMonth: isCurrentMonth,
                               shares: shares, note: note, onSetBudget: onSetBudget)
                        .padding(.horizontal, Theme.horizontalPadding)
                        .containerRelativeFrame(.horizontal)
                        .id(0)
                    // Today's ring sits 3 pt outside its cell; the page margin leaves it room.
                    CalendarPage(model: calendarModel, selectedDay: selectedDay, onSelectDay: onSelectDay,
                                 currency: currency)
                        .padding(.horizontal, Theme.horizontalPadding)
                        .containerRelativeFrame(.horizontal)
                        .id(1)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .scrollIndicators(.hidden)

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
