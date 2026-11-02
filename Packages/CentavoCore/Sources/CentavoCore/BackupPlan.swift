import Foundation

/// Whether tonight's file may take today's name (2026-11-02, second audit). A new iPhone with the
/// same folder, or one just installed before iCloud brought the files down, would otherwise write
/// an empty backup over the good one of the day, and the cleanup would then drop the month's.
public enum BackupPlan: Equatable, Sendable {
    /// Today's name, and the cleanup runs.
    case daily
    /// Today's name, but nothing old is trimmed: the newest backup couldn't be read to compare
    /// (another password, or still only in iCloud).
    case dailyKeepingOld
    /// Another name the cleanup never touches, and no cleanup: the file of the day, or the newest
    /// backup, had much more.
    case aside
    /// Nothing written and nothing trimmed: this phone has nothing and the folder has backups.
    case newPhone

    /// What a backup file holds: today's (if there is one) or the newest daily one.
    public enum Today: Equatable, Sendable {
        case none
        /// It's there and doesn't open (another password, damaged, not downloaded).
        case unreadable
        /// `money`: «Mi dinero» with something in it (`BackupMoney.hasContent`).
        case holds(expenses: Int, money: Bool)
    }

    /// Fewer than this many, and fewer than half, is not a few deleted: a new iPhone, or one
    /// before iCloud brought its data (2026-11-02, independent review).
    public static let muchFewer = 5

    /// - Parameters:
    ///   - hasMoney: «Mi dinero» with something in it, on this phone.
    ///   - today: the file with today's name.
    ///   - newest: the newest daily file in the folder (maybe today's): a new iPhone with a few
    ///     expenses must not become «the newest» and, thirty days later, the only one.
    public static func decide(expenses: Int, hasMoney: Bool, today: Today, newest: Today,
                              folderHasBackups: Bool) -> BackupPlan {
        // Nothing at all here, and backups there: restore first. Someone who only uses «Mi
        // dinero», or emptied everything after an empty backup, still backs up.
        if expenses == 0 && !hasMoney && folderHasBackups && newest != .holds(expenses: 0, money: false) {
            return .newPhone
        }
        switch today {
        case .none: break
        case .unreadable: return .aside
        case .holds(let count, let money):
            if expenses < count || (money && !hasMoney) { return .aside }
        }
        switch newest {
        case .none: return .daily
        case .unreadable: return .dailyKeepingOld
        case .holds(let count, let money):
            let fewer = count - expenses >= muchFewer && expenses * 2 < count
            return fewer || (money && !hasMoney) ? .aside : .daily
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

