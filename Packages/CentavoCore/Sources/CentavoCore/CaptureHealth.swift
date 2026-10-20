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
