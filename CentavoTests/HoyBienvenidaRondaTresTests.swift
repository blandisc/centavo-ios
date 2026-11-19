import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// Third round of QA on «Hoy», the welcome and the backup's notices (2026-11-19).
@MainActor
final class HoyBienvenidaRondaTresTests: XCTestCase {
    // MARK: «···» said as «Más»

    func testTheMenuPathIsSaidWithTheButtonsSpokenName() {
        XCTAssertEqual(MenuPath.spoken("Revísalo en ··· › Ajustes › Respaldo diario.", button: "Más"),
                       "Revísalo en Más › Ajustes › Respaldo diario.")
        XCTAssertEqual(MenuPath.spoken("Check it in ··· › Settings › Daily backup.", button: "More"),
                       "Check it in More › Settings › Daily backup.")
        XCTAssertEqual(MenuPath.spoken("Sin menú.", button: "Más"), "Sin menú.")
    }

    // MARK: The search's store question in English

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: Expense.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        context.insert(Expense(amount: 89, currencyMarker: "MXN", merchant: "Oxxo", card: "Efectivo", category: "Despensa"))
        context.insert(Expense(amount: 40, currencyMarker: "MXN", merchant: Expense.noMerchant))
        context.insert(Expense(amount: 300, currencyMarker: "MXN", merchant: "Uber", card: "Nu"))
        try context.save()
        return context
    }

    private static func english(_ stored: String) -> String {
        switch stored {
        case "Despensa": "Groceries"
        case "Efectivo": "Cash"
        case Expense.noMerchant: "No merchant"
        default: stored
        }
    }

    private func names(_ words: [String], display: (String) -> String) throws -> Set<String> {
        let found = try context().fetch(HomeModel.searchCandidates(for: SearchQuery(words: words), display: display))
        return Set(found.map(\.merchant))
    }

    func testAWordOfATranslationNarrowsToWhatIsStoredInSpanish() throws {
        // «No merchant» found nothing: «merchant» was asked of the store, which keeps «Sin comercio».
        XCTAssertEqual(try names(["merchant"], display: Self.english), [Expense.noMerchant])
        // «groc» and «cash» narrowed nothing and scanned every expense; now only what can match.
        XCTAssertEqual(try names(["groc"], display: Self.english), ["Oxxo"])
        XCTAssertEqual(try names(["cash"], display: Self.english), ["Oxxo"])
        // What is stored still counts.
        XCTAssertEqual(try names(["uber"], display: Self.english), ["Uber"])
    }

    func testInSpanishTheStoreIsAskedAsBefore() throws {
        XCTAssertEqual(try names(["despensa"], display: { $0 }), ["Oxxo"])
        XCTAssertEqual(try names(["comercio"], display: { $0 }), [Expense.noMerchant])
        XCTAssertEqual(try names(["merchant"], display: { $0 }), [])
    }

    // MARK: A backup that kept only the expenses

    func testOnlyTheFailureThatKeptTheExpensesSaysSo() throws {
        let suite = "ronda-tres-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let night = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(DailyBackup.lastFailureKeptExpensesOnly(defaults: defaults))
        defaults.set(night, forKey: DailyBackup.failedKey)
        defaults.set(night, forKey: DailyBackup.failedPartialKey)
        XCTAssertEqual(DailyBackup.lastFailureKeptExpensesOnly(defaults: defaults), !Features.money)
        // A later failure of another kind (the store down for the intent) isn't that one.
        defaults.set(night.addingTimeInterval(86_400), forKey: DailyBackup.failedKey)
        XCTAssertFalse(DailyBackup.lastFailureKeptExpensesOnly(defaults: defaults))
        XCTAssertEqual(DailyBackup.lastFailureText(defaults: defaults),
                       String(localized: "El último intento no se pudo hacer."))
    }

    func testAWorkingBackupClearsTheNote() throws {
        let suite = "ronda-tres-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let night = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(night, forKey: DailyBackup.failedKey)
        defaults.set(night, forKey: DailyBackup.failedPartialKey)
        DailyBackup.record(DailyBackup.Written(name: "al-dia-2027-01-15.aldia"), at: night, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: DailyBackup.failedPartialKey))
        XCTAssertFalse(DailyBackup.lastFailureKeptExpensesOnly(defaults: defaults))
    }
}
