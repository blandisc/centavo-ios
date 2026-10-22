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
