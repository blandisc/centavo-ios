import SwiftData
import SwiftUI
import UIKit

@main
struct CentavoApp: App {
    init() {
        TicketFont.register()
        if Store.syncsBudget { BudgetSync.start() }
        WidgetBridge.start()
        #if DEBUG
        // The UI tests wait for every animation to settle; without them each step is quicker.
        if ProcessInfo.processInfo.arguments.contains("-centavo-sin-animaciones") {
            UIView.setAnimationsEnabled(false)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch Store.opened {
                case .success(let container):
                    RootView().modelContainer(container)
                case .failure:
                    StoreErrorView()
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.brass)
        }
    }
}
