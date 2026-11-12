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

    var body: some Scene {
        WindowGroup {
            Group {
                switch store {
                case .success(let container):
                    RootView().modelContainer(container)
                case .failure(let error):
                    StoreErrorView(trouble: StoreFiles.trouble(of: error), retry: retryStore)
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.brass)
        }
    }

    /// Opens the store again without closing the app (2026-11-11). `true` when it opened: the
    /// widgets, which had nothing to read at launch, are brought up to date.
    private func retryStore() -> Bool {
        store = Store.retry()
        guard case .success = store else { return false }
        WidgetBridge.refresh()
        return true
    }
}
