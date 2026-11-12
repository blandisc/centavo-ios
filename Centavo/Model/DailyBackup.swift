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
    /// The last time a run failed, cleared by the next one that works: «Hoy» says so.
    static let failedKey = "respaldo.fallo"
    /// The newest file's name, to ask iCloud whether it went up.
    static let fileKey = "respaldo.archivo"
    /// The last backup went apart, and why (`BackupAsideNote.stored`), until a daily one is
    /// written again (2026-11-11). Like the others, it belongs to this phone.
    static let asideKey = "respaldo.aparte"
    /// When a backup was last restored on this phone (2026-11-11): a restored phone with no
    /// daily backup set up is said in «Hoy». Like the others, it doesn't travel.
    static let restoredKey = "respaldo.restaurado"
    /// The last «Ahora no» to «Seguir respaldando aquí», or the last look at the backup's screen
    /// without it set up: «Hoy» stays quiet a week after it (`BackupSetupReminder`).
    static let laterKey = "respaldo.ahoraNo"

    enum Failure: Error, CustomLocalizedStringResourceConvertible, Equatable {
        case noPassword, passwordUnavailable, noFolder, folderGone, notWritten, moneyUnreadable, unreadable(BackupError)
        /// This phone has no expenses and the folder already has backups: restore first.
        case newPhone
        /// Restoring: «Mi dinero» was damaged, was set aside, and a new one didn't open either.
        case moneyNotReady
        /// Restoring: the expenses failed after «Mi dinero» changed, and it couldn't go back.
        case halfRestored
        /// «Este iPhone es el bueno»: the backup that had more couldn't be kept under another name.
        case oldNotKept
        /// «Este iPhone es el bueno»: the new file wasn't written, and the file of the day stayed
        /// under the name it was kept with (a half-written one was in the way of its own).
        case notWrittenOldKept(String)
        /// Another backup is being written right now: this one did nothing.
        case busy
        /// Restoring: there's something on this phone and no folder to copy it to first.
        case noPlaceForCopy
        /// Restoring: the copy of what there is couldn't be written where the person can see it.
        case copyNotSaved

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .noPassword: "Primero crea la contraseña del respaldo en Ajustes de Al día."
            case .passwordUnavailable: "El iPhone no dejó leer la contraseña del respaldo (suele pasar si no se ha desbloqueado desde que se encendió). Desbloquéalo y respalda otra vez."
            case .newPhone: "Parece un iPhone nuevo: restaura tu respaldo antes de respaldar."
            case .moneyNotReady: "No se pudo abrir «Mi dinero» para restaurarlo. Tus gastos no cambiaron. Si «Mi dinero» no abría, quedó guardado aparte en este iPhone, sin borrarse. Cierra Al día por completo, vuelve a abrirla e intenta otra vez."
            case .halfRestored: "No se pudieron restaurar tus gastos, pero «Mi dinero» ya quedó como en el respaldo. Para dejar todo como estaba, restaura la copia «antes de restaurar» que se guardó antes de empezar."
            case .noPlaceForCopy: "Antes de restaurar hay que guardar una copia de lo que hay en este iPhone, y no hay una carpeta donde ponerla. No se cambió nada."
            case .copyNotSaved: "No se pudo guardar la copia de lo que hay en este iPhone, así que no se restauró nada. Revisa que la carpeta siga ahí y que haya espacio, o elige otra."
            case .noFolder: "Primero elige la carpeta del respaldo en Ajustes de Al día."
            case .folderGone: "La carpeta del respaldo ya no está. Elígela otra vez en Ajustes de Al día."
            case .oldNotKept: "No se pudo conservar el respaldo que tenía más, así que no se cambió nada. Abre la carpeta en Archivos, espera a que ese archivo termine de bajar de iCloud e intenta otra vez."
            case .notWrittenOldKept(let name): "No se pudo guardar el respaldo en la carpeta. El respaldo de hoy que ya tenías no se perdió: quedó en tu carpeta como «\(name)». Revisa que haya espacio e intenta otra vez."
            case .busy: "Ya se está guardando un respaldo. Espera un momento."
            case .notWritten: "No se pudo guardar el respaldo en la carpeta. Revisa que siga ahí y que haya espacio."
            case .moneyUnreadable: "Se guardaron tus gastos, pero no «Mi dinero»: no se pudo abrir. Cierra Al día por completo, vuelve a abrirla y respalda otra vez."
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
    /// A password that can't be read right now (the phone locked since it was turned on) still
    /// counts as set up: the warning in «Hoy» should still show.
    static var isSetUp: Bool {
        BackupPassword.lookup() != .missing && UserDefaults.standard.data(forKey: folderKey) != nil
    }

    static var lastFailure: Date? { UserDefaults.standard.object(forKey: failedKey) as? Date }

    /// The last backup was written apart instead of taking the day's name, and why; `nil` while
    /// the last one is a daily file.
    static var aside: BackupAsideNote? {
        BackupAsideNote(stored: UserDefaults.standard.string(forKey: asideKey))
    }

    static let asideWarning = "Tu último respaldo se guardó aparte. Revísalo en Más › Ajustes › Respaldo diario."

    /// Three days without a backup (or none yet, once it's set up) is worth a line.
    static func isOverdue(now: Date = AppClock.now) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) > 3 * 24 * 60 * 60
    }

    /// What «Hoy» says, quietly: nothing while the backup is fine, and nothing on a phone that
    /// never had one, unless it was restored and still has none (`setUpNotice`).
    static func warning(now: Date = AppClock.now) -> String? {
        guard isSetUp else { return setUpNotice(now: now) }
        return notice(now: now)
    }

    /// A restored phone with no daily backup: its settings don't travel in the file, so the new
    /// phone had none and nothing said so (2026-11-11). At most once a week after «Ahora no».
    /// Apart from `warning` so it can be tried without the Keychain.
    static func setUpNotice(now: Date = AppClock.now, defaults: UserDefaults = .standard) -> String? {
        BackupSetupReminder.isDue(restoredAt: defaults.object(forKey: restoredKey) as? Date,
                                  saidLaterAt: defaults.object(forKey: laterKey) as? Date, now: now)
            ? BackupSetupReminder.warning : nil
    }

    /// This phone was restored and the daily backup isn't set up on it.
    static var needsSetUpAfterRestore: Bool {
        !isSetUp && UserDefaults.standard.object(forKey: restoredKey) != nil
    }

    /// A restore just worked: from now on a phone without a daily backup is worth a line.
    static func noteRestored(now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: restoredKey)
        defaults.removeObject(forKey: laterKey)
    }

    /// «Ahora no», or the person saw the line on the backup's screen: «Hoy» waits a week.
    static func sayLater(now: Date = AppClock.now, defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: laterKey)
    }

    /// What there is to say once it's set up, in order of urgency. Apart from `warning` so it
    /// can be tried without a password in the Keychain.
    static func notice(now: Date = AppClock.now) -> String? {
        if let failed = lastFailure, failed > (lastBackup ?? .distantPast) {
            return "El último respaldo no se pudo hacer. Revísalo en Más › Ajustes › Respaldo diario."
        }
        if isOverdue(now: now) { return "Llevas más de 3 días sin respaldo. Revísalo en Más › Ajustes › Respaldo diario." }
        // Written on the phone but not up in iCloud (full, or no network for a day): the date in
        // «Último respaldo» alone would say it's fine (2026-11-02, second audit).
        if BackupCloud.isStuck(cloudState(), writtenAt: lastBackup, now: now) {
            return "El último respaldo no ha subido a iCloud; puede que no haya espacio. Revísalo en Más › Ajustes › Respaldo diario."
        }
        // Saved, but not as the file of the day: it stays said until the person looks at it or
        // a daily file is written again. Last, so it never hides the three above.
        if aside != nil { return asideWarning }
        return nil
    }

    /// Where the newest file is: only on this phone, still going up to iCloud, or up.
    typealias CloudState = BackupCloudState

    /// Asked of the newest file each time: iCloud uploads after the app wrote it.
    static func cloudState() -> CloudState? {
        guard let name = UserDefaults.standard.string(forKey: fileKey), let folder = try? folder() else { return nil }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        return cloudState(of: folder.appending(path: name))
    }

    /// Whether one file in the folder is only here, going up, up, or failed to go up.
    static func cloudState(of url: URL) -> CloudState? {
        var file = url
        file.removeAllCachedResourceValues()
        guard let values = try? file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey,
                                                             .ubiquitousItemUploadingErrorKey]) else { return nil }
        guard values.isUbiquitousItem == true else { return .local }
        if values.ubiquitousItemUploadingError != nil { return .failed }
        return values.ubiquitousItemIsUploaded == true ? .uploaded : .uploading
    }

    /// Whether a folder lives in iCloud Drive (and so outside this phone).
    static func isInCloud(_ url: URL) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
            || FileManager.default.isUbiquitousItem(at: url)
    }

    // MARK: Folder

    /// Remembers a folder the person picked, so the app can write there tomorrow without asking.
    static func choose(folder url: URL) throws {
        try remember(folder: url)
        // «Aparte» was said about the other folder's backups (2026-11-11).
        UserDefaults.standard.removeObject(forKey: asideKey)
    }

    /// The bookmark alone: also to refresh one that went stale, which is the same folder.
    private static func remember(folder url: URL) throws {
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
        // A folder sent to the trash still resolves: writing there would look fine and be lost.
        if isTrashed(url) { throw Failure.folderGone }
        if stale { try? remember(folder: url) }
        return url
    }

    /// Whether the chosen folder is there to write to: picked, still resolving, not in the trash.
    static var folderIsUsable: Bool {
        guard let url = try? folder() else { return false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isFolder)
            && isFolder.boolValue
    }

    /// «Seguir respaldando aquí» (2026-11-11): tries the folder the restored file came from as
    /// this phone's backup folder. Only when it can really be written to (Archivos usually hands
    /// over the file alone, not its folder); otherwise nothing changes and the person picks it.
    static func adoptFolder(of file: URL) -> Bool {
        let parent = file.deletingLastPathComponent()
        // Never a folder inside the app itself (a copy listed from Documents): nobody sees it.
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path(percentEncoded: false)
        guard !parent.resolvingSymlinksInPath().path(percentEncoded: false).hasPrefix(home), !isTrashed(parent) else { return false }
        let defaults = UserDefaults.standard
        let before = (defaults.data(forKey: folderKey), defaults.string(forKey: folderNameKey))
        func undo() {
            defaults.set(before.0, forKey: folderKey)
            defaults.set(before.1, forKey: folderNameKey)
        }
        let fileAccess = file.startAccessingSecurityScopedResource()
        defer { if fileAccess { file.stopAccessingSecurityScopedResource() } }
        guard (try? remember(folder: parent)) != nil else { undo(); return false }
        // Through the bookmark, as tomorrow's backup will: a small file written and removed.
        let probe = ".al-dia-prueba-\(UUID().uuidString)"
        let wrote = (try? inFolder { folder -> Bool in
            let url = folder.appending(path: probe)
            try Data("Al día".utf8).write(to: url, options: .atomic)
            try FileManager.default.removeItem(at: url)
            return true
        }) ?? false
        guard wrote else { undo(); return false }
        defaults.removeObject(forKey: asideKey)
        return true
    }

    /// A folder in the trash (Archivos keeps it in «.Trash» until it's emptied).
    static func isTrashed(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains(".Trash")
    }

    // MARK: Writing

    /// Writes today's file, checks it opens, and trims old ones. Returns when it was written.
    ///
    /// The expenses and «Mi dinero» are read here, on the main actor; locking the file (600,000
    /// rounds of PBKDF2), writing it and reading it back run apart, so «Respaldar ahora» doesn't
    /// freeze the screen (2026-11-02, second audit).
    ///
    /// A file written apart still counts as the day's backup (it's whole, and checked), and is
    /// noted in `asideKey` so the screen and «Hoy» say it. `trustingThisPhone`: «Este iPhone es
    /// el bueno», asked by the person, writes the daily file even with less.
    @MainActor @discardableResult
    static func runNow(in context: ModelContext, now: Date = AppClock.now,
                       trustingThisPhone: Bool = false) async throws -> Date {
        // One at a time (the 21:00 automation while «Respaldar ahora» is tapped, or two taps):
        // the second one writes nothing and isn't a failed night.
        guard !isRunning else { throw Failure.busy }
        isRunning = true
        defer { isRunning = false }
        do {
            let password = try BackupPassword.current()
            let payload: BackupPayload
            do {
                payload = try snapshot(in: context, now: now)
            } catch Failure.moneyUnreadable {
                // The expenses are still kept, in a file of their own that the cleanup never
                // touches; the day doesn't count as backed up and the good files stay.
                let partial = try snapshot(in: context, now: now, moneyContainer: nil)
                try await apart {
                    try inFolder { folder in
                        try writeChecked(partial, password: password, named: BackupRetention.partialName(for: now), in: folder)
                    }
                }
                throw Failure.moneyUnreadable
            }
            let written = try await apart {
                try writeToday(payload, password: password, now: now, trustingThisPhone: trustingThisPhone)
            }
            record(written, at: now)
            return now
        } catch {
            UserDefaults.standard.set(now, forKey: failedKey)
            throw error
        }
    }

    /// A run is writing right now (`runNow`).
    @MainActor static var isRunning = false

    /// What a run that worked leaves on this phone: when, which file, and whether it went apart.
    /// A daily file clears the note of the one before.
    static func record(_ written: Written, at now: Date, defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: lastKey)
        defaults.set(written.name, forKey: fileKey)
        defaults.removeObject(forKey: failedKey)
        if let stored = written.aside?.stored {
            defaults.set(stored, forKey: asideKey)
        } else {
            defaults.removeObject(forKey: asideKey)
        }
    }

    /// The file a run wrote, and why it went apart when it did.
    struct Written: Equatable, Sendable {
        var name: String
        var aside: BackupAsideNote?
    }

    /// Heavy work off the main thread.
    private static func apart<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated, operation: work).value
    }

    /// The chosen folder, opened for the length of `work`.
    private static func inFolder<T>(_ work: (URL) throws -> T) throws -> T {
        try within(try folder(), work)
    }

    /// A folder the person picked (now or before), opened for the length of `work`.
    private static func within<T>(_ folder: URL, _ work: (URL) throws -> T) throws -> T {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        return try work(folder)
    }

    /// Today's file, unless that would put less over what today's file, or the newest backup in
    /// the folder, already has (`BackupPlan`). Returns the name written and, apart, why.
    ///
    /// `trustingThisPhone` («Este iPhone es el bueno», 2026-11-11): what would go apart takes
    /// today's name. The backup that had more is first kept as «al-dia-reemplazado-…», a name no
    /// cleanup touches (an apart name would be trimmed with the other apart files, and it may be
    /// the only copy of what this phone no longer has): the file of the day renamed, the newest
    /// daily file of another day copied. If it can't be kept nothing is written, and if the
    /// write fails everything goes back. Nothing is trimmed that night.
    static func writeToday(_ payload: BackupPayload, password: String, now: Date,
                           trustingThisPhone: Bool = false) throws -> Written {
        try inFolder { folder in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            // A file only in iCloud, not on this phone yet, shows as «.name.icloud».
            let present = Array(Set(names.map(Self.visibleName)))
            func state(of name: String?) -> BackupPlan.Today {
                guard let name else { return .none }
                if names.contains(name) { return holds(folder.appending(path: name), password: password) }
                return present.contains(name) ? .unreadable : .none
            }
            let daily = BackupRetention.fileName(for: now)
            let today = state(of: daily)
            let newestName = BackupRetention.newestDaily(present, now: now)
            let newest = newestName == daily ? today : state(of: newestName)
            let hasMoney = payload.money?.hasContent ?? false
            let reason = BackupPlan.aside(expenses: payload.expenses.count, hasMoney: hasMoney, today: today, newest: newest)
            let plan = BackupPlan.decide(expenses: payload.expenses.count, hasMoney: hasMoney,
                                         today: today, newest: newest,
                                         folderHasBackups: present.contains(where: BackupRetention.isBackupFile),
                                         trustingThisPhone: trustingThisPhone)
            // In iCloud, nothing is trimmed until the last file made it up (iCloud full).
            let previous = UserDefaults.standard.string(forKey: fileKey)
                .flatMap { cloudState(of: folder.appending(path: $0)) }
            let mayTrim = !payload.expenses.isEmpty
                && BackupCloud.mayTrim(folderInCloud: isInCloud(folder), previous: previous)
            switch plan {
            case .newPhone:
                throw Failure.newPhone
            case .aside:
                // The day's file, or the newest, had much more: this one goes apart, and no daily
                // file is trimmed. Of the apart ones only the newest few stay.
                let name = BackupRetention.asideName(for: now)
                try writeChecked(payload, password: password, named: name, in: folder)
                if mayTrim {
                    remove(BackupRetention.asidesToDelete(names, keeping: name, now: now), from: folder)
                }
                // `reason` is never `nil` when the plan is `.aside` (the same function decides both).
                let compared = (reason?.source ?? .today) == .today ? daily : newestName
                return Written(name: name, aside: BackupAsideNote(reason ?? .unreadable, comparedWith: compared, file: name))
            case .daily, .dailyKeepingOld:
                // «Este iPhone es el bueno»: the backup that had more is kept for good as
                // «reemplazado». The file of the day is renamed (its name is about to be written
                // over); the newest daily file, of another day, is copied (it stays where it is,
                // but the daily cleanup would drop it some thirty backups later).
                var moved: String?, copied: String?
                if trustingThisPhone, let reason {
                    let kept = BackupRetention.replacedName(for: now)
                    if reason.source == .today, present.contains(daily) {
                        guard move(daily, to: kept, in: folder) else { throw Failure.oldNotKept }
                        moved = kept
                    } else if reason.source == .newest, let newestName, newestName != daily {
                        guard copyChecked(newestName, to: kept, in: folder) else { throw Failure.oldNotKept }
                        copied = kept
                    }
                }
                do {
                    try writeChecked(payload, password: password, named: daily, in: folder)
                } catch {
                    // Nothing changed: the copy goes (its original is where it was) and the file
                    // of the day gets its name back. If a half-written one is in the way, it
                    // stays as «reemplazado», never lost, and the message says where.
                    if let copied { remove([copied], from: folder) }
                    if let moved, !move(moved, to: daily, in: folder) { throw Failure.notWrittenOldKept(moved) }
                    throw error
                }
                if plan == .daily && mayTrim {
                    remove(BackupRetention.toDelete(Array(Set(names).union([daily])), now: now), from: folder)
                }
                return Written(name: daily, aside: nil)
            }
        }
    }

    /// Copies a file under another name and reads the copy back: only one that comes back byte
    /// for byte counts. Never over a file that's already there.
    private static func copyChecked(_ name: String, to other: String, in folder: URL) -> Bool {
        let target = folder.appending(path: other)
        guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)),
              let data = coordinatedRead(folder.appending(path: name)) else { return false }
        var coordination: NSError?
        var wrote = false
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordination) { url in
            wrote = (try? data.write(to: url, options: .atomic)) != nil
        }
        guard coordination == nil, wrote, coordinatedRead(target) == data else {
            remove([other], from: folder)
            return false
        }
        return true
    }

    /// Never over a file that's already there.
    private static func move(_ name: String, to other: String, in folder: URL) -> Bool {
        let from = folder.appending(path: name), to = folder.appending(path: other)
        var coordination: NSError?
        var moved = false
        NSFileCoordinator().coordinate(writingItemAt: from, options: .forMoving, writingItemAt: to,
                                       options: .forReplacing, error: &coordination) { source, target in
            guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else { return }
            moved = (try? FileManager.default.moveItem(at: source, to: target)) != nil
        }
        return coordination == nil && moved
    }

    /// «.al-dia-2026-11-01.aldia.icloud» (in iCloud, not downloaded) is «al-dia-2026-11-01.aldia».
    static func visibleName(_ name: String) -> String {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return name }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    /// What today's file holds, or that it can't be read (another password, damaged).
    private static func holds(_ url: URL, password: String) -> BackupPlan.Today {
        guard let data = coordinatedRead(url), let back = try? BackupSeal.open(data, password: password) else {
            return .unreadable
        }
        return .holds(expenses: back.expenses.count, money: back.money?.hasContent ?? false)
    }

    /// Before a restore replaces everything, what there was goes to a folder the person can
    /// open in Archivos (never trimmed: the name isn't a daily one): the backup's folder, or
    /// `chosen`, picked for this copy when there's none. Never to the app's own Documents alone,
    /// which nobody can see (2026-11-11): without a visible copy this throws and the restore
    /// doesn't happen. A cut left half-done goes too (2026-11-02, second audit): restoring
    /// replaces it, and this copy is where it's kept.
    ///
    /// Locking the copy takes a moment off the main thread, and a Wallet payment can be saved in
    /// it: the restore would delete it with no copy (independent review). So once written, the
    /// expenses are counted again and, if any came, the copy is taken again, over the same file.
    @MainActor @discardableResult
    static func safetyCopy(in context: ModelContext, password: String, into chosen: URL? = nil,
                           now: Date = AppClock.now) async throws -> SafetyCopy {
        let target: URL
        if let chosen {
            target = chosen
        } else {
            do { target = try folder() } catch { throw Failure.noPlaceForCopy }
        }
        let name = BackupRetention.safetyName(for: now)
        for _ in 0..<safetyAttempts {
            let payload = try await writeSafetyCopy(in: context, password: password, named: name, into: target, now: now)
            if try expensesMark(in: context) == mark(of: payload) {
                return SafetyCopy(name: name, folderName: target.lastPathComponent)
            }
        }
        // Payments keep arriving: better not to restore now than to lose one.
        throw Failure.copyNotSaved
    }

    /// The copy taken before a restore: its file and the folder it's in, as the screen says them.
    struct SafetyCopy: Equatable, Sendable {
        var name: String
        var folderName: String
    }

    static let safetyAttempts = 3

    /// How many expenses and the newest date: what a payment arriving changes.
    struct ExpensesMark: Equatable {
        var count: Int
        var newest: Date?
    }

    static func mark(of payload: BackupPayload) -> ExpensesMark {
        ExpensesMark(count: payload.expenses.count, newest: payload.expenses.map(\.date).max())
    }

    @MainActor
    static func expensesMark(in context: ModelContext) throws -> ExpensesMark {
        var newest = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        newest.fetchLimit = 1
        return ExpensesMark(count: try context.fetchCount(FetchDescriptor<Expense>()),
                            newest: try context.fetch(newest).first?.date)
    }

    @MainActor
    private static func writeSafetyCopy(in context: ModelContext, password: String, named name: String,
                                        into target: URL, now: Date) async throws -> BackupPayload {
        // A «Mi dinero» that doesn't open can't be copied, but the expenses still can (and its
        // file is set aside, never deleted, if the restore needs a new one).
        let payload = try (try? snapshot(in: context, now: now, drafts: true))
            ?? snapshot(in: context, now: now, moneyContainer: nil)
        try await apart {
            do {
                // Read back and opened with the password, like every backup: only then it counts.
                try within(target) { folder in
                    try writeChecked(payload, password: password, named: name, in: folder)
                }
            } catch {
                throw Failure.copyNotSaved
            }
        }
        return payload
    }

    /// What the person sets up by hand and a restore replaces: the budget, the fixed expenses
    /// to come, their own categories and payment methods (with colors, hidden and deleted ones
    /// and the default) and the rules and renames. A phone with any of them isn't empty, even
    /// with no expenses. The main currency isn't here: the welcome picks it on every phone.
    static let personalKeys = [BudgetStore.key, FixedPlan.key, UserCatalog.categoriesKey, UserCatalog.sourcesKey,
                               UserCatalog.defaultSourceKey, UserCatalog.hiddenCategoriesKey,
                               UserCatalog.categoryRulesKey, UserCatalog.deletedCategoriesKey,
                               UserCatalog.merchantRenamesKey, UserCatalog.cardRenamesKey,
                               UserCatalog.categoryColorsKey, UserCatalog.sourceColorsKey]

    /// What a restore has to do first with what's on this phone (`BackupSafetyPlan`). A «Mi
    /// dinero» that's there and doesn't open has nothing that can be copied: restoring sets its
    /// files aside, never deleted. `settings`: what would travel in a backup right now.
    @MainActor
    static func safetyPlan(in context: ModelContext,
                           money: @autoclosure () -> ModelContainer? = try? MoneyStore.opened.get(),
                           settings: [String: BackupSetting] = Settings.current()) -> BackupSafetyPlan {
        // If the expenses can't be counted, there may be some: never «nothing to copy».
        let expenses = (try? context.fetchCount(FetchDescriptor<Expense>())) ?? 1
        var hasMoney = false
        if expenses == 0, let container = money() {
            hasMoney = (try? moneySnapshot(container, drafts: true))?.hasContent ?? true
        }
        return BackupSafetyPlan.decide(expenses: expenses, hasMoney: hasMoney,
                                       configured: BackupSafetyPlan.isConfigured(settings, keys: personalKeys),
                                       folderUsable: folderIsUsable)
    }

    /// The only way the screen restores (2026-11-11): what's on this phone is first copied where
    /// the person can see it, and only then replaced. With something to keep and nowhere to put
    /// it (`chosen` is the folder picked for the copy when the backup has none) it throws before
    /// anything changes. An empty phone has nothing to copy: it returns `nil` for the copy.
    @MainActor @discardableResult
    static func restoreKeepingCopy(_ payload: BackupPayload, in context: ModelContext, password: String,
                                   copyInto chosen: URL? = nil, now: Date = AppClock.now,
                                   money: @autoclosure () -> ModelContainer? = try? MoneyStore.opened.get(),
                                   settings: [String: BackupSetting] = Settings.current()) async throws -> SafetyCopy? {
        var copy: SafetyCopy?
        if chosen != nil || safetyPlan(in: context, money: money(), settings: settings) != .nothingToCopy {
            copy = try await safetyCopy(in: context, password: password, into: chosen, now: now)
        }
        // No suspension between the copy's last count (or the plan) and the restore: both run
        // here, on the main actor, so no payment lands in between.
        try restore(payload, into: context.container, now: now)
        return copy
    }

    // MARK: Copies left inside the app

    /// The app's own Documents, where copies «antes de restaurar» were also written until
    /// 2026-11-11. Archivos doesn't show it.
    static var ownDocuments: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// The copies «antes de restaurar» that earlier restores left inside the app, newest first:
    /// the screen lists them so they can be restored or taken out to Archivos.
    static func strandedCopies(in documents: URL? = ownDocuments) -> [BackupSafetyCopy] {
        guard let documents,
              let names = try? FileManager.default.contentsOfDirectory(atPath: documents.path(percentEncoded: false))
        else { return [] }
        return BackupSafetyCopy.list(names)
    }

    /// Deletes one, because the person asked. Never any other file.
    @discardableResult
    static func removeStranded(_ copy: BackupSafetyCopy, in documents: URL? = ownDocuments) -> Bool {
        guard let documents, BackupRetention.safetyDate(of: copy.name) != nil else { return false }
        return (try? FileManager.default.removeItem(at: documents.appending(path: copy.name))) != nil
    }

    /// Drops the copies inside the app that are also in the backup's folder, byte for byte (until
    /// 2026-11-11 each was written to both): those are already where the person can see them.
    /// Any other stays until it's taken out to Archivos or deleted by hand.
    @discardableResult
    static func tidyStrandedCopies(in documents: URL? = ownDocuments) -> [String] {
        guard let documents else { return [] }
        let copies = strandedCopies(in: documents)
        guard !copies.isEmpty else { return [] }
        return (try? inFolder { folder in
            copies.map(\.name).filter { name in
                let inside = documents.appending(path: name)
                guard let mine = try? Data(contentsOf: inside), !mine.isEmpty,
                      FileManager.default.fileExists(atPath: folder.appending(path: name).path(percentEncoded: false)),
                      coordinatedRead(folder.appending(path: name)) == mine else { return false }
                return (try? FileManager.default.removeItem(at: inside)) != nil
            }
        }) ?? []
    }

    /// Writes a file and reads it back: only a file that comes back byte for byte, and opens with
    /// the password holding the same counts, counts as written. Every coordination error is
    /// checked (a `nil` error pointer let a write that never ran pass, 2026-11-02).
    private static func writeChecked(_ payload: BackupPayload, password: String, named name: String,
                                     in folder: URL, sealed: Data? = nil) throws {
        let sealed = try sealed ?? BackupSeal.seal(payload, password: password)
        let target = folder.appending(path: name)

        var coordination: NSError?
        var problem: Error?
        var wrote = false
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordination) { url in
            do {
                try sealed.write(to: url, options: .atomic)
                wrote = true
            } catch {
                problem = error
            }
        }
        guard coordination == nil, problem == nil, wrote else { throw Failure.notWritten }

        // Read it back and open it: only a file that opens counts as a backup.
        // «Mi dinero» is compared too: a file without it, when there was some, isn't a backup.
        guard let reread = coordinatedRead(target), reread == sealed,
              let back = try? BackupSeal.open(reread, password: password),
              back.expenses.count == payload.expenses.count,
              back.money?.accounts.count == payload.money?.accounts.count,
              back.money?.cuts.count == payload.money?.cuts.count,
              back.money?.incomes?.count == payload.money?.incomes?.count,
              back.money?.drafts?.count == payload.money?.drafts?.count else { throw Failure.notWritten }
    }

    /// A file's bytes through the coordinator (iCloud may still be bringing it), or `nil`.
    private static func coordinatedRead(_ url: URL) -> Data? {
        var coordination: NSError?
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordination) { data = try? Data(contentsOf: $0) }
        return coordination == nil ? data : nil
    }

    /// Deletes files the cleanup picked (`BackupRetention.toDelete`, `asidesToDelete`), through
    /// the coordinator.
    private static func remove(_ names: [String], from folder: URL) {
        for old in names {
            var coordination: NSError?
            NSFileCoordinator().coordinate(writingItemAt: folder.appending(path: old), options: .forDeleting,
                                           error: &coordination) { url in
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: What goes in

    /// `drafts`: a cut left half-done goes too (only the copy before a restore).
    @MainActor
    static func snapshot(in context: ModelContext, now: Date = AppClock.now, drafts: Bool = false) throws -> BackupPayload {
        try snapshot(in: context, now: now, moneyContainer: moneyContainer(), drafts: drafts)
    }

    @MainActor
    static func snapshot(in context: ModelContext, now: Date = AppClock.now,
                         moneyContainer: ModelContainer?, drafts: Bool = false) throws -> BackupPayload {
        let expenses = try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
        return BackupPayload(createdAt: now, writtenBy: AppVersion.line,
                             expenses: expenses.map(\.backedUp), settings: Settings.current(),
                             money: try moneySnapshot(moneyContainer, drafts: drafts))
    }

    /// «Mi dinero», read without Face ID: the backup is written in the background and the file
    /// is locked with the password anyway. `nil` only when it was never written on this phone; a
    /// store that's there and doesn't open stops the backup, so a file without it never
    /// counts as done (and never makes the cleanup drop the good ones).
    static func moneyContainer() throws -> ModelContainer? {
        switch MoneyStore.opened {
        case .success(let container): return container
        case .failure: if MoneyStore.hasFile { throw Failure.moneyUnreadable } else { return nil }
        }
    }

    @MainActor
    static func moneySnapshot(_ container: ModelContainer?, drafts: Bool = false) throws -> BackupMoney? {
        guard let container else { return nil }
        let context = ModelContext(container)
        let accounts = try context.fetch(FetchDescriptor<MoneyAccount>(sortBy: [SortDescriptor(\.createdAt)]))
        let cuts = try context.fetch(MoneyCut.finished)
        let incomes = try context.fetch(FetchDescriptor<MoneyIncome>(sortBy: [SortDescriptor(\.createdAt)]))
        let halfDone = drafts ? try MoneyStore.drafts(in: context) : []
        func row(_ cut: MoneyCut) -> BackupMoney.Cut {
            .init(id: cut.id.uuidString, month: cut.month, date: cut.date, mainCurrency: cut.mainCurrency,
                  rates: cut.rates, entries: (cut.entries ?? []).compactMap { entry in
                      guard let account = entry.account else { return nil }
                      return .init(account: account.id.uuidString, balance: BackupNumber.text(entry.balance),
                                   yieldOverride: entry.yieldOverride.map(BackupNumber.text),
                                   movement: entry.movement.map(BackupNumber.text), reviewed: entry.reviewed)
                  },
                  reviewedRates: cut.isDraft ? cut.reviewedRates : nil)
        }
        return BackupMoney(
            accounts: accounts.map { account in
                .init(id: account.id.uuidString, name: account.name, kind: account.kindRaw, currency: account.currency,
                      yearlyRate: account.yearlyRate.map(BackupNumber.text), order: account.order,
                      archived: account.archived, createdAt: account.createdAt,
                      subtype: account.subtype, institution: account.institution)
            },
            cuts: cuts.map(row),
            incomes: incomes.map { income in
                .init(id: income.id.uuidString, name: income.name, institution: income.institution,
                      amount: BackupNumber.text(income.amount), currency: income.currency,
                      since: income.since, archived: income.archived, createdAt: income.createdAt,
                      until: income.until)
            },
            drafts: drafts ? halfDone.map(row) : nil)
    }

    /// Replaces «Mi dinero» with the backup's, in one save. A damaged figure stops it whole.
    @MainActor
    static func restoreMoney(_ money: BackupMoney, into container: ModelContainer) throws {
        func number(_ text: String) throws -> Decimal {
            guard let value = BackupNumber.value(text) else { throw Failure.unreadable(.damaged) }
            return value
        }
        func optional(_ text: String?) throws -> Decimal? { try text.map(number) }

        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            for cut in try context.fetch(FetchDescriptor<MoneyCut>()) { context.delete(cut) }
            for entry in try context.fetch(FetchDescriptor<MoneyEntry>()) { context.delete(entry) }
            for account in try context.fetch(FetchDescriptor<MoneyAccount>()) { context.delete(account) }
            // An older file has no incomes: the ones here stay.
            if money.incomes != nil {
                for income in try context.fetch(FetchDescriptor<MoneyIncome>()) { context.delete(income) }
            }
            for row in money.incomes ?? [] {
                let income = MoneyIncome(name: row.name, institution: row.institution, amount: try number(row.amount),
                                         currency: row.currency, since: row.since)
                income.id = UUID(uuidString: row.id) ?? UUID()
                income.archived = row.archived
                if let createdAt = row.createdAt { income.createdAt = createdAt }
                income.until = row.until
                context.insert(income)
            }
            var byID: [String: MoneyAccount] = [:]
            for row in money.accounts {
                let account = MoneyAccount(name: row.name, kind: MoneyKind(rawValue: row.kind) ?? .account,
                                           currency: row.currency, yearlyRate: try optional(row.yearlyRate), order: row.order)
                account.id = UUID(uuidString: row.id) ?? UUID()
                account.archived = row.archived
                account.createdAt = row.createdAt
                account.subtype = row.subtype
                account.institution = row.institution
                context.insert(account)
                byID[row.id] = account
            }
            // The copy taken before a restore also brings the cuts that were half-done.
            let rows = money.cuts.map { ($0, false) } + (money.drafts ?? []).map { ($0, true) }
            for (row, isDraft) in rows {
                let cut = MoneyCut(month: row.month, date: row.date, mainCurrency: row.mainCurrency, isDraft: isDraft)
                cut.id = UUID(uuidString: row.id) ?? UUID()
                cut.rates = row.rates
                if isDraft { cut.reviewedRates = row.reviewedRates ?? "" }
                context.insert(cut)
                for line in row.entries {
                    guard let account = byID[line.account] else { throw Failure.unreadable(.damaged) }
                    // A file from before kept no «reviewed»: a finished cut's lines were all looked at.
                    let entry = MoneyEntry(balance: try number(line.balance), account: account,
                                           reviewed: line.reviewed ?? !isDraft)
                    entry.yieldOverride = try optional(line.yieldOverride)
                    entry.movement = try optional(line.movement)
                    context.insert(entry)
                    entry.cut = cut
                }
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
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
        guard let data = coordinatedRead(url) else { throw Failure.unreadable(.damaged) }
        do { return try BackupSeal.open(data, password: password) } catch let error as BackupError {
            throw Failure.unreadable(error)
        }
    }

    /// Replaces every expense and setting with the backup's, all at once: one save, so it's
    /// either the old data or the new, never a mix. Settings change only after the save.
    /// «Mi dinero» first (a format-1 file has none and leaves it as it is), then the expenses.
    /// Two stores can't be saved as one: if the expenses fail after «Mi dinero» changed, «Mi
    /// dinero» goes back to what it was, so «nothing changed» stays true. The safety copy taken
    /// before covers both anyway.
    @MainActor
    static func restore(_ payload: BackupPayload, into container: ModelContainer, now: Date = AppClock.now) throws {
        // A file without «Mi dinero» never needs it open.
        guard payload.money != nil else { return try restore(payload, into: container, money: nil) }
        // Before anything changes: a backup that can't be turned into expenses, or whose «Mi
        // dinero» wouldn't restore whole, stops here, and a damaged «Mi dinero» is never set
        // aside for nothing (independent review).
        _ = try payload.expenses.map { try Expense(backup: $0) }
        guard payload.money?.isWhole ?? true else { throw Failure.unreadable(.damaged) }
        do {
            try restore(payload, into: container, money: moneyContainer())
        } catch Failure.moneyUnreadable {
            // Once more first: a store busy a moment ago may open now.
            MoneyStore.forget()
            if case .success(let again) = MoneyStore.opened {
                return try restore(payload, into: container, money: again)
            }
            // «Mi dinero» is there and doesn't open: restoring is what fixes it (2026-11-02, second
            // audit). Its files go aside, never deleted, and a new one takes the backup's.
            let moved = try setAsideMoneyFiles(at: MoneyStore.url, now: now)
            MoneyStore.forget()
            guard case .success(let fresh) = MoneyStore.opened else {
                undoSetAside(moved, at: MoneyStore.url)
                throw Failure.moneyNotReady
            }
            do {
                try restore(payload, into: container, money: fresh, wasDamaged: true)
            } catch Failure.halfRestored {
                // «Mi dinero» is the backup's already: that stays, the damaged one aside.
                throw Failure.halfRestored
            } catch {
                // Nothing went in: the new store goes and the old files come back as they were,
                // never an empty «Mi dinero» with the good one hidden.
                undoSetAside(moved, at: MoneyStore.url)
                throw error
            }
        }
    }

    /// Puts set-aside files back where they were, after removing the new store made in their place.
    static func undoSetAside(_ moved: [(from: URL, to: URL)], at url: URL) {
        MoneyStore.forget()
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent()
        for suffix in ["", "-wal", "-shm"] {
            try? manager.removeItem(at: folder.appending(path: url.lastPathComponent + suffix))
        }
        for file in moved { try? manager.moveItem(at: file.to, to: file.from) }
    }

    /// `wasDamaged`: «Mi dinero» was set aside for this restore, so there's nothing to put back
    /// if the expenses fail.
    @MainActor
    static func restore(_ payload: BackupPayload, into container: ModelContainer,
                        money moneyContainer: ModelContainer?, wasDamaged: Bool = false) throws {
        let expenses = try payload.expenses.map { try Expense(backup: $0) }
        var before: BackupMoney?
        if let money = payload.money {
            // The file brings «Mi dinero» and there's none to put it in: nothing changes.
            guard let moneyContainer else { throw Failure.moneyNotReady }
            // Drafts included: if the expenses fail, «Mi dinero» comes back whole.
            if !wasDamaged { before = try moneySnapshot(moneyContainer, drafts: true) }
            try restoreMoney(money, into: moneyContainer)
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            for old in try context.fetch(FetchDescriptor<Expense>()) { context.delete(old) }
            expenses.forEach(context.insert)
            try context.save()
        } catch {
            context.rollback()
            if payload.money != nil, let moneyContainer {
                // «Mi dinero» already changed. Only «nothing changed» if it really went back.
                guard let before else { throw Failure.halfRestored }
                do { try restoreMoney(before, into: moneyContainer) } catch { throw Failure.halfRestored }
            }
            throw error
        }
        Settings.restore(payload.settings)
        // «Aparte» compared the data that was just replaced (2026-11-11): the next backup says.
        UserDefaults.standard.removeObject(forKey: asideKey)
        WidgetBridge.refreshAfterIntent()
    }

    /// Moves a store that doesn't open, with its `-wal` and `-shm`, to «dinero.store.danado-<fecha>»
    /// next to it: never deleted, and a new store can be made in its place. All or nothing: a
    /// journal left behind would be read into the new store.
    @discardableResult
    static func setAsideMoneyFiles(at url: URL, now: Date = AppClock.now) throws -> [(from: URL, to: URL)] {
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent()
        var base = url.lastPathComponent + ".danado-" + BackupRetention.stamp(now, withTime: true)
        var extra = 1
        while manager.fileExists(atPath: folder.appending(path: base).path(percentEncoded: false)) {
            extra += 1
            base = url.lastPathComponent + ".danado-" + BackupRetention.stamp(now, withTime: true) + "-\(extra)"
        }
        var moved: [(from: URL, to: URL)] = []
        for suffix in ["", "-wal", "-shm"] {
            let from = folder.appending(path: url.lastPathComponent + suffix)
            guard manager.fileExists(atPath: from.path(percentEncoded: false)) else { continue }
            let to = folder.appending(path: base + suffix)
            do {
                try manager.moveItem(at: from, to: to)
                moved.append((from, to))
            } catch {
                for file in moved { try? manager.moveItem(at: file.to, to: file.from) }
                throw Failure.moneyNotReady
            }
        }
        return moved
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
        row.fixedID = fixedID
        row.fixedOf = fixedOf
        row.maybeRepeated = maybeRepeated
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
        fixedID = row.fixedID
        fixedOf = row.fixedOf
        maybeRepeated = row.maybeRepeated
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

    /// What the Keychain says: the password, that there is none, or that it can't be read right
    /// now (locked since the phone was turned on, or another error). Only `missing` means
    /// «create one» (2026-11-02, second audit: a locked Keychain at night said so, wrongly).
    enum Lookup: Equatable {
        case found(String)
        case missing
        case unavailable(OSStatus)
    }

    static func lookup() -> Lookup {
        var item: CFTypeRef?
        var ask = query
        ask[kSecReturnData as String] = true
        ask[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(ask as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
                return .unavailable(errSecDecode)
            }
            return .found(password)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable(status)
        }
    }

    /// The password, or only when there is none, «create one».
    static func current() throws -> String {
        switch lookup() {
        case .found(let password): return password
        case .missing: throw DailyBackup.Failure.noPassword
        case .unavailable: throw DailyBackup.Failure.passwordUnavailable
        }
    }

    static func read() -> String? {
        if case .found(let password) = lookup() { return password }
        return nil
    }

    /// Changes the one there is, or adds it if there's none. Never deletes first: a failed add
    /// after a delete left the phone with no password at all.
    @discardableResult
    static func save(_ password: String) -> Bool {
        let data = Data(password.utf8)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var add = query
        add[kSecValueData as String] = data
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
