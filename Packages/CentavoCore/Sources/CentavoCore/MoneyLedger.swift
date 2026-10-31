import Foundation

/// What a line in «Mi dinero» is (2026-10-31). Stored by its raw value.
public enum MoneyKind: String, CaseIterable, Codable, Sendable {
    /// A bank account, a savings box, cash: money that is yours today.
    case account = "cuenta"
    /// Goes up and down (a fund, stocks): no fixed rate, its value is typed at each cut.
    case investment = "inversion"
    /// Money someone owes you, or a bonus that hasn't arrived: counts, marked «por caer».
    case receivable = "por_cobrar"
    /// A card balance, a loan: subtracts.
    case debt = "deuda"

    /// Whether it adds to or takes from the net worth.
    public var sign: Decimal { self == .debt ? -1 : 1 }
}

/// One line of a cut, in its own currency.
public struct MoneyLine: Equatable, Sendable {
    public var kind: MoneyKind
    public var currency: String
    public var balance: Decimal

    public init(kind: MoneyKind, currency: String, balance: Decimal) {
        self.kind = kind
        self.currency = currency
        self.balance = balance
    }
}

/// The net worth of one cut, in the cut's main currency.
public struct NetWorth: Equatable, Sendable {
    /// Accounts and investments: yours today.
    public var owned: Decimal = 0
    /// Owed to you, «por caer».
    public var receivable: Decimal = 0
    /// What you owe, as a positive amount.
    public var debts: Decimal = 0
    /// Currencies with no rate in the cut: their lines are left out rather than guessed.
    public var missingRates: Set<String> = []

    public var total: Decimal { owned + receivable - debts }

    public init() {}

    /// `rates` are units of the main currency per one unit of each other currency
    /// («USD»: 18.5 when the main one is pesos). The main currency needs no rate.
    public init(lines: [MoneyLine], main: String, rates: [String: Decimal]) {
        for line in lines {
            let rate: Decimal
            if line.currency == main {
                rate = 1
            } else if let known = rates[line.currency], known > 0 {
                rate = known
            } else {
                missingRates.insert(line.currency)
                continue
            }
            let value = MoneyMath.cents(line.balance * rate)
            switch line.kind {
            case .account, .investment: owned += value
            case .receivable: receivable += value
            case .debt: debts += value
            }
        }
    }
}

public enum MoneyMath {
    /// Rounded to cents, half away from zero, as a bank statement does.
    public static func cents(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }

    /// The currencies other than `main` that a set of lines needs a rate for, sorted.
    public static func foreignCurrencies(in lines: [MoneyLine], main: String) -> [String] {
        Set(lines.map(\.currency)).subtracting([main]).sorted()
    }

    /// Exchange rates as the cut stores them: «USD=18.5;EUR=20.1». Text, not JSON numbers,
    /// so a rate never passes through `Double`.
    public static func encodeRates(_ rates: [String: Decimal]) -> String {
        rates.keys.sorted().map { "\($0)=\(BackupNumber.text(rates[$0]!))" }.joined(separator: ";")
    }

    public static func decodeRates(_ text: String?) -> [String: Decimal] {
        var rates: [String: Decimal] = [:]
        for pair in (text ?? "").split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, let value = BackupNumber.value(parts[1]) else { continue }
            rates[parts[0]] = value
        }
        return rates
    }

    /// «2026-10»: one cut per calendar month, and the month is its identity.
    public static func monthKey(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// How a cut's yield hint reads: the previous balance × the yearly rate × days ÷ 365.
    /// Only a hint: the cut keeps what the person types.
    public static func expectedYield(previous: Decimal, yearlyRate: Decimal, days: Int) -> Decimal {
        guard days > 0, yearlyRate != 0 else { return 0 }
        return cents(previous * yearlyRate / 100 * Decimal(days) / 365)
    }
}
