import Foundation
import Testing
@testable import CentavoCore

/// The pieces that let the main screen work its numbers out once instead of on every redraw.
@Suite struct HomeCachingTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int,
                             _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute, second: second))!
    }

    // MARK: Memo

    @Test func memoWorksItOutOnlyWhenTheInputsChange() {
        var memo = Memo<Int, String>()
        var made = 0
        let first = memo.value(for: 1) { made += 1; return "uno" }
        let again = memo.value(for: 1) { made += 1; return "otro" }
        #expect(first == "uno" && again == "uno")
        #expect(made == 1)
        let changed = memo.value(for: 2) { made += 1; return "dos" }
        #expect(changed == "dos" && made == 2)
        memo.reset()
        _ = memo.value(for: 2) { made += 1; return "dos" }
        #expect(made == 3)
    }

    // MARK: DayRuns

    private struct Item: Equatable { let name: String; let date: Date }

    private func split(_ items: [Item]) -> [(day: Date, names: [String])] {
        DayRuns.split(items, calendar: Self.calendar, date: \.date).map { ($0.day, $0.items.map(\.name)) }
    }

    @Test func nothingSplitsIntoNothing() {
        #expect(split([]).isEmpty)
    }

    @Test func eachDayIsOneRunInTheOrderGiven() {
        let items = [Item(name: "a", date: Self.date(2026, 10, 20, 23, 59)),
                     Item(name: "b", date: Self.date(2026, 10, 20, 0, 0)),
                     Item(name: "c", date: Self.date(2026, 10, 19, 18)),
                     Item(name: "d", date: Self.date(2026, 10, 1, 9))]
        let runs = split(items)
        #expect(runs.map(\.names) == [["a", "b"], ["c"], ["d"]])
        #expect(runs.map(\.day) == [Self.date(2026, 10, 20, 0, 0), Self.date(2026, 10, 19, 0, 0),
                                    Self.date(2026, 10, 1, 0, 0)])
    }

    @Test func aDayThatComesBackStartsAnotherRun() {
        // As the list drew it before: only neighbors join.
        let items = [Item(name: "a", date: Self.date(2026, 10, 20)),
                     Item(name: "b", date: Self.date(2026, 10, 19)),
                     Item(name: "c", date: Self.date(2026, 10, 20))]
        #expect(split(items).map(\.names) == [["a"], ["b"], ["c"]])
    }

    @Test func aLongDayStaysWholeAndInOrder() {
        let items = (0..<2_000).map { Item(name: "\($0)", date: Self.date(2026, 10, 20, 12, 0, $0 % 60)) }
        let runs = split(items)
        #expect(runs.count == 1)
        #expect(runs.first?.names.count == 2_000)
        #expect(runs.first?.names.first == "0")
        #expect(runs.first?.names.last == "1999")
    }

    // MARK: Month bounds

    @Test func aMonthsBoundsHoldExactlyItsDates() {
        let reference = Self.date(2026, 10, 13)
        let bounds = MonthNavigator.bounds(of: reference, calendar: Self.calendar)
        let samples = [Self.date(2026, 9, 30, 23, 59, 59), Self.date(2026, 10, 1, 0, 0, 0),
                       Self.date(2026, 10, 31, 23, 59, 59), Self.date(2026, 11, 1, 0, 0, 0),
                       Self.date(2026, 10, 15)]
        for sample in samples {
            let inside = sample >= bounds.start && sample < bounds.end
            #expect(inside == MonthNavigator.isSameMonth(sample, as: reference, calendar: Self.calendar))
        }
    }

    @Test func boundsGoFromTheFirstToTheNextFirst() {
        let bounds = MonthNavigator.bounds(of: Self.date(2026, 2, 10), calendar: Self.calendar)
        #expect(bounds.start == Self.date(2026, 2, 1, 0, 0))
        #expect(bounds.end == Self.date(2026, 3, 1, 0, 0))
    }
}
