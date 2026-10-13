import CentavoCore
import SwiftUI

/// The swipeable middle of the main screen: calendar, then budget.
struct MonthCarousel: View {
    let calendarModel: MonthCalendar
    let spent: MoneyTotal
    let pace: BudgetPace?
    let isCurrentMonth: Bool
    let onSetBudget: () -> Void

    @State private var page: Int? = 0

    private let pageNames = ["Calendario", "Presupuesto"]

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    CalendarPage(model: calendarModel)
                        .containerRelativeFrame(.horizontal)
                        .id(0)
                    BudgetPage(spent: spent, pace: pace, isCurrentMonth: isCurrentMonth,
                               onSetBudget: onSetBudget)
                        .containerRelativeFrame(.horizontal)
                        .id(1)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .scrollIndicators(.hidden)

            HStack(spacing: 0) {
                ForEach(pageNames.indices, id: \.self) { index in
                    Button {
                        withAnimation { page = index }
                    } label: {
                        Circle()
                            .fill(page == index ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            .frame(width: 7, height: 7)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pageNames[index])
                    .accessibilityAddTraits(page == index ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .sensoryFeedback(.selection, trigger: page)
        }
    }
}
