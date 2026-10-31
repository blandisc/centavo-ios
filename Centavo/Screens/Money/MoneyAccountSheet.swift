import CentavoCore
import SwiftData
import SwiftUI

/// Adds an account with today's balance, or edits one's name and rate. The kind and currency
/// are fixed once it exists: changing them would rewrite every past cut.
struct MoneyAccountSheet: View {
    let account: MoneyAccount?
    let mainCurrency: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var kind: MoneyKind = .account
    @State private var name = ""
    @State private var currency = ""
    @State private var balance = ""
    @State private var rate = ""
    @State private var exchange = ""
    @State private var confirmingArchive = false
    @State private var problem: String?

    private var isNew: Bool { account == nil }
    private var isForeign: Bool { currency != mainCurrency }
    private var takesRate: Bool { kind == .account || kind == .debt }
    private static let currencies = ["MXN", "USD", "EUR"]

    private var parsedBalance: Decimal? { AmountParser.parse(balance)?.value }
    private var parsedRate: Decimal? { rate.isEmpty ? nil : AmountParser.parse(rate)?.value }
    private var parsedExchange: Decimal? { AmountParser.parse(exchange)?.value }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if !rate.isEmpty && parsedRate == nil { return false }
        guard isNew else { return true }
        return parsedBalance != nil && (!isForeign || (parsedExchange ?? 0) > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isNew {
                    Section {
                        Picker("Qué es", selection: $kind) {
                            Text("Cuenta").tag(MoneyKind.account)
                            Text("Inversión").tag(MoneyKind.investment)
                            Text("Me deben").tag(MoneyKind.receivable)
                            Text("Debo").tag(MoneyKind.debt)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Theme.background)
                        .listRowInsets(EdgeInsets())
                        .accessibilityIdentifier("cuenta-tipo")
                    } footer: {
                        HintText(kindHint)
                    }
                }

                Section {
                    TicketTextField("Nombre", text: $name, prompt: namePrompt, identifier: "cuenta-nombre")
                    if isNew {
                        Picker(selection: $currency) {
                            ForEach(Self.currencies, id: \.self) { Text(CurrencyPreference.name($0)).tag($0) }
                        } label: {
                            Text("Moneda").font(.ticket(.body)).foregroundStyle(Theme.ink)
                        }
                    } else if let account {
                        LabeledContent("Moneda") { Text(CurrencyPreference.name(account.currency)).foregroundStyle(Theme.muted) }
                            .font(.ticket(.body))
                    }
                } header: {
                    Text("Cuenta").ticketCaption()
                }
                .listRowBackground(Theme.surface)

                if isNew {
                    Section {
                        amountField(balanceTitle, text: $balance, identifier: "cuenta-saldo")
                        if isForeign {
                            amountField("1 \(currency) = \(mainCurrency)", text: $exchange, identifier: "cuenta-cambio")
                        }
                    } header: {
                        Text(balanceTitle).ticketCaption()
                    } footer: {
                        HintText(isForeign ? "El tipo de cambio de hoy: con él se suma a tu patrimonio en \(mainCurrency). Lo actualizas en cada corte."
                                           : "Lo que hay hoy. Lo actualizas en cada corte.")
                    }
                    .listRowBackground(Theme.surface)
                }

                if takesRate {
                    Section {
                        amountField("Tasa anual · opcional", text: $rate, identifier: "cuenta-tasa")
                    } header: {
                        Text("Rendimiento").ticketCaption()
                    } footer: {
                        HintText(kind == .debt ? "El interés que te cobran al año, en %. Solo para orientarte en el corte."
                                               : "En %, por ejemplo 10.5. Con ella el corte te dice cuánto debió rendir.")
                    }
                    .listRowBackground(Theme.surface)
                }

                if !isNew {
                    Section {
                        DestructiveRowButton("Archivar", identifier: "cuenta-archivar") { confirmingArchive = true }
                    } footer: {
                        HintText("Sale de tus próximos cortes. Los cortes pasados la conservan.")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .ticketForm()
            .foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle(isNew ? "Nueva cuenta" : "Cuenta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.font(.ticket(.footnoteStrong))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .font(.ticket(.footnoteStrong))
                        .disabled(!canSave)
                        .accessibilityIdentifier("cuenta-guardar")
                }
            }
            .alert("¿Archivar \(name)?", isPresented: $confirmingArchive) {
                Button("Cancelar", role: .cancel) {}
                Button("Archivar", role: .destructive, action: archive)
            } message: {
                Text("Deja de salir en tu patrimonio y en los próximos cortes.")
            }
            .alert("No se pudo", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: { Text(problem ?? "") }
            .onAppear(perform: load)
        }
    }

    private var kindHint: String {
        switch kind {
        case .account: "Banco, ahorro o efectivo: dinero tuyo hoy."
        case .investment: "Sube y baja, como un fondo o acciones. En cada corte escribes cuánto vale."
        case .receivable: "Un préstamo que hiciste o un bono que aún no te pagan. Suma marcado «por caer»."
        case .debt: "Lo que debes hoy en una tarjeta o un préstamo, no su límite."
        }
    }

    private var namePrompt: String {
        switch kind {
        case .account: "Nu cajita, BBVA nómina…"
        case .investment: "Fondo GBM, acciones…"
        case .receivable: "Préstamo a Ana, bono anual…"
        case .debt: "Amex, préstamo del auto…"
        }
    }

    private var balanceTitle: String { kind == .debt ? "Lo que debes hoy" : "Cuánto hay hoy" }

    private func amountField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        TextField(title, text: text, prompt: Text(title).foregroundStyle(Theme.faint))
            .font(.ticket(.field))
            .keyboardType(.decimalPad)
            .foregroundStyle(Theme.ink)
            .accessibilityIdentifier(identifier)
    }

    private func load() {
        guard currency.isEmpty else { return }
        currency = account?.currency ?? mainCurrency
        guard let account else { return }
        kind = account.kind
        name = account.name
        rate = account.yearlyRate.map { BackupNumber.text($0) } ?? ""
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            if let account {
                account.name = trimmed
                account.yearlyRate = takesRate ? parsedRate : nil
                try context.save()
            } else if let value = parsedBalance {
                let new = MoneyAccount(name: trimmed, kind: kind, currency: currency, yearlyRate: takesRate ? parsedRate : nil)
                try MoneyStore.add(new, balance: value, rate: isForeign ? parsedExchange : nil,
                                   in: context, mainCurrency: mainCurrency)
            }
            dismiss()
        } catch {
            problem = "No se guardó. Intenta otra vez."
        }
    }

    private func archive() {
        account?.archived = true
        try? context.save()
        dismiss()
    }
}
