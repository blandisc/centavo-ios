import Foundation

/// The welcome's «¿Ya usabas Al día? Restaurar un respaldo» (2026-11-19): the welcome counts as
/// done only if a restore worked after it was left for Ajustes › Respaldo. Cancelled or failed,
/// it comes back on the next launch.
public enum WelcomeRestore {
    /// `since`: when the welcome was left to restore. `restoredAt`: the last restore that
    /// worked (`DailyBackup.restoredKey`), if any.
    public static func counts(since: Date, restoredAt: Date?) -> Bool {
        guard let restoredAt else { return false }
        return restoredAt >= since
    }
}
