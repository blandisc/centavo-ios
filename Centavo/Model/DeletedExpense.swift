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
    var displayName: String? { row.displayName }

    func make() -> Expense? { try? Expense(backup: row) }
}
