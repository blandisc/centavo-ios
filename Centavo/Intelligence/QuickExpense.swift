import CentavoCore
import Foundation

/// One sentence into an expense, for Siri and for the expense sheet, by plain rules
/// (`QuickEntryParser`) that work the same on every iPhone.
enum QuickExpense {
    static func read(_ sentence: String, sources: [String], now: Date = .now) async -> QuickEntry? {
        QuickEntryParser.parse(sentence, sources: sources, now: now)
    }

    /// «ayer», «el viernes 16 de oct.»; nothing for today.
    static func spokenDay(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String? {
        if calendar.isDate(date, inSameDayAs: now) { return nil }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "ayer" }
        return "el " + date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)
            .locale(Locale(identifier: "es_MX")))
    }
}
