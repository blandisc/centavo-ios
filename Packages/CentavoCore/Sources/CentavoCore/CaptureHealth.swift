import Foundation

/// Whether the Wallet automation looks alive, judged by its last payment.
///
/// An automation that broke (iOS updated, the app's signature expired, the bank stopped
/// firing it) fails in silence. Saying when the last payment arrived makes that visible.
public enum CaptureHealth: Equatable, Sendable {
    /// No payment has ever come from Wallet: the automation was never set up.
    case never
    /// The last one came recently.
    case recent(Date)
    /// Nothing for `days` days, long enough to be worth a look.
    case quiet(days: Int)

    /// The last payment came recently: nothing to look at.
    public var isRecent: Bool {
        if case .recent = self { return true }
        return false
    }

    /// Days without a payment before it is worth a look. Two quiet days are normal.
    public static let quietAfterDays = 3

    public init(lastCapture: Date?, now: Date, calendar: Calendar = .current) {
        guard let lastCapture else { self = .never; return }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastCapture),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        self = days >= Self.quietAfterDays ? .quiet(days: days) : .recent(lastCapture)
    }
}

/// What the setup guide can say about the automation: only a payment that arrived on this
/// iPhone after the guide was opened proves it (2026-11-11, the map of states).
///
/// A payment from before the guide was opened, or one that came inside a restored backup or
/// from another device, says nothing about the automation someone came here to set up or fix.
public enum CaptureProof: Equatable, Sendable {
    /// A payment arrived here since the guide was opened: «Ya funciona».
    case working(arrived: Date)
    /// Still waiting; `last` is the newest payment known, from before, to say when it was.
    case waiting(last: Date?)

    public var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    /// How long one setup lasts: opening the guide again within it carries on, so a payment
    /// that arrived while the person was in Atajos or at the store still counts.
    public static let sessionLength: TimeInterval = 24 * 3600
    /// A proof older than this, on coming back to the guide, is old news: whoever returns
    /// came to check again.
    public static let freshProof: TimeInterval = 3600

    /// - Parameters:
    ///   - sessionStart: when the guide was opened for this setup (`sessionStart(previous:arrivedHere:now:)`).
    ///   - arrivedHere: the last payment the automation delivered on this iPhone; never one
    ///     that came in a backup or from iCloud.
    ///   - lastKnown: the newest Wallet payment among the expenses, wherever it came from.
    public init(sessionStart: Date?, arrivedHere: Date?, lastKnown: Date?, now: Date) {
        if let sessionStart, let arrivedHere,
           sessionStart <= now, now.timeIntervalSince(sessionStart) < Self.sessionLength,
           arrivedHere > sessionStart, arrivedHere <= now {
            self = .working(arrived: arrivedHere)
        } else {
            self = .waiting(last: [arrivedHere, lastKnown].compactMap { $0 }.filter { $0 <= now }.max())
        }
    }

    /// When this setup started, decided each time the guide opens: the same one while it is
    /// under a day old and has no old proof; otherwise it starts now.
    public static func sessionStart(previous: Date?, arrivedHere: Date?, now: Date) -> Date {
        guard let previous, previous <= now, now.timeIntervalSince(previous) < sessionLength else { return now }
        if let arrivedHere, arrivedHere > previous, now.timeIntervalSince(arrivedHere) >= freshProof { return now }
        return previous
    }
}
