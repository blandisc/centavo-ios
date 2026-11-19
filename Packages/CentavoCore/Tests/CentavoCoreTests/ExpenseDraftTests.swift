import Foundation
import Testing
@testable import CentavoCore

/// The new expense's sheet kept while iOS may close the app (2026-11-19).
@Suite struct ExpenseDraftTests {
    @Test func whatWasTypedComesBackAsItWas() throws {
        let day = Date(timeIntervalSinceReferenceDate: 815_000_000)
        let draft = ExpenseDraft(amountText: "1,234.5", currency: "USD", merchant: "Oxxo", card: "BBVA",
                                 category: "Comida", categoryAutofilled: true, date: day, dateProposed: true,
                                 isRefund: true, counts: false, reason: UncountedReason.betweenAccounts.rawValue,
                                 repeats: true, rule: RepeatRule.weeks(2).stored, showsDetails: true)
        let read = try #require(ExpenseDraft.decode(draft.encoded))
        #expect(read == draft)
        #expect(read.uncountedReason == .betweenAccounts)
        #expect(read.repeatRule == .weeks(2))
    }

    @Test func aDateLeftAloneStaysUnpicked() throws {
        let draft = ExpenseDraft(amountText: "89", currency: "MXN")
        let read = try #require(ExpenseDraft.decode(draft.encoded))
        #expect(read.date == nil)
        #expect(read.repeatRule == .monthly)
        #expect(read.uncountedReason == .reimbursed)
        #expect(read.counts)
    }

    @Test func nothingOrJunkIsNoDraft() {
        #expect(ExpenseDraft.decode(nil) == nil)
        #expect(ExpenseDraft.decode("") == nil)
        #expect(ExpenseDraft.decode("{\"amountText\":\"5\"}") == nil)
        #expect(ExpenseDraft.decode("lo que sea") == nil)
    }

    @Test func anUnknownReasonIsTheDefault() {
        var draft = ExpenseDraft(currency: "MXN")
        draft.reason = "otra-cosa"
        #expect(draft.uncountedReason == .reimbursed)
    }
}
