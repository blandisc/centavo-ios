import CentavoCore
import SwiftUI

/// First page of the carousel: the month as a calendar, each day tinted by how much was spent.
struct CalendarPage: View {
    let model: MonthCalendar

    @ScaledMetric(relativeTo: .footnote) private var cellHeight: CGFloat = 36

    private var rows: [[MonthCalendar.Cell]] {
        var cells = model.cells
        while cells.count % 7 != 0 { cells.append(.padding) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cada día del mes")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
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

    /// The heat of a day is the accent at three strengths. It adapts to light and dark by itself.
    private var fill: AnyShapeStyle {
        switch day.state {
        case .future, .refund: AnyShapeStyle(Color.clear)
        case .empty: AnyShapeStyle(.quaternary)
        case .spent(let level):
            AnyShapeStyle(Color.accentColor.opacity(level == 1 ? 0.22 : level == 2 ? 0.5 : 0.9))
        }
    }

    /// Dark-on-light or light-on-dark, whichever the strength of the tint needs.
    private var textStyle: AnyShapeStyle {
        switch day.state {
        case .refund: AnyShapeStyle(.tint)
        case .spent(let level) where level >= 3: AnyShapeStyle(.background)
        default: AnyShapeStyle(.primary)
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
            .font(.footnote.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(textStyle)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                switch day.state {
                case .future:
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                case .refund:
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.tint, lineWidth: 2)
                default:
                    EmptyView()
                }
            }
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: 10).stroke(.primary, lineWidth: 2).padding(-3)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Día \(day.number)\(day.isToday ? ", hoy" : ""): \(spokenState)")
    }
}
