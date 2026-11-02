import CentavoCore
import Foundation
import Testing

@Suite("«¿Lo tienes en Excel?»: leer lo que devuelve la IA")
struct MoneyImportTests {
    func d(_ text: String) -> Decimal { Decimal(string: text)! }

    let csv = """
    ```csv
    tipo,nombre,institucion,moneda,monto,tasa_anual,tipo_cambio,repite
    cuenta,Cajita,Nu,MXN,185000,10.5,,
    cuenta,Dólares,BBVA,USD,2000,,19,
    tarjeta,Platinum,Amex,MXN,6420.50,48,,
    prestamo,Auto,BBVA,MXN,-120000,,,
    por_caer,Bono anual,Arca,MXN,35000,,,
    ingreso,Sueldo,Arca,MXN,60000,,,si
    # Fondo GBM: el monto decía «25 mil», no lo incluí.
    ```
    """

    @Test("Un CSV como el que pide la instrucción se lee completo")
    func happyPath() {
        let result = MoneyImport.parse(csv, main: "MXN")
        #expect(result.refusal == nil)
        #expect(result.lines.count == 6)
        #expect(result.ready.count == 6)
        #expect(result.notes == ["Fondo GBM: el monto decía «25 mil», no lo incluí."])
        let cajita = result.lines[0]
        #expect(cajita.kind == .account && cajita.institution == "Nu" && cajita.amount == 185_000 && cajita.yearlyRate == d("10.5"))
        #expect(result.lines[1].exchange == 19 && result.rates == ["USD": [19]])
        #expect(result.lines[2].amount == d("6420.50"))
        #expect(result.lines[3].amount == 120_000, "Una deuda negativa se toma en positivo")
        #expect(result.lines[5].kind == .income && result.lines[5].repeats == true)
    }

    @Test("Una tabla de Markdown también se lee")
    func markdown() {
        let table = """
        | Tipo | Nombre | Institución | Moneda | Monto |
        |------|--------|-------------|--------|-------|
        | cuenta | Nómina | BBVA | MXN | 42,300 |
        | tarjeta | Oro | Amex | MXN | $6,420 |
        """
        let result = MoneyImport.parse(table, main: "MXN")
        #expect(result.ready.count == 2)
        #expect(result.lines[0].amount == 42_300 && result.lines[0].institution == "BBVA")
        #expect(result.lines[1].amount == 6_420)
    }

    @Test("Una tabla copiada (con tabuladores) y con punto y coma, también")
    func tabsAndSemicolons() {
        let tabs = "tipo\tnombre\tmonto\ncuenta\tEfectivo\t3500"
        #expect(MoneyImport.parse(tabs, main: "MXN").ready.first?.amount == 3_500)
        let semis = "tipo;nombre;monto;tasa_anual\ninversion;Fondo;25000;\"7,5\""
        let line = MoneyImport.parse(semis, main: "MXN").lines.first
        #expect(line?.amount == 25_000 && line?.yearlyRate == d("7.5"))
    }

    @Test("Títulos y tipos en inglés o con acentos")
    func english() {
        let text = "Type,Name,Bank,Currency,Balance,APY\nSavings,Emergency,Nu,mxn,1000,10%\nCredit card,Gold,Amex,MXN,250,"
        let result = MoneyImport.parse(text, main: "MXN")
        #expect(result.lines.map(\.kind) == [.account, .card])
        #expect(result.lines[0].currency == "MXN" && result.lines[0].yearlyRate == 10 && result.lines[0].institution == "Nu")
    }

    @Test("«25 mil» o «12k» no se leen como 25 o 12: salen para revisar")
    func abbreviations() {
        let text = "tipo,nombre,monto\ninversion,GBM,25 mil\ncuenta,Nu,12k\ncuenta,BBVA,1.5M"
        let result = MoneyImport.parse(text, main: "MXN")
        #expect(result.ready.isEmpty)
        #expect(result.lines.allSatisfy { $0.amount == nil && !$0.problems.isEmpty })
    }

    @Test("Una tasa como fracción (0.105) se propone como 10.5% pero se pregunta; 0 es vacía")
    func fractionRate() {
        let lines = MoneyImport.parse("tipo,nombre,monto,tasa_anual\ncuenta,Nu,100,0.105\ncuenta,BBVA,100,0\ncuenta,X,100,350", main: "MXN").lines
        #expect(lines[0].yearlyRate == d("10.5") && !lines[0].isReady)
        #expect(lines[1].yearlyRate == nil && lines[1].isReady)
        #expect(!lines[2].isReady, "Una tasa de 350% se pregunta")
    }

    @Test("Varios tipos de cambio para la misma moneda se guardan todos, para elegir")
    func conflictingRates() {
        let text = "tipo,nombre,moneda,monto,tipo_cambio\ncuenta,A,USD,10,19\ncuenta,B,USD,20,18.5\ncuenta,C,EUR,5,\ncuenta,D,USD,1,19"
        let result = MoneyImport.parse(text, main: "MXN")
        #expect(result.rates["USD"] == [19, d("18.5")])
        #expect(result.rates["EUR"] == nil, "Sin tipo de cambio en el archivo: lo pide la revisión")
        #expect(result.ready.count == 4)
    }

    @Test("Un tipo de cambio con tres decimales no se vuelve miles")
    func threeDecimals() {
        let line = MoneyImport.parse("tipo,nombre,moneda,monto,tipo_cambio\ncuenta,A,USD,10,18.125", main: "MXN").lines[0]
        #expect(line.exchange == d("18.125"))
    }

    @Test("Un ingreso de una sola vez se vuelve «por caer», con aviso")
    func oneOffIncome() {
        let line = MoneyImport.parse("tipo,nombre,monto,repite\ningreso,Extra,5000,no", main: "MXN").lines[0]
        #expect(line.kind == .coming && line.isReady && !line.warnings.isEmpty)
    }

    @Test("Un monto con comas en un CSV sin comillas no se lee mal en silencio")
    func commasInAmount() {
        let line = MoneyImport.parse("tipo,nombre,institucion,moneda,monto,tasa_anual\ncuenta,Cajita,Nu,MXN,12,500,10.5", main: "MXN").lines[0]
        #expect(!line.isReady)
    }

    @Test("El texto después de la tabla, las negritas y el BOM no estorban")
    func proseAndBold() {
        let text = "\u{FEFF}Aquí está:\n| tipo | nombre | monto |\n|---|---|---|\n| **cuenta** | Nu | 100 |\n| me_deben | Ana | |\nListo, revisa lo de Ana."
        let result = MoneyImport.parse(text, main: "MXN")
        #expect(result.lines.count == 2)
        #expect(result.lines[0].kind == .account && result.lines[0].isReady)
        #expect(result.lines[1].kind == .lent && !result.lines[1].isReady)
    }

    @Test("La moneda pegada al monto llena la columna vacía, o choca con ella")
    func markerCurrency() {
        let lines = MoneyImport.parse("tipo,nombre,moneda,monto\ncuenta,A,,USD 2000\ncuenta,B,EUR,US$10\ncuenta,C,MXN,$5", main: "MXN").lines
        #expect(lines[0].currency == "USD" && lines[0].amount == 2_000)
        #expect(!lines[1].isReady)
        #expect(lines[2].isReady && lines[2].currency == "MXN")
    }

    @Test("Comillas dobles dentro de un campo")
    func quotes() {
        let line = MoneyImport.parse("tipo,nombre,monto\ncuenta,\"Nu \"\"cajita\"\", ahorro\",100", main: "MXN").lines[0]
        #expect(line.name == "Nu \"cajita\", ahorro")
    }

    @Test("Lo que no se entiende sale con su motivo; lo demás entra")
    func partial() {
        let text = "tipo,nombre,moneda,monto\nalcancia,Cochinito,MXN,100\ncuenta,,MXN,5\ncuenta,Nu,PESOS,5\ncuenta,BBVA,MXN,7\ncuenta,BBVA,MXN,7"
        let result = MoneyImport.parse(text, main: "MXN")
        #expect(result.ready.map(\.name) == ["BBVA"])
        #expect(result.toReview.count == 4)
        #expect(result.lines.last?.problems.contains("Viene repetida en el archivo.") == true)
    }

    @Test("El CSV de gastos se reconoce y se manda a su lugar")
    func expensesFile() {
        let result = MoneyImport.parse("Fecha,Comercio,Monto,Moneda\n2026-10-01,OXXO,47.50,MXN", main: "MXN")
        #expect(result.refusal?.contains("gastos") == true)
        #expect(result.lines.isEmpty)
    }

    @Test("Algo que no es tabla lo dice")
    func notATable() {
        #expect(MoneyImport.parse("Hola, ¿me pasas tu Excel?", main: "MXN").refusal != nil)
        #expect(MoneyImport.parse(MoneyImport.header, main: "MXN").refusal != nil)
    }

    @Test("Las instrucciones traen el encabezado y la moneda principal")
    func instructions() {
        let text = MoneyImport.instructions(main: "USD")
        #expect(text.contains(MoneyImport.header))
        #expect(text.contains("Mi moneda principal es USD"))
        #expect(text.contains("No incluyas números de cuenta"))
    }
}
