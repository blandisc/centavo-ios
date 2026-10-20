import CentavoCore
import Foundation

/// One sentence into an expense, for Siri and for the expense sheet. The plain reading
/// (`QuickEntryParser`) works on every iPhone; with the on-device model, its reading is used
/// wherever it matches what was said.
enum QuickExpense {
    static func read(_ sentence: String, sources: [String], now: Date = .now) async -> QuickEntry? {
        let plain = QuickEntryParser.parse(sentence, sources: sources, now: now)
        guard let reading = await LocalModel.readSentence(sentence) else { return plain }
        // No number the plain rules could find: the model's, if it really is in the sentence.
        let base = plain ?? QuickEntry(amountText: "", merchant: nil, date: now, source: nil)
        let refined = QuickEntryParser.refine(base, sentence: sentence, amount: reading.amount,
                                              merchant: reading.merchant, when: reading.when,
                                              payment: reading.payment, sources: sources, now: now)
        return refined.amountText.isEmpty ? nil : refined
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
