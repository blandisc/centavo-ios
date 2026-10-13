import CentavoCore
import SwiftUI

/// First page of the carousel: the month as a calendar, each day tinted by how much was spent.
struct CalendarPage: View {
    let model: MonthCalendar

    @ScaledMetric(relativeTo: .caption2) private var cellHeight: CGFloat = 32

    private var rows: [[MonthCalendar.Cell]] {
        var cells = model.cells
        while cells.count % 7 != 0 { cells.append(.padding) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cada día del mes").ticketCaption()
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.ticket(10, relativeTo: .caption2))
                            .tracking(1)
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            switch cell {
                            case .padding:
                                Color.clear.frame(maxWidth: .infinity, minHeight: cellHeight)
                            case .day(let day):
                                DayCell(day: day, height: cellHeight)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: MonthCalendar.Day
    let height: CGFloat

    private var fill: Color {
        switch day.state {
        case .future, .refund: .clear
        case .empty: Theme.surface
        case .spent(let level): level >= 3 ? Theme.brass : level == 2 ? Theme.brassMid : Theme.brassLow
        }
    }

    private var textColor: Color {
        switch day.state {
        case .future: Theme.faint
        case .empty: Theme.muted
        case .refund: Theme.brass
        // Light text only holds up on the darkest tint (6.8:1); on the middle one it drops to 3.4:1.
        case .spent(let level): level == 1 ? Theme.ink : Theme.onBrass
        }
    }

    private var spokenState: String {
        switch day.state {
        case .future: "todavía no llega"
        case .empty: "sin gastos"
        case .refund: "devolvieron \(day.total.magnitude.formatted(.number.precision(.fractionLength(2))))"
        case .spent: "gastaste \(day.total.formatted(.number.precision(.fractionLength(2))))"
        }
    }

    var body: some View {
        Text("\(day.number)")
            .font(.ticket(11, relativeTo: .caption2))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                switch day.state {
                case .future:
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                case .refund:
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.brass, lineWidth: 1.5)
                default:
                    EmptyView()
                }
            }
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: 6).stroke(Theme.ink, lineWidth: 1.5).padding(-3)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Día \(day.number)\(day.isToday ? ", hoy" : ""): \(spokenState)")
    }
}
