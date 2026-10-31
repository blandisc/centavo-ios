import AppIntents
import Foundation

/// «Respaldar Al día»: what the nightly automation in Atajos runs. The app writes the file to
/// the folder chosen in Ajustes; Atajos only wakes it up, so nothing is passed around.
struct BackupIntent: AppIntent {
    static let title: LocalizedStringResource = "Respaldar Al día"
    static let description = IntentDescription("Guarda un respaldo con contraseña de todo Al día en la carpeta que elegiste.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard case .success(let container) = Store.opened else { throw CaptureError.storeUnavailable }
        try DailyBackup.runNow(in: container.mainContext)
        return .result(dialog: "Respaldo guardado.")
    }
}
