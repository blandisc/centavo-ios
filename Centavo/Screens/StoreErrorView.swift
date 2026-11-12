import CentavoCore
import SwiftData
import SwiftUI

/// Shown instead of the app when the on-device store cannot be opened. It scrolls, so the
/// largest accessibility text sizes never cut it short (2026-11-02, second audit).
///
/// It used to be words alone, the same whatever happened (2026-11-11, map of states). Now it
/// says the cause when it's known, tries again without closing the app, and gives a way out:
/// the stores' own files, copied to Archivos as they are. Restoring isn't offered from here:
/// without a store there's nowhere to restore to (2026-11-02).
struct StoreErrorView: View {
    /// Why the store didn't open, as far as it can be known.
    let trouble: StoreTrouble
    /// Opens the store again; `true` when it opened (and this screen goes away).
    let retry: () -> Bool

    /// «Intentar de nuevo» was tapped and it still doesn't open.
    @State private var stillShut = false
    /// The folder with the copy, waiting for the person to say where it goes.
    @State private var copy: URL?
    @State private var exporting = false
    @State private var copyNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("Al día")
                        .font(.ticket(.footnoteStrong))
                        .tracking(Theme.Tracking.title)
                        .textCase(.uppercase)
                    Text(trouble.title)
                        .font(.ticket(.heading))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("error-base")
                    Text(trouble.explanation)
                        .font(.ticket(.callout))
                        .lineSpacing(Theme.Space.xxs)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("error-base-causa")
                }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Button(action: tryAgain) { PrimaryButtonLabel("Intentar de nuevo", systemImage: "arrow.clockwise") }
                        .ticketProminent()
                        .accessibilityIdentifier("error-base-reintentar")
                    if stillShut {
                        NoteText(Self.stillShutText, color: Theme.ink)
                            .accessibilityIdentifier("error-base-sigue")
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Button { Task { await saveCopy() } } label: {
                        LinkActionLabel("Guardar una copia de mis datos", systemImage: "square.and.arrow.down",
                                        alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("error-base-copia")
                    HintText(Self.copyHint)
                    if let copyNote {
                        NoteText(copyNote, color: Theme.ink)
                            .accessibilityIdentifier("error-base-copia-nota")
                    }
                }
            }
            .padding(Theme.Space.screen)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.background.ignoresSafeArea())
        .fileMover(isPresented: $exporting, file: copy) { result in
            switch result {
            case .success(let url): copyNote = "Copia guardada en Archivos, en la carpeta «\(url.lastPathComponent)»."
            case .failure: copyNote = Self.copyFailedText
            }
            StoreFiles.discard(copy)
            copy = nil
        } onCancellation: {
            StoreFiles.discard(copy)
            copy = nil
        }
    }

    static let stillShutText = "Todavía no abre. Puedes intentarlo otra vez más tarde; mientras, guarda una copia de tus datos."
    static let copyHint = "Guarda en Archivos los archivos de Al día tal como están, para que no dependan de la app. Con esa copia puedes pedir ayuda para recuperar tus gastos. No lleva contraseña y trae también «Mi dinero»: guárdala donde solo tú la veas."
    static let copyFailedText = "No se pudo guardar la copia. Tus datos siguen donde estaban. Intenta otra vez."
    static let nothingToCopyText = "No se encontraron archivos de Al día para copiar."
    static let copyNotMadeText = "No se pudo preparar la copia. Tus datos siguen donde estaban. Si el iPhone no tiene espacio, libera un poco e intenta otra vez."

    private func tryAgain() {
        stillShut = !retry()
    }

    /// The owner first: the copy isn't locked and brings «Mi dinero», which sits behind Face ID.
    private func saveCopy() async {
        guard !exporting else { return }
        guard await OwnerCheck.confirm(reason: "Para guardar una copia de tus datos.") else { return }
        copyNote = nil
        do {
            guard let folder = try StoreFiles.copyOut() else {
                copyNote = Self.nothingToCopyText
                return
            }
            copy = folder
            exporting = true
        } catch {
            copyNote = Self.copyNotMadeText
        }
    }
}

/// The stores' files as they are on the phone: the way out when the expenses don't open.
enum StoreFiles {
    /// The expenses' store and «Mi dinero», each with its journal, and any «Mi dinero» that was
    /// set aside damaged: every file there is, in the folders where the two stores live.
    static func all(in folders: [URL] = folders, store: String = Store.url.lastPathComponent) -> [URL] {
        var seen = Set<String>()
        return folders.flatMap { folder -> [URL] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            return names.sorted().filter { StoreTrouble.isStoreFile($0, store: store) }.map { folder.appending(path: $0) }
        }
        .filter { seen.insert($0.standardizedFileURL.path(percentEncoded: false)).inserted }
    }

    static var folders: [URL] {
        [Store.url.deletingLastPathComponent(), MoneyStore.url.deletingLastPathComponent()]
    }

    /// Copies them, untouched, into a new folder in the temporary directory («Al día - copia de
    /// datos 2026-11-11T214000») and returns it, or `nil` when there's no file to copy. On the
    /// phone's own disk a copy takes no extra room until one of the two changes, so it works
    /// with the phone full. All or nothing: a folder with only some files is never handed over.
    static func copyOut(_ files: [URL] = all(), to parent: URL = FileManager.default.temporaryDirectory,
                        now: Date = AppClock.now) throws -> URL? {
        guard !files.isEmpty else { return nil }
        let manager = FileManager.default
        let folder = parent.appending(path: "Al día - copia de datos " + BackupRetention.stamp(now, withTime: true))
        try? manager.removeItem(at: folder)
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in files {
                try manager.copyItem(at: file, to: folder.appending(path: file.lastPathComponent))
            }
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
        return folder
    }

    /// The temporary copy, once it was moved out or the person changed their mind.
    static func discard(_ folder: URL?) {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// The error and every error under it, as `StoreTrouble` reads them.
    static func codes(of error: Error) -> [StoreTrouble.Code] {
        var found: [StoreTrouble.Code] = []
        var pending = [error as NSError]
        while let next = pending.popLast(), found.count < 32 {
            found.append(.init(domain: next.domain, code: next.code))
            pending.append(contentsOf: next.underlyingErrors.map { $0 as NSError })
        }
        return found
    }

    /// How much room the phone says it has for the app's data, or `nil` if it doesn't say.
    static var freeBytes: Int64? {
        let values = try? URL.applicationSupportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func trouble(of error: Error) -> StoreTrouble {
        StoreTrouble.cause(codes: codes(of: error), freeBytes: freeBytes)
    }
}

#Preview { StoreErrorView(trouble: .unknown, retry: { false }).ticketPreview() }
