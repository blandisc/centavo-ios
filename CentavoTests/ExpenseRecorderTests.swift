import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// The Wallet capture, end to end, against a throwaway in-memory store.
final class ExpenseRecorderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func saved() throws -> [Expense] {
        try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
    }

    @discardableResult
    private func record(_ amount: String, _ merchant: String? = "Oxxo", card: String? = "BBVA",
                        at date: Date? = nil, rules: CategoryRules = CategoryRules(),
                        hidden: [String] = []) throws -> CaptureOutcome {
        try ExpenseRecorder.record(amountText: amount, merchant: merchant, card: card,
                                   in: context, rules: rules, hidden: hidden, renames: MerchantRenames(),
                                   now: date ?? now)
    }

    private func filed(_ merchant: String, _ category: String?, daysAgo: Double) throws {
        context.insert(Expense(amount: 50, currencyMarker: "$", merchant: merchant,
                               date: now.addingTimeInterval(-86_400 * daysAgo), category: category))
        try context.save()
    }

    func testSavesAWalletPaymentWithEverythingItCame() throws {
        XCTAssertEqual(try record("$89.00"), .saved(merchant: "Oxxo"))
        let expense = try XCTUnwrap(saved().first)
        XCTAssertEqual(expense.amount, 89)
        XCTAssertEqual(expense.currencyMarker, "$")
        XCTAssertEqual(expense.merchant, "Oxxo")
        XCTAssertEqual(expense.card, "BBVA")
        XCTAssertEqual(expense.rawAmount, "$89.00")
        XCTAssertEqual(expense.date, now)
    }

    /// A capture that kept the bank as the merchant is read again from its notice; one
    /// someone named by hand, or a real shop, stays as it is.
    func testOldCapturesWithTheBankAsMerchantAreRepaired() throws {
        let notice = "Ahora\nAmerican Express México\nMXN 1,060.00\nLa Docena"
        try ExpenseRecorder.record(amountText: "MXN 1,060.00", merchant: "American Express México",
                                   card: nil, rawNotice: notice, in: context, renames: MerchantRenames(), now: now)
        try ExpenseRecorder.record(amountText: "MXN 20.00", merchant: "Oxxo Roble", card: "HSBC México",
                                   rawNotice: "HSBC México\nMXN 20.00\nOxxo Roble", in: context,
                                   renames: MerchantRenames(), now: now.addingTimeInterval(3_600))
        XCTAssertEqual(try ExpenseRecorder.repairBankMerchants(in: context, knownCards: [], defaults: nil), 1)
        let rows = try saved()
        XCTAssertEqual(rows[0].merchant, "La Docena")
        XCTAssertEqual(rows[0].card, "American Express México")
        XCTAssertEqual(rows[0].shownName, "La Docena")
        XCTAssertEqual(rows[1].merchant, "Oxxo Roble")
        XCTAssertEqual(try ExpenseRecorder.repairBankMerchants(in: context, knownCards: [], defaults: nil), 0)
    }

    /// The repair runs on every return to the app: after its first run it only reads what
    /// came since, unless the list of cards changed.
    func testTheRepairOnlyReadsWhatCameSinceItsLastRun() throws {
        let suite = "repair-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let notice = "Ahora\nAmerican Express México\nMXN 1,060.00\nLa Docena"
        XCTAssertEqual(try ExpenseRecorder.repairBankMerchants(in: context, knownCards: [], defaults: defaults,
                                                               now: now), 0)
        // An old line written before the last run (as if left by an older version): not read again.
        context.insert(Expense(amount: 1_060, currencyMarker: "MXN", merchant: "American Express México",
                               date: now.addingTimeInterval(-3_600)))
        let old = try XCTUnwrap(try saved().first)
        old.rawNotice = notice
        try context.save()
        XCTAssertEqual(try ExpenseRecorder.repairBankMerchants(in: context, knownCards: [], defaults: defaults,
                                                               now: now.addingTimeInterval(60)), 0)
        XCTAssertEqual(old.merchant, "American Express México")
        // A new list of cards reads everything again.
        XCTAssertEqual(try ExpenseRecorder.repairBankMerchants(in: context, knownCards: ["Amex"], defaults: defaults,
                                                               now: now.addingTimeInterval(120)), 1)
        XCTAssertEqual(old.merchant, "La Docena")
    }

    func testABlankMerchantBecomesSinComercio() throws {
        XCTAssertEqual(try record("$10", "   "), .saved(merchant: "Sin comercio"))
        XCTAssertEqual(try record("$11", nil, at: now.addingTimeInterval(3_600)),
                       .saved(merchant: "Sin comercio"))
    }

    func testACardThatIsOnlySpacesIsNoCard() throws {
        try record("$10", card: "   ")
        XCTAssertNil(try saved().first?.card)
        try record("$20", "Seven", card: " Nu ", at: now.addingTimeInterval(3_600))
        XCTAssertEqual(try saved().last?.card, "Nu")
    }

    func testAnAbsurdlyLongMerchantIsCut() throws {
        try record("$10", String(repeating: "X", count: 5_000))
        XCTAssertEqual(try saved().first?.merchant.count, ExpenseRecorder.maxMerchantLength)
    }

    func testAZeroPaymentIsAWalletGlitchAndSavesNothing() throws {
        XCTAssertEqual(try record("$0.00", ""), .empty)
        XCTAssertEqual(try saved().count, 0)
    }

    /// Connecting «Entrada del atajo» instead of «Importe» hands over the whole payment.
    func testTheWholePaymentStillSavesTheRightAmount() throws {
        XCTAssertEqual(try record("Oxxo\n$89.00\nBBVA •••• 1234", nil), .saved(merchant: "Sin comercio"))
        XCTAssertEqual(try saved().first?.amount, 89)
    }

    /// The card's last four right after the amount used to lose the payment; a bank's initials
    /// in front of a bare number used to save it in a "currency" called BBVA.
    func testTheCardAfterTheAmountSavesTheAmountAndABankIsNoCurrency() throws {
        XCTAssertEqual(try record("Oxxo $89.00 1234", nil), .saved(merchant: "Sin comercio"))
        XCTAssertEqual(try saved().first?.amount, 89)
        XCTAssertEqual(try saved().first?.currencyMarker, "$")
        XCTAssertEqual(try record("BBVA 1234", "Seven", at: now.addingTimeInterval(3_600)), .unreadable)
        XCTAssertEqual(try saved().count, 1)
    }

    /// What a real automation sent on 2026-10-15: the payment itself in the amount field, whose
    /// text is only the merchant (twice). It once saved 501,501 in a "currency" of letters.
    func testAMerchantNameInTheAmountIsRejectedNotSaved() throws {
        XCTAssertEqual(try record("Oxxo Roble Mty 50ht1Oxxo Roble Mty 50ht1", nil), .unreadable)
        XCTAssertEqual(try saved().count, 0)
    }

    /// A junk "currency" (a merchant's name, seen for real) never pushes a row off screen.
    func testALongJunkMarkerIsCutInTheLedger() {
        let expense = Expense(amount: 501_501, currencyMarker: "OxxoRobleMtyhtOxxoRobleMtyht",
                              merchant: "Sin comercio")
        XCTAssertEqual(ledgerAmount(for: expense, primary: "MXN"), "Oxxo 501,501.00")
    }

    /// The Wallet notification of an online purchase, read and saved.
    func testAWalletNoticeSavesCardMerchantAndAmount() throws {
        let notice = try XCTUnwrap(WalletNotice.parse("American Express México\nGoogle\nMXN 319.00"))
        XCTAssertEqual(try record(notice.amountText, notice.merchant, card: notice.card), .saved(merchant: "Google"))
        let expense = try XCTUnwrap(saved().first)
        XCTAssertEqual(expense.amount, 319)
        XCTAssertEqual(expense.currencyMarker, "MXN")
        XCTAssertEqual(expense.card, "American Express México")
        XCTAssertEqual(expense.rawAmount, "MXN 319.00")
    }

    func testACardNumberIsNeverReadAsTheAmount() throws {
        XCTAssertEqual(try record("Oxxo BBVA 1234"), .unreadable)
        XCTAssertEqual(try saved().count, 0)
    }

    // MARK: A mano, con Siri

    func testSiriSavesHowMuchAndWhere() throws {
        XCTAssertEqual(try ExpenseRecorder.recordByHand(amountText: "89.50", merchant: " Tacos ",
                                                        in: context, primary: "MXN", now: now),
                       .saved(merchant: "Tacos"))
        let expense = try XCTUnwrap(saved().first)
        XCTAssertEqual(expense.amount, Decimal(string: "89.5"))
        XCTAssertEqual(expense.currencyMarker, "MXN", "Se guarda el código, no un «$» ambiguo")
        XCTAssertNil(expense.rawAmount, "Un gasto a mano no debe contar como captura de Wallet")
    }

    func testTwoCoffeesByHandAreTwoCoffees() throws {
        for _ in 0..<2 {
            _ = try ExpenseRecorder.recordByHand(amountText: "45", merchant: "Café", in: context, now: now)
        }
        XCTAssertEqual(try saved().count, 2)
    }

    func testAWordForACurrencyKeepsItInTheTotal() throws {
        _ = try ExpenseRecorder.recordByHand(amountText: "89 pesos", merchant: "Oxxo", in: context,
                                             primary: "MXN", now: now)
        XCTAssertEqual(try saved().first?.currencyMarker, "MXN")
    }

    func testSiriUnderstandsDollarsAndEuros() {
        XCTAssertEqual(ExpenseRecorder.spokenCurrency("dólares", primary: "MXN"), "USD")
        XCTAssertEqual(ExpenseRecorder.spokenCurrency("Euros", primary: "MXN"), "EUR")
        XCTAssertEqual(ExpenseRecorder.spokenCurrency("US$", primary: "MXN"), "USD")
        XCTAssertEqual(ExpenseRecorder.spokenCurrency(nil, primary: "MXN"), "MXN")
        XCTAssertEqual(ExpenseRecorder.spokenCurrency("varos", primary: "MXN"), "MXN")
    }

    func testSiriRejectsZeroAndNonsense() throws {
        XCTAssertEqual(try ExpenseRecorder.recordByHand(amountText: "0", merchant: "x", in: context), .empty)
        XCTAssertEqual(try ExpenseRecorder.recordByHand(amountText: "mucho", merchant: "x", in: context),
                       .unreadable)
        XCTAssertEqual(try saved().count, 0)
    }

    func testUnreadableAmountsSaveNothing() throws {
        for junk in ["", "abc", "$", "1234567890123", "1.23456"] {
            XCTAssertEqual(try record(junk), .unreadable, "«\(junk)» debía ser ilegible")
        }
        XCTAssertEqual(try saved().count, 0)
    }

    func testTheSameTapTwiceWithinMinutesIsOnePayment() throws {
        XCTAssertEqual(try record("$89.00"), .saved(merchant: "Oxxo"))
        XCTAssertEqual(try record("$89.00", "OXXO ", card: "bbva", at: now.addingTimeInterval(90)),
                       .duplicate(merchant: "OXXO"))
        XCTAssertEqual(try saved().count, 1)
    }

    func testTheSamePurchaseLaterIsANewPayment() throws {
        try record("$89.00")
        XCTAssertEqual(try record("$89.00", at: now.addingTimeInterval(10 * 60)),
                       .saved(merchant: "Oxxo"))
        XCTAssertEqual(try saved().count, 2)
    }

    func testARefundIsSavedNegative() throws {
        try record("-$230.00", "Liverpool")
        XCTAssertEqual(try saved().first?.amount, -230)
    }

    func testAForeignCurrencyKeepsItsMarker() throws {
        try record("USD 24.99", "Steam")
        let expense = try XCTUnwrap(saved().first)
        XCTAssertEqual(expense.amount, Decimal(string: "24.99"))
        XCTAssertEqual(expense.currencyMarker, "USD")
    }

    func testAPaymentLandsInTheCategoryTheMerchantWasLastFiledUnder() throws {
        context.insert(Expense(amount: 50, currencyMarker: "$", merchant: "Oxxo",
                               date: now.addingTimeInterval(-86_400), category: "Despensa"))
        try context.save()
        try record("$89.00", "OXXO")
        let capture = try XCTUnwrap(saved().last)
        XCTAssertEqual(capture.category, "Despensa")
    }

    /// «Borrar el último gasto» finds the newest one up to now, never a fixed one.
    func testTheLastExpenseIsTheNewestThatIsNotFixed() throws {
        try filed("Oxxo", nil, daysAgo: 2)
        try filed("Starbucks", nil, daysAgo: 1)
        let rent = Expense(amount: 9_000, currencyMarker: "$", merchant: "Renta", date: now.addingTimeInterval(-60))
        rent.isRepeat = true
        context.insert(rent)
        context.insert(Expense(amount: 10, currencyMarker: "$", merchant: "Mañana", date: now.addingTimeInterval(86_400)))
        try context.save()
        XCTAssertEqual(try ExpenseRecorder.lastLogged(in: context, now: now)?.merchant, "Starbucks")
    }

    /// A category said to Siri is used as is, over the memory.
    func testACategorySaidToSiriWins() throws {
        try filed("Fonda Lupita", "Comida", daysAgo: 3)
        _ = try ExpenseRecorder.recordByHand(amountText: "120", merchant: "Fonda Lupita", category: "Antojos",
                                         in: context, primary: "MXN", rules: CategoryRules(), hidden: [], now: now)
        XCTAssertEqual(try saved().last?.category, "Antojos")
    }

    /// The memory looks back a year: a merchant last filed before that starts over, while a
    /// category chosen as a rule still wins.
    func testTheMemoryLooksBackOneYearButARuleStillWins() throws {
        try filed("Fonda Lupita", "Comida", daysAgo: 400)
        try record("$89.00", "Fonda Lupita")
        XCTAssertNil(try saved().last?.category, "Más de un año: no se recuerda")
        try filed("Fonda Chabelita", "Comida", daysAgo: 300)
        try record("$95.00", "Fonda Chabelita", at: now.addingTimeInterval(3_600))
        XCTAssertEqual(try saved().last?.category, "Comida")
        var rules = CategoryRules()
        rules.learn("Antojos", for: "Fonda Lupita")
        try record("$99.00", "Fonda Lupita", at: now.addingTimeInterval(7_200), rules: rules)
        XCTAssertEqual(try saved().last?.category, "Antojos")
    }

    /// «Recordar mi categoría»: the owner's newest decision beats the newest expense.
    func testTheLatestManualChoiceWinsEvenOnAnOlderExpense() throws {
        try filed("Oxxo", "Antojos", daysAgo: 9)   // corrected by hand today
        try filed("Oxxo", "Despensa", daysAgo: 1)  // got Despensa from the memory
        var rules = CategoryRules()
        rules.learn("Despensa", for: "Oxxo")
        rules.learn("Antojos", for: "Oxxo")
        try record("$89.00", "  oxxo ", rules: rules)
        XCTAssertEqual(try saved().last?.category, "Antojos")
    }

    func testAMerchantTheOwnerLeftWithoutCategoryStaysWithout() throws {
        try filed("Oxxo", "Despensa", daysAgo: 3)
        var rules = CategoryRules()
        rules.learn(nil, for: "Oxxo")
        try record("$89.00", "OXXO", rules: rules)
        XCTAssertNil(try saved().last?.category, "Ni la memoria ni el catálogo después de quitarla")
    }

    func testAHiddenCategoryIsNotFilledIn() throws {
        try filed("Petco", "Mascotas", daysAgo: 3)
        var rules = CategoryRules()
        rules.learn("Mascotas", for: "Petco")
        try record("$300.00", "Petco", rules: rules, hidden: ["Mascotas"])
        XCTAssertNil(try saved().last?.category)
    }

    func testADeletedCategoryStaysInThePickerButIsNotFilledIn() throws {
        try filed("Petco", "Mascotas", daysAgo: 3)
        var rules = CategoryRules()
        rules.learn("Mascotas", for: "Petco")
        // Deleting adds it to the deleted list, never to the hidden one.
        let deleted = UserCatalog.decodeNames(UserCatalog.names("", setting: "Mascotas", included: true))
        let known = CategoryMemory.known(in: try saved().map(\.categorized))
        XCTAssertTrue(CategoryStyle.offered(known: known, custom: [], hidden: []).contains("Mascotas"))
        try record("$300.00", "PETCO", rules: rules, hidden: deleted)
        XCTAssertNil(try saved().last?.category)
        // Made again: off the list, filled in as before.
        let again = UserCatalog.decodeNames(UserCatalog.names(UserCatalog.encodeNames(deleted),
                                                              setting: "mascotas", included: false))
        XCTAssertEqual(again, [])
        try record("$120.00", "Petco", rules: rules, hidden: again)
        XCTAssertEqual(try saved().last?.category, "Mascotas")
    }

    func testRememberingNeverTouchesExpensesAlreadySaved() throws {
        try filed("Oxxo", "Despensa", daysAgo: 5)
        try filed("Oxxo", nil, daysAgo: 2)
        var rules = CategoryRules()
        rules.learn("Antojos", for: "Oxxo")
        try record("$89.00", "Oxxo", rules: rules)
        XCTAssertEqual(try saved().map(\.category), ["Despensa", nil, "Antojos"])
    }

    func testSiriAlsoGetsTheRememberedCategory() throws {
        var rules = CategoryRules()
        rules.learn("Café", for: "La Esquina")
        XCTAssertEqual(try ExpenseRecorder.recordByHand(amountText: "45", merchant: "la esquina", in: context,
                                                        primary: "MXN", rules: rules, hidden: [], now: now),
                       .saved(merchant: "la esquina"))
        XCTAssertEqual(try saved().first?.category, "Café")
    }

    func testAKnownMexicanMerchantGetsASuggestedCategory() throws {
        try record("$120.00", "UBER *TRIP")
        XCTAssertEqual(try saved().first?.category, "Transporte")
    }

    func testAMerchantNeverSeenBeforeHasNoCategory() throws {
        try record("$89.00", "Un lugar nuevo")
        XCTAssertNil(try saved().first?.category)
    }

    func testAWalletNameReadsCleanAndTheOriginalStays() throws {
        try record("$89.00", "CLIP*MX TAQ GUERO 02")
        let capture = try XCTUnwrap(saved().first)
        XCTAssertEqual(capture.merchant, "CLIP*MX TAQ GUERO 02")
        XCTAssertEqual(capture.shownName, "Taq Guero")
    }

    func testTheReadableNameAndASuggestionCarryOverButAreNotRemembered() throws {
        let earlier = Expense(amount: 80, currencyMarker: "$", merchant: "CLIP*MX TAQ GUERO 02",
                              date: now.addingTimeInterval(-86_400), category: "Comida")
        earlier.categorySource = Expense.suggestedCategory
        earlier.displayName = "Taquería El Güero"
        context.insert(earlier)
        try context.save()

        try record("$95.00", "CLIP*MX TAQ GUERO 02")
        let capture = try XCTUnwrap(saved().last)
        XCTAssertEqual(capture.shownName, "Taquería El Güero")
        XCTAssertEqual(capture.category, "Comida")
        XCTAssertTrue(capture.hasSuggestedCategory, "Una sugerencia se volvió elección sin que nadie la eligiera")
    }

    func testAByHandExpenseKeepsItsCardAndDay() throws {
        let yesterday = now.addingTimeInterval(-86_400)
        XCTAssertEqual(try ExpenseRecorder.recordByHand(amountText: "230", merchant: "Tacos", card: "Efectivo",
                                                        in: context, primary: "MXN", now: yesterday),
                       .saved(merchant: "Tacos"))
        let expense = try XCTUnwrap(saved().first)
        XCTAssertEqual(expense.card, "Efectivo")
        XCTAssertEqual(expense.date, yesterday)
        XCTAssertEqual(expense.currencyMarker, "MXN")
    }

    /// A merchant renamed by hand comes back from Wallet with its new name, and with the
    /// category it was filed under after the rename.
    func testARenamedMerchantArrivesWithItsNewName() throws {
        var renames = MerchantRenames()
        renames.rename("OXXO SUC 1234", to: "Oxxo de la esquina")
        try filed("Oxxo de la esquina", "Súper", daysAgo: 1)
        try ExpenseRecorder.record(amountText: "$45.00", merchant: "OXXO SUC 1234", card: "BBVA",
                                   in: context, rules: CategoryRules(), hidden: [], renames: renames, now: now)
        let expense = try XCTUnwrap(saved().last)
        XCTAssertEqual(expense.merchant, "Oxxo de la esquina")
        XCTAssertEqual(expense.shownName, "Oxxo de la esquina")
        XCTAssertEqual(expense.category, "Súper")
        // Another branch was never renamed.
        try ExpenseRecorder.record(amountText: "$20.00", merchant: "OXXO SUC 5678", card: "BBVA",
                                   in: context, rules: CategoryRules(), hidden: [], renames: renames,
                                   now: now.addingTimeInterval(3_600))
        XCTAssertEqual(try saved().last?.merchant, "OXXO SUC 5678")
    }
}
