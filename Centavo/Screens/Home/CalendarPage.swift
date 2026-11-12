import CentavoCore
import SwiftUI

/// Second page of the carousel: the month as a calendar, each day tinted by how much was spent.
struct CalendarPage: View {
    let model: MonthCalendar
    /// The day whose expenses the list shows, if one was tapped.
    var selectedDay: Int?
    var onSelectDay: (Int?) -> Void = { _ in }

    /// The month's currency, so VoiceOver says "$310.00" and not a bare number.
    var currency = CurrencyPreference.fallback

    /// 44 pt: Apple's minimum for something to tap.
    @ScaledMetric(relativeTo: .caption2) private var scaledCellHeight: CGFloat = Theme.Size.tapTarget
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The grid's width, measured: a cell's side with accessibility type.
    @State private var gridWidth = Theme.Space.none

    /// With accessibility type a cell is a square, as wide as its column (2026-11-11): grown
    /// with the type it was three times as tall as wide, and its number, grown too, ran into
    /// the next («22232425262728»). The number stops growing where the cell does (`DayCell`).
    private var cellHeight: CGFloat {
        guard typeSize.isAccessibilitySize else { return scaledCellHeight }
        let gaps = Theme.Space.xxs * CGFloat(Self.columns - 1)
        return max((gridWidth - gaps) / CGFloat(Self.columns), Theme.Size.tapTarget)
    }

    private static let columns = 7

    private var rows: [[MonthCalendar.Cell]] {
        var cells = model.cells
        while cells.count % Self.columns != 0 { cells.append(.padding) }
        return stride(from: 0, to: cells.count, by: Self.columns).map { Array(cells[$0..<$0 + Self.columns]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Grid(horizontalSpacing: Theme.Space.xxs, verticalSpacing: Theme.Space.xxs) {
                GridRow {
                    ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.ticket(.micro))
                            .tracking(Theme.Tracking.tag)
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
                                Button {
                                    onSelectDay(selectedDay == day.number ? nil : day.number)
                                } label: {
                                    DayCell(day: day, height: cellHeight, currency: currency,
                                            isSelected: selectedDay == day.number)
                                }
                                .buttonStyle(.plain)
                                // The ring is drawn outside the cell: over its neighbours, not under.
                                .zIndex(selectedDay == day.number || day.isToday ? 1 : 0)
                                // A day that has not come has nothing to show.
                                .disabled(day.state == .future)
                                .accessibilityAddTraits(selectedDay == day.number ? .isSelected : [])
                                .accessibilityHint(day.state == .future ? "" : "Muestra los gastos de ese día")
                            }
                        }
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        }
        // Today's ring and the selected day's sit 3 pt outside their cell; on the last row
        // the carousel, sized to this page, cut them off.
        .padding(.bottom, Theme.Space.xxs)
    }
}

private struct DayCell: View {
    let day: MonthCalendar.Day
    let height: CGFloat
    let currency: String
    var isSelected = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        case .refund: "devolvieron \(day.total.magnitude.formatted(currencyStyle(currency)))"
        case .spent: "gastaste \(day.total.formatted(currencyStyle(currency)))"
        }
    }

    var body: some View {
        Text("\(day.number)")
            .font(.ticket(.hint))
            // The cell doesn't widen with the type, so its number stops growing while two digits
            // still fit in it, as `Signature` does in its bar (2026-11-11). The picked day is
            // read whole, at any size, in the list below.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .lineLimit(1)
            .minimumScaleFactor(Theme.MinimumScale.figure)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip))
            .overlay {
                switch day.state {
                case .future:
                    RoundedRectangle(cornerRadius: Theme.Radius.chip)
                        .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: Theme.Stroke.hairline, dash: Theme.Dash.perforation))
                case .refund:
                    RoundedRectangle(cornerRadius: Theme.Radius.chip).strokeBorder(Theme.brass, lineWidth: Theme.Stroke.emphasis)
                default:
                    EmptyView()
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.ticket).stroke(Theme.brass, lineWidth: Theme.Stroke.strong).padding(Theme.Space.outset)
                }
            }
            .animation(Theme.Motion.animation(Theme.Motion.select, reduceMotion: reduceMotion), value: isSelected)
            .overlay {
                if day.isToday && !isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.ticket).stroke(Theme.ink, lineWidth: Theme.Stroke.emphasis).padding(Theme.Space.outset)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Día \(day.number)\(day.isToday ? ", hoy" : ""): \(spokenState)")
    }
}
