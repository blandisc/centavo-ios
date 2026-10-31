import CentavoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// «Respaldo diario» in Ajustes: the password, the folder, a backup now, and restoring one.
/// The nightly run itself is an automation in Atajos with «Respaldar Al día».
struct BackupSettingsView: View {
    @Environment(\.modelContext) private var context

    @State private var hasPassword = BackupPassword.read() != nil
    @State private var newPassword = ""
    @State private var repeated = ""
    @State private var changingPassword = false
    @State private var shownPassword: String?

    @State private var folderName = DailyBackup.folderName
    @State private var choosingFolder = false

    @State private var last = DailyBackup.lastBackup
    @State private var working = false
    @State private var problem: String?

    @State private var choosingFile = false
    @State private var fileToOpen: URL?
    @State private var typedPassword = ""
    @State private var askingPassword = false
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
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do {
                try DailyBackup.choose(folder: url)
                folderName = DailyBackup.folderName
            } catch {
                problem = "No se pudo usar esa carpeta. Elige otra."
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.aldiaBackup, .data]) { result in
            guard case .success(let url) = result else { return }
            open(url, password: BackupPassword.read())
        }
        .alert("Contraseña del respaldo", isPresented: $askingPassword) {
            SecureField("Contraseña", text: $typedPassword)
            Button("Cancelar", role: .cancel) { typedPassword = "" }
            Button("Abrir") {
                if let fileToOpen { open(fileToOpen, password: typedPassword) }
                typedPassword = ""
            }
        } message: {
            Text("Escribe la contraseña con la que se guardó este respaldo.")
        }
        .alert("¿Restaurar este respaldo?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Cancelar", role: .cancel) { pending = nil }
            Button("Restaurar", role: .destructive) { if let pending { restore(pending) } }
        } message: {
            if let pending { Text(Self.describe(pending.summary) + "\n\nReemplaza todo lo que hay en este iPhone. Antes se guarda una copia de lo actual en tu carpeta.") }
        }
        .alert("Listo", isPresented: Binding(get: { restored != nil }, set: { if !$0 { restored = nil } })) {
            Button("Aceptar", role: .cancel) { restored = nil }
        } message: {
            if let restored { Text("Se restauraron \(restored.expenseCount) gastos y tus ajustes.") }
        }
        .alert("No se pudo", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
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
                Button { changingPassword = true; shownPassword = nil } label: {
                    IconRow("Cambiar contraseña", systemImage: "key") { EmptyView() }
                }
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
                Button(action: savePassword) {
                    LinkActionLabel("Guardar contraseña", alignment: .leading)
                }
                .disabled(!passwordIsValid)
                .accessibilityIdentifier("respaldo-guardar-contrasena")
            }
        } header: {
            Text("Contraseña").ticketCaption()
        } footer: {
            HintText(hasPassword && !changingPassword
                     ? "Sin ella el respaldo no se puede abrir, ni por ti ni por nadie. Guárdala también en la app Contraseñas."
                     : "Guárdala también en la app Contraseñas: si pierdes este iPhone, la vas a necesitar para abrir tu respaldo en otro. Sin ella, nadie puede abrirlo.")
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
            HintText("A las 21:00 el iPhone suele estar despierto. Al reinstalar Al día desde la Mac, el atajo sigue: si un día no se respalda, aquí lo verás.")
        }
        .listRowBackground(Theme.surface)
    }

    private var restoreSection: some View {
        Section {
            Button { choosingFile = true } label: {
                IconRow("Restaurar respaldo", systemImage: "clock.arrow.circlepath") { EmptyView() }
            }
            .accessibilityIdentifier("respaldo-restaurar")
        } footer: {
            HintText("Antes de restaurar ves de qué día es y cuántos gastos trae. Nada cambia hasta que confirmas.")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: Actions

    private var passwordIsValid: Bool {
        newPassword.count >= Self.minimumLength && newPassword == repeated
    }

    private var lastText: String {
        guard let last else { return hasPassword && folderName != nil ? "Todavía no hay respaldo." : "Primero la contraseña y la carpeta." }
        return "Último respaldo: " + last.formatted(.relative(presentation: .named).locale(Locale(identifier: "es_MX")))
    }

    private func savePassword() {
        guard passwordIsValid, BackupPassword.save(newPassword) else { return }
        newPassword = ""
        repeated = ""
        hasPassword = true
        changingPassword = false
    }

    private func reveal() async {
        if shownPassword != nil { shownPassword = nil; return }
        if await BackupPassword.unlock(reason: "Para mostrar la contraseña del respaldo.") {
            shownPassword = BackupPassword.read()
        }
    }

    private func backUpNow() {
        working = true
        defer { working = false }
        do {
            last = try DailyBackup.runNow(in: context)
        } catch {
            problem = message(for: error)
        }
    }

    private func open(_ url: URL, password: String?) {
        fileToOpen = url
        guard let password else { askingPassword = true; return }
        do {
            pending = try DailyBackup.read(url, password: password)
            openedWith = password
        } catch DailyBackup.Failure.unreadable(.wrongPassword) {
            askingPassword = true
        } catch {
            problem = message(for: error)
        }
    }

    private func restore(_ payload: BackupPayload) {
        pending = nil
        do {
            // The current data is kept first, locked with the password that's set (or the
            // backup's own, typed a moment ago, when this phone has none yet).
            if let password = BackupPassword.read() ?? openedWith {
                try DailyBackup.safetyCopy(in: context, password: password)
            }
            try DailyBackup.restore(payload, into: context.container)
            restored = payload.summary
        } catch {
            problem = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        if let failure = error as? DailyBackup.Failure { return String(localized: failure.localizedStringResource) }
        return "Algo falló al guardar. No se cambió nada."
    }

    private static func describe(_ summary: BackupSummary) -> String {
        let mx = Locale(identifier: "es_MX")
        let made = summary.createdAt.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(mx))
        var text = "Del \(made): \(summary.expenseCount) gastos"
        if let first = summary.firstExpense, let lastOne = summary.lastExpense {
            let style = Date.FormatStyle.dateTime.month(.abbreviated).year().locale(mx)
            text += " (de \(first.formatted(style)) a \(lastOne.formatted(style)))"
        }
        if let accounts = summary.accountCount, let cuts = summary.cutCount {
            text += ", y «Mi dinero» con \(accounts) cuentas y \(cuts) cortes"
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
