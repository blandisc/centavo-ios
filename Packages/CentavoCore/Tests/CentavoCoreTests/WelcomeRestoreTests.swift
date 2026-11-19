import Foundation
import Testing
@testable import CentavoCore

/// «Restaurar un respaldo» desde la bienvenida (2026-11-19): solo cuenta como bienvenida vista
/// si la restauración funcionó después de dejarla.
@Suite("Restaurar desde la bienvenida")
struct WelcomeRestoreTests {
    private let left = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("Cancelar el selector (nunca se restauró): la bienvenida vuelve")
    func cancelled() {
        #expect(!WelcomeRestore.counts(since: left, restoredAt: nil))
    }

    @Test("Una restauración vieja, de antes de dejar la bienvenida, no cuenta")
    func oldRestore() {
        #expect(!WelcomeRestore.counts(since: left, restoredAt: left.addingTimeInterval(-60)))
    }

    @Test("Restaurar con éxito después de dejarla: la bienvenida queda vista")
    func worked() {
        #expect(WelcomeRestore.counts(since: left, restoredAt: left.addingTimeInterval(30)))
        #expect(WelcomeRestore.counts(since: left, restoredAt: left))
    }
}
