#if DEBUG
import Foundation
import SwiftData

/// Sample data for the UI tests that photograph the app (see CentavoUITests).
/// Only compiled into Debug builds; it never ships.
///
/// - `-centavo-demo`: an in-memory store with a believable month.
/// - `-centavo-empty`: an in-memory store with nothing in it (the first-launch screen).
enum DemoData {
    enum DemoError: Error { case brokenStore }

    /// `-centavo-broken-store`: pretend the store failed to open, to see the error screen.
    static var isBrokenStoreRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-centavo-broken-store")
    }

    static var isRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-centavo-demo") || arguments.contains("-centavo-empty")
    }

    static func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        guard ProcessInfo.processInfo.arguments.contains("-centavo-demo") else { return container }

        let context = ModelContext(container)
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.component(.day, from: now)

        func at(day: Int, hour: Int = 13, monthsAgo: Int = 0) -> Date? {
            guard let month = calendar.date(byAdding: .month, value: -monthsAgo, to: now),
                  var parts = Optional(calendar.dateComponents([.year, .month], from: month))
            else { return nil }
            parts.day = day
            parts.hour = hour
            return calendar.date(from: parts)
        }

        // (day, amount, marker, merchant, card, category)
        let thisMonth: [(Int, Decimal, String, String, String?, String?)] = [
            (1, 215, "$", "Soriana", "BBVA", "Despensa"),
            (2, 89, "$", "Oxxo", "BBVA", "Despensa"),
            (4, 1234.5, "$", "Liverpool", "BBVA", "Ropa"),
            (5, 62, "$", "Starbucks", "Nu", "Café"),
            (7, 540, "$", "CFE", nil, "Servicios"),
            (8, 98, "$", "Oxxo", "BBVA", "Despensa"),
            (9, -230, "$", "Liverpool", "BBVA", "Ropa"),
            (11, 24.99, "USD", "Steam", "BBVA", nil),
            (12, 310, "$", "Cinépolis", "Nu", "Salidas"),
        ]
        for (day, amount, marker, merchant, card, category) in thisMonth where day <= today {
            guard let date = at(day: day) else { continue }
            context.insert(Expense(amount: amount, currencyMarker: marker, merchant: merchant,
                                   card: card, date: min(date, now), category: category))
        }
        // Today's own payment, so the list always opens on something recent.
        context.insert(Expense(amount: 47.5, currencyMarker: "$", merchant: "Oxxo",
                               card: "BBVA", date: now.addingTimeInterval(-3_600), category: "Despensa"))

        let lastMonth: [(Int, Decimal, String, String, String?, String?)] = [
            (3, 880, "$", "Soriana", "BBVA", "Despensa"),
            (10, 2400, "$", "Renta", nil, "Casa"),
            (17, 150, "$", "Uber", "Nu", "Transporte"),
            (24, 399, "$", "Netflix", "BBVA", "Suscripciones"),
        ]
        for (day, amount, marker, merchant, card, category) in lastMonth {
            guard let date = at(day: day, monthsAgo: 1) else { continue }
            context.insert(Expense(amount: amount, currencyMarker: marker, merchant: merchant,
                                   card: card, date: date, category: category))
        }
        try context.save()
        return container
    }
}
#endif
