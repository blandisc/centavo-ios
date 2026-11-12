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
    /// What the folder being picked is for: one picker for the three.
    @State private var folderPurpose = FolderPurpose.backup

    @State private var last = DailyBackup.lastBackup
    @State private var cloud = DailyBackup.cloudState()
    /// The last backup was written apart (this phone had less than the one in the folder).
    @State private var aside = DailyBackup.aside
    @State private var confirmingTrust = false
    /// How many expenses this phone has when «Este iPhone es el bueno» is tapped.
    @State private var countNow: Int?
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
    /// What a restore has to do first with what's on this phone, read when the file opens.
    @State private var safetyPlan = BackupSafetyPlan.copyToFolder
    /// A restore that worked: what it brought, where the copy of before went, and whether
    /// «Seguir respaldando aquí» is offered.
    @State private var outcome: RestoreOutcome?
    /// The copy before restoring couldn't be written to the folder: another one is asked for.
    @State private var needsCopyFolder: BackupPayload?
    /// This phone was restored and has no daily backup set up: a line says so.
    @State private var notSetUp = DailyBackup.needsSetUpAfterRestore
    /// «Seguir respaldando aquí» worked: what's set, and what's still missing (the automation).
    @State private var setUpMessage: String?

    /// Copies «antes de restaurar» left inside the app by earlier restores.
    @State private var copies = DailyBackup.strandedCopies()
    @State private var removingCopy: BackupSafetyCopy?
    @State private var movingCopy: URL?
    @State private var moving = false

    private static let minimumLength = 8

    var body: some View {
        withPickers
            .modifier(RestoreAlerts(pending: $pending, outcome: $outcome, needsCopyFolder: $needsCopyFolder,
                                    question: restoreQuestion, done: doneText,
                                    restore: { restore($0) }, pickCopyFolder: askCopyFolder,
                                    keep: { Task { await keepBackingUp() } },
                                    later: { DailyBackup.sayLater() }))
            .alert("Respaldo configurado", isPresented: Self.shown($setUpMessage)) {
                Button("Aceptar", role: .cancel) { setUpMessage = nil }
            } message: {
                Text(setUpMessage ?? "")
            }
            .alert("Esa carpeta está solo en este iPhone", isPresented: $localFolder) {
                Button("Elegir otra") { choosingFolder = true }
                Button("Usarla así", role: .cancel) {}
            } message: {
                Text("Si pierdes el iPhone, el respaldo se pierde con él. Elige una carpeta dentro de iCloud Drive.")
            }
            .alert(problemTitle, isPresented: Self.shown($problem)) {
                Button("Aceptar", role: .cancel) { problem = nil }
            } message: {
                Text(problem ?? "")
            }
            .confirmsRemoval(of: $removingCopy, question: { copy in
                TicketQuestion(title: "¿Borrar esta copia?", name: copy.title(now: AppClock.now),
                               detail: "Antes de restaurar",
                               note: "Es lo que había en este iPhone antes de esa restauración. No se puede deshacer.")
            }) { copy in
                DailyBackup.removeStranded(copy)
                copies = DailyBackup.strandedCopies()
            }
    }

    /// The form itself. Apart from `body`: the CI's compiler gives up on one long chain.
    private var form: some View {
        Form {
            notSetUpSection
            passwordSection
            folderSection
            nowSection
            dailySection
            restoreSection
            copiesSection
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
            // The nightly run may have happened while the app was away.
            if phase == .active { aside = DailyBackup.aside }
            if phase == .background, changingPassword { cancelChanging() }
        }
        .onDisappear { shownPassword = nil }
        .onAppear {
            cloud = DailyBackup.cloudState()
            aside = DailyBackup.aside
        }
        // The copies that are also in the folder, byte for byte, don't need to stay in the app.
        .task {
            await Task.detached { _ = DailyBackup.tidyStrandedCopies() }.value
            copies = DailyBackup.strandedCopies()
        }
    }

    /// The system's pickers: a folder (for the backup, for the copy before restoring, or to keep
    /// backing up here), the file to restore, and where a copy left in the app goes.
    private var withPickers: some View {
        form
            // The form with a cancel: closing the picker without a folder has to be known (the
            // copy before a restore).
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false,
                          onCompletion: { pickedFolder($0.map(\.first)) }, onCancellation: { pickedFolder(.success(nil)) })
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
            // On its own view: two pickers of the same kind on one view can hide each other.
            .background {
                Color.clear.fileMover(isPresented: $moving, file: movingCopy) { result in
                    movingCopy = nil
                    copies = DailyBackup.strandedCopies()
                    if case .failure = result {
                        fail("No se guardó la copia", "Sigue guardada dentro de Al día. Intenta otra vez.")
                    }
                }
            }
    }

    // MARK: Sections

    /// A restored phone without a daily backup: said here until it's set up, and in «Hoy».
    @ViewBuilder private var notSetUpSection: some View {
        if notSetUp && !(hasPassword && folderName != nil) {
            Section {
                NoteText(BackupSetupReminder.text, color: Theme.ink)
                    .padding(.vertical, Theme.Space.xxs)
                    .accessibilityIdentifier("respaldo-sin-configurar")
                    // Seen here, «Hoy» doesn't repeat it for a week.
                    .onAppear { DailyBackup.sayLater() }
                if openedWith != nil || hasPassword {
                    Button { Task { await keepBackingUp() } } label: {
                        IconRow("Seguir respaldando aquí", systemImage: "arrow.triangle.2.circlepath") { EmptyView() }
                    }
                    .disabled(working)
                    .accessibilityIdentifier("respaldo-seguir-aqui")
                }
            } footer: {
                HintText("Restauraste tus datos en este iPhone, pero aquí todavía no se respaldan: la contraseña, la carpeta y la automatización de Atajos no viajan en el respaldo. Todo se configura en esta pantalla.")
            }
            .listRowBackground(Theme.surface)
        }
    }

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
            if let aside {
                asideNote(aside)
                trustButton
                restoreInsteadButton
            }
        } footer: {
            HintText(aside == nil ? lastText : lastText + "\n" + Self.asideHint)
        }
        .listRowBackground(Theme.surface)
    }

    /// Why the last backup went apart, in one line; what to do about it are the two rows under
    /// it, each with its case (owner, 2026-11-11: it was fifty words with both ways mixed).
    private func asideNote(_ aside: BackupAsideNote) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            SectionLabel("Respaldo guardado aparte")
                .accessibilityAddTraits(.isHeader)
            NoteText(Self.asideText(aside), color: Theme.ink)
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("respaldo-aparte")
    }

    /// One way out of a backup apart: when it applies, quiet, over what it does, in brass.
    private func asideChoice(_ when: String, _ action: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(when)
                .font(.ticket(.detail))
                .foregroundStyle(Theme.muted)
            Text(action)
                .font(.ticket(.body))
                .foregroundStyle(Theme.brass)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Size.tallRow, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// «Aquí falta algo»: the same restore as the row further down, offered where it is needed.
    private var restoreInsteadButton: some View {
        Button { Task { await startRestoring() } } label: {
            asideChoice("Aquí falta algo", "Restaurar el respaldo anterior")
        }
        .disabled(working)
        .accessibilityIdentifier("respaldo-aparte-restaurar")
    }

    /// «Este iPhone es el bueno»: asks, checks it's the owner, and writes the daily file from
    /// this phone even with less. The dialog is this screen's own for now.
    private var trustButton: some View {
        Button {
            countNow = try? context.fetchCount(FetchDescriptor<Expense>())
            confirmingTrust = true
        } label: {
            asideChoice("Aquí está lo correcto", "Este iPhone es el bueno")
        }
        .disabled(working)
        .accessibilityIdentifier("respaldo-este-iphone")
        .confirmationDialog("¿Respaldar desde este iPhone?", isPresented: $confirmingTrust, titleVisibility: .visible) {
            Button("Este iPhone es el bueno") { Task { await trustThisPhone() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(Self.trustQuestion(expenses: countNow))
        }
    }

    static func asideText(_ aside: BackupAsideNote, now: Date = AppClock.now) -> String {
        aside.reason(now: now)
    }

    static let asideHint = "El respaldo anterior sigue en tu carpeta, sin cambios."

    /// `expenses`: what this phone has right now, which may no longer be what the note said.
    static func trustQuestion(expenses: Int?) -> String {
        let has = expenses.map { "Este iPhone tiene ahora " + count($0, "gasto", "gastos") + ". " } ?? ""
        return has + "El respaldo de hoy se guardará con lo que hay en este iPhone, aunque tenga menos. El respaldo que tenía más no se borra: queda guardado con «reemplazado» en el nombre."
    }

    private var dailySection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(Self.automationSteps, id: \.self) { NoteText($0, color: Theme.ink) }
            }
            .padding(.vertical, Theme.Space.xxs)
        } header: {
            Text("Cada día, solo").ticketCaption()
        } footer: {
            HintText("A las 21:00 el iPhone suele estar despierto. Si un día no se respalda, aquí lo verás y «Hoy» te avisará.")
        }
        .listRowBackground(Theme.surface)
    }

    /// How to make the nightly automation: on this screen, and said again when a restored phone
    /// starts backing up (the automation doesn't travel either).
    static let automationSteps = ["1. Abre Atajos → Automatización → «+».",
                                  "2. Elige «Hora del día»: 21:00, diario, y «Ejecutar de inmediato».",
                                  "3. Agrega la acción «Respaldar Al día»."]

    /// Copies «antes de restaurar» that earlier restores left inside the app, where Archivos
    /// doesn't show them (2026-11-11): each can be restored, taken out to Archivos or deleted.
    @ViewBuilder private var copiesSection: some View {
        if !copies.isEmpty {
            Section {
                ForEach(copies) { copy in
                    Menu {
                        Button("Restaurar", systemImage: "clock.arrow.circlepath") { Task { await restoreCopy(copy) } }
                        Button("Guardar en Archivos", systemImage: "folder") { move(copy) }
                        Button("Borrar", systemImage: "trash", role: .destructive) { removingCopy = copy }
                    } label: {
                        IconRow(copy.title(now: AppClock.now), systemImage: "doc.badge.clock") {
                            Image(systemName: "ellipsis")
                                .font(Theme.Symbol.regular)
                                .foregroundStyle(Theme.muted)
                                .accessibilityHidden(true)
                        }
                    }
                    .disabled(working)
                    .accessibilityIdentifier("respaldo-copia")
                }
            } header: {
                Text("Copias de antes de restaurar").ticketCaption()
            } footer: {
                HintText("Lo que había en este iPhone justo antes de restauraciones anteriores. Quedaron guardadas dentro de Al día, donde Archivos no las muestra. Toca una para restaurarla o para guardarla en Archivos (al guardarla sale de esta lista). Se abren con la contraseña del respaldo que tenías ese día.")
            }
            .listRowBackground(Theme.surface)
        }
    }

    private var restoreSection: some View {
        Section {
            Button { Task { await startRestoring() } } label: {
                IconRow("Restaurar respaldo", systemImage: "clock.arrow.circlepath") { EmptyView() }
            }
            .disabled(working)
            .accessibilityIdentifier("respaldo-restaurar")
        } footer: {
            HintText("Primero confirmas que eres tú. Antes de restaurar ves de qué día es y cuántos gastos trae. Nada cambia hasta que confirmas, y antes se guarda una copia de lo que hay en este iPhone en una carpeta que puedas abrir en Archivos.")
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
        guard !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                last = try await DailyBackup.runNow(in: context)
                cloud = DailyBackup.cloudState()
            } catch {
                failBackup(error)
            }
            aside = DailyBackup.aside
        }
    }

    /// A backup that did nothing because another one is being written isn't a problem to show.
    private func failBackup(_ error: Error) {
        if case DailyBackup.Failure.busy = error { return }
        fail("No se pudo respaldar", message(for: error))
    }

    /// After the dialog: the owner first, like «Cambiar contraseña» and restoring. Whoever holds
    /// the phone shouldn't be able to make a phone with less the backup of every day.
    private func trustThisPhone() async {
        guard !working else { return }
        guard await OwnerCheck.confirm(reason: "Para respaldar desde este iPhone aunque tenga menos.") else { return }
        // Again: «Respaldar ahora» may have been tapped while Face ID was asking.
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            last = try await DailyBackup.runNow(in: context, trustingThisPhone: true)
            cloud = DailyBackup.cloudState()
        } catch {
            failBackup(error)
        }
        aside = DailyBackup.aside
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
                let payload = try await Task.detached { try DailyBackup.read(url, password: password) }.value
                openedWith = password
                safetyPlan = DailyBackup.safetyPlan(in: context)
                pending = payload
            } catch DailyBackup.Failure.unreadable(.wrongPassword) {
                // The saved one not opening it is the first ask; a typed one is a retry.
                wrongTry = typed
                askingPassword = true
            } catch {
                fail("No se pudo abrir el respaldo", message(for: error))
            }
        }
    }

    /// Restores, keeping first a copy of what's here where the person can see it: in the
    /// backup's folder or in `chosen`, picked for this copy. With something to keep and no
    /// folder, the picker comes first; without one nothing is replaced (2026-11-11).
    private func restore(_ payload: BackupPayload, copyInto chosen: URL? = nil) {
        pending = nil
        guard !working else { return }
        if chosen == nil, DailyBackup.safetyPlan(in: context) == .askWhere {
            askCopyFolder(for: payload)
            return
        }
        // The copy is locked with the password that's set (or the backup's own, typed a moment
        // ago, when this phone has none yet).
        let saved = BackupPassword.read()
        guard let password = saved ?? openedWith else {
            fail("No se pudo restaurar", "Abre el respaldo otra vez. No se cambió nada.")
            return
        }
        working = true
        Task {
            defer { working = false }
            do {
                let copy = try await DailyBackup.restoreKeepingCopy(payload, in: context, password: password,
                                                                    copyInto: chosen)
                DailyBackup.noteRestored()
                let offers = !DailyBackup.isSetUp
                notSetUp = offers
                outcome = RestoreOutcome(summary: payload.summary, copy: copy, copyUsesSavedPassword: saved != nil,
                                         offersSetUp: offers, hasPassword: BackupPassword.lookup() != .missing)
                aside = DailyBackup.aside
            } catch DailyBackup.Failure.copyNotSaved where chosen == nil {
                // The backup's folder didn't take the copy: another one, or nothing is restored.
                needsCopyFolder = payload
            } catch DailyBackup.Failure.noPlaceForCopy {
                needsCopyFolder = payload
            } catch DailyBackup.Failure.halfRestored {
                let place = chosen?.lastPathComponent ?? folderName
                fail("No se pudo restaurar", message(for: DailyBackup.Failure.halfRestored)
                     + (place.map { " Está en «\($0)»." } ?? ""))
            } catch {
                fail("No se pudo restaurar", message(for: error))
            }
        }
    }

    private func askCopyFolder(for payload: BackupPayload) {
        needsCopyFolder = nil
        folderPurpose = .safetyCopy(payload)
        choosingFolder = true
    }

    /// The folder picker closed: with a folder, or without one (cancelled, or it failed).
    private func pickedFolder(_ result: Result<URL?, Error>) {
        let purpose = folderPurpose
        folderPurpose = .backup
        let url = (try? result.get()) ?? nil
        switch (purpose, url) {
        case (.safetyCopy(let payload), let url?):
            restore(payload, copyInto: url)
        case (.safetyCopy, nil):
            fail("No se restauró nada", "Sin una carpeta donde guardar la copia de lo que hay en este iPhone, Al día no reemplaza tus datos.")
        case (.keepBackingUp, let url?):
            if useFolder(url) { finishSetUp(localOnly: !DailyBackup.isInCloud(url)) }
        case (.backup, let url?):
            if useFolder(url) { localFolder = !DailyBackup.isInCloud(url) }
        case (.keepBackingUp, nil), (.backup, nil):
            break
        }
    }

    private func useFolder(_ url: URL) -> Bool {
        do {
            try DailyBackup.choose(folder: url)
            folderName = DailyBackup.folderName
            aside = DailyBackup.aside
            return true
        } catch {
            fail("No se pudo usar esa carpeta", "Elige otra.")
            return false
        }
    }

    /// «Seguir respaldando aquí» (2026-11-11): the owner first, like «Cambiar contraseña». The
    /// password that opened the file goes to this phone's Keychain (never over one that's
    /// already there), and the folder is the file's own if it can be written to, or one picked.
    private func keepBackingUp() async {
        guard !working else { return }
        guard await OwnerCheck.confirm(reason: "Para seguir respaldando en este iPhone.") else { return }
        if BackupPassword.lookup() == .missing {
            guard let openedWith, BackupPassword.save(openedWith) else {
                fail("No se guardó la contraseña", "Créala en esta pantalla, en «Contraseña», y elige la carpeta.")
                return
            }
            hasPassword = true
        }
        if DailyBackup.folderIsUsable {
            finishSetUp(localOnly: false)
        } else if let fileToOpen, DailyBackup.adoptFolder(of: fileToOpen) {
            folderName = DailyBackup.folderName
            aside = DailyBackup.aside
            finishSetUp(localOnly: !DailyBackup.isInCloud(fileToOpen.deletingLastPathComponent()))
        } else {
            folderPurpose = .keepBackingUp
            choosingFolder = true
        }
    }

    private func finishSetUp(localOnly: Bool) {
        openedWith = nil
        notSetUp = false
        setUpMessage = Self.setUpText(folder: folderName ?? "", localOnly: localOnly)
    }

    static func setUpText(folder: String, localOnly: Bool) -> String {
        var text = "Este iPhone ya respalda en «\(folder)». Toca «Respaldar ahora» para hacer el primero."
        if localOnly {
            text += " Esa carpeta está solo en este iPhone: si lo pierdes, el respaldo se pierde con él. Mejor elige una dentro de iCloud Drive."
        }
        return text + "\n\nFalta crear en este iPhone la automatización de cada día:\n" + automationSteps.joined(separator: "\n")
    }

    // MARK: Copies left inside the app

    private func restoreCopy(_ copy: BackupSafetyCopy) async {
        guard let url = DailyBackup.ownDocuments?.appending(path: copy.name) else { return }
        guard await OwnerCheck.confirm(reason: "Para restaurar un respaldo.") else { return }
        open(url, password: BackupPassword.read())
    }

    /// «Guardar en Archivos»: the system moves the file where the person says, so it leaves the app.
    private func move(_ copy: BackupSafetyCopy) {
        guard let url = DailyBackup.ownDocuments?.appending(path: copy.name) else { return }
        movingCopy = url
        moving = true
    }

    // MARK: Words

    /// «¿Restaurar este respaldo?»: what it brings, what it replaces, and where the copy of
    /// what's here goes, which depends on this phone (`BackupSafetyPlan`).
    private var restoreQuestion: String {
        guard let pending else { return "" }
        return Self.question(Self.describe(pending.summary), plan: safetyPlan, folder: folderName)
    }

    static func question(_ what: String, plan: BackupSafetyPlan, folder: String?) -> String {
        let replaces = what + "\n\nReemplaza todo lo que hay en este iPhone, y en tus otros dispositivos si usan Al día con iCloud. "
        switch plan {
        case .copyToFolder:
            return replaces + "Antes se guarda una copia de lo actual en tu carpeta" + (folder.map { " «\($0)»." } ?? ".")
        case .askWhere:
            return replaces + "Antes hay que guardar una copia de lo actual donde puedas verla: al tocar «Restaurar» eliges la carpeta en Archivos. Si no eliges ninguna, no se restaura nada."
        case .nothingToCopy:
            return replaces + "Este iPhone no tiene gastos, ni «Mi dinero», ni presupuesto o listas tuyas, así que no hay nada que guardar antes."
        }
    }

    private var doneText: String {
        outcome.map(Self.done) ?? ""
    }

    static func done(_ outcome: RestoreOutcome) -> String {
        var text = outcome.summary.expenseCount == 1 ? "Se restauró 1 gasto y tus ajustes."
            : "Se restauraron \(outcome.summary.expenseCount) gastos y tus ajustes."
        if let copy = outcome.copy {
            text += " Lo que había antes quedó en la carpeta «\(copy.folderName)», como «\(copy.name)». Se abre con "
                + (outcome.copyUsesSavedPassword ? "la contraseña del respaldo de este iPhone." : "la misma contraseña de este respaldo.")
        } else {
            text += " Este iPhone estaba vacío: no había nada que guardar antes."
        }
        guard outcome.offersSetUp else { return text }
        text += "\n\n" + BackupSetupReminder.text + " «Seguir respaldando aquí» "
            + (outcome.hasPassword ? "usa la contraseña que ya tiene este iPhone"
                                   : "guarda en este iPhone la contraseña con la que abriste este respaldo")
            + " y usa su misma carpeta, o te pide elegirla.\n\nTambién hay que crear aquí la automatización de cada día:\n"
            + automationSteps.joined(separator: "\n")
        return text
    }

    /// `true` while there's something to show: an alert's flag from an optional.
    static func shown<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
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

/// What the folder picker was opened for.
private enum FolderPurpose {
    /// «Carpeta»: where the daily backup goes.
    case backup
    /// Where the copy of what's here goes before this restore, when the backup has no folder.
    case safetyCopy(BackupPayload)
    /// «Seguir respaldando aquí», when the restored file's own folder can't be used.
    case keepBackingUp
}

/// A restore that worked, as «Listo» tells it.
struct RestoreOutcome: Equatable {
    var summary: BackupSummary
    /// Where what was here before went; `nil` when the phone was empty.
    var copy: DailyBackup.SafetyCopy?
    /// The copy is locked with this phone's password, not with the one typed for the file.
    var copyUsesSavedPassword: Bool
    /// The daily backup isn't set up on this phone: «Seguir respaldando aquí» / «Ahora no».
    var offersSetUp: Bool
    /// This phone already has a backup password (only the folder is missing).
    var hasPassword: Bool
}

/// The questions and answers of a restore. Apart from the screen's `body`: the CI's compiler
/// gives up on one long chain.
private struct RestoreAlerts: ViewModifier {
    @Binding var pending: BackupPayload?
    @Binding var outcome: RestoreOutcome?
    @Binding var needsCopyFolder: BackupPayload?
    let question: String
    let done: String
    let restore: (BackupPayload) -> Void
    let pickCopyFolder: (BackupPayload) -> Void
    let keep: () -> Void
    let later: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("¿Restaurar este respaldo?", isPresented: BackupSettingsView.shown($pending)) {
                Button("Cancelar", role: .cancel) { pending = nil }
                Button("Restaurar", role: .destructive) { if let pending { restore(pending) } }
            } message: {
                Text(question)
            }
            .alert("Listo", isPresented: BackupSettingsView.shown($outcome)) {
                if outcome?.offersSetUp == true {
                    Button("Seguir respaldando aquí") { outcome = nil; keep() }
                    Button("Ahora no", role: .cancel) { later(); outcome = nil }
                } else {
                    Button("Aceptar", role: .cancel) { outcome = nil }
                }
            } message: {
                Text(done)
            }
            .alert("Falta dónde guardar la copia", isPresented: BackupSettingsView.shown($needsCopyFolder)) {
                Button("Elegir carpeta") { if let needsCopyFolder { pickCopyFolder(needsCopyFolder) } }
                Button("Cancelar", role: .cancel) { needsCopyFolder = nil }
            } message: {
                Text("La copia de lo que hay en este iPhone no se pudo guardar en la carpeta del respaldo, así que no se restauró nada. Elige una carpeta para esa copia; al elegirla se restaura.")
            }
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
