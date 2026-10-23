import CentavoCore
import Foundation
import SwiftData
import WidgetKit

/// Keeps the widgets up to date: after every change the app writes the month's sums
/// (`WidgetSnapshot`) to the App Group it shares with them and asks WidgetKit to redraw.
/// The widgets never open the store: they only read this.
enum WidgetBridge {
    /// `group.` + the app's bundle identifier. Free accounts can sign App Groups (CloudKit
    /// they cannot), so the widgets work with the free account too.
    static let appGroup = "group.com.blandisc.centavo"

    static var shared: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// DEBUG only: the moment the widgets pretend it is, to show «día 1» on any day.
    static let demoDateKey = "widgetDemoDate"

    @MainActor private static var pending: Task<Void, Never>?

    /// Called once at launch: every save, from a screen or from Siri and Atajos (which run in
    /// the app's process), refreshes the widgets.
    @MainActor static func start() {
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            // Later, never inside the save: a save can come while the store is still opening
            // (the demo seeds it there), and reading it then would open it twice. Several
            // saves in a row make one refresh.
            pending?.cancel()
            pending = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                refresh()
            }
        }
    }

    /// Writes this month as it stands now and reloads the widgets.
    @MainActor static func refresh(now: Date = .now) {
        #if DEBUG
        // `-centavo-widget-estado …`: a fixed month to look at the widgets with.
        if let sample = DemoData.widgetSample {
            shared?.set(sample.snapshot.encoded(), forKey: WidgetSnapshot.key)
            shared?.set(sample.date, forKey: demoDateKey)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        shared?.removeObject(forKey: demoDateKey)
        #endif
        guard let container = try? Store.container else { return }
        let context = container.mainContext
        let budget = BudgetStore.amount(from: UserDefaults.standard.string(forKey: BudgetStore.key) ?? "")
        let interval = Calendar.current.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
        let start = interval.start, end = interval.end
        guard let rows = try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= start && $0.date < end })),
              let originals = try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.repeatsMonthly == true }))
        else { return }
        let snapshot = TodayBudget.snapshot(budget: budget, rows: rows, originals: originals, plans: FixedPlan.saved,
                                            primary: CurrencyPreference.current, month: now, now: now)
        guard let data = snapshot.encoded(), data != shared?.data(forKey: WidgetSnapshot.key) else { return }
        shared?.set(data, forKey: WidgetSnapshot.key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
