import Foundation

/// The currency someone's money is actually in, read from their payments.
///
/// Wallet writes the currency of every payment ("MXN 175.00"), so the payments say which
/// currency the month should add up in better than the phone's region does.
public enum CurrencySuggestion {
    /// The offered currency most of these payments are in, or `nil` when there are none or
    /// none of them is a clear majority. A bare "$" says nothing: it follows `primary`.
    public static func dominant(markers: [String?], primary: String, offered: [String]) -> String? {
        var counts: [String: Int] = [:]
        for marker in markers {
            guard let marker, !marker.trimmingCharacters(in: .whitespaces).isEmpty,
                  marker.trimmingCharacters(in: .whitespaces) != "$",
                  let code = CurrencyResolver.isoCode(for: marker, primary: primary),
                  offered.contains(code) else { continue }
            counts[code, default: 0] += 1
        }
        let total = markers.count
        guard let (code, count) = counts.max(by: { $0.value < $1.value }), count * 2 > total else { return nil }
        return code
    }

    /// The other currency to offer as the main one: most of the payments are in it and it is
    /// not the main one already.
    public static func switchTo(markers: [String?], primary: String, offered: [String]) -> String? {
        guard let code = dominant(markers: markers, primary: primary, offered: offered),
              code != primary else { return nil }
        return code
    }
}
