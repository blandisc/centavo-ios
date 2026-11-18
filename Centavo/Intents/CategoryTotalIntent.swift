import AppIntents
import CentavoCore
import Foundation
import SwiftData

/// «¿Cuánto llevo en Café en Al día?»: this month's total in one category, out loud.
/// The sum is the same one the screen shows; nothing here needs the model, except to
/// understand a category said loosely («cafecitos»).
struct CategoryTotalIntent: AppIntent {
    static let title: LocalizedStringResource = "Cuánto llevo en una categoría"
    static let description = IntentDescription("Dice cuánto llevas gastado este mes en una categoría.")
    static let openAppWhenRun = false

    @Parameter(title: "Categoría", requestValueDialog: "¿En qué categoría?")
    var category: CategoryEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Cuánto llevo en \(\.$category)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // One more try at a store that failed earlier in this launch (`Store.forIntent`).
        guard let container = Store.forIntent else { throw CaptureError.storeUnavailable }
        // A fixed expense now due may have been saved: on the widgets before returning.
        defer { WidgetBridge.refreshAfterIntent() }
        _ = try? RecurringExpenses.logDue(in: container.mainContext)
        let sentence = try MonthStatus.categorySentence(category.id, in: container.mainContext)
        return .result(value: sentence, dialog: "\(sentence)")
    }
}

/// A category, for Siri: its name is its identity, as in the expenses themselves.
struct CategoryEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Categoría" }
    static var defaultQuery: CategoryQuery { CategoryQuery() }

    let id: String

    /// The app's own categories in the iPhone's language; the identity stays the stored name.
    var displayRepresentation: DisplayRepresentation {
        let shown = CategoryStyle.shown(id)
        return DisplayRepresentation(title: "\(shown)")
    }
}

struct CategoryQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
        identifiers.map(CategoryEntity.init)
    }

    func suggestedEntities() async throws -> [CategoryEntity] {
        await CategoryNames.all().map(CategoryEntity.init)
    }

    /// What Siri heard: a category by its name, whole or in part.
    func entities(matching string: String) async throws -> [CategoryEntity] {
        let names = await CategoryNames.all()
        // Said in the iPhone's language («groceries»), it is the one stored in Spanish (2026-11-18).
        let said = CategoryStyle.stored(string)
        if let exact = CategoryPick.validate(said, among: names) { return [CategoryEntity(id: exact)] }
        let folded = UserCatalog.fold(string)
        let partial = names.filter { name in
            Self.loosely(folded, UserCatalog.fold(name)) || Self.loosely(folded, UserCatalog.fold(CategoryStyle.shown(name)))
        }
        return partial.map(CategoryEntity.init)
    }

    /// «cafecitos» and «café»: one holds the other.
    private static func loosely(_ said: String, _ name: String) -> Bool {
        name.contains(said) || said.contains(name)
    }
}

/// Every category someone may ask about: the usual ones, their own, and any they used.
@MainActor
enum CategoryNames {
    static func all() -> [String] {
        let custom = UserCatalog.decode(UserDefaults.standard.string(forKey: UserCatalog.categoriesKey) ?? "")
        var used: [String] = []
        if let container = Store.forIntent {
            var descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            descriptor.fetchLimit = 1_000
            let expenses = (try? container.mainContext.fetch(descriptor)) ?? []
            used = CategoryMemory.known(in: expenses.map(\.categorized))
        }
        return CategoryPick.candidates(CategoryStyle.common.map(\.name), custom.map(\.name), used)
    }
}
