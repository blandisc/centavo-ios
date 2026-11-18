import Foundation

/// The locale the dates a person reads are written in (2026-11-18, the app in English).
///
/// In the app and its widgets it is the person's own: an iPhone in English reads «Nov 12».
/// Anywhere else, which is this package's own tests on the Mac, it stays Mexican Spanish, so
/// what they check doesn't depend on the Mac's language. Never for file names, CSV or parsing.
public enum DisplayLocale {
    public static var current: Locale {
        let kind = Bundle.main.bundleURL.pathExtension
        if kind == "app" || kind == "appex" { return .current }
        return Locale(identifier: "es_MX")
    }

    /// Whether `locale` writes Spanish: then the fixed formats the screens were made with
    /// («12 nov, 9:40 p.m.») still apply. Any other language gets its own order of the parts.
    static func isSpanish(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "es"
    }
}
