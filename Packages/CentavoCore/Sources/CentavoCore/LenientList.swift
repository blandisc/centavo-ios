import Foundation

/// A list kept as JSON text (fixed expenses to come, categories, cards) read one item at a
/// time (2026-11-02): one item that doesn't read (written by a newer version, or damaged)
/// used to empty the whole list, and the next save wrote the empty list over everything.
/// Now the rest reads, and the item that didn't is written back as it was.
public enum LenientList {
    /// The items that read, in order, and the raw JSON of the ones that didn't.
    public static func decode<T: Decodable>(_ type: T.Type, from stored: String) -> (items: [T], unread: [Data]) {
        guard let data = stored.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any]
        else { return ([], []) }
        var items: [T] = []
        var unread: [Data] = []
        for element in raw {
            guard let one = try? JSONSerialization.data(withJSONObject: element, options: [.fragmentsAllowed]) else { continue }
            if let item = try? JSONDecoder().decode(T.self, from: one) {
                items.append(item)
            } else {
                unread.append(one)
            }
        }
        return (items, unread)
    }

    /// The items as JSON text, with the ones `stored` had and couldn't read kept at the end.
    public static func encode<T: Codable>(_ items: [T], keepingUnreadFrom stored: String = "") -> String {
        guard let data = try? JSONEncoder().encode(items) else { return stored }
        let unread = decode(T.self, from: stored).unread
        guard !unread.isEmpty, var list = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return String(decoding: data, as: UTF8.self)
        }
        for one in unread {
            if let element = try? JSONSerialization.jsonObject(with: one, options: [.fragmentsAllowed]) { list.append(element) }
        }
        guard let merged = try? JSONSerialization.data(withJSONObject: list) else { return stored }
        return String(decoding: merged, as: UTF8.self)
    }
}
