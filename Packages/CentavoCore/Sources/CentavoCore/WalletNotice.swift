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
    /// Wallet notice that is not a charge.
    public static func parse(_ text: String) -> WalletNotice? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let index = lines.firstIndex(where: { line in
            CaptureText.amount(in: line).map { $0.currencyMarker != nil } ?? false
        }), let amount = CaptureText.amount(in: lines[index]) else { return nil }

        var others = lines
        others.remove(at: index)
        // The amount may share its line with the merchant ("Google MXN 319.00").
        let leftover = lines[index]
            .replacingOccurrences(of: amountPattern(in: lines[index]) ?? lines[index], with: "")
            .trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        if !leftover.isEmpty { others.insert(leftover, at: index) }

        let card = others.count >= 2 ? others.first : nil
        let merchant = others.count >= 2 ? others[1] : others.first
        return WalletNotice(amount: amount, amountText: amountPattern(in: lines[index]) ?? lines[index],
                            merchant: merchant, card: card)
    }

    /// The currency figure inside a line ("MXN 319.00" in "Google MXN 319.00").
    private static func amountPattern(in line: String) -> String? {
        let regex = try? NSRegularExpression(pattern:
            #"[-−]?(?:[A-Z]{1,2}\$|\b[A-Z]{3}\b|[$€£¥₱₩₹])\s?[-−]?\d[\d.,]*|[-−]?\d[\d.,]*\s?(?:[$€£¥₱₩₹]|\b[A-Z]{3}\b)"#)
        guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range, in: line) else { return nil }
        return String(line[range])
    }
}
