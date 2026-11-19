import CentavoCore
import Foundation

/// Where the new expense's sheet is kept while the app is away (`ExpenseDraft`, 2026-11-19):
/// this iPhone's `UserDefaults`, under a `respaldo.` key, which the backup leaves out
/// (`DailyBackup`), and never iCloud. Only what was being typed: a saved expense is in the store.
enum ExpenseDraftStore {
    static let key = "respaldo.esteIPhone.borradorGasto"

    /// This launch already looked for a draft to open the sheet with: once per launch, so a
    /// «Hoy» drawn again does not open it a second time.
    @MainActor static var checkedThisLaunch = false

    static var saved: ExpenseDraft? {
        ExpenseDraft.decode(UserDefaults.standard.string(forKey: key))
    }

    static func keep(_ draft: ExpenseDraft) {
        guard let text = draft.encoded else { return }
        UserDefaults.standard.set(text, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
