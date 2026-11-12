import Foundation
import Testing
@testable import CentavoCore

/// «Al día no pudo abrir tus gastos» (2026-11-11): la causa cuando se sabe, sin prometer lo que
/// no se sabe, y qué archivos van en la copia de salida.
@Suite("La base de gastos no abre")
struct StoreTroubleTests {
    private let plenty: Int64 = 20_000_000_000

    private func code(_ domain: String, _ code: Int) -> StoreTrouble.Code { .init(domain: domain, code: code) }

    @Test("Un error de «sin espacio», a cualquier profundidad, es sin espacio")
    func outOfSpaceErrors() {
        #expect(StoreTrouble.cause(codes: [code("NSCocoaErrorDomain", 640)], freeBytes: plenty) == .noSpace)
        #expect(StoreTrouble.cause(codes: [code("SwiftData.SwiftDataError", 1), code("NSCocoaErrorDomain", 256),
                                           code("NSPOSIXErrorDomain", 28)], freeBytes: plenty) == .noSpace)
        #expect(StoreTrouble.cause(codes: [code("NSSQLiteErrorDomain", 13)], freeBytes: nil) == .noSpace)
    }

    @Test("Con el iPhone casi lleno, un error que no dice por qué también es sin espacio")
    func almostFull() {
        let vague = [code("SwiftData.SwiftDataError", 1)]
        #expect(StoreTrouble.cause(codes: vague, freeBytes: 0) == .noSpace)
        #expect(StoreTrouble.cause(codes: vague, freeBytes: StoreTrouble.lowSpace - 1) == .noSpace)
        #expect(StoreTrouble.cause(codes: vague, freeBytes: StoreTrouble.lowSpace) == .unknown)
    }

    @Test("Cualquier otra cosa no se adivina")
    func anythingElseIsUnknown() {
        #expect(StoreTrouble.cause(codes: [code("NSCocoaErrorDomain", 134_110)], freeBytes: plenty) == .unknown)
        #expect(StoreTrouble.cause(codes: [], freeBytes: nil) == .unknown)
        // 640 and 28 mean something else in other domains.
        #expect(StoreTrouble.cause(codes: [code("NSURLErrorDomain", 28), code("OtroDominio", 640)], freeBytes: nil) == .unknown)
    }

    @Test("Ningún texto promete que no se perdió nada, y todos piden no desinstalar")
    func theWordsPromiseNothing() {
        for trouble in [StoreTrouble.noSpace, .unknown] {
            #expect(trouble.title == "Al día no pudo abrir tus gastos")
            #expect(!trouble.explanation.contains("no se borró nada"))
            #expect(!trouble.explanation.contains("siguen guardados"))
            #expect(trouble.explanation.contains("deberían seguir en este iPhone"))
            #expect(trouble.explanation.contains("No desinstales la app"))
            #expect(trouble.explanation.contains("«Intentar de nuevo»"))
        }
        #expect(StoreTrouble.noSpace.explanation.contains("espacio"))
        #expect(!StoreTrouble.unknown.explanation.contains("espacio"))
    }

    @Test("La copia lleva los dos almacenes con sus diarios y lo apartado, y nada más")
    func whichFilesGoInTheCopy() {
        for name in ["default.store", "default.store-wal", "default.store-shm", "dinero.store", "dinero.store-wal",
                     "dinero.store-shm", "dinero.store.danado-2026-11-02T210000", "dinero.store.danado-2026-11-02T210000-wal"] {
            #expect(StoreTrouble.isStoreFile(name, store: "default.store"), "\(name)")
        }
        for name in ["Library", "notas.txt", "al-dia-2026-11-12.aldia", ".default.store", "otro.store"] {
            #expect(!StoreTrouble.isStoreFile(name, store: "default.store"), "\(name)")
        }
    }
}
