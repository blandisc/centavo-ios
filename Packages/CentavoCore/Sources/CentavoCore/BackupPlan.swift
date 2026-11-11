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

    /// Why tonight's file can't take today's name, or `nil` when it can. The file of the day is
    /// looked at first: it's the one that would be written over.
    public static func aside(expenses: Int, hasMoney: Bool, today: Today, newest: Today) -> BackupAside? {
        switch today {
        case .none: break
        case .unreadable: return .unreadable
        case .holds(let count, let money):
            if expenses < count { return .fewer(than: .today, here: expenses, there: count) }
            if money && !hasMoney { return .noMoney(than: .today) }
        }
        guard case .holds(let count, let money) = newest else { return nil }
        if count - expenses >= muchFewer && expenses * 2 < count {
            return .fewer(than: .newest, here: expenses, there: count)
        }
        return money && !hasMoney ? .noMoney(than: .newest) : nil
    }

    /// - Parameters:
    ///   - hasMoney: «Mi dinero» with something in it, on this phone.
    ///   - today: the file with today's name.
    ///   - newest: the newest daily file in the folder (maybe today's): a new iPhone with a few
    ///     expenses must not become «the newest» and, thirty days later, the only one.
    ///   - trustingThisPhone: the person said «Este iPhone es el bueno» (2026-11-11): what would
    ///     go apart takes today's name, and that night nothing old is trimmed. A phone with
    ///     nothing at all still doesn't back up over a folder with backups.
    public static func decide(expenses: Int, hasMoney: Bool, today: Today, newest: Today,
                              folderHasBackups: Bool, trustingThisPhone: Bool = false) -> BackupPlan {
        // Nothing at all here, and backups there: restore first. Someone who only uses «Mi
        // dinero», or emptied everything after an empty backup, still backs up.
        if expenses == 0 && !hasMoney && folderHasBackups && newest != .holds(expenses: 0, money: false) {
            return .newPhone
        }
        if aside(expenses: expenses, hasMoney: hasMoney, today: today, newest: newest) != nil {
            return trustingThisPhone ? .dailyKeepingOld : .aside
        }
        return newest == .unreadable ? .dailyKeepingOld : .daily
    }
}

/// Why a backup was written apart (`BackupPlan.aside`), with what the screen needs to say it.
public enum BackupAside: Equatable, Sendable {
    /// Which file this phone was compared with.
    public enum Source: String, Equatable, Sendable, Codable {
        case today, newest
    }

    /// This phone has fewer expenses than that file.
    case fewer(than: Source, here: Int, there: Int)
    /// That file has «Mi dinero» and this phone doesn't.
    case noMoney(than: Source)
    /// The file of the day is there and doesn't open (another password, damaged, not downloaded).
    case unreadable

    public var source: Source {
        switch self {
        case .fewer(let source, _, _), .noMoney(let source): return source
        case .unreadable: return .today
        }
    }
}

/// The last backup went apart: kept on this phone (never in the backup itself) until a daily
/// file is written again, so «Respaldo diario» and «Hoy» can say it (2026-11-11).
public struct BackupAsideNote: Equatable, Sendable, Codable {
    public enum Kind: String, Equatable, Sendable, Codable {
        case fewer = "menos", noMoney = "sin-dinero", unreadable = "ilegible"
    }

    public var kind: Kind
    /// Expenses on this phone and in the file it was compared with (only for `fewer`).
    public var here: Int?
    public var there: Int?
    /// The day in the name of the file it was compared with («2026-11-10»).
    public var day: String?
    /// The name the apart file was written with.
    public var file: String

    public init(_ aside: BackupAside, comparedWith name: String?, file: String) {
        switch aside {
        case .fewer(_, let here, let there):
            kind = .fewer
            self.here = here
            self.there = there
        case .noMoney: kind = .noMoney
        case .unreadable: kind = .unreadable
        }
        day = name.flatMap(BackupRetention.day(of:))
        self.file = file
    }

    /// As `UserDefaults` keeps it. `nil` only if it can't be written (it never happens).
    public var stored: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// `nil` for anything that isn't a note: then nothing is said, never a guess.
    public init?(stored: String?) {
        guard let data = stored?.data(using: .utf8),
              let note = try? JSONDecoder().decode(BackupAsideNote.self, from: data) else { return nil }
        self = note
    }

    /// «el respaldo del 10 nov», with the year when it isn't this one; «el respaldo anterior»
    /// when the day isn't known.
    public func otherBackup(now: Date, timeZone: TimeZone = .current) -> String {
        let pieces = (day ?? "").split(separator: "-").compactMap { Int($0) }
        var calendar = BackupRetention.calendar(in: timeZone)
        calendar.locale = Locale(identifier: "es_MX")
        guard pieces.count == 3,
              let date = calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2], hour: 12)),
              calendar.component(.day, from: date) == pieces[2] else { return "el respaldo anterior" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.timeZone = timeZone
        formatter.dateFormat = pieces[0] == calendar.component(.year, from: now) ? "d MMM" : "d MMM yyyy"
        // «nov.» in some systems: the dot would read as the end of the sentence.
        return "el respaldo del " + formatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    /// What «Respaldo diario» says under «Respaldar ahora», in plain words.
    public func message(now: Date, timeZone: TimeZone = .current) -> String {
        let other = otherBackup(now: now, timeZone: timeZone)
        switch kind {
        case .fewer:
            guard let here, let there else {
                return "Tu último respaldo se guardó aparte: este iPhone tiene menos gastos que \(other)."
            }
            return "Tu último respaldo se guardó aparte: este iPhone tiene menos gastos (\(here)) que \(other) (\(there))."
        case .noMoney:
            return "Tu último respaldo se guardó aparte: este iPhone no tiene «Mi dinero» y \(other) sí."
        case .unreadable:
            return "Tu último respaldo se guardó aparte: \(other) no se pudo abrir para compararlo. Puede tener otra contraseña o no haber bajado de iCloud."
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

