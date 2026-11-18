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

    var body: some Scene {
        WindowGroup {
            Group {
                switch store {
                case .success(let container):
                    RootView().modelContainer(container)
                case .failure(let error):
                    StoreErrorView(trouble: StoreFiles.trouble(of: error), retry: retryStore)
                        .onOpenURL { url in
                            if url.scheme == "centavo" { pendingLink = url }
                        }
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
        if let link = pendingLink {
            pendingLink = nil
            // Once «Hoy» is up to take it (its `onOpenURL`), as `AddExpenseLink` opens it.
            Task { @MainActor in
                try? await Task.sleep(for: Self.screenUp)
                _ = await UIApplication.shared.open(link)
            }
        }
        return true
    }

    /// A beat for the main screen to replace the error before the link is opened again.
    private static let screenUp = Duration.milliseconds(400)
}
