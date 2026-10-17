import Foundation

/// The monthly budget, one amount in the primary currency.
///
/// It lives in UserDefaults (as text, to keep the cents exact) rather than in SwiftData:
/// it is a single setting, and keeping it out of the store means the `Expense` schema
/// does not change. Empty text means no budget.
enum BudgetStore {
    static let key = "monthlyBudget"

    static func amount(from stored: String) -> Decimal? {
        guard let value = Decimal(string: stored, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        return value
    }

    static func stored(_ amount: Decimal?) -> String {
        guard let amount, amount > 0 else { return "" }
        return "\(amount)"
    }
}

/// Keeps the budget in the person's iCloud key-value store as well, so it comes back after
/// reinstalling or on a new phone. Without the iCloud entitlement that store never leaves
/// the phone and none of this does any harm.
enum BudgetSync {
    private static var cloud: NSUbiquitousKeyValueStore { .default }
    private static var local: UserDefaults { .standard }

    /// At launch: take what iCloud has, or hand it the budget this phone already had.
    static func start() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil, queue: .main
        ) { _ in adoptCloud() }
        cloud.synchronize()
        if cloud.string(forKey: BudgetStore.key) == nil {
            // On a new phone iCloud may not have arrived yet: handing it "no budget" here
            // would wipe the real one. Only a budget this phone actually has goes up.
            let mine = local.string(forKey: BudgetStore.key) ?? ""
            if !mine.isEmpty { push(mine) }
        } else {
            adoptCloud()
        }
    }

    /// Every change on this phone, including clearing it.
    static func push(_ stored: String) {
        cloud.set(stored, forKey: BudgetStore.key)
    }

    private static func adoptCloud() {
        guard let remote = cloud.string(forKey: BudgetStore.key),
              remote != local.string(forKey: BudgetStore.key) else { return }
        local.set(remote, forKey: BudgetStore.key)
    }
}
