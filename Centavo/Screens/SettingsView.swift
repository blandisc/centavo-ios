import CentavoCore
import SwiftData
import SwiftUI

/// The preferences that do not change the month's money: how it looks, where a payment was,
/// the Wallet automation and the data in and out. «Más» keeps only what the month is made of
/// (budget, fixed expenses, cards and categories) and this sheet.
struct SettingsView: View {
    /// The currency the month adds up in, and how to change it (the parent asks about the budget).
    let currency: String
    let setCurrency: (String) -> Void
    let health: CaptureHealth
    /// Closes this sheet and opens the guide, or the file picker for a CSV.
    let openGuide: () -> Void
    let importCSV: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(PaymentPlace.key) private var savesPlace = false
    @AppStorage(WalletWatch.key) private var ignoresWallet = false
    /// The whole history as a CSV, read once when the sheet opens (not on every redraw).
    @State private var csv: ExpensesCSVFile?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: Binding(get: { currency }, set: setCurrency)) {
                        ForEach(CurrencyPreference.offered, id: \.self) { code in
                            Text(CurrencyPreference.name(code)).tag(code)
                        }
                    } label: {
                        IconRow("Moneda principal", systemImage: "dollarsign.circle") { EmptyView() }
                    }
                } header: {
                    Text("Moneda").ticketCaption()
                } footer: {
                    HintText("La moneda en la que suma tu mes. Lo que llega en otra se muestra aparte. "
                             + "La vista (Lista, Mosaico o Mínima) se elige en «···».")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button(action: openGuide) {
                        IconRow("Configurar atajo", systemImage: "wallet.pass") {
                            Text(healthText)
                                .font(.ticket(.detail))
                                .foregroundStyle(health.isRecent ? Theme.muted : Theme.brass)
                        }
                    }
                    .accessibilityIdentifier("ajustes-configurar-atajo")
                    Toggle(isOn: Binding(get: { !ignoresWallet }, set: { ignoresWallet = !$0 })) {
                        IconRow("Avisar si no llegan pagos", systemImage: "bell.badge") { EmptyView() }
                    }
                    .tint(Theme.brass)
                    .accessibilityIdentifier("ajustes-avisar-wallet")
                    Toggle(isOn: Binding(get: { savesPlace }, set: { on in
                        savesPlace = on
                        if on { PaymentPlace.requestPermission() }
                    })) {
                        IconRow("Guardar dónde pagas", systemImage: "mappin.and.ellipse") { EmptyView() }
                    }
                    .tint(Theme.brass)
                } header: {
                    Text("Wallet").ticketCaption()
                } footer: {
                    HintText("Si no usas Wallet, apaga el aviso y la pantalla principal deja de pedirte que lo conectes. «Dónde pagas» usa la ubicación del iPhone al anotar.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    if let csv, !csv.records.isEmpty {
                        ShareLink(item: csv, preview: SharePreview("Gastos de Al día")) {
                            IconRow("Exportar CSV", systemImage: "square.and.arrow.up") { EmptyView() }
                        }
                    } else {
                        IconRow("Exportar CSV", systemImage: "square.and.arrow.up") { EmptyView() }
                            .foregroundStyle(Theme.faint)
                    }
                    Button(action: importCSV) {
                        IconRow("Importar CSV", systemImage: "square.and.arrow.down") { EmptyView() }
                    }
                } header: {
                    Text("Tus datos").ticketCaption()
                } footer: {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        HintText("Se exportan todos los meses. Importar acepta el mismo archivo y no duplica gastos.")
                        // Which build this is, to tell whether the iPhone has the latest (2026-10-30).
                        HintText(AppVersion.line)
                            .accessibilityIdentifier("version")
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .font(.ticket(.footnoteStrong))
                        .accessibilityIdentifier("ajustes-listo")
                }
            }
            .task {
                let all = (try? context.fetch(FetchDescriptor<Expense>(
                    sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
                csv = ExpensesCSVFile(expenses: all, primaryCurrency: currency)
            }
        }
    }

    private var healthText: String {
        if ignoresWallet { return "Aviso apagado" }
        switch health {
        case .never: return "Sin conectar"
        case .recent: return "Funciona"
        case .quiet(let days): return "\(days) días sin pagos"
        }
    }
}

/// Whether the person told Al día they don't use Wallet: then the main screen stops asking
/// to connect it and stops warning about quiet days.
enum WalletWatch {
    static let key = "noUsaWallet"
}

#Preview {
    SettingsView(currency: "MXN", setCurrency: { _ in }, health: .never, openGuide: {}, importCSV: {})
        .ticketPreview()
}
