import SwiftData
import SwiftUI

@main
struct CentavoApp: App {
    init() {
        TicketFont.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch Store.opened {
                case .success(let container):
                    ExpenseListView().modelContainer(container)
                case .failure:
                    StoreErrorView()
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.brass)
        }
    }
}
