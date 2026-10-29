import CentavoCore
import Foundation
import WidgetKit
import AppIntents

/// One moment of the month, as the app last left it (`WidgetSnapshot`).
struct DayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// What the medium «Hoy puedes gastar» shows (chosen in «Editar widget»); the rest ignore it.
    var show: HoyMediumLayout = .pace

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

/// Reads what the app left (`WidgetSnapshotStore`: App Group or shared Keychain). The app reloads the timelines after every
/// change; each timeline also carries the next two midnights, so «Hoy puedes gastar» starts
/// the new day on its own.
struct DayProvider: TimelineProvider {
    /// The same App Group as `WidgetBridge.appGroup` in the app (the snapshot may come from the Keychain instead).
    static let appGroup = WidgetSnapshotStore.appGroup

    /// DEBUG only: the moment the app's sample asks the widgets to pretend it is.
    private var now: Date {
        #if DEBUG
        if let date = UserDefaults(suiteName: Self.appGroup)?.object(forKey: "widgetDemoDate") as? Date { return date }
        #endif
        return .now
    }

    private var saved: WidgetSnapshot? {
        WidgetSnapshot.decode(WidgetSnapshotStore().read())
    }

    func placeholder(in context: Context) -> DayEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(snapshot(isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        completion(timeline())
    }

    func snapshot(isPreview: Bool) -> DayEntry {
        isPreview && saved == nil ? .sample : DayEntry(date: now, snapshot: saved)
    }

    func timeline() -> Timeline<DayEntry> {
        let snapshot = saved
        #if DEBUG
        if UserDefaults(suiteName: Self.appGroup)?.object(forKey: "widgetDemoDate") != nil {
            return Timeline(entries: [DayEntry(date: now, snapshot: snapshot)], policy: .never)
        }
        #endif
        let calendar = Calendar.current
        let now = self.now
        let today = calendar.startOfDay(for: now)
        let midnights = (1...2).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        // The moment it turns a day old, so «Actualizado hace 1 día» shows up on time.
        let last = midnights.last ?? now
        let stale = [snapshot?.takenAt.addingTimeInterval(WidgetSnapshot.freshFor)]
            .compactMap { $0 }
            .filter { $0 > now && $0 < last }
        let moments = (midnights + stale).sorted()
        let entries = [DayEntry(date: now, snapshot: snapshot)] + moments.map { DayEntry(date: $0, snapshot: snapshot) }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

/// «Hoy puedes gastar» (small and medium): the same timeline as `DayProvider`, carrying the
/// layout picked in «Editar widget» for the medium one.
struct HoyProvider: AppIntentTimelineProvider {
    private let base = DayProvider()

    func placeholder(in context: Context) -> DayEntry { .sample }

    func snapshot(for configuration: HoyConfiguration, in context: Context) async -> DayEntry {
        base.snapshot(isPreview: context.isPreview).showing(configuration.show)
    }

    func timeline(for configuration: HoyConfiguration, in context: Context) async -> Timeline<DayEntry> {
        let timeline = base.timeline()
        return Timeline(entries: timeline.entries.map { $0.showing(configuration.show) }, policy: timeline.policy)
    }
}

extension DayEntry {
    func showing(_ layout: HoyMediumLayout) -> DayEntry {
        var entry = self
        entry.show = layout
        return entry
    }
}
