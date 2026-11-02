import Foundation

/// The app's «now» (2026-11-02). Always the real clock, except in the demo the screen tests
/// open (DEBUG builds only): on the first days of a month its sample month would have no days
/// yet, so the demo lives on the 20th of the current month, with time still running.
enum AppClock {
    static var now: Date { Date.now.addingTimeInterval(offset) }

    /// How far the demo's day is from the real one; 0 outside the demo.
    static let offset: TimeInterval = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-centavo-demo") || arguments.contains("-centavo-demo-large") else { return .zero }
        let calendar = Calendar.current
        let real = Date.now
        guard calendar.component(.day, from: real) < demoDay,
              let later = calendar.date(bySetting: .day, value: demoDay, of: real) else { return .zero }
        // `bySetting` may jump to a later month; the same month, same time of day, is wanted.
        var parts = calendar.dateComponents([.year, .month, .hour, .minute, .second], from: real)
        parts.day = demoDay
        let target = calendar.date(from: parts) ?? later
        return target.timeIntervalSince(real)
        #else
        return .zero
        #endif
    }()

    /// «hace 1 h», «ayer»: measured against this clock, not the system's.
    static func relative(_ date: Date, abbreviated: Bool = false, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = abbreviated ? .abbreviated : .full
        formatter.locale = locale
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func isToday(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    /// The demo's day of the month: late enough for every sample day (the 12th is the latest).
    static let demoDay = 20
}
