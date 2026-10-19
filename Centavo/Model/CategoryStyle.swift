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

    static func icon(for category: String) -> String {
        let wanted = fold(category)
        if wanted == fold("Casa") || wanted == fold("Renta") { return "house" }
        return common.first { fold($0.name) == wanted }?.icon ?? "tag"
    }

    /// The common ones plus every other category already used, most used first.
    static func offered(known: [String]) -> [String] {
        let commonNames = common.map(\.name)
        let extra = known.filter { name in !commonNames.contains { fold($0) == fold(name) } }
        return commonNames + extra
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
