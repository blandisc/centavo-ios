import CentavoCore
import Foundation

/// Everything needed to bring a deleted expense back exactly as it was («Deshacer»). Kept as
/// the backup's row, so a field added to `Expense` later comes back too without anyone
/// remembering it here (the place, the Wallet notice and the mark of a repeat once didn't).
struct DeletedExpense: Identifiable {
    let id = UUID()
    let row: BackupExpense

    init(_ expense: Expense) { row = expense.backedUp }

    var merchant: String { row.merchant }
    /// The name «Deshacer» says: the one shown, never the stored «Sin comercio» (2026-11-18:
    /// stored in Spanish, shown translated), which read «You deleted Sin comercio» in English.
    var displayName: String? { row.displayName ?? Expense.shownMerchant(row.merchant) }

    func make() -> Expense? { try? Expense(backup: row) }
}
