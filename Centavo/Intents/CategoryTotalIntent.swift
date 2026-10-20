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
        guard case .success(let container) = Store.opened else { throw CaptureError.storeUnavailable }
        try? RecurringExpenses.logDue(in: container.mainContext)
        let sentence = try MonthStatus.categorySentence(category.id, in: container.mainContext)
        return .result(value: sentence, dialog: "\(sentence)")
    }
}

/// A category, for Siri: its name is its identity, as in the expenses themselves.
struct CategoryEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Categoría" }
    static var defaultQuery: CategoryQuery { CategoryQuery() }

    let id: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct CategoryQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
        identifiers.map(CategoryEntity.init)
    }

    func suggestedEntities() async throws -> [CategoryEntity] {
        await CategoryNames.all().map(CategoryEntity.init)
    }

    /// What Siri heard: a category by its name, or, with the on-device model, by what it
    /// means («cafecitos» → «Café»).
    func entities(matching string: String) async throws -> [CategoryEntity] {
        let names = await CategoryNames.all()
        if let exact = CategoryPick.validate(string, among: names) { return [CategoryEntity(id: exact)] }
        let folded = UserCatalog.fold(string)
        let partial = names.filter { UserCatalog.fold($0).contains(folded) || folded.contains(UserCatalog.fold($0)) }
        if !partial.isEmpty { return partial.map(CategoryEntity.init) }
        if let meant = await LocalModel.category(for: string, candidates: names) {
            return [CategoryEntity(id: meant)]
        }
        return []
    }
}

/// Every category someone may ask about: the usual ones, their own, and any they used.
@MainActor
enum CategoryNames {
    static func all() -> [String] {
        let custom = UserCatalog.decode(UserDefaults.standard.string(forKey: UserCatalog.categoriesKey) ?? "")
        var used: [String] = []
        if case .success(let container) = Store.opened {
            var descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            descriptor.fetchLimit = 1_000
            let expenses = (try? container.mainContext.fetch(descriptor)) ?? []
            used = CategoryMemory.known(in: expenses.map(\.categorized))
        }
        return CategoryPick.candidates(CategoryStyle.common.map(\.name), custom.map(\.name), used)
    }
}
