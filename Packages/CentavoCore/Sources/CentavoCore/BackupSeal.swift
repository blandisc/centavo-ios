import Foundation
#if canImport(CryptoKit) && canImport(CommonCrypto)
import CommonCrypto
import CryptoKit
#endif

/// Locks a backup with a password, and opens it again.
///
/// The file is `ALDIA` + a version byte, then how many PBKDF2-SHA256 rounds made the key
/// (4 bytes, big-endian), a random 16-byte salt, a 16-byte password check (version 2) and the
/// AES-GCM box (nonce, ciphertext and tag). GCM's tag means a wrong password and a tampered
/// file both fail to open, and never open into something else; the check, derived from the
/// key, tells the two apart: a cut or damaged file says so instead of blaming the password.
/// Version 1 files (no check, until 2026-11-02) still open; there a failed box can only say
/// «wrong password».
public enum BackupSeal {
    static let magic = Data("ALDIA".utf8)
    static let version: UInt8 = 2
    /// OWASP's figure for PBKDF2-SHA256 (2023): about half a second on an iPhone, once a day.
    public static let rounds: UInt32 = 600_000
    /// More rounds than this in a file is damage, not a choice: deriving the key would take
    /// minutes before failing anyway.
    static let maxRounds: UInt32 = 10_000_000
    static let saltLength = 16
    static let checkLength = 16
    /// AES-GCM's nonce and tag: the smallest box there is.
    static let boxOverhead = 12 + 16

    static func headerLength(version: UInt8) -> Int {
        magic.count + 1 + 4 + saltLength + (version >= 2 ? checkLength : 0)
    }

    public static func seal(_ payload: BackupPayload, password: String,
                            rounds: UInt32 = BackupSeal.rounds) throws -> Data {
        try seal(payload, password: password, rounds: rounds, version: version)
    }

    /// `version` 1 only to write the files older apps wrote, for the tests.
    static func seal(_ payload: BackupPayload, password: String, rounds: UInt32, version: UInt8) throws -> Data {
        #if canImport(CryptoKit) && canImport(CommonCrypto)
        var salt = Data(count: saltLength)
        let made = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!) }
        guard made == errSecSuccess else { throw BackupError.cryptoUnavailable }
        let key = try derive(password, salt: salt, rounds: rounds)
        guard let box = try AES.GCM.seal(payload.encoded(), using: key).combined else {
            throw BackupError.cryptoUnavailable
        }
        var file = magic
        file.append(version)
        withUnsafeBytes(of: rounds.bigEndian) { file.append(contentsOf: $0) }
        file.append(salt)
        if version >= 2 { file.append(check(for: key)) }
        file.append(box)
        return file
        #else
        throw BackupError.cryptoUnavailable
        #endif
    }

    public static func open(_ file: Data, password: String) throws -> BackupPayload {
        #if canImport(CryptoKit) && canImport(CommonCrypto)
        let file = Data(file)  // Indices from zero, whatever slice came in.
        guard file.count > magic.count, file.prefix(magic.count) == magic else { throw BackupError.notABackup }
        let fileVersion = file[magic.count]
        guard fileVersion <= version else { throw BackupError.newerFormat }
        // Shorter than a header and an empty box: it was cut while copying or saving.
        let headerLength = headerLength(version: fileVersion)
        guard fileVersion >= 1, file.count >= headerLength + boxOverhead else { throw BackupError.damaged }
        let roundsAt = magic.count + 1
        let rounds = file[roundsAt..<roundsAt + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard rounds > 0, rounds <= maxRounds else { throw BackupError.damaged }
        let saltEnd = roundsAt + 4 + saltLength
        let key = try derive(password, salt: Data(file[(roundsAt + 4)..<saltEnd]), rounds: rounds)
        if fileVersion >= 2 {
            guard file[saltEnd..<(saltEnd + checkLength)] == check(for: key) else { throw BackupError.wrongPassword }
        }
        let plain: Data
        do {
            plain = try AES.GCM.open(AES.GCM.SealedBox(combined: file[headerLength...]), using: key)
        } catch {
            // With the password checked, a box that doesn't open was changed or cut.
            throw fileVersion >= 2 ? BackupError.damaged : BackupError.wrongPassword
        }
        return try BackupPayload.decoded(from: plain)
        #else
        throw BackupError.cryptoUnavailable
        #endif
    }

    #if canImport(CryptoKit) && canImport(CommonCrypto)
    /// A fingerprint of the key, never the key itself: HKDF with its own label, so it says
    /// nothing that would help open the box.
    private static func check(for key: SymmetricKey) -> Data {
        let derived = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, info: Data("Al día · comprobar contraseña".utf8),
                                             outputByteCount: checkLength)
        return derived.withUnsafeBytes { Data($0) }
    }

    private static func derive(_ password: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        let secret = Array(password.precomposedStringWithCanonicalMapping.utf8)
        var key = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            secret.withUnsafeBufferPointer { secretBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     secretBytes.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                                     secret.count,
                                     saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                     &key, key.count)
            }
        }
        guard status == kCCSuccess else { throw BackupError.cryptoUnavailable }
        return SymmetricKey(data: key)
    }
    #endif
}
