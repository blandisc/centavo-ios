import CentavoCore
import SwiftUI

/// The color of each category and each way of paying, read once from the synced settings and
/// handed to whatever draws them (the list reads it once, not once per row).
struct CatalogColors: Equatable {
    var categories: ColorTags
    var sources: ColorTags

    static let empty = CatalogColors(categories: ColorTags(), sources: ColorTags())

    init(categories: ColorTags, sources: ColorTags) {
        self.categories = categories
        self.sources = sources
    }

    init(categories: String, sources: String) {
        self.init(categories: ColorTags(stored: categories), sources: ColorTags(stored: sources))
    }

    /// For code outside a view (the widget snapshot).
    static var current: CatalogColors {
        CatalogColors(categories: UserDefaults.standard.string(forKey: UserCatalog.categoryColorsKey) ?? "",
                      sources: UserDefaults.standard.string(forKey: UserCatalog.sourceColorsKey) ?? "")
    }

    func categoryIndex(_ name: String) -> Int {
        categories.index(for: name, fallback: CategoryStyle.colorIndex(for: name))
    }

    func sourceIndex(_ name: String) -> Int {
        sources.index(for: name, fallback: Self.isCash(name) ? Self.cashColor : nil)
    }

    /// Which of the two a color belongs to.
    enum Kind {
        case category, source
        var key: String { self == .category ? UserCatalog.categoryColorsKey : UserCatalog.sourceColorsKey }
    }

    func index(_ name: String, kind: Kind) -> Int {
        kind == .category ? categoryIndex(name) : sourceIndex(name)
    }

    /// For a new one: the color the fewest of `names` have.
    func nextFree(_ kind: Kind, among names: [String]) -> Int {
        switch kind {
        case .category: categories.nextFree(among: names, fallback: CategoryStyle.colorIndex(for:))
        case .source: sources.nextFree(among: names) { Self.isCash($0) ? Self.cashColor : nil }
        }
    }

    /// `name` takes `index`; saved and synced at once.
    static func set(_ index: Int, for name: String, kind: Kind) {
        UserCatalog.setColor(index, for: name, key: kind.key)
    }

    func category(_ name: String) -> Color { Theme.categories[categoryIndex(name)] }
    func source(_ name: String) -> Color { Theme.categories[sourceIndex(name)] }

    /// Cash starts green, like a banknote.
    static let cashColor = 1

    static func isCash(_ name: String) -> Bool {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.contains("efectivo") || folded.contains("cash")
    }
}
