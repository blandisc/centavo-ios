import CentavoCore
import Foundation

/// A name someone chose and the icon they gave it: a category of their own, or a way they
/// pay (a card, cash).
struct LabeledIcon: Codable, Hashable, Identifiable {
    var name: String
    var icon: String
    var id: String { name }
}

/// The categories and payment sources someone set up, kept as JSON in the same synced
/// settings as the budget (see `BudgetSync`), so a new iPhone on the same iCloud has them.
enum UserCatalog {
    static let categoriesKey = "customCategories"
    static let sourcesKey = "paymentSources"
    static let defaultSourceKey = "defaultPaymentSource"
    /// Category names someone chose not to see when writing down an expense (the app's own or
    /// any already used). Expenses keep them; only the picker leaves them out.
    static let hiddenCategoriesKey = "hiddenCategories"
    /// The category the owner last chose for each merchant (`CategoryRules`), synced too.
    static let categoryRulesKey = "categoryRules"
    /// Custom categories someone deleted (and has not made again), synced too. Only the
    /// remembered category reads it: those are never filled in on their own. The picker
    /// does not, so one still used keeps showing there.
    static let deletedCategoriesKey = "deletedCategories"
    /// The names the owner gave merchants by hand (`MerchantRenames`), synced too.
    static let merchantRenamesKey = "merchantRenames"

    static func decodeNames(_ stored: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(stored.utf8))) ?? []
    }

    static func encodeNames(_ names: [String]) -> String {
        (try? JSONEncoder().encode(names)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    static func decode(_ stored: String) -> [LabeledIcon] {
        guard let data = stored.data(using: .utf8),
              let list = try? JSONDecoder().decode([LabeledIcon].self, from: data) else { return [] }
        return list
    }

    /// The cards and ways of paying someone set up, for code outside a view (the Wallet intent).
    static var sourceNames: [String] {
        decode(UserDefaults.standard.string(forKey: sourcesKey) ?? "").map(\.name)
    }

    /// Hidden category names, for code outside a view (the intents, the importer).
    static var hiddenNames: [String] {
        decodeNames(UserDefaults.standard.string(forKey: hiddenCategoriesKey) ?? "")
    }

    /// Deleted custom category names (`deletedCategoriesKey`).
    static var deletedNames: [String] {
        decodeNames(UserDefaults.standard.string(forKey: deletedCategoriesKey) ?? "")
    }

    /// What a new expense never gets on its own: hidden categories and deleted ones.
    static var notAutoAssigned: [String] { hiddenNames + deletedNames }

    /// A custom category was deleted (`true`) or made again with that name (`false`).
    static func markDeleted(_ name: String, _ deleted: Bool) {
        let stored = names(UserDefaults.standard.string(forKey: deletedCategoriesKey) ?? "",
                           setting: name, included: deleted)
        UserDefaults.standard.set(stored, forKey: deletedCategoriesKey)
        if Store.syncsBudget { BudgetSync.push(stored, for: deletedCategoriesKey) }
    }

    /// What the owner chose per merchant, for code outside a view.
    static var categoryRules: CategoryRules {
        CategoryRules(stored: UserDefaults.standard.string(forKey: categoryRulesKey) ?? "")
    }

    /// The owner filed `merchant` under `category` by hand (`nil`: under none): the next
    /// expense from there starts with it. Pushed to iCloud like the other settings.
    static func learnCategory(_ category: String?, for merchant: String) {
        var rules = categoryRules
        rules.learn(category, for: merchant)
        saveRules(rules)
    }

    /// The names the owner gave merchants, for code outside a view (the Wallet intent).
    static var merchantRenames: MerchantRenames {
        MerchantRenames(stored: UserDefaults.standard.string(forKey: merchantRenamesKey) ?? "")
    }

    /// The owner renamed `old` to `new`: the next payment Wallet sends as `old` is saved as `new`.
    static func learnRename(_ old: String, to new: String) {
        var renames = merchantRenames
        renames.rename(old, to: new)
        let stored = renames.stored
        UserDefaults.standard.set(stored, forKey: merchantRenamesKey)
        if Store.syncsBudget { BudgetSync.push(stored, for: merchantRenamesKey) }
    }

    /// One of their categories was renamed: what was filed under the old name follows it.
    static func renameCategory(_ old: String, to new: String) {
        guard !same(old, new) else { return }
        var rules = categoryRules
        rules.renameCategory(old, to: new)
        saveRules(rules)
    }

    private static func saveRules(_ rules: CategoryRules) {
        let stored = rules.stored
        UserDefaults.standard.set(stored, forKey: categoryRulesKey)
        if Store.syncsBudget { BudgetSync.push(stored, for: categoryRulesKey) }
    }

    /// The stored list with `name` added (`included`) or taken out.
    static func names(_ stored: String, setting name: String, included: Bool) -> String {
        var list = decodeNames(stored).filter { !same($0, name) }
        if included { list.append(name) }
        return encodeNames(list)
    }

    static func encode(_ list: [LabeledIcon]) -> String {
        guard let data = try? JSONEncoder().encode(list) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Names compare the way people read them: "nu" and "Nu " are the same card.
    static func same(_ left: String, _ right: String) -> Bool {
        fold(left) == fold(right)
    }

    static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static let categoryIcons = [
        "cart", "fork.knife", "cup.and.saucer", "car", "bus", "fuelpump", "bolt", "drop",
        "wifi", "iphone", "play.rectangle", "music.note", "gamecontroller", "wineglass",
        "tshirt", "bag", "gift", "cross.case", "pills", "heart", "dumbbell", "house",
        "bed.double", "pawprint", "graduationcap", "book", "airplane", "suitcase",
        "wrench.and.screwdriver", "scissors", "sparkles", "figure.2.and.child.holdinghands",
        "briefcase", "building.2", "leaf", "tag",
    ]

    static let sourceIcons = [
        "creditcard", "creditcard.fill", "wallet.pass", "banknote", "dollarsign.circle",
        "building.columns", "iphone", "applelogo", "giftcard", "person.2", "briefcase", "star",
    ]
}
