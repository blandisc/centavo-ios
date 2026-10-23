import CentavoCore
import Foundation
import WidgetKit

/// One moment of the month, as the app last left it (`WidgetSnapshot`).
struct DayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    /// The month at this entry's moment: at midnight, today's spending becomes yesterday's.
    var month: WidgetSnapshot? { snapshot?.month(at: date) }
    var pace: BudgetPace? { snapshot?.pace(at: date) }

    /// The sample in the widget gallery: the numbers of the design proposals.
    static let sample = DayEntry(date: .now, snapshot: WidgetSnapshot(
        budget: 12_000, isoCode: "MXN", label: "$", takenAt: .now, spent: 8_140, spentToday: 84,
        reserved: 1_200, slices: [.init(name: "Comida", amount: 2_450), .init(name: "Despensa", amount: 1_980),
                                  .init(name: "Transporte", amount: 1_320),
                                  .init(name: nil, amount: 2_390, isRest: true)]))
}

/// Reads what the app wrote to the App Group. The app reloads the timelines after every
/// change; each timeline also carries the next two midnights, so «Hoy puedes gastar» starts
/// the new day on its own.
struct DayProvider: TimelineProvider {
    /// The same App Group as `WidgetBridge.appGroup` in the app.
    static let appGroup = "group.com.blandisc.centavo"

    /// DEBUG only: the moment the app's sample asks the widgets to pretend it is.
    private var now: Date {
        #if DEBUG
        if let date = UserDefaults(suiteName: Self.appGroup)?.object(forKey: "widgetDemoDate") as? Date { return date }
        #endif
        return .now
    }

    private var saved: WidgetSnapshot? {
        WidgetSnapshot.decode(UserDefaults(suiteName: Self.appGroup)?.data(forKey: WidgetSnapshot.key))
    }

    func placeholder(in context: Context) -> DayEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(context.isPreview && saved == nil ? .sample : DayEntry(date: now, snapshot: saved))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let snapshot = saved
        #if DEBUG
        if UserDefaults(suiteName: Self.appGroup)?.object(forKey: "widgetDemoDate") != nil {
            completion(Timeline(entries: [DayEntry(date: now, snapshot: snapshot)], policy: .never))
            return
        }
        #endif
        let calendar = Calendar.current
        let now = self.now
        let today = calendar.startOfDay(for: now)
        let midnights = (1...2).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let entries = [DayEntry(date: now, snapshot: snapshot)] + midnights.map { DayEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
