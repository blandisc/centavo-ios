import Foundation

/// A first guess at the category of well-known merchants in Mexico, for a merchant you have
/// never categorized yourself. `CategoryMemory` (what *you* chose) always wins over this.
///
/// It looks for a brand as whole words inside the name, so «OXXO ROBLE MTY 1234» is Oxxo
/// but «Boxxon» is not. Longer brands are checked first, so «Uber Eats» is food and «Uber»
/// is a ride.
public enum MerchantCatalog {
    /// The category names match the ones the app already uses.
    static let brands: [(words: [String], category: String)] = [
        // Food delivery before rides: «Uber Eats», «DiDi Food».
        (["uber", "eats"], "Comida"), (["didi", "food"], "Comida"), (["rappi"], "Comida"),
        (["uber"], "Transporte"), (["didi"], "Transporte"), (["cabify"], "Transporte"),
        (["pemex"], "Transporte"), (["shell"], "Transporte"), (["bp"], "Transporte"),
        (["metrobus"], "Transporte"), (["ado"], "Transporte"), (["viva", "aerobus"], "Transporte"),
        (["volaris"], "Transporte"), (["aeromexico"], "Transporte"),

        (["oxxo"], "Despensa"), (["7", "eleven"], "Despensa"), (["seven", "eleven"], "Despensa"),
        (["soriana"], "Despensa"), (["walmart"], "Despensa"), (["bodega", "aurrera"], "Despensa"),
        (["chedraui"], "Despensa"), (["la", "comer"], "Despensa"), (["costco"], "Despensa"),
        (["sams"], "Despensa"), (["heb"], "Despensa"), (["city", "market"], "Despensa"),
        (["superama"], "Despensa"), (["fresko"], "Despensa"), (["circle", "k"], "Despensa"),

        (["starbucks"], "Café"), (["cielito"], "Café"), (["punta", "del", "cielo"], "Café"),
        (["tim", "hortons"], "Café"),

        (["netflix"], "Suscripciones"), (["spotify"], "Suscripciones"), (["disney"], "Suscripciones"),
        // «Max» alone is left out: as a whole word it catches «Zapatos Max»; «HBO» covers it.
        (["hbo"], "Suscripciones"), (["youtube"], "Suscripciones"),
        (["apple", "com", "bill"], "Suscripciones"), (["icloud"], "Suscripciones"),
        (["prime", "video"], "Suscripciones"), (["paramount"], "Suscripciones"),
        (["chatgpt"], "Suscripciones"), (["openai"], "Suscripciones"),

        (["cfe"], "Servicios"), (["telmex"], "Servicios"), (["izzi"], "Servicios"),
        (["totalplay"], "Servicios"), (["telcel"], "Servicios"), (["at", "t"], "Servicios"),
        (["megacable"], "Servicios"), (["naturgy"], "Servicios"), (["agua", "y", "drenaje"], "Servicios"),

        (["liverpool"], "Ropa"), (["palacio", "de", "hierro"], "Ropa"), (["zara"], "Ropa"),
        (["h", "m"], "Ropa"), (["suburbia"], "Ropa"), (["coppel"], "Ropa"), (["shein"], "Ropa"),
        (["pull", "bear"], "Ropa"), (["bershka"], "Ropa"),

        (["cinepolis"], "Salidas"), (["cinemex"], "Salidas"), (["ticketmaster"], "Salidas"),

        (["farmacias", "del", "ahorro"], "Salud"), (["farmacia", "del", "ahorro"], "Salud"),
        (["benavides"], "Salud"), (["farmacias", "guadalajara"], "Salud"), (["san", "pablo"], "Salud"),
        (["similares"], "Salud"),

        (["amazon"], "Compras"), (["mercado", "libre"], "Compras"), (["mercadolibre"], "Compras"),
        (["home", "depot"], "Hogar"), (["ikea"], "Hogar"), (["sodimac"], "Hogar"),
    ]
    /// Longest first, so «uber eats» is tried before «uber».
    private static let ordered = brands.sorted { $0.words.count > $1.words.count }

    /// The catalog's category for `merchant`, or `nil` when it is not a brand it knows.
    public static func category(for merchant: String) -> String? {
        let words = tokens(merchant)
        guard !words.isEmpty else { return nil }
        for brand in ordered where contains(words, brand.words) {
            return brand.category
        }
        return nil
    }

    /// Lowercased, accent-free words; punctuation splits («Sam's» → sams, «AT&T» → at t).
    static func tokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    static func contains(_ words: [String], _ phrase: [String]) -> Bool {
        guard phrase.count <= words.count else { return false }
        return (0...(words.count - phrase.count)).contains { start in
            Array(words[start..<(start + phrase.count)]) == phrase
        }
    }
}
