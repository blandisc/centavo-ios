import Foundation

/// The categories offered with one tap, each with its icon and its usual color (a place in
/// `Theme.categories`; the eight most used never share one). Other names typed by hand are
/// kept as they are and get a tag.
enum CategoryStyle {
    static let common: [(name: String, icon: String, color: Int)] = [
        ("Despensa", "cart", 0),
        ("Comida", "fork.knife", 1),
        ("Café", "cup.and.saucer", 6),
        ("Transporte", "car", 2),
        ("Servicios", "bolt", 5),
        ("Suscripciones", "play.rectangle", 4),
        ("Salidas", "wineglass", 3),
        ("Ropa", "tshirt", 7),
        ("Salud", "cross.case", 5),
        ("Hogar", "house", 7),
        ("Compras", "bag", 3),
    ]

    /// The usual color of one of the app's own categories; `nil` for one someone made.
    static func colorIndex(for category: String) -> Int? {
        let wanted = fold(category)
        if wanted == fold("Casa") || wanted == fold("Renta") { return colorIndex(for: "Hogar") }
        return common.first { fold($0.name) == wanted }?.color
    }

    static func icon(for category: String, custom: [LabeledIcon] = []) -> String {
        if let own = custom.first(where: { UserCatalog.same($0.name, category) }) { return own.icon }
        let wanted = fold(category)
        if wanted == fold("Casa") || wanted == fold("Renta") { return "house" }
        return common.first { fold($0.name) == wanted }?.icon ?? "tag"
    }

    /// The common ones, then the ones someone made, then any other already used (most used
    /// first), each name once.
    /// `hidden` ones are left out, unless the expense already has it.
    static func offered(known: [String], custom: [LabeledIcon] = [], current: String = "",
                        hidden: [String] = []) -> [String] {
        var names: [String] = []
        for name in common.map(\.name) + custom.map(\.name) + known + [current]
        where !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !names.contains(where: { UserCatalog.same($0, name) })
            && (UserCatalog.same(name, current) || !hidden.contains(where: { UserCatalog.same($0, name) })) {
            names.append(name)
        }
        return names
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
