import SwiftData
import SwiftUI

@main
struct CentavoApp: App {
    var body: some Scene {
        WindowGroup {
            ExpenseListView()
        }
        .modelContainer(Store.container)
    }
}
