import Foundation

/// The lock of «Mi dinero» as plain rules (2026-11-02 audit): an answer from Face ID only opens
/// the tab if nothing locked it while the prompt was up and the tab is still on screen.
///
/// Every `lock()` starts a new generation. A Face ID request remembers the generation it started
/// in; when its answer arrives, it only counts if that generation is still the current one.
public struct UnlockGate: Equatable, Sendable {
    public private(set) var generation = 0

    public init() {}

    /// Locks again: any answer still on its way belongs to an older generation.
    public mutating func lock() { generation &+= 1 }

    /// Whether an answer from the request started in `started` opens the tab.
    public func opens(granted: Bool, started: Int, stillVisible: Bool) -> Bool {
        granted && started == generation && stillVisible
    }
}

/// How this iPhone proves it's its owner, to say it in words (2026-11-02 audit): the intro said
/// «tu cara» on every phone, and a phone with no passcode opens «Mi dinero» without asking.
public enum UnlockMethod: Equatable, Sendable {
    case faceID, touchID
    /// A passcode but no Face ID or Touch ID set up.
    case passcode
    /// No passcode at all: nothing to check against, so it opens without asking.
    case none

    public var title: String {
        switch self {
        case .faceID: "«Mi dinero» se abre solo con tu cara"
        case .touchID: "«Mi dinero» se abre solo con tu huella"
        case .passcode: "«Mi dinero» se abre solo con el código de tu iPhone"
        case .none: "Tu iPhone no tiene código"
        }
    }

    /// The lines under the title, in order.
    public var points: [String] {
        let what = "Aquí van tus saldos y lo que debes: si le prestas tu iPhone a alguien en «Hoy», no puede pasar a verlos."
        switch self {
        case .faceID:
            return [what,
                    "Te lo pide cada vez que abres esta pestaña. Si Face ID falla, usas el código de tu iPhone.",
                    "Al tocar «Activar», iOS te pregunta si Al día puede usar Face ID. Tu cara nunca sale del iPhone."]
        case .touchID:
            return [what,
                    "Te lo pide cada vez que abres esta pestaña. Si Touch ID falla, usas el código de tu iPhone.",
                    "Tu huella nunca sale del iPhone."]
        case .passcode:
            return [what,
                    "Te lo pide cada vez que abres esta pestaña.",
                    "Si después activas Face ID o Touch ID en tu iPhone, Al día lo usa en lugar del código."]
        case .none:
            return ["Aquí van tus saldos y lo que debes. Sin un código en el iPhone, «Mi dinero» se abre sin pedir nada: cualquiera con tu iPhone puede verlos.",
                    "Para protegerlo, ponle un código en Ajustes › Face ID y código. Al día lo pedirá desde ese momento."]
        }
    }

    public var button: String {
        switch self {
        case .faceID: "Activar Face ID"
        case .touchID: "Activar Touch ID"
        case .passcode: "Continuar"
        case .none: "Entendido"
        }
    }

    /// The SF Symbol that stands for it.
    public var symbol: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .passcode: "lock"
        case .none: "lock.open"
        }
    }
}

/// Small words of «Mi dinero» that depend on a count or a set.
public enum MoneyWords {
    /// Under «Agregar N» in the import, when some rows still need a look: they aren't saved.
    public static func waitingLeftOut(_ count: Int) -> String? {
        switch count {
        case ..<1: nil
        case 1: "1 por revisar no se agrega. Complétala antes de guardar o agrégala después a mano."
        default: "\(count) por revisar no se agregan. Complétalas antes de guardar o agrégalas después a mano."
        }
    }

    /// The currencies whose exchange rate was already looked at in a draft cut, kept as text
    /// on the cut («EUR,USD») so reopening it doesn't ask them again.
    public static func encodeCodes(_ codes: Set<String>) -> String {
        codes.sorted().joined(separator: ",")
    }

    public static func decodeCodes(_ text: String?) -> Set<String> {
        Set((text ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
}

/// Editing an income in «Mi dinero» (2026-11-02 audit). An income keeps the month it started
/// (`since`) so a raise doesn't rewrite what months past should have saved: a new amount or
/// currency from a later month starts a new version and the old one is archived. Within the
/// month it started, it's simply corrected.
public enum MoneyIncomeRule {
    public static func startsNewVersion(oldAmount: Decimal, oldCurrency: String, since: Date,
                                        newAmount: Decimal, newCurrency: String,
                                        now: Date, calendar: Calendar = .current) -> Bool {
        guard oldAmount != newAmount || oldCurrency != newCurrency else { return false }
        return MoneyMath.monthKey(of: since, calendar: calendar) != MoneyMath.monthKey(of: now, calendar: calendar)
    }
}
