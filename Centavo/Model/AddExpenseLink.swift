import Foundation
import UIKit

/// The app's side of `OpenAddExpenseIntent`: it opens `centavo://anotar`, the same link the
/// medium widget's «+» uses, and the main screen opens «Anotar gasto» (its `onOpenURL`).
enum AddExpenseLink {
    static let url = URL(string: "centavo://anotar")!

    /// How long to wait for the window when the intent woke the app from scratch.
    private static let patience = 30

    @MainActor static func install() {
        AddExpenseRoute.handler = {
            // The system opens the app before running the intent, but a cold start may still be
            // bringing its window up: a link opened before that is lost.
            var tries = 0
            while UIApplication.shared.applicationState != .active, tries < patience {
                tries += 1
                try? await Task.sleep(for: .milliseconds(100))
            }
            await UIApplication.shared.open(url)
        }
    }
}
