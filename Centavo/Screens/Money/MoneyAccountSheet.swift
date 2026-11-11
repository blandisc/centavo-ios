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
    /// What a new debt or money owed is within its kind, as the first time asks (second audit,
    /// 2026-11-02: from here they were saved without it).
    @State private var debtSubtype: MoneySubtype = .card
    @State private var owedSubtype: MoneySubtype = .lent
    @State private var name = ""
    @State private var institution = ""
    @State private var currency = ""
    @State private var balance = ""
    @State private var rate = ""
    @State private var exchange = ""
    @State private var confirmingArchive = false
    @State private var askingDiscard = false
    @State private var problem: String?

    private var isNew: Bool { account == nil }
    private var isForeign: Bool { currency != mainCurrency }
    /// The same rule as the first time: an investment keeps its rate (editing it used to drop it).
    private var takesRate: Bool { account.map { MoneySubtype.of($0).takesRate } ?? subtype.takesRate }
    /// The subtype a new line is saved with.
    private var subtype: MoneySubtype {
        switch kind {
        case .account: .account
        case .investment: .investment
        case .debt: debtSubtype
        case .receivable: owedSubtype
        }
    }
    /// The rate typed now won't change the latest cut (a past month's, which keeps its own):
    /// it waits for the next cut, and the sheet says so.
    /// Added after the latest cut's month: its money may have come out of another account,
    /// still shown with its balance at that cut (independent review).
    private var opensAfterLatest: Bool {
        isNew && MoneyStore.latestCut(in: context).map { $0.month < MoneyMath.monthKey(of: AppClock.now) } == true
    }
    private var rateWaits: Bool { isNew && isForeign && MoneyStore.rateWaits(for: currency, in: context) }
    /// The same seven as the first time (`MoneyCurrency.offered`), and the main one if it isn't.
    private var currencies: [String] {
        MoneyCurrency.offered.contains(mainCurrency) ? MoneyCurrency.offered : [mainCurrency] + MoneyCurrency.offered
    }
    @Environment(\.dynamicTypeSize) private var typeSize

    private var parsedBalance: Decimal? { MoneyAmount.read(balance) }
    private var parsedRate: Decimal? { rate.isEmpty ? nil : MoneyMath.decimal(rate) }
    private var parsedExchange: Decimal? { MoneyMath.decimal(exchange) }
    private var institutionOrNil: String? {
        let text = institution.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if !rate.isEmpty && parsedRate == nil { return false }
        guard isNew else { return true }
        return parsedBalance != nil && (!isForeign || (parsedExchange ?? 0) > 0)
    }

    /// What «Guardar» will save, or the first thing still missing (owner, 2026-11-11), in the
    /// order `canSave` asks for it.
    private var saveSummary: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Falta el nombre" }
        if !rate.isEmpty && parsedRate == nil { return "La tasa no se lee" }
        guard isNew else { return [trimmed, institutionOrNil].compactMap { $0 }.joined(separator: " · ") }
        guard let value = parsedBalance else {
            if !balance.trimmingCharacters(in: .whitespaces).isEmpty { return "El saldo no se lee" }
            return kind == .debt ? "Falta cuánto debes" : "Falta el saldo"
        }
        if isForeign && (parsedExchange ?? 0) <= 0 { return "Falta el tipo de cambio" }
        return "\(trimmed) · \(formatMoney(value, isoCode: currency, label: currency, main: mainCurrency))"
    }

    var body: some View {
        NavigationStack {
            Form {
                if isNew {
                    Section {
                        // Four segments cut their names with large text: there, one row each.
                        if typeSize.isAccessibilitySize {
                            kindPicker
                                .pickerStyle(.inline)
                                .labelsHidden()
                                .listRowBackground(Theme.surface)
                        } else {
                            kindPicker
                                .pickerStyle(.segmented)
                                .listRowBackground(Theme.background)
                                .listRowInsets(EdgeInsets())
                        }
                    } footer: {
                        HintText(kindHint)
                    }
                    if kind == .debt || kind == .receivable {
                        Section {
                            Picker(selection: kind == .debt ? $debtSubtype : $owedSubtype) {
                                ForEach(kind == .debt ? [MoneySubtype.card, .loan, .other] : [MoneySubtype.lent, .coming],
                                        id: \.self) { Text($0.name).tag($0) }
                            } label: {
                                Text(kind == .debt ? "Qué debes" : "Qué es").font(.ticket(.body)).foregroundStyle(Theme.ink)
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.brass)
                            .accessibilityIdentifier("cuenta-subtipo")
                        }
                        .listRowBackground(Theme.surface)
                    }
                }

                Section {
                    TicketTextField("Nombre", text: $name, prompt: namePrompt, identifier: "cuenta-nombre")
                    TicketTextField("Institución", text: $institution, prompt: "Institución · opcional (Nu, BBVA…)",
                                    identifier: "cuenta-institucion")
                    if isNew {
                        Picker(selection: $currency) {
                            ForEach(currencies, id: \.self) { Text(CurrencyPreference.name($0)).tag($0) }
                        } label: {
                            Text("Moneda").font(.ticket(.body)).foregroundStyle(Theme.ink)
                        }
                    } else if let account {
                        LabeledContent("Moneda") { Text(CurrencyPreference.name(account.currency)).foregroundStyle(Theme.muted) }
                            .font(.ticket(.body))
                    }
                } header: {
                    Text("Cuenta").ticketCaption()
                } footer: {
                    if !isNew { HintText("El saldo se actualiza en el corte.") }
                }
                .listRowBackground(Theme.surface)

                if isNew {
                    Section {
                        amountField(balanceTitle, text: $balance, identifier: "cuenta-saldo")
                            .groupsMoney($balance)
                        if isForeign {
                            amountField("1 \(currency) = \(mainCurrency)", text: $exchange, identifier: "cuenta-cambio")
                        }
                    } header: {
                        Text(balanceTitle).ticketCaption()
                    } footer: {
                        HintText(rateWaits ? "Tu último corte ya tiene tipo de cambio de \(currency) y se suma con ese. Este se usa en tu próximo corte."
                                 : isForeign ? "El tipo de cambio de hoy: con él se suma a tu patrimonio en \(mainCurrency). Lo actualizas en cada corte."
                                 : opensAfterLatest ? "Lo que hay hoy. Si este dinero salió de otra de tus cuentas, cambia también su saldo."
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
                                               : "En %, por ejemplo 10.5. Con ella, cada corte te dice cuánto debió rendir.")
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
            .moneySheetKeyboard()
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle(isNew ? "Nueva cuenta" : "Cuenta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        if hasChanges { askingDiscard = true } else { dismiss() }
                    }
                    .font(.ticket(.footnoteStrong))
                }
            }
            // «Guardar» at the bottom with what it saves, as in the sheets of «Hoy» (2026-11-11).
            .saveBar(saveSummary, enabled: canSave, identifier: "cuenta-guardar", action: save)
            // The one way to ask before something goes away (owner, 2026-11-11).
            .confirmsRemoval(isPresented: $confirmingArchive, question: {
                TicketQuestion(title: "¿Archivar esta cuenta?", name: account?.name ?? name,
                               note: "Deja de sumar en tu patrimonio y de salir en los próximos cortes; los cortes pasados la conservan. La puedes regresar desde «Archivadas».",
                               verb: "Archivar")
            }, onConfirm: archive)
            .alert(problem ?? "", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: { Text("Intenta otra vez.") }
            .onAppear(perform: load)
            .onMoneyCovered { confirmingArchive = false; askingDiscard = false; problem = nil }
        }
        // «¿Descartar cambios?» on «Cancelar» and on swiping down, with something typed.
        .confirmsDiscard(hasChanges: hasChanges, isAsking: $askingDiscard) { dismiss() }
    }

    private var kindPicker: some View {
        Picker("Qué es", selection: $kind) {
            Text("Cuenta").tag(MoneyKind.account)
            Text("Inversión").tag(MoneyKind.investment)
            Text("Te deben").tag(MoneyKind.receivable)
            Text("Debes").tag(MoneyKind.debt)
        }
        .accessibilityIdentifier("cuenta-tipo")
    }

    /// Something typed: a stray swipe down must not throw it away.
    private var hasChanges: Bool {
        guard let account else {
            return !(name + institution + balance + rate + exchange).trimmingCharacters(in: .whitespaces).isEmpty
                || kind != .account || (!currency.isEmpty && currency != mainCurrency)
                || debtSubtype != .card || owedSubtype != .lent
        }
        return name != account.name || institution != (account.institution ?? "")
            || rate != (account.yearlyRate.map { BackupNumber.text($0) } ?? "")
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
        institution = account.institution ?? ""
        rate = account.yearlyRate.map { BackupNumber.text($0) } ?? ""
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            if let account {
                account.name = trimmed
                account.institution = institutionOrNil
                account.yearlyRate = takesRate ? parsedRate : nil
                do {
                    try context.save()
                } catch {
                    // Not left half-saved in memory, looking saved until the app closes.
                    context.rollback()
                    throw error
                }
            } else if let value = parsedBalance {
                let new = MoneyAccount(name: trimmed, kind: kind, currency: currency, yearlyRate: takesRate ? parsedRate : nil)
                new.subtype = subtype.rawValue
                new.institution = institutionOrNil
                try MoneyStore.add(new, balance: value, rate: isForeign ? parsedExchange : nil,
                                   in: context, mainCurrency: mainCurrency)
            }
            dismiss()
        } catch {
            problem = "No se guardó la cuenta"
        }
    }

    private func archive() {
        account?.archived = true
        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            problem = "No se archivó la cuenta"
        }
    }
}
