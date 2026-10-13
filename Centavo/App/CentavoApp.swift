import SwiftData
import SwiftUI

@main
struct CentavoApp: App {
    init() {
        TicketFont.register()
    }

    var body: some Scene {
        WindowGroup {
            ExpenseListView()
                .preferredColorScheme(.dark)
                .tint(Theme.brass)
        }
        .modelContainer(Store.container)
    }
}
