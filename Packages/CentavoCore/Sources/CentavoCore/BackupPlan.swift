import Foundation

/// Whether tonight's file may take today's name (2026-11-02, second audit). A new iPhone with the
/// same folder, or one just installed before iCloud brought the files down, would otherwise write
/// an empty backup over the good one of the day, and the cleanup would then drop the month's.
public enum BackupPlan: Equatable, Sendable {
    /// Today's name, and the cleanup runs.
    case daily
    /// Another name the cleanup never touches, and no cleanup: today's file had more.
    case aside
    /// Nothing written and nothing trimmed: this phone has no expenses and the folder has backups.
    case newPhone

    /// What today's file (if there is one) holds.
    public enum Today: Equatable, Sendable {
        case none
        /// It's there and doesn't open (another password, damaged): never replaced.
        case unreadable
        case holds(expenses: Int, money: Bool)
    }

    public static func decide(expenses: Int, hasMoney: Bool, today: Today, folderHasBackups: Bool) -> BackupPlan {
        if expenses == 0 && folderHasBackups { return .newPhone }
        switch today {
        case .none: return .daily
        case .unreadable: return .aside
        case .holds(let count, let money):
            return expenses < count || (money && !hasMoney) ? .aside : .daily
        }
    }
}

/// Where a backup file is: only on this phone, still going up to iCloud, up, or failed to go up.
public enum BackupCloudState: Equatable, Sendable {
    case local, uploading, uploaded, failed
}

public enum BackupCloud {
    /// More than this going up is a file that isn't going to make it (iCloud full, no network).
    public static let stuckAfter: TimeInterval = 24 * 60 * 60

    /// The newest file failed to go up, or has been going up for over a day.
    public static func isStuck(_ state: BackupCloudState?, writtenAt: Date?, now: Date) -> Bool {
        switch state {
        case .failed: return true
        case .uploading:
            guard let writtenAt else { return false }
            return now.timeIntervalSince(writtenAt) > stuckAfter
        default: return false
        }
    }

    /// In iCloud, the old files are only trimmed once the newest before tonight's is up: a
    /// deletion goes up even when the new file can't, and iCloud would keep neither.
    public static func mayTrim(folderInCloud: Bool, previous: BackupCloudState?) -> Bool {
        !folderInCloud || previous == .uploaded
    }
}

