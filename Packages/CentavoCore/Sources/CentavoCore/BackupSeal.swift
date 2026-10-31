import Foundation
#if canImport(CryptoKit) && canImport(CommonCrypto)
import CommonCrypto
import CryptoKit
#endif

/// Locks a backup with a password, and opens it again.
///
/// The file is `ALDIA` + a version byte, then how many PBKDF2-SHA256 rounds made the key
/// (4 bytes, big-endian), a random 16-byte salt, and the AES-GCM box (nonce, ciphertext and
/// tag). GCM's tag means a wrong password and a tampered file both fail to open, and never
/// open into something else.
public enum BackupSeal {
    static let magic = Data("ALDIA".utf8)
    static let version: UInt8 = 1
    /// OWASP's figure for PBKDF2-SHA256 (2023): about half a second on an iPhone, once a day.
    public static let rounds: UInt32 = 600_000
    static let saltLength = 16
    static let headerLength = magic.count + 1 + 4 + saltLength

    public static func seal(_ payload: BackupPayload, password: String,
                            rounds: UInt32 = BackupSeal.rounds) throws -> Data {
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
        file.append(box)
        return file
        #else
        throw BackupError.cryptoUnavailable
        #endif
    }

    public static func open(_ file: Data, password: String) throws -> BackupPayload {
        #if canImport(CryptoKit) && canImport(CommonCrypto)
        let file = Data(file)  // Indices from zero, whatever slice came in.
        guard file.count > headerLength, file.prefix(magic.count) == magic else { throw BackupError.notABackup }
        guard file[magic.count] <= version else { throw BackupError.newerFormat }
        let roundsAt = magic.count + 1
        let rounds = file[roundsAt..<roundsAt + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard rounds > 0 else { throw BackupError.damaged }
        let salt = file[(roundsAt + 4)..<headerLength]
        let key = try derive(password, salt: Data(salt), rounds: rounds)
        let plain: Data
        do {
            plain = try AES.GCM.open(AES.GCM.SealedBox(combined: file[headerLength...]), using: key)
        } catch {
            throw BackupError.wrongPassword
        }
        return try BackupPayload.decoded(from: plain)
        #else
        throw BackupError.cryptoUnavailable
        #endif
    }

    #if canImport(CryptoKit) && canImport(CommonCrypto)
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
