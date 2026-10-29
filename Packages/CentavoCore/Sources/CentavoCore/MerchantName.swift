import Foundation

/// A merchant's name the way people read it: «CLIP*MX TAQ GUERO 02» is «Taq Guero» and
/// «AMZN MKTP MX*2K3J» is «Amazon».
///
/// Only for the screen. The expense keeps the name Wallet sent: the CSV, the category memory
/// and duplicate detection all still use it, and two branches stay two merchants.
public enum MerchantName {
    /// How `raw` reads on screen, or `nil` when it already reads fine.
    public static func readable(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Sin comercio" else { return nil }

        // The processor's prefix goes first: «GOOGLE *DUOLINGO» is Duolingo, not Google.
        let rest = withoutProcessor(trimmed)
        if let brand = brand(in: rest) {
            return same(brand, trimmed) ? nil : brand
        }

        var words = rest
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: edgePunctuation) }
            .filter { !$0.isEmpty }
        // A folio or terminal mixes letters and digits («50HT1», «G500»); a branch number
        // trails («02»). A number inside a name stays: «Farmacia 24 Horas».
        words.removeAll { $0.contains(where: \.isNumber) && $0.contains(where: \.isLetter) }
        while let last = words.last, last.contains(where: \.isNumber) { words.removeLast() }
        if let branch = words.firstIndex(where: { branchWords.contains(fold($0)) }) {
            words.removeSubrange(branch...)
        }
        words = withoutLegalSuffix(words)
        // Wallet shouts («TAQ GUERO»); a name that already has lowercase letters was written
        // by someone and keeps its case, and its words: «Mx Café» stays «Mx Café».
        let shouted = !words.joined().contains(where: \.isLowercase)
        if shouted {
            while words.count > 1, let first = words.first, places.contains(fold(first)) { words.removeFirst() }
            while words.count > 1, let last = words.last, places.contains(fold(last)) { words.removeLast() }
        }
        // Nothing left but numbers, a city code or «SA DE CV»: no name to show.
        guard words.contains(where: { !places.contains(fold($0)) && $0.contains(where: \.isLetter) }) else {
            return nil
        }

        let result = (shouted ? titleCased(words) : words).joined(separator: " ")
        return result == trimmed ? nil : result
    }

    /// Brands whose name Wallet mangles, as their own name. Longer first, so «Uber Eats» is
    /// not «Uber».
    static let brands: [(words: [String], name: String)] = [
        (["amzn"], "Amazon"), (["amazon"], "Amazon"), (["mercado", "libre"], "Mercado Libre"),
        (["mercadolibre"], "Mercado Libre"), (["uber", "eats"], "Uber Eats"), (["uber"], "Uber"),
        (["didi", "food"], "DiDi Food"), (["didi"], "DiDi"), (["rappi"], "Rappi"), (["cabify"], "Cabify"),
        (["oxxo"], "Oxxo"), (["7", "eleven"], "7-Eleven"), (["seven", "eleven"], "7-Eleven"),
        (["walmart"], "Walmart"), (["wal", "mart"], "Walmart"), (["bodega", "aurrera"], "Bodega Aurrera"),
        (["soriana"], "Soriana"), (["chedraui"], "Chedraui"), (["costco"], "Costco"),
        (["sams"], "Sam's Club"), (["heb"], "HEB"), (["la", "comer"], "La Comer"),
        (["city", "market"], "City Market"), (["superama"], "Superama"), (["circle", "k"], "Circle K"),
        (["liverpool"], "Liverpool"), (["palacio", "de", "hierro"], "El Palacio de Hierro"),
        (["starbucks"], "Starbucks"), (["netflix"], "Netflix"), (["spotify"], "Spotify"),
        (["disney", "plus"], "Disney+"), (["disney"], "Disney+"), (["hbo"], "HBO Max"), (["youtube"], "YouTube"),
        (["apple", "com", "bill"], "Apple"), (["icloud"], "iCloud"), (["google"], "Google"),
        (["steam"], "Steam"), (["playstation"], "PlayStation"), (["nintendo"], "Nintendo"),
        (["airbnb"], "Airbnb"), (["volaris"], "Volaris"), (["viva", "aerobus"], "Viva Aerobus"),
        (["aeromexico"], "Aeroméxico"), (["pemex"], "Pemex"), (["cfe"], "CFE"), (["telmex"], "Telmex"),
        (["telcel"], "Telcel"), (["izzi"], "izzi"), (["totalplay"], "Totalplay"),
        (["cinepolis"], "Cinépolis"), (["cinemex"], "Cinemex"),
        (["farmacias", "del", "ahorro"], "Farmacias del Ahorro"),
        (["farmacia", "del", "ahorro"], "Farmacias del Ahorro"),
        (["farmacias", "guadalajara"], "Farmacias Guadalajara"), (["benavides"], "Benavides"),
        (["home", "depot"], "The Home Depot"), (["ikea"], "IKEA"), (["zara"], "Zara"),
        (["shein"], "Shein"), (["coppel"], "Coppel"), (["suburbia"], "Suburbia"),
    ]
    private static let ordered = brands.enumerated()
        .sorted { ($0.element.words.count, -$0.offset) > ($1.element.words.count, -$1.offset) }
        .map(\.element)

    /// The brand a Wallet name is, if it is one. Its name is never reworded by the model.
    public static func brand(for raw: String) -> String? {
        brand(in: withoutProcessor(raw.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    /// Brand words that are also ordinary words or other businesses («Disney Store», «Steam Car
    /// Wash»): they name the brand only when nothing else but a branch or a folio is there.
    static let strictBrands: Set<String> = ["Disney+", "Steam", "Google"]

    private static func brand(in text: String) -> String? {
        let tokens = MerchantCatalog.tokens(text)
        guard let brand = ordered.first(where: { MerchantCatalog.contains(tokens, $0.words) }) else { return nil }
        guard strictBrands.contains(brand.name) else { return brand.name }
        let noise: Set<String> = places.union(branchWords).union(["com", "sa", "de", "cv", "s", "a", "c", "v"])
        let extra = tokens.filter { !brand.words.contains($0) && !noise.contains($0) && !$0.contains(where: \.isNumber) }
        return extra.isEmpty ? brand.name : nil
    }

    /// What payment processors put before the shop's name: «CLIP*», «MERPAGO*», «PAYPAL *»,
    /// «GOOGLE *».
    static let processors: Set<String> = [
        "google",
        "clip", "merpago", "mercadopago", "mp", "paypal", "pp", "sq", "stripe", "dlo", "conekta",
        "openpay", "billpocket", "netpay", "getnet", "sumup", "zettle", "izettle", "srv",
    ]
    /// Where the branch name starts.
    static let branchWords: Set<String> = ["suc", "sucursal"]
    /// City and country codes Wallet tacks on at either end.
    static let places: Set<String> = [
        "mx", "mex", "mty", "gdl", "cdmx", "df", "qro", "pue", "mer", "tij", "nl", "jal", "edomex",
    ]
    static let smallWords: Set<String> = ["de", "del", "la", "las", "el", "los", "y", "e", "en", "a", "al"]
    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:-_#*/\\|()[]\"'")

    private static func withoutProcessor(_ text: String) -> String {
        guard let star = text.firstIndex(of: "*") else { return text }
        let before = MerchantCatalog.tokens(String(text[..<star]))
        guard let first = before.first, processors.contains(first) else { return text }
        return String(text[text.index(after: star)...])
    }

    /// «SA DE CV», «S.A. de C.V.», «SAPI DE CV», «S DE RL» at the end.
    private static func withoutLegalSuffix(_ words: [String]) -> [String] {
        let suffixes: Set<String> = ["sadecv", "sapidecv", "sderl", "sderldecv", "sa", "sapi"]
        for count in stride(from: min(5, words.count), through: 1, by: -1) {
            let letters = words.suffix(count).map { fold($0).filter(\.isLetter) }.joined()
            if suffixes.contains(letters) { return Array(words.dropLast(count)) }
        }
        return words
    }

    private static func titleCased(_ words: [String]) -> [String] {
        words.enumerated().map { index, word in
            let lower = word.lowercased()
            if index > 0, smallWords.contains(fold(lower)) { return lower }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
    }

    private static func same(_ left: String, _ right: String) -> Bool { fold(left) == fold(right) }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
