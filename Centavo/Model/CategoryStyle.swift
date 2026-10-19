import Foundation

/// The categories offered with one tap, each with its icon. Other names typed by hand are
/// kept as they are and get a tag.
enum CategoryStyle {
    static let common: [(name: String, icon: String)] = [
        ("Despensa", "cart"),
        ("Comida", "fork.knife"),
        ("Café", "cup.and.saucer"),
        ("Transporte", "car"),
        ("Servicios", "bolt"),
        ("Suscripciones", "play.rectangle"),
        ("Salidas", "wineglass"),
        ("Ropa", "tshirt"),
        ("Salud", "cross.case"),
        ("Hogar", "house"),
        ("Compras", "bag"),
    ]

    static func icon(for category: String, custom: [LabeledIcon] = []) -> String {
        if let own = custom.first(where: { UserCatalog.same($0.name, category) }) { return own.icon }
        let wanted = fold(category)
        if wanted == fold("Casa") || wanted == fold("Renta") { return "house" }
        return common.first { fold($0.name) == wanted }?.icon ?? "tag"
    }

    /// The common ones, then the ones someone made, then any other already used (most used
    /// first), each name once.
    static func offered(known: [String], custom: [LabeledIcon] = [], current: String = "") -> [String] {
        var names: [String] = []
        for name in common.map(\.name) + custom.map(\.name) + known + [current]
        where !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !names.contains(where: { UserCatalog.same($0, name) }) {
            names.append(name)
        }
        return names
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
