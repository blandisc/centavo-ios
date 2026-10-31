import Foundation

/// Everything Al día keeps, as one file: every expense with every field, and every setting.
///
/// Amounts travel as text, never as JSON numbers: `JSONDecoder` reads a `Decimal` through
/// `Double`, so `0.1` would come back as `0.1000000000000000512` and every restore would
/// nudge the money. Dates travel as seconds since 2001, which a `Double` keeps exactly.
public struct BackupPayload: Codable, Equatable, Sendable {
    /// Bumped when the shape changes in a way an older app cannot read.
    public static let currentFormat = 1

    public var format: Int
    public var createdAt: Date
    /// Which build wrote it («Al día 0.1.0 · compilación 312 · 59f8d9e»), for tracing.
    public var writtenBy: String
    public var expenses: [BackupExpense]
    public var settings: [String: BackupSetting]

    public init(createdAt: Date, writtenBy: String, expenses: [BackupExpense],
                settings: [String: BackupSetting]) {
        self.format = Self.currentFormat
        self.createdAt = createdAt
        self.writtenBy = writtenBy
        self.expenses = expenses
        self.settings = settings
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(self)
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
                             firstExpense: dates.min(), lastExpense: dates.max())
    }
}

public struct BackupSummary: Equatable, Sendable {
    public var createdAt: Date
    public var expenseCount: Int
    public var firstExpense: Date?
    public var lastExpense: Date?
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
    /// The password doesn't open it (or the file was changed after it was written).
    case wrongPassword
    /// Written by a newer Al día.
    case newerFormat
    /// Opened, but what's inside doesn't read.
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

    public static func fileName(for day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let name = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "\(prefix)\(name).\(fileExtension)"
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

    /// The names to delete, from everything in the folder.
    public static func toDelete(_ names: [String]) -> [String] {
        let backups = names.compactMap { name in day(of: name).map { (name: name, day: $0) } }
            .sorted { $0.day > $1.day }
        var keep = Set(backups.prefix(dailyKept).map(\.name))
        var monthsSeen = Set<String>()
        for backup in backups where monthsSeen.insert(String(backup.day.prefix(7))).inserted {
            keep.insert(backup.name)
        }
        return backups.map(\.name).filter { !keep.contains($0) }
    }
}
