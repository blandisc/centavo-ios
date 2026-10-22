import Foundation

/// A Wallet notice the capture couldn't read that looks like a wrong wiring in Atajos: one
/// line and no amount, as when «Notificación» is set to «Subtítulo» and only the merchant
/// arrives (seen on the owner's iPhone, 2026-10-21). Kept so the main screen can say so
/// instead of the payment vanishing. A pass or a promotion comes as title and body, so it
/// is not kept.
enum UnreadNotice {
    static let textKey = "unreadWalletNotice"
    static let dateKey = "unreadWalletNoticeDate"

    static func note(_ text: String, now: Date = .now, defaults: UserDefaults = .standard) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count == 1, !lines[0].contains(where: \.isNumber) else { return }
        defaults.set(String(lines[0].prefix(80)), forKey: textKey)
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: dateKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: textKey)
        defaults.removeObject(forKey: dateKey)
    }
}
