import Foundation

/// What has to happen before a restore replaces everything on this phone (2026-11-11, map of
/// states): what there is now is copied first to a place the person can open, or nothing is
/// replaced. The copy used to fall back to the app's own Documents, which Archivos doesn't show.
public enum BackupSafetyPlan: Equatable, Sendable {
    /// No expenses, nothing in «Mi dinero» and nothing the person set up (budget, their own
    /// categories and payment methods, fixed expenses to come, rules): there's nothing to copy,
    /// the restore goes ahead.
    case nothingToCopy
    /// The copy goes to the backup's folder.
    case copyToFolder
    /// There's something to keep and no folder to put it in: the person picks one, or the
    /// restore doesn't happen.
    case askWhere

    /// `configured`: the person set something up on this phone (`isConfigured`). A restore
    /// replaces the settings too, so a phone with a budget and no expenses isn't empty
    /// (independent review, 2026-11-11).
    public static func decide(expenses: Int, hasMoney: Bool, configured: Bool, folderUsable: Bool) -> BackupSafetyPlan {
        guard expenses > 0 || hasMoney || configured else { return .nothingToCopy }
        return folderUsable ? .copyToFolder : .askWhere
    }

    /// Whether any of `keys` (the settings a person makes by hand: the app passes the budget,
    /// the fixed expenses to come, the catalog and the rules) holds something in `settings`,
    /// which is what travels in a backup. An empty text, an empty list («[]», «{}») and a zero
    /// are nothing; anything else is something, so a doubt always means a copy.
    public static func isConfigured(_ settings: [String: BackupSetting], keys: [String]) -> Bool {
        keys.contains { key in
            switch settings[key] {
            case nil: return false
            case .text(let text):
                let bare = text.filter { !$0.isWhitespace }
                return !["", "[]", "{}", "0", "null"].contains(bare)
            case .flag(let flag): return flag
            case .whole(let whole): return whole != 0
            case .number(let number): return number != 0
            case .date: return true
            }
        }
    }
}

/// A copy taken before a restore («al-dia-antes-de-restaurar-2026-11-12T214000.aldia»), as the
/// screen lists the ones left inside the app by earlier restores.
public struct BackupSafetyCopy: Equatable, Sendable, Identifiable {
    public var name: String
    /// When it was taken, read from its name.
    public var date: Date

    public var id: String { name }

    public init(name: String, date: Date) {
        self.name = name
        self.date = date
    }

    /// «12 nov, 9:40 p.m.»; with the year when it isn't this one.
    public func title(now: Date, timeZone: TimeZone = .current) -> String {
        let calendar = BackupRetention.calendar(in: timeZone)
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = sameYear ? "d MMM, h:mm a" : "d MMM y, h:mm a"
        return formatter.string(from: date)
    }

    /// The copies among a folder's file names, newest first. Any other file is left out.
    public static func list(_ names: [String], timeZone: TimeZone = .current) -> [BackupSafetyCopy] {
        names.compactMap { name in
            BackupRetention.safetyDate(of: name, timeZone: timeZone).map { BackupSafetyCopy(name: name, date: $0) }
        }
        .sorted { ($0.date, $0.name) > ($1.date, $1.name) }
    }
}

extension BackupRetention {
    public static let safetyPrefix = "al-dia-antes-de-restaurar-"

    /// When a copy «antes de restaurar» was taken, from its name; `nil` for any other file, or
    /// for a date that doesn't exist.
    public static func safetyDate(of name: String, timeZone: TimeZone = .current) -> Date? {
        guard name.hasPrefix(safetyPrefix), name.hasSuffix(".\(fileExtension)") else { return nil }
        let stamp = name.dropFirst(safetyPrefix.count).dropLast(fileExtension.count + 1)
        let halves = stamp.split(separator: "T", omittingEmptySubsequences: false)
        guard stamp.count == 17, halves.count == 2, halves[1].count == 6, halves[1].allSatisfy(\.isNumber) else { return nil }
        let day = halves[0].split(separator: "-", omittingEmptySubsequences: false)
        guard day.count == 3, day.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let time = Array(halves[1])
        func number(_ text: some StringProtocol) -> Int? { Int(text) }
        let parts = DateComponents(year: number(day[0]), month: number(day[1]), day: number(day[2]),
                                   hour: number(String(time[0...1])), minute: number(String(time[2...3])),
                                   second: number(String(time[4...5])))
        let calendar = calendar(in: timeZone)
        // «2026-13-45» would roll over into another day: only a date that reads back the same.
        guard let date = calendar.date(from: parts),
              stamp == Substring(self.stamp(date, timeZone: timeZone, withTime: true)) else { return nil }
        return date
    }
}

/// A phone that was just restored and has no daily backup set up (2026-11-11, map of states):
/// the backup's own settings don't travel, so a new phone stayed without one and nobody said so.
public enum BackupSetupReminder {
    public static let text = "El respaldo diario no está configurado en este iPhone."
    /// What «Hoy» says, with where to fix it, like its other backup lines.
    public static let warning = text + " Configúralo en Más › Ajustes › Respaldo diario."

    /// After «Ahora no», or after the person saw it on the backup's screen, «Hoy» stays quiet
    /// this long.
    public static let quiet: TimeInterval = 7 * 24 * 60 * 60

    /// Whether «Hoy» says it now. Only on a phone that was restored (`restoredAt`); `saidLaterAt`
    /// is the last «Ahora no» or the last look at the backup's screen.
    public static func isDue(restoredAt: Date?, saidLaterAt: Date?, now: Date) -> Bool {
        guard restoredAt != nil else { return false }
        guard let saidLaterAt else { return true }
        // A clock set back doesn't bring the line back early, and never hides it for good.
        return abs(now.timeIntervalSince(saidLaterAt)) >= quiet
    }
}
