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
    public static func parse(_ text: String) -> WalletNotice? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let folded = lines.joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
        if received.contains(where: folded.contains) { return nil }
        let isRefund = refunds.contains(where: folded.contains)
        // The last line with money: a concept like "OXXO 123 MTY" can look like an amount too.
        guard let index = lines.lastIndex(where: { line in
            CaptureText.amount(in: line).map { $0.currencyMarker != nil } ?? false
        }), let amount = CaptureText.amount(in: lines[index]) else { return nil }

        // Read from the amount up, not from the top: the concept sits right above the amount
        // and the card above that. Atajos may add lines first (the app's name, «Wallet»), and
        // counting from the top then took the bank for the merchant (seen on the owner's iPhone).
        let clean: (String) -> String? = { line in
            let folded = line.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                      locale: Locale(identifier: "es_MX"))
            if appLabels.contains(folded) { return nil }
            return isRefund ? withoutRefundWord(line) : line
        }
        let before = lines[..<index].compactMap(clean)
        let after = lines[(index + 1)...].compactMap(clean)
        // The amount may share its line with the merchant ("Google MXN 319.00").
        let leftover = lines[index]
            .replacingOccurrences(of: amountPattern(in: lines[index]) ?? lines[index], with: "")
            .trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        let merchant: String?
        let card: String?
        if let own = clean(leftover), !own.isEmpty {
            merchant = own
            card = before.last
        } else if let concept = before.last {
            merchant = concept
            card = before.dropLast().last
        } else {
            merchant = after.first
            card = nil
        }
        let figure = amountPattern(in: lines[index]) ?? lines[index]
        guard isRefund else {
            return WalletNotice(amount: amount, amountText: figure, merchant: merchant, card: card)
        }
        let negative = ParsedAmount(value: -amount.value.magnitude, currencyMarker: amount.currencyMarker)
        return WalletNotice(amount: negative, amountText: figure.hasPrefix("-") ? figure : "-" + figure,
                            merchant: merchant, card: card)
    }

    /// A notice `parse` could not read (a bank or format it doesn't know), as the on-device
    /// model read it. Trusted only when the amount is literally in the notice with a real
    /// currency, the merchant is too, and it is not money coming in.
    public static func rescue(_ text: String, merchant: String?, card: String?,
                              amountFragment: String) -> WalletNotice? {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
        if received.contains(where: folded.contains) { return nil }
        let figure = amountFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !figure.isEmpty, text.contains(figure),
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
