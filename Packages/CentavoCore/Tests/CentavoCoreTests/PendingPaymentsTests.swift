import Foundation
import Testing
@testable import CentavoCore

@Suite struct PendingPaymentsTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func unread(_ text: String, hoursAgo: Double = 0) -> PendingPayment {
        PendingPayment(kind: .unread, text: text, date: now.addingTimeInterval(-hoursAgo * 3600), isCharge: false)
    }

    /// A shop's name with no figure: «Tienda A», «Tienda B»… (`mayAgeOut`).
    private func shop(_ index: Int) -> String {
        "Tienda " + String(Character(UnicodeScalar(UInt8(65 + index))))
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
        #expect(kept?.isCharge == true)
        #expect(kept?.mayAgeOut == false)
        #expect(PendingPayment.unread("", always: true, date: now) == nil)
        #expect(PendingPayment.unread("Google", date: now)?.isCharge == false)
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

    @Test func newestFirstAndOnlyTheNewestTwentyNamesOnly() {
        var list: [PendingPayment] = []
        for hour in (0..<25).reversed() {
            list = PendingPayments.adding(unread(shop(hour), hoursAgo: Double(hour)), to: list, now: now)
        }
        #expect(list.count == PendingPayments.limit)
        #expect(list.first?.text == shop(0))
        #expect(list.last?.text == shop(19))
    }

    @Test func pastTheLimitNamesOnlyGoFirstAndNeverAnUnsavedWhileOneIsLeft() {
        // 19 old payments that couldn't be saved, then 5 newer notices with only a name.
        var list = (0..<19).map { unsaved("Guardar \($0)", hoursAgo: 100 + Double($0)) }
        list += (0..<5).map { unread(shop($0), hoursAgo: Double($0)) }
        let kept = PendingPayments.current(list, now: now)
        #expect(kept.count == PendingPayments.limit)
        #expect(kept.filter { $0.kind == .unsaved }.count == 19)
        // Of the notices only the newest stays, though all are newer than every unsaved one.
        #expect(kept.filter { $0.kind == .unread }.map(\.text) == [shop(0)])
        #expect(kept.first?.text == shop(0))
    }

    @Test func aNoticeWithAFigureOrAChargeIsNeverCutNorAgesOut() {
        // Only the person removes what the capture received as money (CLAUDE.md, 2026-11-19).
        let figure = unread("Oxxo 3I9", hoursAgo: 24 * 40)
        let charge = PendingPayment.unread("American Express México", always: true,
                                           date: now.addingTimeInterval(-24 * 40 * 3600))!
        let names = (0..<25).map { unread(shop($0), hoursAgo: Double($0)) }
        let kept = PendingPayments.current(names + [figure, charge], now: now)
        #expect(kept.contains(figure))
        #expect(kept.contains(charge))
        #expect(kept.count == PendingPayments.limit)
        #expect(kept.filter(\.mayAgeOut).count == PendingPayments.limit - 2)
    }

    @Test func aChargeKeptByAnEarlierVersionStillReads() throws {
        // Earlier versions kept no `isCharge`: it reads as nil.
        let old = #"[{"id":"0E8B5F1C-2C55-4E2B-9C1B-6B9C3E0C8A11","kind":"unread","text":"Oxxo","date":800000000}]"#
        let read = PendingPayments.decode(old)
        #expect(read.count == 1)
        #expect(read.first?.isCharge == nil)
        let charge = try #require(PendingPayment.unread("Amex", always: true, date: now))
        #expect(PendingPayments.decode(PendingPayments.encode([charge])).first?.isCharge == true)
    }

    @Test func paymentsThatCouldNotBeSavedAreNeverCutByTheLimit() {
        // Only the person removes one (2026-11-18): 25 of them stay, all 25.
        var list: [PendingPayment] = []
        for hour in (0..<25).reversed() {
            list = PendingPayments.adding(unsaved("Guardar \(hour)", hoursAgo: Double(hour)), to: list, now: now)
        }
        #expect(list.count == 25)
        #expect(list.first?.text == "Guardar 0")
        #expect(list.last?.text == "Guardar 24")
    }

    @Test func pastTheLimitOnlyNoticesMakeRoom() {
        let saved = (0..<22).map { unsaved("Guardar \($0)", hoursAgo: Double($0)) }
        let kept = PendingPayments.current(saved + [unread("Leer", hoursAgo: 1)], now: now)
        #expect(kept.count == 22)
        #expect(kept.allSatisfy { $0.kind == .unsaved })
    }

    @Test func aPaymentThatCouldNotBeSavedOutlivesThirtyDaysANoticeDoesNot() {
        let old = unsaved("$89 en Oxxo", hoursAgo: 24 * 40)
        let notice = unread("Google", hoursAgo: 24 * 40)
        let list = PendingPayments.adding(unread("Nuevo"), to: [old, notice], now: now)
        #expect(list.map(\.text) == ["Nuevo", "$89 en Oxxo"])
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

    @Test func aDaySaidToSiriIsTheDayTheSheetStartsOn() throws {
        let said = now.addingTimeInterval(-20 * 24 * 3600)
        let payment = try #require(PendingPayment.unsaved(amount: "$230", merchant: "Tacos", card: nil,
                                                          date: now, spentOn: said))
        #expect(payment.prefill(primary: "MXN").date == said)
        // It still arrived now: it is ordered and ages out from its arrival.
        #expect(PendingPayments.current([payment], now: now.addingTimeInterval(15 * 24 * 3600)) == [payment])
    }

    @Test func whatEarlierVersionsKeptStillReadsWithoutTheDaySaid() throws {
        let kept = PendingPayments.encode([PendingPayment.unsaved(amount: "$89", merchant: "Oxxo", card: nil, date: now)!])
        let read = PendingPayments.decode(kept)
        #expect(read.count == 1)
        #expect(read.first?.spentOn == nil)
        #expect(read.first?.prefill(primary: "MXN").date == now)
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
