import CentavoCore
import Foundation
import Testing

@Suite("Segunda auditoría: importar sin perder miles ni monedas")
struct MoneyImportCommaTests {
    let header = MoneyImport.header

    @Test("«12,000» sin comillas en un CSV con comas va a revisión, no se guarda como 12")
    func thousandsCommaShortRow() {
        let result = MoneyImport.parse("\(header)\ncuenta,Efectivo,,MXN,12,000", main: "MXN")
        let line = result.lines.first
        #expect(line?.isReady == false)
        #expect(line?.problems.contains { $0.contains("¿un monto con comas?") } == true)
    }

    @Test("«1,500» con el renglón completo: el «500» no se toma como tasa")
    func thousandsCommaIntoRate() {
        let result = MoneyImport.parse("\(header)\ncuenta,Nu,Nu,MXN,1,500,,", main: "MXN")
        let line = result.lines.first
        #expect(line?.isReady == false)
        #expect(line?.problems.contains { $0.contains("¿un monto con comas?") } == true)
    }

    @Test("Un renglón con todas sus columnas y tasa normal sigue listo")
    func normalRowStaysReady() {
        let result = MoneyImport.parse("\(header)\ncuenta,Cajita,Nu,MXN,185000,10.5,,", main: "MXN")
        #expect(result.lines.first?.isReady == true)
    }

    @Test("Con punto y coma, «1,500» no es problema")
    func semicolonUnaffected() {
        let result = MoneyImport.parse("tipo;nombre;monto;tasa_anual\ncuenta;Nu;1,500;5", main: "MXN")
        #expect(result.lines.first?.amount == 1_500)
        #expect(result.lines.first?.isReady == true)
    }

    @Test("Un código de tres letras que no es moneda va a revisión")
    func unknownCurrency() {
        let result = MoneyImport.parse("\(header)\ncuenta,Caja,,ABC,100,,,", main: "MXN")
        #expect(result.lines.first?.isReady == false)
        let known = MoneyImport.parse("\(header)\ncuenta,Caja,,USD,100,,19,", main: "MXN")
        #expect(known.lines.first?.isReady == true)
    }
}
