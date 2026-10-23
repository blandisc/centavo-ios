import CentavoCore
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

/// Keeps the budget and the chosen currency in the person's iCloud key-value store as
/// well, so they come back after reinstalling or on a new phone. Without the iCloud
/// entitlement that store never leaves the phone and none of this does any harm.
extension BudgetStore {
    /// What a budget means today, said while it is typed: the same «Hoy puedes gastar» the
    /// main screen will show with it, counting what this month already spent.
    static func dailyPreview(_ amount: Decimal, spent: Decimal = 0, reserved: Decimal = 0,
                             currency: String, now: Date = .now) -> String {
        guard let pace = BudgetPace(budget: amount, spent: spent, reserved: reserved, on: now),
              pace.remaining > 0 else {
            return "Este mes ya gastaste más que eso."
        }
        let figure = pace.dailyAllowance.formatted(currencyStyle(currency).precision(.fractionLength(0)))
        return "Con eso, hoy puedes gastar \(figure)."
    }
}

enum BudgetSync {
    private static var cloud: NSUbiquitousKeyValueStore { .default }
    private static var local: UserDefaults { .standard }
    static let keys = [BudgetStore.key, CurrencyPreference.key, UserCatalog.categoriesKey,
                       UserCatalog.sourcesKey, UserCatalog.defaultSourceKey, FixedPlan.key,
                       UserCatalog.hiddenCategoriesKey, UserCatalog.categoryRulesKey,
                       UserCatalog.deletedCategoriesKey]

    /// At launch: take what iCloud has, or hand it what this phone already had.
    static func start() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil, queue: .main
        ) { _ in keys.forEach(adoptCloud) }
        cloud.synchronize()
        for key in keys {
            if cloud.string(forKey: key) == nil {
                // On a new phone iCloud may not have arrived yet: handing it an empty value
                // here would wipe the real one. Only what this phone actually has goes up.
                let mine = local.string(forKey: key) ?? ""
                if !mine.isEmpty { push(mine, for: key) }
            } else {
                adoptCloud(key)
            }
        }
    }

    /// Set once the welcome is done, so a new or reinstalled phone on the same iCloud does
    /// not show it again (and have rent and the rest typed in twice).
    static func markOnboarded() { cloud.set("1", forKey: "onboarded") }

    /// Whether this iCloud already has someone's setup: the welcome was done, or a budget or
    /// currency is there. The expenses themselves may still be on their way.
    static var hasSetupElsewhere: Bool {
        cloud.synchronize()
        return cloud.string(forKey: "onboarded") == "1"
            || keys.contains { !(cloud.string(forKey: $0) ?? "").isEmpty }
    }

    /// Every change on this phone, including clearing it.
    static func push(_ value: String, for key: String = BudgetStore.key) {
        cloud.set(value, forKey: key)
    }

    private static func adoptCloud(_ key: String) {
        guard let remote = cloud.string(forKey: key),
              remote != local.string(forKey: key) else { return }
        local.set(remote, forKey: key)
    }
}
