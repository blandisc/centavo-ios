import CentavoCore
#if DEBUG
import Foundation
import SwiftData

extension DemoData {
    /// `-centavo-dinero-demo`: «Mi dinero» in memory with the sketches' accounts.
    /// `-centavo-dinero-vacio`: «Mi dinero» in memory and empty (the first time).
    static var isMoneyDemoRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-centavo-dinero-demo") || arguments.contains("-centavo-dinero-vacio")
    }

    /// The UI tests can't look at the simulator: every demo skips the Face ID lock.
    static var skipsLock: Bool { isRequested || isMoneyDemoRequested }
}

enum MoneyDemo {
    static func makeContainer() throws -> ModelContainer {
        let container = try MoneyStore.inMemory()
        guard ProcessInfo.processInfo.arguments.contains("-centavo-dinero-demo") else { return container }
        let context = ModelContext(container)
        let calendar = Calendar.current
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now

        let rows: [(String, MoneyKind, String, Decimal?, Decimal, Decimal)] = [
            ("Nu cajita", .account, "MXN", Decimal(string: "10.5"), 181_900, 185_000),
            ("CETES", .account, "MXN", Decimal(string: "9.8"), 148_770, 150_000),
            ("BBVA nómina", .account, "MXN", nil, 40_100, 42_300),
            ("Cuenta dólares", .account, "USD", nil, 2_000, 2_000),
            ("Fondo GBM", .investment, "MXN", nil, 24_400, 25_000),
            ("Bono anual", .receivable, "MXN", nil, 0, 35_000),
            ("Préstamo a Ana", .receivable, "MXN", nil, 8_000, 8_000),
            ("Amex", .debt, "MXN", nil, 7_600, 6_420),
            ("Préstamo auto", .debt, "MXN", nil, 3_000, 1_500),
        ]
        let before = MoneyCut(month: MoneyMath.monthKey(of: lastMonth), date: lastMonth, mainCurrency: "MXN", isDraft: false)
        before.rateTable = ["USD": 20]
        let now = MoneyCut(month: MoneyMath.monthKey(of: .now), date: .now, mainCurrency: "MXN", isDraft: false)
        now.rateTable = ["USD": 19]
        context.insert(before)
        context.insert(now)
        for (index, row) in rows.enumerated() {
            let account = MoneyAccount(name: row.0, kind: row.1, currency: row.2, yearlyRate: row.3, order: index)
            account.createdAt = lastMonth
            context.insert(account)
            for (cut, balance) in [(before, row.4), (now, row.5)] {
                let entry = MoneyEntry(balance: balance, account: account, reviewed: true)
                context.insert(entry)
                entry.cut = cut
            }
        }
        try context.save()
        return container
    }
}
#endif
