import CentavoCore
import SwiftUI

#if DEBUG
/// How the on-device model does with Mexican merchant names, on this iPhone: the go / no-go
/// test before trusting its suggestions. Debug builds only («Más › Probar el modelo»).
///
/// The bar: 85 % right among the ones it files, and under 5 % filed wrong with confidence (a
/// wrong suggestion is worse than none).
struct ModelCheckView: View {
    struct Row: Identifiable {
        let id = UUID()
        let raw: String
        let expected: String
        var name: String?
        var got: String?
        var seconds: Double?
    }

    @State private var rows = ModelCheckView.golden.map { Row(raw: $0.0, expected: $0.1) }
    @State private var running = false
    @Environment(\.dismiss) private var dismiss

    /// Names the catalog doesn't know, with the category a person would pick (or none).
    static let golden: [(String, String)] = [
        ("CLIP*MX TAQ GUERO 02", "Comida"), ("TAQUERIA LOS PARADOS", "Comida"),
        ("MERPAGO*TORTAS AHOGADAS", "Comida"), ("PIZZERIA NAPOLI SUC 3", "Comida"),
        ("SUSHI ITTO PERISUR", "Comida"), ("CAFE LA CEIBA", "Café"), ("MERPAGO*CAFEBRERIA", "Café"),
        ("GASOLINERA G500 LOS ANGELES", "Transporte"), ("ESTAC PARKING CENTRO", "Transporte"),
        ("CASETA AUTOP MEX-PUE", "Transporte"), ("FARMACIA SAN JORGE", "Salud"),
        ("CONSULTORIO DR LOPEZ", "Salud"), ("LAB CLINICO CHOPO", "Salud"),
        ("FERRETERIA EL MARTILLO", "Hogar"), ("TLAPALERIA HNOS GARCIA", "Hogar"),
        ("MUEBLERIA DEL VALLE", "Hogar"), ("ZAPATERIA ANDREA", "Ropa"), ("BOUTIQUE LUNA SA DE CV", "Ropa"),
        ("BAR EL TENAMPA", "Salidas"), ("BOLICHE LINDAVISTA", "Salidas"), ("TEATRO INSURGENTES", "Salidas"),
        ("MINISUPER DON PEPE", "Despensa"), ("CARNICERIA LA HERRADURA", "Despensa"),
        ("FRUTERIA LA HUERTA", "Despensa"), ("GAS NATURAL DEL NOROESTE", "Servicios"),
        ("DROPBOX", "Suscripciones"), ("CANVA PRO", "Suscripciones"), ("ADOBE CREATIVE CLOUD", "Suscripciones"),
        ("LIBRERIA GANDHI", "Compras"), ("MERPAGO*ESTETICAVALE", CategoryPick.none),
        ("PAGO 0012345", CategoryPick.none), ("CLIP*MX 77812", CategoryPick.none),
        ("SERV ABC SA DE CV", CategoryPick.none),
    ]

    private var done: [Row] { rows.filter { $0.seconds != nil } }

    private var summary: String {
        guard !done.isEmpty else { return "Sin correr" }
        let filed = done.filter { $0.got != nil }
        let right = filed.filter { $0.got == $0.expected }.count
        let wrong = filed.filter { $0.got != $0.expected }.count
        let times = done.compactMap(\.seconds).sorted()
        let median = times[times.count / 2]
        return "Aciertos \(right)/\(filed.count) archivados · Errores \(wrong)/\(done.count) · "
            + "Mediana \(median.formatted(.number.precision(.fractionLength(2)))) s"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(LocalModel.isReady ? "Modelo listo en este iPhone" : "Sin Apple Intelligence aquí")
                    Text(summary)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.raw).font(.ticket(13, relativeTo: .footnote))
                        Text("\(row.name ?? "—") · \(row.got ?? CategoryPick.none) · esperaba \(row.expected)")
                            .font(.ticket(11, relativeTo: .caption))
                            .foregroundStyle(row.seconds == nil ? Theme.muted
                                : (row.got ?? CategoryPick.none) == row.expected ? Theme.ink : Theme.brass)
                    }
                }
            }
            .navigationTitle("Probar el modelo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Listo") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(running ? "Corriendo…" : "Correr") { Task { await run() } }
                        .disabled(running || !LocalModel.isReady)
                }
            }
        }
    }

    private func run() async {
        running = true
        defer { running = false }
        let candidates = CategoryStyle.common.map(\.name)
        for index in rows.indices {
            let start = ContinuousClock.now
            let reading = await LocalModel.readMerchant(rows[index].raw, readable: MerchantName.readable(rows[index].raw),
                                                        candidates: candidates, examples: [])
            let elapsed = ContinuousClock.now - start
            rows[index].name = reading?.name
            rows[index].got = CategoryPick.validate(reading?.category, among: candidates)
            rows[index].seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
        }
    }
}
#endif

/// «Más › Probar el modelo», in Debug builds only; nothing in the App Store build.
struct ModelCheckSheet: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        #if DEBUG
        content.sheet(isPresented: $isPresented) { ModelCheckView() }
        #else
        content
        #endif
    }
}
