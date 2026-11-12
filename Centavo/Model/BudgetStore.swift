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

/// When the budget changed (`BudgetHistory`, 2026-11-11): what lets a month that is over keep
/// the budget it closed with, and a budget first set halfway through the month count from that
/// day. Kept as JSON text under its own key, synced and backed up like the budget; the budget
/// in force is still `key`'s figure, which widgets, Siri and older versions read.
extension BudgetStore {
    /// The saved list, as text.
    static var savedHistory: String { UserDefaults.standard.string(forKey: BudgetHistory.key) ?? "" }

    /// Writes down that the budget went from `old` to `new` (both as stored: empty is none).
    /// Called right where it is saved, so the screen never draws the new budget without its
    /// day; safe to call twice for the same change.
    static func noteChange(from old: String, to new: String, now: Date = AppClock.now) {
        let history = BudgetHistory(stored: savedHistory)
        save(history.recording(amount(from: new), previous: amount(from: old), on: now), replacing: history)
    }

    /// Makes the list agree with the saved budget when it was changed where nobody wrote it
    /// down (an older version on another phone, by iCloud): as of now. At launch and before the
    /// widgets are written.
    static func settleHistory(now: Date = AppClock.now) {
        let history = BudgetHistory(stored: savedHistory)
        let current = amount(from: UserDefaults.standard.string(forKey: key) ?? "")
        save(history.settled(current: current, on: now), replacing: history)
    }

    private static func save(_ history: BudgetHistory, replacing old: BudgetHistory) {
        guard history != old else { return }
        let text = history.stored
        UserDefaults.standard.set(text, forKey: BudgetHistory.key)
        if Store.syncsBudget { BudgetSync.push(text, for: BudgetHistory.key) }
    }
}

/// Keeps the budget and the chosen currency in the person's iCloud key-value store as
/// well, so they come back after reinstalling or on a new phone. Without the iCloud
/// entitlement that store never leaves the phone and none of this does any harm.
extension BudgetStore {
    /// What a budget means today, said while it is typed: the same «Hoy puedes gastar» the
    /// main screen will show with it (`pace` is `TodayBudget`'s, for this budget).
    static func dailyPreview(_ pace: BudgetPace?, currency: String) -> String {
        guard let pace, !pace.isOverspent else {
            return "Este mes ya gastaste más que eso."
        }
        if let excess = pace.fixedOverBudgetShown {
            let text = excess.formatted(currencyStyle(currency).precision(.fractionLength(0)))
            return excess > 0 ? "Con eso, tus fijos pasan el presupuesto por \(text)."
                : "Con eso, tus fijos se llevan todo el presupuesto."
        }
        // Spent exactly that: not «más que eso» (second audit, 2026-11-02).
        if pace.remaining == 0 { return "Este mes ya gastaste justo eso." }
        let figure = pace.dailyAllowance.magnitude.formatted(currencyStyle(currency).precision(.fractionLength(0)))
        return pace.isOverToday ? "Con eso, hoy ya te pasaste por \(figure)." : "Con eso, hoy puedes gastar \(figure)."
    }
}

enum BudgetSync {
    private static var cloud: NSUbiquitousKeyValueStore { .default }
    private static var local: UserDefaults { .standard }
    /// The budget's history goes first: it is adopted while this phone's own budget is still
    /// the one saved (`adoptCloud`).
    static let keys = [BudgetHistory.key, BudgetStore.key, CurrencyPreference.key, UserCatalog.categoriesKey,
                       UserCatalog.sourcesKey, UserCatalog.defaultSourceKey, FixedPlan.key,
                       UserCatalog.hiddenCategoriesKey, UserCatalog.categoryRulesKey,
                       UserCatalog.deletedCategoriesKey, AllowanceMode.key,
                       UserCatalog.merchantRenamesKey, UserCatalog.categoryColorsKey,
                       UserCatalog.sourceColorsKey, UserCatalog.cardRenamesKey]

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
        if key == BudgetHistory.key {
            // Never whole over this phone's: a list that begins today (a second phone's welcome)
            // must not make the budget this phone already had count from today.
            let mine = BudgetHistory(stored: local.string(forKey: key) ?? "")
            let budget = BudgetStore.amount(from: local.string(forKey: BudgetStore.key) ?? "")
            let merged = mine.adopting(BudgetHistory(stored: remote), localBudget: budget).stored
            local.set(merged, forKey: key)
            if merged != remote { push(merged, for: key) }
            return
        }
        local.set(remote, forKey: key)
    }
}
