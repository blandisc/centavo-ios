import SwiftData
import SwiftUI
import UIKit

@main
struct CentavoApp: App {
    init() {
        TicketFont.register()
        TicketFont.dressSegmentedControls()
        if Store.syncsBudget { BudgetSync.start() }
        WidgetBridge.start()
        #if DEBUG
        // The UI tests wait for every animation to settle; without them each step is quicker.
        if ProcessInfo.processInfo.arguments.contains("-centavo-sin-animaciones") {
            UIView.setAnimationsEnabled(false)
        }
        #endif
    }

    /// What `Store.opened` said, kept here so «Intentar de nuevo» can swap the error for the app.
    @State private var store = Store.opened
    /// A widget's «+» or the control's «Anotar gasto» that came while the store was down: kept,
    /// and opened again once «Intentar de nuevo» brings the app back (2026-11-18).
    @State private var pendingLink: URL?
    /// When it came: one older than `linkLasts` is let go, not opened minutes later out of the
    /// blue (2026-11-19).
    @State private var pendingLinkAt: Date?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch store {
                case .success(let container):
                    RootView().modelContainer(container)
                case .failure(let error):
                    StoreErrorView(trouble: StoreFiles.trouble(of: error), retry: retryStore,
                                   opensLink: pendingLink != nil)
                        .onOpenURL { url in
                            guard url.scheme == "centavo" else { return }
                            pendingLink = url
                            pendingLinkAt = AppClock.now
                        }
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.brass)
            .onChange(of: scenePhase, initial: true) { _, phase in retryAfterIntent(phase) }
        }
    }

    /// A store that failed for an intent with the phone locked (`Store.takeFailedOutOfSight`) is
    /// opened again when the app comes to the front (2026-11-18): the data was fine, and the
    /// error screen offered to save a copy of it. Only once per such failure; one that fails
    /// again with the phone unlocked keeps the screen and its «Intentar de nuevo».
    private func retryAfterIntent(_ phase: ScenePhase) {
        guard phase == .active, case .failure = store, Store.takeFailedOutOfSight() else { return }
        _ = retryStore()
    }

    /// Opens the store again without closing the app (2026-11-11). `true` when it opened: the
    /// widgets, which had nothing to read at launch, are brought up to date.
    private func retryStore() -> Bool {
        store = Store.retry()
        guard case .success = store else { return false }
        WidgetBridge.refresh()
        let fresh = freshLink
        pendingLink = nil
        pendingLinkAt = nil
        if let link = fresh {
            // Once «Hoy» is up to take it (its `onOpenURL`), as `AddExpenseLink` opens it.
            Task { @MainActor in
                try? await Task.sleep(for: Self.screenUp)
                _ = await UIApplication.shared.open(link)
            }
        }
        return true
    }

    /// The link kept while the store was down, if it is recent enough to still be wanted.
    private var freshLink: URL? {
        guard let pendingLink, let pendingLinkAt,
              AppClock.now.timeIntervalSince(pendingLinkAt) <= Self.linkLasts else { return nil }
        return pendingLink
    }

    /// How long a «+» kept while the store was down is still opened: a few minutes.
    private static let linkLasts: TimeInterval = 5 * 60

    /// A beat for the main screen to replace the error before the link is opened again.
    private static let screenUp = Duration.milliseconds(400)
}
