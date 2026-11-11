import CentavoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// «Respaldo diario» in Ajustes: the password, the folder, a backup now, and restoring one.
/// The nightly run itself is an automation in Atajos with «Respaldar Al día».
struct BackupSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasPassword = BackupPassword.lookup() != .missing
    @State private var newPassword = ""
    @State private var repeated = ""
    @State private var changingPassword = false
    @State private var shownPassword: String?

    @State private var folderName = DailyBackup.folderName
    @State private var choosingFolder = false

    @State private var last = DailyBackup.lastBackup
    @State private var cloud = DailyBackup.cloudState()
    /// The folder picked is only on this phone: said once, when it's picked.
    @State private var localFolder = false
    @State private var working = false
    @State private var problem: String?
    @State private var problemTitle = ""

    @State private var choosingFile = false
    @State private var fileToOpen: URL?
    @State private var typedPassword = ""
    @State private var askingPassword = false
    /// The password typed a moment ago didn't open the file: the alert says so.
    @State private var wrongTry = false
    @State private var pending: BackupPayload?
    /// The password that opened `pending`, to lock the safety copy when this phone has none.
    @State private var openedWith: String?
    @State private var restored: BackupSummary?

    private static let minimumLength = 8

    var body: some View {
        Form {
            passwordSection
            folderSection
            nowSection
            dailySection
            restoreSection
        }
        .ticketForm()
        .foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .ticketBarTitle("Respaldo")
        // The check before «Cambiar contraseña» is for who's holding the phone now: leaving the
        // app closes the form, so coming back asks again.
        .onChange(of: scenePhase) { _, phase in
            // Shown after Face ID, it would stay in the app switcher's picture and be there on return.
            if phase != .active { shownPassword = nil }
            if phase == .background, changingPassword { cancelChanging() }
        }
        .onDisappear { shownPassword = nil }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do {
                try DailyBackup.choose(folder: url)
                folderName = DailyBackup.folderName
                localFolder = !DailyBackup.isInCloud(url)
            } catch {
                fail("No se pudo usar esa carpeta", "Elige otra.")
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.aldiaBackup, .data]) { result in
            guard case .success(let url) = result else { return }
            open(url, password: BackupPassword.read())
        }
        .alert("Contraseña del respaldo", isPresented: $askingPassword) {
            SecureField("Contraseña", text: $typedPassword)
            Button("Cancelar", role: .cancel) { typedPassword = ""; wrongTry = false }
            Button("Abrir") {
                if let fileToOpen { open(fileToOpen, password: typedPassword, typed: true) }
                typedPassword = ""
            }
        } message: {
            Text(wrongTry ? "Esa contraseña no abre este respaldo. Prueba otra vez."
                          : "Escribe la contraseña con la que se guardó este respaldo.")
        }
        .alert("¿Restaurar este respaldo?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Cancelar", role: .cancel) { pending = nil }
            Button("Restaurar", role: .destructive) { if let pending { restore(pending) } }
        } message: {
            if let pending { Text(Self.describe(pending.summary) + "\n\nReemplaza todo lo que hay en este iPhone, y en tus otros dispositivos si usan Al día con iCloud. Antes se guarda una copia de lo actual en tu carpeta.") }
        }
        .alert("Listo", isPresented: Binding(get: { restored != nil }, set: { if !$0 { restored = nil } })) {
            Button("Aceptar", role: .cancel) { restored = nil }
        } message: {
            if let restored {
                Text(restored.expenseCount == 1 ? "Se restauró 1 gasto y tus ajustes."
                     : "Se restauraron \(restored.expenseCount) gastos y tus ajustes.")
            }
        }
        .alert("Esa carpeta está solo en este iPhone", isPresented: $localFolder) {
            Button("Elegir otra") { choosingFolder = true }
            Button("Usarla así", role: .cancel) {}
        } message: {
            Text("Si pierdes el iPhone, el respaldo se pierde con él. Elige una carpeta dentro de iCloud Drive.")
        }
        .onAppear { cloud = DailyBackup.cloudState() }
        .alert(problemTitle, isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("Aceptar", role: .cancel) { problem = nil }
        } message: {
            Text(problem ?? "")
        }
    }

    // MARK: Sections

    private var passwordSection: some View {
        Section {
            if hasPassword && !changingPassword {
                Button {
                    Task { await reveal() }
                } label: {
                    IconRow("Ver contraseña", systemImage: "faceid") {
                        if let shownPassword {
                            Text(shownPassword)
                                .font(.ticket(.footnote))
                                .foregroundStyle(Theme.ink)
                                .textSelection(.enabled)
                        }
                    }
                }
                .accessibilityIdentifier("respaldo-ver-contrasena")
                Button { Task { await startChanging() } } label: {
                    IconRow("Cambiar contraseña", systemImage: "key") { EmptyView() }
                }
                .accessibilityIdentifier("respaldo-cambiar-contrasena")
            } else {
                SecureField("Contraseña", text: $newPassword,
                            prompt: Text("Contraseña, mínimo \(Self.minimumLength)").foregroundStyle(Theme.faint))
                    .font(.ticket(.field))
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("respaldo-contrasena")
                SecureField("Repítela", text: $repeated, prompt: Text("Repítela").foregroundStyle(Theme.faint))
                    .font(.ticket(.field))
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("respaldo-repite")
                if let passwordProblem {
                    NoteText(passwordProblem, color: Theme.danger)
                        .accessibilityIdentifier("respaldo-contrasena-problema")
                }
                Button(action: savePassword) {
                    LinkActionLabel("Guardar contraseña", alignment: .leading)
                }
                .disabled(!passwordIsValid)
                .accessibilityIdentifier("respaldo-guardar-contrasena")
                if hasPassword {
                    Button(action: cancelChanging) {
                        Text("Cancelar")
                            .font(.ticket(.body))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
                    }
                    .accessibilityIdentifier("respaldo-cancelar-cambio")
                }
            }
        } header: {
            Text("Contraseña").ticketCaption()
        } footer: {
            HintText(!hasPassword
                     ? "Guárdala también en la app Contraseñas: si pierdes este iPhone, la vas a necesitar para abrir tu respaldo en otro. Sin ella, nadie puede abrirlo."
                     : changingPassword
                     ? "Los respaldos que ya tienes se abren con la contraseña anterior. Guárdala también."
                     : "Sin ella el respaldo no se puede abrir, ni por ti ni por nadie. Guárdala también en la app Contraseñas.")
        }
        .listRowBackground(Theme.surface)
    }

    private var folderSection: some View {
        Section {
            Button { choosingFolder = true } label: {
                IconRow("Carpeta", systemImage: "folder") {
                    Text(folderName ?? "Elegir")
                        .font(.ticket(.detail))
                        .foregroundStyle(folderName == nil ? Theme.brass : Theme.muted)
                }
            }
            .accessibilityIdentifier("respaldo-carpeta")
        } header: {
            Text("Dónde se guarda").ticketCaption()
        } footer: {
            HintText("Elige o crea una carpeta «Al día» en iCloud Drive: así el respaldo vive fuera de este iPhone. Se guardan los últimos 30 días y uno por mes.")
        }
        .listRowBackground(Theme.surface)
    }

    private var nowSection: some View {
        Section {
            Button(action: backUpNow) {
                IconRow("Respaldar ahora", systemImage: "arrow.clockwise.icloud") {
                    if working { ProgressView() }
                }
            }
            .disabled(!hasPassword || folderName == nil || working)
            .accessibilityIdentifier("respaldo-ahora")
        } footer: {
            HintText(lastText)
        }
        .listRowBackground(Theme.surface)
    }

    private var dailySection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                NoteText("1. Abre Atajos → Automatización → «+».", color: Theme.ink)
                NoteText("2. Elige «Hora del día»: 21:00, diario, y «Ejecutar de inmediato».", color: Theme.ink)
                NoteText("3. Agrega la acción «Respaldar Al día».", color: Theme.ink)
            }
            .padding(.vertical, Theme.Space.xxs)
        } header: {
            Text("Cada día, solo").ticketCaption()
        } footer: {
            HintText("A las 21:00 el iPhone suele estar despierto. Si un día no se respalda, aquí lo verás y «Hoy» te avisará.")
        }
        .listRowBackground(Theme.surface)
    }

    private var restoreSection: some View {
        Section {
            Button { Task { await startRestoring() } } label: {
                IconRow("Restaurar respaldo", systemImage: "clock.arrow.circlepath") { EmptyView() }
            }
            .disabled(working)
            .accessibilityIdentifier("respaldo-restaurar")
        } footer: {
            HintText("Primero confirmas que eres tú. Antes de restaurar ves de qué día es y cuántos gastos trae. Nada cambia hasta que confirmas.")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: Actions

    private var passwordIsValid: Bool {
        newPassword.count >= Self.minimumLength && newPassword == repeated
    }

    /// Why «Guardar contraseña» is off, once there's something typed to say it about.
    private var passwordProblem: String? {
        if !newPassword.isEmpty, newPassword.count < Self.minimumLength { return "Mínimo \(Self.minimumLength) caracteres." }
        if !repeated.isEmpty, repeated != newPassword { return "No coinciden." }
        return nil
    }

    private var lastText: String {
        guard let last else { return hasPassword && folderName != nil ? "Todavía no hay respaldo." : "Primero la contraseña y la carpeta." }
        var text = "Último respaldo: " + AppClock.relative(last, locale: Locale(identifier: "es_MX"))
        switch cloud {
        case .uploading: text += ". Guardado, aún no sube a iCloud."
        case .failed: text += ". Guardado en el iPhone, pero no pudo subir a iCloud: revisa que tengas espacio."
        case .local: text += ". Está solo en este iPhone: elige una carpeta en iCloud Drive."
        case .uploaded, nil: break
        }
        if let failed = DailyBackup.lastFailure, failed > last {
            text += "\nEl último intento no se pudo hacer."
        }
        return text
    }

    private func savePassword() {
        guard passwordIsValid else { return }
        guard BackupPassword.save(newPassword) else {
            fail("No se guardó la contraseña",
                 hasPassword ? "La anterior sigue igual. Intenta otra vez." : "Intenta otra vez. Sin contraseña no se puede respaldar.")
            return
        }
        newPassword = ""
        repeated = ""
        hasPassword = true
        changingPassword = false
    }

    /// «Cambiar contraseña» asks the owner first (2026-11-02 audit): whoever holds the phone
    /// shouldn't be able to lock the next backups with a password only they know.
    private func startChanging() async {
        guard await OwnerCheck.confirm(reason: "Para cambiar la contraseña del respaldo.") else { return }
        shownPassword = nil
        changingPassword = true
    }

    private func cancelChanging() {
        newPassword = ""
        repeated = ""
        changingPassword = false
    }

    /// Restoring opens a backup with the saved password and replaces everything: the owner first.
    private func startRestoring() async {
        guard await OwnerCheck.confirm(reason: "Para restaurar un respaldo.") else { return }
        choosingFile = true
    }

    private func reveal() async {
        if shownPassword != nil { shownPassword = nil; return }
        if await BackupPassword.unlock(reason: "Para mostrar la contraseña del respaldo.") {
            shownPassword = BackupPassword.read()
        }
    }

    /// The file is locked and written off the main thread: the screen keeps moving meanwhile.
    private func backUpNow() {
        working = true
        Task {
            defer { working = false }
            do {
                last = try await DailyBackup.runNow(in: context)
                cloud = DailyBackup.cloudState()
            } catch {
                fail("No se pudo respaldar", message(for: error))
            }
        }
    }

    private func open(_ url: URL, password: String?, typed: Bool = false) {
        fileToOpen = url
        wrongTry = false
        guard let password else { askingPassword = true; return }
        working = true
        // The key takes a moment to derive: off the main thread, so the screen doesn't freeze.
        Task {
            defer { working = false }
            do {
                pending = try await Task.detached { try DailyBackup.read(url, password: password) }.value
                openedWith = password
            } catch DailyBackup.Failure.unreadable(.wrongPassword) {
                // The saved one not opening it is the first ask; a typed one is a retry.
                wrongTry = typed
                askingPassword = true
            } catch {
                fail("No se pudo abrir el respaldo", message(for: error))
            }
        }
    }

    private func restore(_ payload: BackupPayload) {
        pending = nil
        working = true
        Task {
            defer { working = false }
            do {
                // The current data is kept first, locked with the password that's set (or the
                // backup's own, typed a moment ago, when this phone has none yet).
                if let password = BackupPassword.read() ?? openedWith {
                    try await DailyBackup.safetyCopy(in: context, password: password)
                }
                try DailyBackup.restore(payload, into: context.container)
                restored = payload.summary
            } catch {
                fail("No se pudo restaurar", message(for: error))
            }
        }
    }

    /// An alert that says what didn't work in its title, and why or what to do below.
    private func fail(_ title: String, _ detail: String) {
        problemTitle = title
        problem = detail
    }

    /// «1 gasto», «3 gastos».
    private static func count(_ number: Int, _ one: String, _ many: String) -> String {
        number == 1 ? "1 \(one)" : "\(number) \(many)"
    }

    private func message(for error: Error) -> String {
        if let failure = error as? DailyBackup.Failure { return String(localized: failure.localizedStringResource) }
        return "Algo falló al guardar. No se cambió nada."
    }

    private static func describe(_ summary: BackupSummary) -> String {
        let mx = Locale(identifier: "es_MX")
        let made = summary.createdAt.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(mx))
        var text = "Del \(made): " + count(summary.expenseCount, "gasto", "gastos")
        if let first = summary.firstExpense, let lastOne = summary.lastExpense {
            let style = Date.FormatStyle.dateTime.month(.abbreviated).year().locale(mx)
            text += " (de \(first.formatted(style)) a \(lastOne.formatted(style)))"
        }
        if let accounts = summary.accountCount, let cuts = summary.cutCount {
            text += ", y «Mi dinero» con " + count(accounts, "cuenta", "cuentas") + " y " + count(cuts, "corte", "cortes")
        } else {
            text += ". No trae «Mi dinero»: el tuyo se queda como está"
        }
        return text + "."
    }
}

extension UTType {
    /// The backup file, so the picker doesn't grey it out.
    static let aldiaBackup = UTType(exportedAs: "com.blandisc.centavo.respaldo", conformingTo: .data)
}

#Preview {
    NavigationStack { BackupSettingsView() }
        .ticketPreview()
}
