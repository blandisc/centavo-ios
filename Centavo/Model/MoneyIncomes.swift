import CentavoCore
import Foundation
import SwiftData

/// Seeing, editing and removing what comes in each month, after the first time (2026-11-02
/// audit): before, an income imported or skipped could never be looked at again.
extension MoneyStore {
    /// A new income, from this month on.
    static func addIncome(name: String, institution: String?, amount: Decimal, currency: String,
                          in context: ModelContext, now: Date = AppClock.now) throws {
        context.insert(MoneyIncome(name: name, institution: institution, amount: amount, currency: currency, since: now))
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// Changes an income. A new amount or currency from a later month archives the old one and
    /// starts a new one from this month (`MoneyIncomeRule`); names are just corrected.
    static func updateIncome(_ income: MoneyIncome, name: String, institution: String?, amount: Decimal,
                             currency: String, in context: ModelContext, now: Date = AppClock.now) throws {
        if MoneyIncomeRule.startsNewVersion(oldAmount: income.amount, oldCurrency: income.currency, since: income.since,
                                            newAmount: amount, newCurrency: currency, now: now) {
            income.archived = true
            income.until = now
            context.insert(MoneyIncome(name: name, institution: institution, amount: amount, currency: currency, since: now))
        } else {
            income.name = name
            income.institution = institution
            income.amount = amount
            income.currency = currency
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// «Quitar»: it stops counting from now on; it's archived, never deleted.
    static func removeIncome(_ income: MoneyIncome, in context: ModelContext, now: Date = AppClock.now) throws {
        income.archived = true
        income.until = now
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
