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
    /// Opens on «Respaldo diario», already asking to restore: the welcome's «¿Ya usabas Al día?
    /// Restaurar un respaldo» (2026-11-19). A binding, read when the sheet is up: a plain value
    /// set with the sheet's own flag came in still `false` the first time it opened. Put back to
    /// `false` once used, so it pushes once.
    @Binding var opensRestore: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(PaymentPlace.key) private var savesPlace = false
    @AppStorage(WalletWatch.key) private var ignoresWallet = false
    @Environment(\.scenePhase) private var scenePhase
    /// The location is off for the app in the iPhone's Ajustes: «Guardar dónde pagas» can't work.
    @State private var locationDenied = PaymentPlace.isDenied
    /// The whole history as a CSV, read when the sheet opens and after each save (not on every redraw).
    @State private var csv: ExpensesCSVFile?
    /// «Respaldo diario» pushed by itself (`opensRestore`).
    @State private var showingRestore = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TicketMenuPicker("Moneda principal", selection: Binding(get: { currency }, set: { setCurrency($0) }),
                                     value: CurrencyPreference.flagged(currency)) {
                        CurrencyOptions(codes: CurrencyPreference.offered)
                    } label: {
                        IconRow("Moneda principal", systemImage: "dollarsign.circle")
                    }
                } header: {
                    Text("Moneda").ticketCaption()
                } footer: {
                    // Said with the button's spoken name, «Más» (`MenuPath`, 2026-11-19).
                    let footer = String(localized: "La moneda en la que suma tu mes. Lo que llega en otra se muestra aparte. La vista (Lista, Mosaico o Mínima) se elige en «···».")
                    HintText(footer)
                        .spokenMenuPath(footer)
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button(action: openGuide) {
                        IconRow("Conectar Wallet", systemImage: "wallet.pass") {
                            if health.isRecent || ignoresWallet {
                                Text(healthText)
                                    .font(.ticket(.detail))
                                    .foregroundStyle(Theme.muted)
                            } else {
                                WarningText(healthText)
                            }
                        }
                    }
                    .accessibilityIdentifier("ajustes-configurar-atajo")
                    Toggle(isOn: Binding(get: { !ignoresWallet }, set: { ignoresWallet = !$0 })) {
                        IconRow("Avisar si no llegan pagos", systemImage: "bell.badge") { EmptyView() }
                    }
                    .tint(Theme.brass)
                    .accessibilityIdentifier("ajustes-avisar-wallet")
                    // Off, and not switchable, while the iPhone denies the location: on, it would
                    // say it saves where you pay and save nothing (audit 2026-11-02).
                    Toggle(isOn: Binding(get: { savesPlace && !locationDenied }, set: { on in
                        savesPlace = on
                        if on { PaymentPlace.requestPermission() }
                    })) {
                        IconRow("Guardar dónde pagas", systemImage: "mappin.and.ellipse") { EmptyView() }
                    }
                    .tint(Theme.brass)
                    .disabled(locationDenied)
                    .accessibilityIdentifier("ajustes-ubicacion")
                } header: {
                    Text("Wallet").ticketCaption()
                } footer: {
                    if locationDenied {
                        HintText("Si no usas Wallet, apaga el aviso y la pantalla principal deja de pedirte que lo conectes. «Dónde pagas» usa la ubicación del iPhone al anotar. La ubicación está apagada para Al día en Ajustes del iPhone.")
                    } else {
                        HintText("Si no usas Wallet, apaga el aviso y la pantalla principal deja de pedirte que lo conectes. «Dónde pagas» usa la ubicación del iPhone al anotar.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    exportRow
                    Button(action: importCSV) {
                        IconRow("Importar CSV", systemImage: "square.and.arrow.down") { EmptyView() }
                    }
                    NavigationLink {
                        // Made when it is opened: its first state reads the keychain and the
                        // backup's folder, and a link builds its destination each time this draws.
                        Deferred { BackupSettingsView() }
                    } label: {
                        IconRow("Respaldo diario", systemImage: "lock.doc") {
                            Text(backupText)
                                .font(.ticket(.detail))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityIdentifier("ajustes-respaldo")
                } header: {
                    Text("Tus datos").ticketCaption()
                } footer: {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        if Features.money {
                            HintText("Se exportan todos los meses. Importar acepta el mismo archivo y no duplica gastos: si alguno parece repetido (mismo día y monto, con otro nombre o tarjeta), pregunta antes de agregarlo. El CSV es para tu hoja de cálculo: no guarda todo (ni «Mi dinero», ni tus ajustes, ni tus gastos fijos), así que no sustituye al respaldo diario.")
                        } else {
                            HintText("Se exportan todos los meses. Importar acepta el mismo archivo y no duplica gastos: si alguno parece repetido (mismo día y monto, con otro nombre o tarjeta), pregunta antes de agregarlo. El CSV es para tu hoja de cálculo: no guarda todo (ni tus ajustes, ni tus gastos fijos), así que no sustituye al respaldo diario.")
                        }
                        // Which build this is, to tell whether the iPhone has the latest (2026-10-30).
                        HintText(AppVersion.shownLine)
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
            .navigationDestination(isPresented: $showingRestore) {
                Deferred { BackupSettingsView(startsRestoring: true) }
            }
            .task {
                readCSV()
                if opensRestore {
                    opensRestore = false
                    showingRestore = true
                }
            }
            // A payment that lands, or a backup restored, while the sheet is open: the file
            // shared is what there is now, not what there was when it opened (2026-11-18).
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                readCSV()
            }
            // The answer to the system's question, or a change made in Ajustes of the iPhone.
            .onReceive(NotificationCenter.default.publisher(for: PaymentPlace.permissionChanged)) { _ in
                locationDenied = PaymentPlace.isDenied
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { locationDenied = PaymentPlace.isDenied }
            }
        }
    }

    /// «Exportar CSV», or with nothing to export, the same row off and saying why (2026-11-18):
    /// before, a faint row without a word looked broken, and VoiceOver read it as plain text.
    /// While the expenses are being read it says nothing, so an empty store is never guessed.
    @ViewBuilder private var exportRow: some View {
        if let csv, !csv.records.isEmpty {
            ShareLink(item: csv, preview: SharePreview("Gastos de Al día")) {
                IconRow("Exportar CSV", systemImage: "square.and.arrow.up") { EmptyView() }
            }
        } else {
            Button {} label: {
                IconRow("Exportar CSV", systemImage: "square.and.arrow.up") {
                    if csv != nil {
                        Text("Sin gastos todavía")
                            .font(.ticket(.detail))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .disabled(true)
            .accessibilityHint("Todavía no hay gastos que exportar.")
        }
    }

    /// The whole history as a CSV, read here and not on every redraw.
    private func readCSV() {
        let all = (try? context.fetch(FetchDescriptor<Expense>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        csv = ExpensesCSVFile(expenses: all, primaryCurrency: currency)
    }

    /// «Hoy», «Hace 4 días» or what's missing. Muted always: the guide's line is the warning.
    private var backupText: String {
        guard DailyBackup.isSetUp else { return String(localized: "Sin configurar") }
        guard let last = DailyBackup.lastBackup else { return String(localized: "Sin respaldo") }
        if AppClock.isToday(last) { return String(localized: "Hoy") }
        let text = AppClock.relative(last, locale: .current)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private var healthText: String {
        if ignoresWallet { return String(localized: "Aviso apagado") }
        switch health {
        case .never: return String(localized: "Sin conectar")
        case .waiting: return String(localized: "Esperando el primer pago · Toca si no terminaste")
        case .silent(let days): return String(localized: "\(days) días sin el primer pago")
        case .recent, .first: return String(localized: "Funciona")
        case .quiet(let days): return String(localized: "\(days) días sin pagos")
        }
    }
}

/// Whether the person told Al día they don't use Wallet: then the main screen stops asking
/// to connect it and stops warning about quiet days.
enum WalletWatch {
    static let key = "noUsaWallet"
    /// When Wallet last sent a payment (seconds since 2001), kept apart from the expenses:
    /// deleting the payments that came from Wallet must not make it look disconnected
    /// (owner, 2026-11-01). The main screen takes the later of this and the newest capture.
    static let lastArrivalKey = "walletUltimaLlegada"

    static func noteArrival(_ date: Date = AppClock.now) {
        let defaults = UserDefaults.standard
        let known = defaults.double(forKey: lastArrivalKey)
        if date.timeIntervalSinceReferenceDate > known {
            defaults.set(date.timeIntervalSinceReferenceDate, forKey: lastArrivalKey)
        }
    }

    /// The later of the remembered arrival and the newest capture still in the store.
    static func lastCapture(stored: Double, newestInStore: Date?) -> Date? {
        let remembered = stored > 0 ? Date(timeIntervalSinceReferenceDate: stored) : nil
        return [remembered, newestInStore].compactMap { $0 }.max()
    }
}

#Preview {
    SettingsView(currency: "MXN", setCurrency: { _ in }, health: .never, openGuide: {}, importCSV: {},
                 opensRestore: .constant(false))
        .ticketPreview()
}
