import Foundation
import Testing
@testable import CentavoCore

@Suite struct PendingPaymentsTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func unread(_ text: String, hoursAgo: Double = 0) -> PendingPayment {
        PendingPayment(kind: .unread, text: text, date: now.addingTimeInterval(-hoursAgo * 3600))
    }

    private func unsaved(_ text: String, hoursAgo: Double = 0) -> PendingPayment {
        PendingPayment(kind: .unsaved, text: text, date: now.addingTimeInterval(-hoursAgo * 3600))
    }

    // MARK: What is kept

    @Test func aLoneMerchantLooksLikeAWrongWiringAndIsKept() {
        #expect(PendingPayment.unread("  Google \n", date: now)?.text == "Google")
        #expect(PendingPayment.unread("Google", date: now)?.kind == .unread)
    }

    @Test func aPassOrAPromotionIsLetGo() {
        // Title and body: not a charge.
        #expect(PendingPayment.unread("Aeroméxico\nTu pase de abordar está listo", date: now) == nil)
        // One line with a figure that wasn't read as money: not the wiring this looks for.
        #expect(PendingPayment.unread("Tu vuelo AM 123 sale pronto", date: now) == nil)
        #expect(PendingPayment.unread("  \n ", date: now) == nil)
    }

    @Test func aChargeWhoseAmountDidNotReadIsAlwaysKept() {
        let kept = PendingPayment.unread("American Express México\nGoogle\nMXN 3I9.00", always: true, date: now)
        #expect(kept?.text == "American Express México")
        #expect(PendingPayment.unread("", always: true, date: now) == nil)
    }

    @Test func aLongNoticeIsCutToALine() {
        let long = String(repeating: "a", count: 300)
        #expect(PendingPayment.unread(long, date: now)?.text.count == PendingPayment.maxText)
    }

    @Test func aPaymentThatCouldNotBeSavedSaysHowMuchAndWhere() {
        let both = PendingPayment.unsaved(amount: "$319", merchant: "Google", card: "Amex", date: now)
        #expect(both?.text == "$319 en Google")
        #expect(both?.kind == .unsaved)
        #expect(both?.amount == "$319")
        #expect(both?.merchant == "Google")
        #expect(both?.card == "Amex")
        #expect(PendingPayment.unsaved(amount: "MXN 319.00", merchant: "  ", card: nil, date: now)?.text == "MXN 319.00")
        #expect(PendingPayment.unsaved(amount: "", merchant: "Google", card: nil, date: now)?.text == "Google")
        #expect(PendingPayment.unsaved(amount: " ", merchant: nil, card: "Amex", date: now) == nil)
    }

    // MARK: The list

    @Test func aGoodPaymentAfterDoesNotTakeTheFirstAway() {
        // Nothing but the person removes one: adding keeps what was there.
        var list = PendingPayments.adding(unread("Google", hoursAgo: 2), to: [], now: now)
        list = PendingPayments.adding(unsaved("$89 en Oxxo"), to: list, now: now)
        #expect(list.map(\.text) == ["$89 en Oxxo", "Google"])
    }

    @Test func newestFirstAndOnlyTheNewestTwenty() {
        var list: [PendingPayment] = []
        for hour in (0..<25).reversed() {
            list = PendingPayments.adding(unread("Pago \(hour)", hoursAgo: Double(hour)), to: list, now: now)
        }
        #expect(list.count == PendingPayments.limit)
        #expect(list.first?.text == "Pago 0")
        #expect(list.last?.text == "Pago 19")
    }

    @Test func pastTheLimitTheUnreadGoFirstAndNeverAnUnsavedWhileOneIsLeft() {
        // 19 old payments that couldn't be saved, then 5 newer notices that didn't read.
        var list = (0..<19).map { unsaved("Guardar \($0)", hoursAgo: 100 + Double($0)) }
        list += (0..<5).map { unread("Leer \($0)", hoursAgo: Double($0)) }
        let kept = PendingPayments.current(list, now: now)
        #expect(kept.count == PendingPayments.limit)
        #expect(kept.filter { $0.kind == .unsaved }.count == 19)
        // Of the notices only the newest stays, though all are newer than every unsaved one.
        #expect(kept.filter { $0.kind == .unread }.map(\.text) == ["Leer 0"])
        #expect(kept.first?.text == "Leer 0")
    }

    @Test func withOnlyUnsavedPastTheLimitTheOldestGoes() {
        let list = (0..<22).map { unsaved("Guardar \($0)", hoursAgo: Double($0)) }
        let kept = PendingPayments.current(list, now: now)
        #expect(kept.count == PendingPayments.limit)
        #expect(kept.last?.text == "Guardar 19")
    }

    // MARK: A name-only notice and the good payment it was

    @Test func aNameOnlyNoticeGoesWithAGoodPaymentFromThatShopWithinTwoMinutes() {
        let notice = PendingPayment(kind: .unread, text: "Oxxo", date: now.addingTimeInterval(-90))
        #expect(PendingPayments.settling([notice], savedIn: ["OXXO ROBLE MTY"], at: now).isEmpty)
        // The notice may come after the payment too.
        let after = PendingPayment(kind: .unread, text: "Oxxo", date: now.addingTimeInterval(100))
        #expect(PendingPayments.isSettled(after, by: ["Sin nombre", "Oxxo Roble"], at: now))
    }

    @Test func anotherShopOrALaterPaymentLeavesIt() {
        let notice = PendingPayment(kind: .unread, text: "Oxxo", date: now.addingTimeInterval(-90))
        #expect(PendingPayments.settling([notice], savedIn: ["Google"], at: now) == [notice])
        #expect(PendingPayments.settling([notice], savedIn: ["Oxxo"], at: now.addingTimeInterval(600)) == [notice])
        #expect(PendingPayments.settling([notice], savedIn: [], at: now) == [notice])
    }

    @Test func aNoticeWithAFigureOrACurrencyNeverGoesByItself() {
        let figure = PendingPayment(kind: .unread, text: "Oxxo 3I9", date: now)
        let currency = PendingPayment(kind: .unread, text: "Oxxo MXN", date: now)
        let couldNotSave = PendingPayment(kind: .unsaved, text: "Oxxo", date: now, merchant: "Oxxo")
        let list = [figure, currency, couldNotSave]
        #expect(!figure.isNameOnly)
        #expect(!couldNotSave.isNameOnly)
        #expect(PendingPayments.settling(list, savedIn: ["Oxxo"], at: now).contains(figure))
        #expect(PendingPayments.settling(list, savedIn: ["Oxxo"], at: now).contains(couldNotSave))
        if !currency.isNameOnly {
            #expect(PendingPayments.settling(list, savedIn: ["Oxxo"], at: now) == list)
        }
    }

    // MARK: What the sheet starts with

    @Test func aPaymentThatCouldNotBeSavedFillsTheWholeSheet() {
        let payment = PendingPayment.unsaved(amount: "MXN 1,319.50", merchant: "Google", card: "Amex", date: now)!
        let fill = payment.prefill(primary: "USD")
        #expect(fill == ExpensePrefill(amountText: "1,319.50", currency: "MXN", merchant: "Google", card: "Amex", date: now))
    }

    @Test func aBareDollarIsTheMainCurrencyAndARefundIsSaid() {
        let payment = PendingPayment.unsaved(amount: "-$319", merchant: "Liverpool", card: nil, date: now)!
        let fill = payment.prefill(primary: "MXN")
        #expect(fill.amountText == "319.00")
        #expect(fill.isRefund)
        #expect(fill.currency == "MXN")
        #expect(fill.card == nil)
    }

    @Test func aNoticeWithOnlyANameFillsTheShopAndLeavesTheAmountEmpty() {
        let fill = PendingPayment(kind: .unread, text: "Google", date: now).prefill(primary: "MXN")
        #expect(fill == ExpensePrefill(merchant: "Google", date: now))
    }

    @Test func aNoticeThatIsNotANameFillsOnlyTheDate() {
        let fill = PendingPayment(kind: .unread, text: "American Express 3I9.00", date: now).prefill(primary: "MXN")
        #expect(fill == ExpensePrefill(date: now))
    }

    @Test func afterThirtyDaysItGoesByItself() {
        let old = unread("Viejo", hoursAgo: 24 * 31)
        let recent = unread("Reciente", hoursAgo: 24 * 29)
        #expect(PendingPayments.current([old, recent], now: now).map(\.text) == ["Reciente"])
    }

    @Test func twoAtTheSameInstantKeepTheirOrderAndARepeatedIdCountsOnce() {
        let first = unread("Uno"), second = unread("Dos")
        #expect(PendingPayments.current([first, second, first], now: now).map(\.text) == ["Uno", "Dos"])
    }

    @Test func removingTakesOnlyThatOne() {
        let first = unread("Uno"), second = unread("Dos", hoursAgo: 1)
        #expect(PendingPayments.removing(first.id, from: [first, second]) == [second])
        #expect(PendingPayments.removing(UUID(), from: [first, second]) == [first, second])
    }

    @Test func itSurvivesBeingWrittenAndRead() {
        let list = [unsaved("$319 en Google"), unread("Oxxo", hoursAgo: 3)]
        #expect(PendingPayments.decode(PendingPayments.encode(list)) == list)
        #expect(PendingPayments.encode([]) == "")
        #expect(PendingPayments.decode("").isEmpty)
        #expect(PendingPayments.decode("no es una lista").isEmpty)
    }

    @Test func oneDamagedItemDoesNotEmptyTheRest() {
        let good = unread("Oxxo")
        let stored = PendingPayments.encode([good]).dropLast() + ",{\"kind\":\"otra\"}]"
        #expect(PendingPayments.decode(String(stored)) == [good])
    }

    // MARK: What «Hoy» says

    @Test func theTitleCountsAndSaysWhy() {
        #expect(PendingPayments.title(for: [unread("a")]) == "1 pago no se pudo leer")
        #expect(PendingPayments.title(for: [unread("a"), unread("b")]) == "2 pagos no se pudieron leer")
        #expect(PendingPayments.title(for: [unsaved("a")]) == "1 pago no se pudo guardar")
        #expect(PendingPayments.title(for: [unsaved("a"), unsaved("b"), unsaved("c")]) == "3 pagos no se pudieron guardar")
        #expect(PendingPayments.title(for: [unsaved("a"), unread("b")]) == "2 pagos sin anotar")
    }
}
