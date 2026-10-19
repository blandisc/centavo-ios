import Foundation
import Testing
@testable import CentavoCore

@Suite struct SpendingFactsTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int, month: Int = 10, hour: Int = 13, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private static let now = day(19)

    private func money(_ value: Decimal) -> String {
        "$" + value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US")))
    }

    private func detect(_ records: [SpendingRecord], budget: Decimal? = nil) -> [SpendingFact] {
        SpendingFacts.detect(records, now: Self.now, primary: "MXN", budget: budget, money: money,
                             calendar: Self.calendar)
    }

    private func record(_ amount: Decimal, _ merchant: String, _ date: Date, category: String? = nil,
                        currency: String? = "$", fixed: Bool = false) -> SpendingRecord {
        SpendingRecord(amount: amount, currencyMarker: currency, merchant: merchant, category: category,
                       date: date, isFixed: fixed)
    }

    // MARK: Double charge

    @Test func seesTheSameChargeTwiceMinutesApart() throws {
        let facts = detect([
            record(650, "Pemex", Self.day(18, hour: 9)),
            record(650, "Pemex", Self.day(18, hour: 9, minute: 20)),
        ])
        let fact = try #require(facts.first)
        #expect(fact.kind == .doubleCharge)
        #expect(fact.line.contains("$650.00"))
        #expect(fact.line.contains("Pemex"))
    }

    @Test func twoCoffeesInADayAreNotADoubleCharge() {
        let facts = detect([
            record(65, "Starbucks", Self.day(18, hour: 9)),
            record(65, "Starbucks", Self.day(18, hour: 10)),
            record(650, "Pemex", Self.day(10, hour: 9)),
            record(650, "Pemex", Self.day(10, hour: 9, minute: 5)),   // too long ago
        ])
        #expect(!facts.contains { $0.kind == .doubleCharge })
    }

    // MARK: Subscription

    @Test func seesAMonthlyChargeNotMarkedAsFixed() throws {
        let facts = detect([
            record(129, "Spotify", Self.day(15, month: 8)),
            record(129, "Spotify", Self.day(15, month: 9)),
            record(129, "Spotify", Self.day(15)),
        ])
        let fact = try #require(facts.first { $0.kind == .subscription })
        #expect(fact.line == "Spotify se cobra cada mes ($129.00). Márcalo como fijo y se anotará solo.")
    }

    @Test func notASubscription() {
        // Marked as fixed already, twice in one month, or amounts all over the place.
        let facts = detect([
            record(129, "Spotify", Self.day(15, month: 9), fixed: true),
            record(129, "Spotify", Self.day(15), fixed: true),
            record(89, "Oxxo", Self.day(2, month: 9)), record(89, "Oxxo", Self.day(2)), record(89, "Oxxo", Self.day(4)),
            record(300, "Uber", Self.day(5, month: 9)), record(800, "Uber", Self.day(5)),
        ])
        #expect(!facts.contains { $0.kind == .subscription })
    }

    // MARK: Projection

    @Test func warnsWhenThePaceEndsOverTheBudget() throws {
        // 19 days, 9,500 variable + 3,000 rent: 3,000 + 500 × 31 = 18,500 against 15,000.
        let facts = detect([
            record(3_000, "Renta", Self.day(1), fixed: true),
            record(9_500, "Varios", Self.day(10)),
        ], budget: 15_000)
        let fact = try #require(facts.first { $0.kind == .projection })
        #expect(fact.line == "A este ritmo cierras el mes en $18,500.00, $3,500.00 arriba del presupuesto.")
    }

    @Test func noProjectionOnTrackEarlyOrWithoutBudget() {
        let spend = [record(4_000, "Varios", Self.day(10))]
        #expect(!detect(spend, budget: 15_000).contains { $0.kind == .projection })
        #expect(!detect(spend).contains { $0.kind == .projection })
    }

    // MARK: Category up

    @Test func seesACategoryWellAboveItsUsual() throws {
        var records: [SpendingRecord] = []
        for month in 7...9 {
            records.append(record(1_000, "Uber Eats", Self.day(10, month: month), category: "Comida"))
            records.append(record(2_000, "Soriana", Self.day(10, month: month), category: "Despensa"))
        }
        records.append(record(1_400, "Uber Eats", Self.day(10), category: "Comida"))
        records.append(record(2_000, "Soriana", Self.day(10), category: "Despensa"))
        let fact = try #require(detect(records).first { $0.kind == .categoryUp })
        #expect(fact.line == "Comida va 40 % arriba de lo normal a estas alturas del mes.")
    }

    @Test func noUsualWithoutThreeMonthsOfHistory() {
        let records = [
            record(1_000, "Uber Eats", Self.day(10, month: 9), category: "Comida"),
            record(3_000, "Uber Eats", Self.day(10), category: "Comida"),
        ]
        #expect(!detect(records).contains { $0.kind == .categoryUp })
    }

    @Test func otherCurrenciesDontCount() {
        let facts = detect([
            record(20, "Steam", Self.day(18, hour: 9), currency: "USD"),
            record(20, "Steam", Self.day(18, hour: 9, minute: 10), currency: "USD"),
        ])
        #expect(facts.isEmpty)
    }

    // MARK: Fact check

    private let fact = SpendingFact(kind: .projection, key: "ritmo|10",
                                    line: "A este ritmo cierras el mes en $18,500.00, $3,500.00 arriba del presupuesto.",
                                    figures: ["$18,500.00", "$3,500.00"])

    @Test func acceptsARewordingWithTheSameFigures() {
        #expect(FactCheck.accepts("Vas para cerrar en $18,500, unos $3,500 más de lo que planeaste.", for: fact))
    }

    @Test func rejectsAFigureThatIsNotThere() {
        #expect(!FactCheck.accepts("A este ritmo cierras en $19,000.", for: fact))
        #expect(!FactCheck.accepts("Te pasarás 23 % del presupuesto.", for: fact))
        #expect(!FactCheck.accepts("", for: fact))
        // Leaving the figures out is saying something else.
        #expect(!FactCheck.accepts("Ojo: este mes vas por encima del presupuesto.", for: fact))
        #expect(!FactCheck.accepts("Vas para cerrar en $18,500.", for: fact))
        #expect(!FactCheck.accepts(String(repeating: "a", count: 200), for: fact))
    }
}
