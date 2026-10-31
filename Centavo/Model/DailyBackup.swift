import CentavoCore
import Foundation
import LocalAuthentication
import Security
import SwiftData

/// The daily backup (2026-10-31): one locked file a day in a folder the person picked in
/// Archivos, usually iCloud Drive/Al día. With a free developer account the app has no iCloud
/// of its own and the data lives only on the phone, so this file is what survives a lost phone.
///
/// The app writes the file itself (Atajos only wakes it up), reads it back and opens it with
/// the password before it counts as done: «Último respaldo» never says yes to a file that
/// didn't make it.
enum DailyBackup {
    /// Kept out of the backup itself: they belong to this phone.
    static let folderKey = "respaldo.carpeta"
    static let lastKey = "respaldo.ultimo"
    static let folderNameKey = "respaldo.carpetaNombre"

    enum Failure: Error, CustomLocalizedStringResourceConvertible, Equatable {
        case noPassword, noFolder, folderGone, notWritten, unreadable(BackupError)

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .noPassword: "Primero crea la contraseña del respaldo en Ajustes de Al día."
            case .noFolder: "Primero elige la carpeta del respaldo en Ajustes de Al día."
            case .folderGone: "La carpeta del respaldo ya no está. Elígela otra vez en Ajustes de Al día."
            case .notWritten: "No se pudo guardar el respaldo en la carpeta. Revisa que haya espacio en iCloud."
            case .unreadable(.wrongPassword): "La contraseña no abre este respaldo."
            case .unreadable(.notABackup): "Ese archivo no es un respaldo de Al día."
            case .unreadable(.newerFormat): "Ese respaldo es de una versión más nueva de Al día. Actualiza la app."
            case .unreadable: "El respaldo está dañado y no se puede leer."
            }
        }
    }

    // MARK: Status

    static var lastBackup: Date? { UserDefaults.standard.object(forKey: lastKey) as? Date }
    static var folderName: String? { UserDefaults.standard.string(forKey: folderNameKey) }
    static var isSetUp: Bool { BackupPassword.read() != nil && UserDefaults.standard.data(forKey: folderKey) != nil }

    /// Three days without a backup (or none yet, once it's set up) is worth a line.
    static func isOverdue(now: Date = .now) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) > 3 * 24 * 60 * 60
    }

    // MARK: Folder

    /// Remembers a folder the person picked, so the app can write there tomorrow without asking.
    static func choose(folder url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: folderKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: folderNameKey)
    }

    private static func folder() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(forKey: folderKey) else { throw Failure.noFolder }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { throw Failure.folderGone }
        if stale { try? choose(folder: url) }
        return url
    }

    // MARK: Writing

    /// Writes today's file, checks it opens, and trims old ones. Returns when it was written.
    @MainActor @discardableResult
    static func runNow(in context: ModelContext, now: Date = .now) throws -> Date {
        guard let password = BackupPassword.read() else { throw Failure.noPassword }
        let payload = try snapshot(in: context, now: now)
        try write(payload, password: password, named: BackupRetention.fileName(for: now), trims: true)
        UserDefaults.standard.set(now, forKey: lastKey)
        return now
    }

    /// Before a restore replaces everything, what there was goes to the folder (never trimmed:
    /// the name isn't a daily one) and to the app's own Documents, whichever works.
    @MainActor
    static func safetyCopy(in context: ModelContext, password: String, now: Date = .now) throws {
        let payload = try snapshot(in: context, now: now)
        let stamp = now.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false)
            .timeSeparator(.omitted)).replacingOccurrences(of: ":", with: "")
        let name = "\(BackupRetention.prefix)antes-de-restaurar-\(stamp).\(BackupRetention.fileExtension)"
        let sealed = try BackupSeal.seal(payload, password: password)
        var saved = false
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            saved = (try? sealed.write(to: docs.appending(path: name), options: .atomic)) != nil
        }
        if (try? write(payload, password: password, named: name, trims: false, sealed: sealed)) != nil { saved = true }
        if !saved { throw Failure.notWritten }
    }

    private static func write(_ payload: BackupPayload, password: String, named name: String,
                              trims: Bool, sealed: Data? = nil) throws {
        let sealed = try sealed ?? BackupSeal.seal(payload, password: password)
        let folder = try folder()
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let target = folder.appending(path: name)

        var problem: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: target, options: .forReplacing, error: nil) { url in
            do { try sealed.write(to: url, options: .atomic) } catch { problem = error }
        }
        guard problem == nil else { throw Failure.notWritten }

        // Read it back and open it: only a file that opens counts as a backup.
        var reread: Data?
        coordinator.coordinate(readingItemAt: target, options: [], error: nil) { url in
            reread = try? Data(contentsOf: url)
        }
        guard let reread, let back = try? BackupSeal.open(reread, password: password),
              back.expenses.count == payload.expenses.count else { throw Failure.notWritten }

        guard trims, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        else { return }
        for old in BackupRetention.toDelete(names) {
            coordinator.coordinate(writingItemAt: folder.appending(path: old), options: .forDeleting, error: nil) { url in
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: What goes in

    @MainActor
    static func snapshot(in context: ModelContext, now: Date = .now) throws -> BackupPayload {
        let expenses = try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
        return BackupPayload(createdAt: now, writtenBy: AppVersion.line,
                             expenses: expenses.map(\.backedUp), settings: Settings.current())
    }

    /// Every setting the app keeps in `UserDefaults`, read from the app's own domain rather than
    /// from a list of keys, so a setting added later is backed up without anyone remembering to.
    enum Settings {
        static func isOurs(_ key: String) -> Bool {
            let system = ["Apple", "NS", "AK", "PK", "com.apple.", "INNext", "MSV", "WebKit"]
            return !key.hasPrefix("respaldo.") && !system.contains { key.hasPrefix($0) }
        }

        static func current() -> [String: BackupSetting] {
            guard let id = Bundle.main.bundleIdentifier,
                  let domain = UserDefaults.standard.persistentDomain(forName: id) else { return [:] }
            var settings: [String: BackupSetting] = [:]
            for (key, value) in domain where isOurs(key) {
                if let setting = setting(value) { settings[key] = setting }
            }
            return settings
        }

        static func setting(_ value: Any) -> BackupSetting? {
            switch value {
            case let text as String: return .text(text)
            case let date as Date: return .date(date)
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return .flag(number.boolValue) }
                if CFNumberIsFloatType(number) { return .number(number.doubleValue) }
                return .whole(number.intValue)
            default: return nil
            }
        }

        /// Replaces this phone's settings with the backup's: what the backup doesn't have goes.
        static func restore(_ settings: [String: BackupSetting]) {
            let defaults = UserDefaults.standard
            if let id = Bundle.main.bundleIdentifier, let domain = defaults.persistentDomain(forName: id) {
                for key in domain.keys where isOurs(key) && settings[key] == nil { defaults.removeObject(forKey: key) }
            }
            for (key, value) in settings where isOurs(key) {
                switch value {
                case .text(let text): defaults.set(text, forKey: key)
                case .flag(let flag): defaults.set(flag, forKey: key)
                case .whole(let whole): defaults.set(whole, forKey: key)
                case .number(let number): defaults.set(number, forKey: key)
                case .date(let date): defaults.set(date, forKey: key)
                }
            }
            // With iCloud, the budget and catalog would otherwise come back from there at launch.
            for key in BudgetSync.keys { BudgetSync.push(defaults.string(forKey: key) ?? "", for: key) }
        }
    }

    // MARK: Restoring

    /// Reads a file the person picked (it may be only in iCloud, not yet on the phone).
    static func read(_ url: URL, password: String) throws -> BackupPayload {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { data = try? Data(contentsOf: $0) }
        guard let data else { throw Failure.unreadable(.damaged) }
        do { return try BackupSeal.open(data, password: password) } catch let error as BackupError {
            throw Failure.unreadable(error)
        }
    }

    /// Replaces every expense and setting with the backup's, all at once: one save, so it's
    /// either the old data or the new, never a mix. Settings change only after the save.
    @MainActor
    static func restore(_ payload: BackupPayload, into container: ModelContainer) throws {
        let expenses = try payload.expenses.map { try Expense(backup: $0) }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            for old in try context.fetch(FetchDescriptor<Expense>()) { context.delete(old) }
            expenses.forEach(context.insert)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        Settings.restore(payload.settings)
        WidgetBridge.refreshAfterIntent()
    }
}

extension Expense {
    var backedUp: BackupExpense {
        var row = BackupExpense(amount: amount, date: date, merchant: merchant)
        row.currencyMarker = currencyMarker
        row.card = card
        row.category = category
        row.rawAmount = rawAmount
        row.rawNotice = rawNotice
        row.latitude = latitude
        row.longitude = longitude
        row.placeName = placeName
        row.repeatsMonthly = repeatsMonthly
        row.repeatsThrough = repeatsThrough
        row.repeatDay = repeatDay
        row.repeatRule = repeatRule
        row.isRepeat = isRepeat
        row.displayName = displayName
        row.categorySource = categorySource
        row.countedAmount = countedAmount.map(BackupNumber.text)
        row.uncountedReason = uncountedReason
        return row
    }

    /// A damaged amount stops the whole restore instead of becoming $0.
    convenience init(backup row: BackupExpense) throws {
        guard let amount = row.amountValue, let counted = row.countedValue else {
            throw DailyBackup.Failure.unreadable(.damaged)
        }
        self.init(amount: amount, currencyMarker: row.currencyMarker, merchant: row.merchant, card: row.card,
                  date: row.date, category: row.category, rawAmount: row.rawAmount)
        rawNotice = row.rawNotice
        latitude = row.latitude
        longitude = row.longitude
        placeName = row.placeName
        repeatsMonthly = row.repeatsMonthly
        repeatsThrough = row.repeatsThrough
        repeatDay = row.repeatDay
        repeatRule = row.repeatRule
        isRepeat = row.isRepeat
        displayName = row.displayName
        categorySource = row.categorySource
        countedAmount = counted
        uncountedReason = row.uncountedReason
    }
}

/// The backup's password, in this phone's Keychain so the nightly run locks the file without
/// asking. Only this device, readable after the first unlock (the run happens at night).
enum BackupPassword {
    private static let service = "centavo.respaldo"
    private static let account = "contrasena"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var item: CFTypeRef?
        var ask = query
        ask[kSecReturnData as String] = true
        ask[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(ask as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ password: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(password.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Face ID (or the phone's passcode) before showing it.
    static func unlock(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
