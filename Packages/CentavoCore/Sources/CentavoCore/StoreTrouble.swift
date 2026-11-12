import Foundation

/// Why the expenses' store didn't open, as far as it can be known (2026-11-11, map of states):
/// the screen used to say the same thing whatever happened, and promised nothing was lost
/// without knowing.
public enum StoreTrouble: Equatable, Sendable {
    /// The phone is out of room: the error says so, or there's almost none left.
    case noSpace
    /// Anything else. Nothing is promised about it.
    case unknown

    /// Under this much free room, a store that doesn't open is taken as «no room» (bytes).
    public static let lowSpace: Int64 = 50_000_000

    /// One error in the chain: its domain and code, as `NSError` gives them.
    public struct Code: Equatable, Sendable {
        public var domain: String
        public var code: Int

        public init(domain: String, code: Int) {
            self.domain = domain
            self.code = code
        }
    }

    /// `codes`: the error and every error under it. `freeBytes`: what the phone says it has
    /// left, or `nil` when it doesn't say.
    public static func cause(codes: [Code], freeBytes: Int64?) -> StoreTrouble {
        if codes.contains(where: saysNoSpace) { return .noSpace }
        if let freeBytes, freeBytes < lowSpace { return .noSpace }
        return .unknown
    }

    private static func saysNoSpace(_ error: Code) -> Bool {
        switch (error.domain, error.code) {
        case ("NSCocoaErrorDomain", 640): true // NSFileWriteOutOfSpaceError
        case ("NSPOSIXErrorDomain", 28): true // ENOSPC
        case ("NSPOSIXErrorDomain", 69): true // EDQUOT
        case ("NSSQLiteErrorDomain", 13): true // SQLITE_FULL
        default: false
        }
    }

    public var title: String { "Al día no pudo abrir tus gastos" }

    /// What happened and what to do, without promising what isn't known.
    public var explanation: String {
        switch self {
        case .noSpace:
            "El iPhone casi no tiene espacio libre, y sin espacio Al día no puede abrir tus gastos. Libera espacio en Ajustes › General › Almacenamiento del iPhone y toca «Intentar de nuevo». Tus gastos deberían seguir en este iPhone. No desinstales la app: perderías tus gastos."
        case .unknown:
            "Tus gastos deberían seguir en este iPhone. Toca «Intentar de nuevo». Si sigue igual, cierra Al día por completo y ábrela otra vez, o reinicia el iPhone. No desinstales la app: perderías tus gastos."
        }
    }

    /// Whether a file next to the stores is part of them: the expenses' store and «Mi dinero»,
    /// each with its journal («-wal», «-shm»), and a «Mi dinero» that was set aside damaged.
    /// `store`: the expenses' file name («default.store»).
    public static func isStoreFile(_ name: String, store: String) -> Bool {
        name.hasPrefix(store) || name.hasPrefix("dinero.store")
    }
}
