import Foundation

/// A purchase read from the notification Apple Wallet shows for every payment, contactless or
/// online. Seen on the owner's iPhone (iOS 27, 2026-10-17):
///
///     American Express México      ← the card (title)
///     Google                       ← the merchant
///     MXN 319.00                   ← the amount, with its currency
///
/// Atajos may hand the notification over as one text or as title and body apart, so this reads
/// lines, whichever way they come.
public struct WalletNotice: Equatable, Sendable {
    public let amount: ParsedAmount
    /// The exact line the amount came from, kept as the capture's raw text.
    public let amountText: String
    public let merchant: String?
    public let card: String?

    /// `nil` when there is no amount with a currency: a boarding pass, a top-up reminder, any
    /// Wallet notice that is not a charge, or money that came in (someone paid you).
    /// A refund comes back negative, so it subtracts instead of counting as spending.
    ///
    /// `knownCards` are names the person already pays with (their cards, earlier captures):
    /// a line that matches one is the card, never the merchant.
    public static func parse(_ text: String, knownCards: [String] = []) -> WalletNotice? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces.union(invisibles)) }
            .filter { !$0.isEmpty }
        let folded = lines.joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
        if received.contains(where: folded.contains) { return nil }
        let isRefund = refunds.contains(where: folded.contains)
        // The last line with money: a concept like "OXXO 123 MTY" can look like an amount too.
        guard let index = lines.lastIndex(where: { line in
            CaptureText.amount(in: line).map { $0.currencyMarker != nil } ?? false
        }), let amount = CaptureText.amount(in: lines[index]) else { return nil }

        // Lines that say nothing about the purchase («Wallet», «Ahora», «10:32») go first.
        let clean: (String) -> String? = { line in
            if isNoise(line) { return nil }
            return isRefund ? withoutRefundWord(line) : line
        }
        let before = lines[..<index].compactMap(clean)
        let after = lines[(index + 1)...].compactMap(clean)
        let isCard = { (line: String) in looksLikeCard(line, knownCards: knownCards) }
        // The amount may share its line with the merchant ("Google MXN 319.00").
        let leftover = lines[index]
            .replacingOccurrences(of: amountPattern(in: lines[index]) ?? lines[index], with: "")
            .trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        // The bank is told apart by its name first, not by where it sits: Atajos and each bank
        // put the lines in their own order, and every guess by position took the bank for the
        // merchant on some iPhone (the owner's, three times).
        let named = (before + after).first(where: isCard)
        let shops = (before: before.filter { !isCard($0) }, after: after.filter { !isCard($0) })

        let merchant: String?
        var card: String?
        if let own = clean(leftover), !own.isEmpty, !isCard(own) {
            merchant = own
            card = named ?? before.last
        } else if let concept = shops.after.first, named != nil || !before.isEmpty {
            // Card, amount, then the concept (as the owner's notices arrive).
            merchant = concept
            card = named ?? before.last
        } else if let concept = shops.before.last {
            // Card, concept, then the amount: the concept sits right above the amount.
            merchant = concept
            card = named ?? before.prefix(while: { $0 != concept }).last
        } else {
            merchant = shops.after.first
            card = named
        }
        if card == merchant { card = nil }
        let merchantName = merchant.map(withoutJoiner)
        let figure = amountPattern(in: lines[index]) ?? lines[index]
        guard isRefund else {
            return WalletNotice(amount: amount, amountText: figure, merchant: merchantName, card: card)
        }
        let negative = ParsedAmount(value: -amount.value.magnitude, currencyMarker: amount.currencyMarker)
        return WalletNotice(amount: negative, amountText: figure.hasPrefix("-") ? figure : "-" + figure,
                            merchant: merchantName, card: card)
    }

    /// «en La Docena», «at Google», «Compra en Oxxo»: only the place.
    static func withoutJoiner(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
        for joiner in ["compra en ", "pago en ", "cargo en ", "en ", "at ", "@ "] where folded.hasPrefix(joiner) {
            let rest = String(text.dropFirst(joiner.count)).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? text : rest
        }
        return text
    }

    /// A notice `parse` could not read (a bank or format it doesn't know), as the on-device
    /// model read it. Trusted only when the amount is literally in the notice with a real
    /// currency, the merchant is too, and it is not money coming in.
    public static func rescue(_ text: String, merchant: String?, card: String?,
                              amountFragment: String) -> WalletNotice? {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
        if received.contains(where: folded.contains) { return nil }
        let figure = amountFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !figure.isEmpty, containsWhole(figure, in: text),
              let amount = CaptureText.amount(in: figure), amount.value != 0,
              let marker = amount.currencyMarker, CaptureText.isCurrency(marker) else { return nil }
        func inNotice(_ part: String?) -> String? {
            guard let part = part?.trimmingCharacters(in: .whitespacesAndNewlines), !part.isEmpty,
                  part != figure, text.range(of: part, options: [.caseInsensitive]) != nil else { return nil }
            return part
        }
        // The bank or card is not the shop: that mix-up is exactly what `parse` had to learn.
        guard let shop = inNotice(merchant),
              shop.caseInsensitiveCompare(card ?? "") != .orderedSame else { return nil }
        let isRefund = refunds.contains(where: folded.contains)
        let value = isRefund ? -amount.value.magnitude : amount.value
        return WalletNotice(amount: ParsedAmount(value: value, currencyMarker: amount.currencyMarker),
                            amountText: isRefund && !figure.hasPrefix("-") ? "-" + figure : figure,
                            merchant: shop, card: inNotice(card))
    }

    /// `figure` in `text` as a whole amount: «$45» is not in «$450.00».
    private static func containsWhole(_ figure: String, in text: String) -> Bool {
        var start = text.startIndex
        while let found = text.range(of: figure, range: start..<text.endIndex) {
            let before = found.lowerBound > text.startIndex ? text[text.index(before: found.lowerBound)] : " "
            let after = text[found.upperBound...].prefix(2)
            let runsOn = after.first.map { $0.isNumber || (",.".contains($0) && after.dropFirst().first?.isNumber == true) } ?? false
            if !before.isNumber && !runsOn { return true }
            start = text.index(after: found.lowerBound)
        }
        return false
    }

    private static func withoutRefundWord(_ line: String) -> String? {
        let folded = line.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                  locale: Locale(identifier: "es_MX"))
        guard let word = refunds.first(where: { folded.hasPrefix($0) }) else { return line }
        var rest = String(line.dropFirst(word.count)).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        for joiner in ["de ", "en "] where rest.lowercased().hasPrefix(joiner) {
            rest = String(rest.dropFirst(joiner.count))
        }
        return rest.isEmpty ? nil : rest
    }

    /// Lines that name the app, not the purchase.
    static let appLabels: Set<String> = ["wallet", "apple wallet", "apple pay", "cartera"]

    /// Characters a notification may carry that `trimmingCharacters(in: .whitespaces)` keeps.
    static let invisibles = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}")

    /// The app's name, or when the notice came: «Ahora», «hace 2 min», «10:32 a.m.», «ayer».
    static func isNoise(_ line: String) -> Bool {
        let folded = fold(line)
        if appLabels.contains(folded) { return true }
        if ["ahora", "justo ahora", "now", "ayer", "hoy"].contains(folded) { return true }
        return folded.range(of: #"^(hace \d+ ?\w*|\d+ ?(min|h|s|d)|\d{1,2}:\d{2}( ?[ap]\.? ?m\.?)?)$"#,
                            options: .regularExpression) != nil
    }

    /// A line that names the card or its bank, not a shop: one the person pays with, a known
    /// issuer («American Express México», «BBVA»), or words only a card has («•••• 1234»,
    /// «Tarjeta de crédito»).
    public static func looksLikeCard(_ line: String, knownCards: [String] = []) -> Bool {
        let folded = fold(line)
        if knownCards.contains(where: { !$0.isEmpty && fold($0) == folded }) { return true }
        if issuersAlone.contains(folded) { return true }
        if folded.range(of: #"(•|\*{2,}|x{4})\s?\d{4}|terminacion|terminada en"#, options: .regularExpression) != nil {
            return true
        }
        let words = Set(folded.components(separatedBy: CharacterSet.alphanumerics.inverted))
        if !cardWords.isDisjoint(with: words) { return true }
        let spaced = " " + folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ") + " "
        return issuers.contains { spaced.contains(" \($0) ") }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
            .trimmingCharacters(in: .whitespaces)
    }

    /// Banks and card issuers in Mexico, anywhere in the line.
    static let issuers = ["american express", "amex", "bbva", "bancomer", "banamex", "citibanamex",
                          "santander", "hsbc", "banorte", "scotiabank", "inbursa", "banregio",
                          "banbajio", "afirme", "bancoppel", "banco azteca", "hey banco", "invex",
                          "nu mexico", "mercado pago", "apple card", "apple cash", "rappicard",
                          "didi card", "plata card", "spin by oxxo", "uala", "stori",
                          "klar", "vexi", "openbank", "banco"]
    /// Issuers whose name is also a common word: only the whole line.
    static let issuersAlone: Set<String> = ["nu", "plata", "hey", "spin", "costco citi", "liverpool visa"]
    /// Words on a card, never on a shop's name.
    static let cardWords: Set<String> = ["tarjeta", "credito", "debito", "visa", "mastercard", "card"]

    /// Money back from a purchase: it is logged, as a refund.
    static let refunds = ["reembolso", "devolucion", "reverso", "reversion", "cargo cancelado",
                          "compra cancelada"]
    /// Money that came in from someone: not spending at all.
    static let received = ["recibiste", "te enviaron", "te envio", "te mando", "deposito recibido"]

    /// The currency figure inside a line ("MXN 319.00" in "Google MXN 319.00").
    private static func amountPattern(in line: String) -> String? {
        let regex = try? NSRegularExpression(pattern:
            // Digits may be grouped with spaces ("MXN 1 234,56"): a space counts only before a
            // group of exactly three.
            #"[-−]?(?:[A-Z]{1,2}\$|\b[A-Z]{3}\b|[$€£¥₱₩₹])\s?[-−]?\d(?:[\d.,]| (?=\d{3}(?!\d)))*|[-−]?\d(?:[\d.,]| (?=\d{3}(?!\d)))*\s?(?:[$€£¥₱₩₹]|\b[A-Z]{3}\b)"#)
        guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range, in: line) else { return nil }
        return String(line[range])
    }
}
