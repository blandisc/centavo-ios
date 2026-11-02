import CentavoCore
import SwiftData
import SwiftUI

/// Adds or edits what comes in each month (2026-11-02 audit): the salary, a rent collected.
/// Only incomes that repeat; they never add to the net worth. «Quitar» archives it.
struct MoneyIncomeSheet: View {
    let income: MoneyIncome?
    let mainCurrency: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var institution = ""
    @State private var currency = ""
    @State private var amount = ""
    @State private var confirmingRemove = false
    @State private var problem: String?

    private var isNew: Bool { income == nil }
    /// The offered ones, plus the income's own and the main one when they aren't (an imported
    /// income in another currency showed an empty picker; second audit, 2026-11-02).
    private var currencies: [String] {
        var list = MoneyCurrency.offered
        for code in [mainCurrency, income?.currency].compactMap({ $0 }) where !list.contains(code) { list.insert(code, at: 0) }
        return list
    }
    /// Something typed: a stray swipe down must not throw it away.
    private var hasChanges: Bool {
        guard let income else {
            return !(name + institution + amount).trimmingCharacters(in: .whitespaces).isEmpty
                || (!currency.isEmpty && currency != mainCurrency)
        }
        return name != income.name || institution != (income.institution ?? "")
            || amount != BackupNumber.text(income.amount) || (!currency.isEmpty && currency != income.currency)
    }
    private var parsedAmount: Decimal? { MoneyAmount.read(amount) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (parsedAmount ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TicketTextField("Nombre", text: $name, prompt: "Sueldo, renta que cobras…", identifier: "ingreso-nombre")
                    TicketTextField("De dónde", text: $institution, prompt: "De dónde · opcional (tu empresa…)",
                                    identifier: "ingreso-institucion")
                    Picker(selection: $currency) {
                        ForEach(currencies, id: \.self) { Text(MoneyCurrency.name($0)).tag($0) }
                    } label: {
                        Text("Moneda").font(.ticket(.body)).foregroundStyle(Theme.ink)
                    }
                } header: {
                    Text("Ingreso").ticketCaption()
                }
                .listRowBackground(Theme.surface)

                Section {
                    TextField("Cuánto te entra al mes", text: $amount,
                              prompt: Text("\(MoneyCurrency.symbol(currency.isEmpty ? mainCurrency : currency))0").foregroundStyle(Theme.faint))
                        .font(.ticket(.field))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("ingreso-monto")
                } header: {
                    Text("Cuánto te entra al mes").ticketCaption()
                } footer: {
                    HintText(isNew ? "Ya sin impuestos. No suma a tu patrimonio: sirve para saber cuánto debías ahorrar."
                                   : "Si cambia desde este mes, los meses pasados conservan lo de antes.")
                }
                .listRowBackground(Theme.surface)

                if !isNew {
                    Section {
                        DestructiveRowButton("Quitar ingreso", identifier: "ingreso-quitar") { confirmingRemove = true }
                    } footer: {
                        HintText("Deja de contar desde este mes.")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .ticketForm()
            .foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle(isNew ? "Nuevo ingreso" : "Ingreso")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.font(.ticket(.footnoteStrong))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .font(.ticket(.footnoteStrong))
                        .disabled(!canSave)
                        .accessibilityIdentifier("ingreso-guardar")
                }
            }
            .alert("¿Quitar \(name)?", isPresented: $confirmingRemove) {
                Button("Cancelar", role: .cancel) {}
                Button("Quitar", role: .destructive, action: remove)
            } message: {
                Text("Deja de contar como lo que te entra al mes.")
            }
            .alert("No se guardó el ingreso", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: { Text(problem ?? "") }
            .onAppear(perform: load)
            .onMoneyCovered { confirmingRemove = false; problem = nil }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    private func load() {
        guard currency.isEmpty else { return }
        currency = income?.currency ?? mainCurrency
        guard let income else { return }
        name = income.name
        institution = income.institution ?? ""
        amount = BackupNumber.text(income.amount)
    }

    private func save() {
        guard let value = parsedAmount else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let from = institution.trimmingCharacters(in: .whitespaces)
        do {
            if let income {
                try MoneyStore.updateIncome(income, name: trimmed, institution: from.isEmpty ? nil : from,
                                            amount: value, currency: currency, in: context)
            } else {
                try MoneyStore.addIncome(name: trimmed, institution: from.isEmpty ? nil : from,
                                         amount: value, currency: currency, in: context)
            }
            dismiss()
        } catch {
            problem = "Intenta otra vez."
        }
    }

    private func remove() {
        guard let income else { return }
        do {
            try MoneyStore.removeIncome(income, in: context)
            dismiss()
        } catch {
            problem = "No se pudo quitar. Intenta otra vez."
        }
    }
}

#Preview {
    MoneyIncomeSheet(income: nil, mainCurrency: "MXN")
        .modelContainer(try! MoneyStore.inMemory())
        .ticketPreview()
}
