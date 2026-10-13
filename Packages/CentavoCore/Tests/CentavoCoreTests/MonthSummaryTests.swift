import Foundation
import Testing
@testable import CentavoCore

@Suite struct MonthSummaryTests {
    /// A fixed calendar so the tests don't move with the machine's time zone.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func summarize(_ amounts: [ExpenseAmount],
                           month: Date = MonthSummaryTests.day(2026, 10, 15),
                           primary: String = "MXN") -> MonthSummary {
        MonthSummarizer.summarize(amounts, inMonthOf: month, primary: primary,
                                  calendar: MonthSummaryTests.calendar)
    }

    @Test func addsUpThePrimaryCurrencyOnly() {
        let summary = summarize([
            ExpenseAmount(value: 89, currencyMarker: "$", date: Self.day(2026, 10, 1)),
            ExpenseAmount(value: 11, currencyMarker: "MX$", date: Self.day(2026, 10, 9)),
            ExpenseAmount(value: 500, currencyMarker: nil, date: Self.day(2026, 10, 30)),
        ])
        #expect(summary.primary.amount == 600)
        #expect(summary.primary.isoCode == "MXN")
        #expect(summary.others.isEmpty)
    }

    @Test func otherCurrenciesAreReportedApartNeverMixedIn() {
        let summary = summarize([
            ExpenseAmount(value: 100, currencyMarker: "$", date: Self.day(2026, 10, 2)),
            ExpenseAmount(value: 20, currencyMarker: "USD", date: Self.day(2026, 10, 3)),
            ExpenseAmount(value: 5, currencyMarker: "US$", date: Self.day(2026, 10, 4)),
            ExpenseAmount(value: 12.5, currencyMarker: "€", date: Self.day(2026, 10, 5)),
        ])
        #expect(summary.primary.amount == 100)
        #expect(summary.others == [
            MoneyTotal(isoCode: "EUR", label: "EUR", amount: 12.5),
            MoneyTotal(isoCode: "USD", label: "USD", amount: 25),
        ])
    }

    @Test func refundsSubtract() {
        let summary = summarize([
            ExpenseAmount(value: 500, currencyMarker: "$", date: Self.day(2026, 10, 2)),
            ExpenseAmount(value: -120, currencyMarker: "$", date: Self.day(2026, 10, 6)),
            ExpenseAmount(value: 50, currencyMarker: "USD", date: Self.day(2026, 10, 7)),
            ExpenseAmount(value: -80, currencyMarker: "USD", date: Self.day(2026, 10, 8)),
        ])
        #expect(summary.primary.amount == 380)
        // A refund bigger than the month's spending leaves that currency negative.
        #expect(summary.others == [MoneyTotal(isoCode: "USD", label: "USD", amount: -30)])
    }

    @Test func ignoresOtherMonths() {
        let summary = summarize([
            ExpenseAmount(value: 100, currencyMarker: "$", date: Self.day(2026, 10, 1)),
            ExpenseAmount(value: 999, currencyMarker: "$", date: Self.day(2026, 9, 30)),
            ExpenseAmount(value: 999, currencyMarker: "$", date: Self.day(2026, 11, 1)),
            ExpenseAmount(value: 999, currencyMarker: "$", date: Self.day(2025, 10, 15)),
        ])
        #expect(summary.primary.amount == 100)
        #expect(summary.others.isEmpty)
    }

    @Test func anEmptyMonthStillReportsZeroInThePrimaryCurrency() {
        let summary = summarize([])
        #expect(summary.primary == MoneyTotal(isoCode: "MXN", label: "MXN", amount: 0))
        #expect(summary.others.isEmpty)
    }

    @Test func unknownMarkersAreGroupedUnderTheMarkerItself() {
        let summary = summarize([
            ExpenseAmount(value: 100, currencyMarker: "$", date: Self.day(2026, 10, 2)),
            ExpenseAmount(value: 300, currencyMarker: "₱", date: Self.day(2026, 10, 3)),
            ExpenseAmount(value: 200, currencyMarker: " ₱ ", date: Self.day(2026, 10, 4)),
        ])
        #expect(summary.primary.amount == 100)
        #expect(summary.others == [MoneyTotal(isoCode: nil, label: "₱", amount: 500)])
    }

    @Test func breaksThePrimaryTotalDownByCategoryBiggestFirst() {
        let summary = summarize([
            ExpenseAmount(value: 300, currencyMarker: "$", date: Self.day(2026, 10, 2),
                          category: "Despensa"),
            ExpenseAmount(value: 120, currencyMarker: "$", date: Self.day(2026, 10, 3),
                          category: "Transporte"),
            ExpenseAmount(value: 200, currencyMarker: "$", date: Self.day(2026, 10, 4),
                          category: "despensa"),
            ExpenseAmount(value: 50, currencyMarker: "$", date: Self.day(2026, 10, 5)),
        ])
        #expect(summary.primary.amount == 670)
        #expect(summary.categories == [
            // Two spellings, one category; the newest spelling is the one shown.
            CategoryTotal(category: "despensa", amount: 500),
            CategoryTotal(category: "Transporte", amount: 120),
            CategoryTotal(category: nil, amount: 50),
        ])
    }

    @Test func categoriesOnlyBreakDownThePrimaryCurrency() {
        let summary = summarize([
            ExpenseAmount(value: 100, currencyMarker: "$", date: Self.day(2026, 10, 2),
                          category: "Despensa"),
            ExpenseAmount(value: 900, currencyMarker: "USD", date: Self.day(2026, 10, 3),
                          category: "Despensa"),
        ])
        #expect(summary.categories == [CategoryTotal(category: "Despensa", amount: 100)])
    }

    @Test func refundsSubtractFromTheirCategory() {
        let summary = summarize([
            ExpenseAmount(value: 300, currencyMarker: "$", date: Self.day(2026, 10, 2),
                          category: "Ropa"),
            ExpenseAmount(value: -300, currencyMarker: "$", date: Self.day(2026, 10, 9),
                          category: "Ropa"),
        ])
        #expect(summary.categories == [CategoryTotal(category: "Ropa", amount: 0)])
    }

    @Test func anEmptyMonthHasNoCategories() {
        #expect(summarize([]).categories.isEmpty)
    }

    @Test func blankCategoriesCountAsUnfiled() {
        let summary = summarize([
            ExpenseAmount(value: 10, currencyMarker: "$", date: Self.day(2026, 10, 2),
                          category: "   "),
            ExpenseAmount(value: 5, currencyMarker: "$", date: Self.day(2026, 10, 3)),
        ])
        #expect(summary.categories == [CategoryTotal(category: nil, amount: 15)])
    }

    @Test func thePrimaryCurrencyFollowsThePerson() {
        let amounts = [
            ExpenseAmount(value: 10, currencyMarker: "€", date: Self.day(2026, 10, 2)),
            ExpenseAmount(value: 40, currencyMarker: "MX$", date: Self.day(2026, 10, 3)),
        ]
        let euros = summarize(amounts, primary: "EUR")
        #expect(euros.primary.amount == 10)
        #expect(euros.others == [MoneyTotal(isoCode: "MXN", label: "MXN", amount: 40)])
    }
}
