import Foundation

/// Everything Al día keeps, as one file: every expense with every field, and every setting.
///
/// Amounts travel as text, never as JSON numbers: `JSONDecoder` reads a `Decimal` through
/// `Double`, so `0.1` would come back as `0.1000000000000000512` and every restore would
/// nudge the money. Dates travel as seconds since 2001, which a `Double` keeps exactly.
public struct BackupPayload: Codable, Equatable, Sendable {
    /// Bumped when the shape changes in a way an older app cannot read. 2 (2026-10-31) adds
    /// «Mi dinero»: an app that only knows 1 refuses it instead of restoring without it. 3
    /// (2026-11-01) adds each line's subtype and institution, and the incomes.
    public static let currentFormat = 3

    public var format: Int
    public var createdAt: Date
    /// Which build wrote it («Al día 0.1.0 · compilación 312 · 59f8d9e»), for tracing.
    public var writtenBy: String
    public var expenses: [BackupExpense]
    public var settings: [String: BackupSetting]
    /// «Mi dinero». `nil` in a format-1 file: restoring it leaves «Mi dinero» as it is.
    public var money: BackupMoney?

    public init(createdAt: Date, writtenBy: String, expenses: [BackupExpense],
                settings: [String: BackupSetting], money: BackupMoney? = nil) {
        self.format = Self.currentFormat
        self.createdAt = createdAt
        self.writtenBy = writtenBy
        self.expenses = expenses
        self.settings = settings
        self.money = money
    }

    /// A `Double` that is not a number (NaN, infinity) can't be written as JSON and would fail
    /// the whole backup: a setting like that is left out and such a place is dropped, since
    /// neither ever meant anything.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        var clean = self
        clean.settings = settings.filter { _, setting in
            if case .number(let value) = setting { return value.isFinite }
            return true
        }
        for index in clean.expenses.indices {
            if clean.expenses[index].latitude?.isFinite == false { clean.expenses[index].latitude = nil }
            if clean.expenses[index].longitude?.isFinite == false { clean.expenses[index].longitude = nil }
        }
        return try encoder.encode(clean)
    }

    public static func decoded(from data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        // Read the format first, so a newer file says so instead of failing on a field.
        struct Head: Decodable { var format: Int }
        guard let head = try? decoder.decode(Head.self, from: data) else { throw BackupError.damaged }
        guard head.format <= currentFormat else { throw BackupError.newerFormat }
        do { return try decoder.decode(BackupPayload.self, from: data) } catch { throw BackupError.damaged }
    }

    /// What the restore sheet shows before anything is replaced.
    public var summary: BackupSummary {
        let dates = expenses.map(\.date)
        return BackupSummary(createdAt: createdAt, expenseCount: expenses.count,
                             firstExpense: dates.min(), lastExpense: dates.max(),
                             accountCount: money?.accounts.count, cutCount: money?.cuts.count)
    }
}

/// Counts only: the restore sheet is shown before Face ID, so no money figures.
public struct BackupSummary: Equatable, Sendable {
    public var createdAt: Date
    public var expenseCount: Int
    public var firstExpense: Date?
    public var lastExpense: Date?
    /// `nil` when the file has no «Mi dinero» at all (format 1).
    public var accountCount: Int?
    public var cutCount: Int?
}

/// «Mi dinero» as the backup keeps it: amounts as text, cuts already finished (a draft is
/// work in progress and stays out).
public struct BackupMoney: Codable, Equatable, Sendable {
    public var accounts: [Account]
    public var cuts: [Cut]
    /// Format 3. `nil` in an older file.
    public var incomes: [Income]?
    /// Cuts left half-done. Only in the copy taken before a restore (2026-11-02, second audit),
    /// so restoring that copy brings them back; `nil` in the daily files, which leave drafts out.
    public var drafts: [Cut]?

    public init(accounts: [Account], cuts: [Cut], incomes: [Income]? = nil, drafts: [Cut]? = nil) {
        self.accounts = accounts
        self.cuts = cuts
        self.incomes = incomes
        self.drafts = drafts
    }

    /// Something in it: an account, a cut or an income. An empty «Mi dinero» is nothing to keep.
    public var hasContent: Bool {
        !accounts.isEmpty || !cuts.isEmpty || !(incomes ?? []).isEmpty || !(drafts ?? []).isEmpty
    }

    /// Every figure reads and every line of a cut or a draft names an account the file brings:
    /// restoring it can't stop halfway. Checked before a damaged «Mi dinero» is set aside
    /// (independent review), so a broken file never leaves it empty with the good one hidden.
    public var isWhole: Bool {
        func reads(_ text: String?) -> Bool { text.map { BackupNumber.value($0) != nil } ?? true }
        let ids = Set(accounts.map(\.id))
        guard accounts.allSatisfy({ reads($0.yearlyRate) }),
              (incomes ?? []).allSatisfy({ reads($0.amount) }) else { return false }
        return (cuts + (drafts ?? [])).allSatisfy { cut in
            cut.entries.allSatisfy { line in
                ids.contains(line.account) && reads(line.balance) && reads(line.yieldOverride) && reads(line.movement)
            }
        }
    }

    /// What comes in each month (format 3).
    public struct Income: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var institution: String?
        public var amount: String
        public var currency: String
        public var since: Date
        public var archived: Bool
        /// When it was added. `nil` in a file written before 2026-11-02.
        public var createdAt: Date?
        /// When it stopped counting. `nil` while it counts, and in a file written before.
        public var until: Date?

        public init(id: String, name: String, institution: String?, amount: String, currency: String, since: Date,
                    archived: Bool, createdAt: Date? = nil, until: Date? = nil) {
            self.id = id; self.name = name; self.institution = institution; self.amount = amount
            self.currency = currency; self.since = since; self.archived = archived; self.createdAt = createdAt
            self.until = until
        }
    }

    public struct Account: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var kind: String
        public var currency: String
        public var yearlyRate: String?
        public var order: Int
        public var archived: Bool
        public var createdAt: Date
        /// Format 3: a card or a loan among debts, money lent or to come among receivables.
        public var subtype: String?
        public var institution: String?

        public init(id: String, name: String, kind: String, currency: String, yearlyRate: String?,
                    order: Int, archived: Bool, createdAt: Date, subtype: String? = nil, institution: String? = nil) {
            self.id = id; self.name = name; self.kind = kind; self.currency = currency
            self.yearlyRate = yearlyRate; self.order = order; self.archived = archived; self.createdAt = createdAt
            self.subtype = subtype; self.institution = institution
        }
    }

    public struct Cut: Codable, Equatable, Sendable {
        public var id: String
        public var month: String
        public var date: Date
        public var mainCurrency: String
        public var rates: String
        public var entries: [Entry]
        /// A draft's currencies already looked at. `nil` in a finished cut and in older files.
        public var reviewedRates: String?

        public init(id: String, month: String, date: Date, mainCurrency: String, rates: String, entries: [Entry],
                    reviewedRates: String? = nil) {
            self.id = id; self.month = month; self.date = date; self.mainCurrency = mainCurrency
            self.rates = rates; self.entries = entries; self.reviewedRates = reviewedRates
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var account: String
        public var balance: String
        public var yieldOverride: String?
        public var movement: String?
        /// Whether the person already checked this line. `nil` in a file written before
        /// 2026-11-02: restore it as before (reviewed).
        public var reviewed: Bool?

        public init(account: String, balance: String, yieldOverride: String? = nil, movement: String? = nil,
                    reviewed: Bool? = nil) {
            self.account = account; self.balance = balance; self.yieldOverride = yieldOverride; self.movement = movement
            self.reviewed = reviewed
        }
    }
}

/// One expense, field for field as the app stores it. Every field but the three a payment
/// always has is optional, exactly like the model.
public struct BackupExpense: Codable, Equatable, Sendable {
    public var amount: String
    public var date: Date
    public var merchant: String
    public var currencyMarker: String?
    public var card: String?
    public var category: String?
    public var rawAmount: String?
    public var rawNotice: String?
    public var latitude: Double?
    public var longitude: Double?
    public var placeName: String?
    public var repeatsMonthly: Bool?
    public var repeatsThrough: Date?
    public var repeatDay: Int?
    public var repeatRule: String?
    public var isRepeat: Bool?
    public var displayName: String?
    public var categorySource: String?
    public var countedAmount: String?
    public var uncountedReason: String?
    /// A fixed expense's own stable id (the original, not its copies). Added 2026-11-02.
    public var fixedID: String?
    /// In a copy of a fixed expense: the `fixedID` of the original. Added 2026-11-02.
    public var fixedOf: String?
    /// A Wallet capture identical to another within five minutes, marked «¿repetida?».
    /// Added 2026-11-02.
    public var maybeRepeated: Bool?

    public init(amount: Decimal, date: Date, merchant: String) {
        self.amount = BackupNumber.text(amount)
        self.date = date
        self.merchant = merchant
    }

    /// `nil` when the text is not a plain number: a damaged file, never a guess.
    public var amountValue: Decimal? { BackupNumber.value(amount) }
    public var countedValue: Decimal?? {
        guard let countedAmount else { return .some(nil) }
        return BackupNumber.value(countedAmount).map { .some($0) }
    }
}

/// A setting as `UserDefaults` holds it. Only the kinds the app writes; anything else is left
/// out of the backup rather than turned into something it wasn't.
public enum BackupSetting: Codable, Equatable, Sendable {
    case text(String)
    case flag(Bool)
    case whole(Int)
    case number(Double)
    case date(Date)
}

/// Amounts as text with a dot, whatever the phone's region.
public enum BackupNumber {
    private static let posix = Locale(identifier: "en_US_POSIX")

    public static func text(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: posix)
    }

    public static func value(_ text: String) -> Decimal? {
        guard !text.isEmpty, text.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return Decimal(string: text, locale: posix)
    }
}

public enum BackupError: Error, Equatable, Sendable {
    /// Not an Al día backup at all.
    case notABackup
    /// The password doesn't open it (in a version-1 file, also a file changed after it was written).
    case wrongPassword
    /// Written by a newer Al día.
    case newerFormat
    /// Cut short, changed after it was written, or opened but what's inside doesn't read.
    case damaged
    /// The phone couldn't do the cryptography (it never fails on a real iPhone).
    case cryptoUnavailable
}

/// Which backup files to keep: the newest 30 days, plus the newest file of every month for
/// good. Names that aren't Al día backups are never touched.
public enum BackupRetention {
    public static let prefix = "al-dia-"
    public static let fileExtension = "aldia"
    public static let dailyKept = 30

    /// The calendar every name is written with: always Gregorian, on this phone's clock. A phone
    /// set to the Japanese or Buddhist calendar wrote «0008-…» or «2569-…» and broke the cleanup;
    /// UTC wrote tomorrow's date at 21:00 in Mexico (2026-11-02, second audit).
    public static func calendar(in timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    /// «2026-03-07», or «2026-03-07T210500» with the time.
    public static func stamp(_ date: Date, timeZone: TimeZone = .current, withTime: Bool = false) -> String {
        let parts = calendar(in: timeZone).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        guard withTime else { return day }
        return day + String(format: "T%02d%02d%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    public static func fileName(for day: Date, timeZone: TimeZone = .current) -> String {
        "\(prefix)\(stamp(day, timeZone: timeZone)).\(fileExtension)"
    }

    /// A day's expenses alone, when «Mi dinero» didn't open. Not a daily name: never trimmed.
    public static func partialName(for date: Date, timeZone: TimeZone = .current) -> String {
        "\(prefix)solo-gastos-\(stamp(date, timeZone: timeZone)).\(fileExtension)"
    }

    /// What there was before a restore. Never trimmed.
    public static func safetyName(for date: Date, timeZone: TimeZone = .current) -> String {
        "\(prefix)antes-de-restaurar-\(stamp(date, timeZone: timeZone, withTime: true)).\(fileExtension)"
    }

    /// A backup that would have replaced today's file with less (`BackupPlan.aside`). Never trimmed.
    public static func asideName(for date: Date, timeZone: TimeZone = .current) -> String {
        "\(prefix)aparte-\(stamp(date, timeZone: timeZone, withTime: true)).\(fileExtension)"
    }

    /// Any file Al día wrote: daily, apart, or before a restore.
    public static func isBackupFile(_ name: String) -> Bool {
        name.hasPrefix(prefix) && name.hasSuffix(".\(fileExtension)")
    }

    /// The day in a backup's name, or `nil` for any other file.
    public static func day(of name: String) -> String? {
        guard name.hasPrefix(prefix), name.hasSuffix(".\(fileExtension)") else { return nil }
        let day = name.dropFirst(prefix.count).dropLast(fileExtension.count + 1)
        let pieces = day.split(separator: "-")
        guard day.count == 10, pieces.count == 3,
              pieces.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        return String(day)
    }

    /// A day no clock gives yet: «2569-…» was written by a phone set to the Buddhist calendar
    /// before names were Gregorian. Such files are left alone: never deleted (they may be the
    /// only copy of their day) and never counted among the newest 30 (independent review).
    static func isPlausible(_ day: String, now: Date) -> Bool {
        guard let year = Int(day.prefix(4)) else { return false }
        return year <= calendar().component(.year, from: now) + 1
    }

    /// The newest daily file, by the day in its name.
    public static func newestDaily(_ names: [String], now: Date = .now) -> String? {
        names.compactMap { name in day(of: name).map { (name: name, day: $0) } }
            .filter { isPlausible($0.day, now: now) }
            .max { $0.day < $1.day }?.name
    }

    /// The names to delete, from everything in the folder.
    public static func toDelete(_ names: [String], now: Date = .now) -> [String] {
        let backups = names.compactMap { name in day(of: name).map { (name: name, day: $0) } }
            .filter { isPlausible($0.day, now: now) }
            .sorted { $0.day > $1.day }
        var keep = Set(backups.prefix(dailyKept).map(\.name))
        var monthsSeen = Set<String>()
        for backup in backups where monthsSeen.insert(String(backup.day.prefix(7))).inserted {
            keep.insert(backup.name)
        }
        return backups.map(\.name).filter { !keep.contains($0) }
    }
}
