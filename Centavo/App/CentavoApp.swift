import SwiftData
import SwiftUI

@main
struct CentavoApp: App {
    var body: some Scene {
        WindowGroup {
            switch Store.opened {
            case .success(let container):
                ExpenseListView().modelContainer(container)
            case .failure:
                StoreErrorView()
            }
        }
    }
}
