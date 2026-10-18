import CentavoCore
import SwiftData
import SwiftUI

/// Sheet to add a manual expense (`expense == nil`) or correct an existing one.
struct ExpenseEditorView: View {
    let expense: Expense?
    /// Where a new expense's date starts (the end of the month being browsed); `nil` is now.
    var initialDate: Date?
    /// How the list deletes, so «Deshacer» works from here too. Without it, a plain delete.
    var onDelete: ((Expense) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Expense.date, order: .reverse) private var history: [Expense]
    @State private var amountText = ""
    /// The expense's currency. New ones start in the month's currency.
    @State private var currency = CurrencyPreference.current
    @State private var isRefund = false
    @State private var merchant = ""
    @State private var card = ""
    @State private var category = ""
    @State private var date = Date.now
    @State private var repeatsMonthly = false
    @State private var confirmingDelete = false
    @FocusState private var amountFocused: Bool

    /// Whether something was typed or changed since the sheet opened.
    private var hasChanges: Bool {
        guard let expense else {
            return !(amountText + merchant + card + category).trimmingCharacters(in: .whitespaces).isEmpty
        }
        return parsed?.value != expense.amount.magnitude || isRefund != (expense.amount < 0)
            || merchant != expense.merchant || card != (expense.card ?? "")
            || category != (expense.category ?? "") || date != expense.date
            || repeatsMonthly != (expense.repeatsMonthly == true)
    }

    private var parsed: ParsedAmount? { AmountParser.parse(amountText) }
    /// The offered currencies, plus this expense's own if it came in another (Wallet abroad).
    private var currencies: [String] {
        CurrencyPreference.offered.contains(currency)
            ? CurrencyPreference.offered : CurrencyPreference.offered + [currency]
    }
    /// A zero amount is never a real expense, so it cannot be saved.
    private var canSave: Bool {
        guard let parsed, parsed.value != 0 else { return false }
        return !merchant.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Read once when the sheet opens: rebuilding it from the whole history on every key
    /// typed was felt with thousands of expenses.
    @State private var pastExpenses: [CategorizedExpense] = []

    private var allPastExpenses: [CategorizedExpense] {
        history.map {
            CategorizedExpense(merchant: $0.merchant, category: $0.category, date: $0.date)
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String,
                       identifier: String) -> some View {
        TextField(title, text: text, prompt: Text(prompt).foregroundStyle(Theme.faint))
            .font(.ticket(17, relativeTo: .body))
            .tracking(0.6)
            .foregroundStyle(Theme.ink)
            .accessibilityIdentifier(identifier)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.ticket(11, relativeTo: .caption2))
            .tracking(0.6)
            .foregroundStyle(Theme.faint)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Monto", text: $amountText,
                              prompt: Text("0.00").foregroundStyle(Theme.faint))
                        .font(.ticket(44, weight: .medium, relativeTo: .largeTitle))
                        .tracking(-1.5)
                        .foregroundStyle(Theme.ink)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .accessibilityIdentifier("monto")
                    // The decimal pad has no minus key, so a refund is a switch rather than a sign.
                    Toggle(isOn: $isRefund) {
                        Text("Es una devolución")
                            .font(.ticket(12, relativeTo: .footnote))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    .tint(Theme.brass)
                    .accessibilityIdentifier("devolucion")
                    // The decimal pad cannot type "USD" or "€", so the currency is a choice.
                    Picker("Moneda", selection: $currency) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("moneda")
                } header: {
                    Text("Monto").ticketCaption()
                }
                .listRowBackground(Theme.surface)

                Section {
                    field("Comercio", text: $merchant, prompt: "Nombre del comercio",
                          identifier: "comercio")
                        .textInputAutocapitalization(.words)
                    categoryRow
                } header: {
                    Text("Comercio y categoría").ticketCaption()
                } footer: {
                    if let remembered = CategoryMemory.category(for: merchant, in: pastExpenses) {
                        hint("La última vez en \(merchant.trimmingCharacters(in: .whitespaces)) fue \(remembered).")
                    } else if let suggested = MerchantCatalog.category(for: merchant) {
                        hint("Sugerida para \(merchant.trimmingCharacters(in: .whitespaces)): \(suggested). Cámbiala si no te queda.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    DatePicker(selection: $date, in: ...Date.now) {
                        Text("Fecha")
                            .font(.ticket(12, relativeTo: .footnote))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    field("Tarjeta o efectivo (opcional)", text: $card,
                          prompt: "BBVA, Nu, efectivo…", identifier: "tarjeta")
                        .textInputAutocapitalization(.words)
                    if expense?.isRepeat != true {
                        Toggle(isOn: $repeatsMonthly) {
                            Text("Se repite cada mes")
                                .font(.ticket(12, relativeTo: .footnote))
                                .tracking(1.2)
                                .textCase(.uppercase)
                        }
                        .tint(Theme.brass)
                        .accessibilityIdentifier("se-repite")
                    }
                } header: {
                    Text("Fecha y tarjeta").ticketCaption()
                } footer: {
                    if repeatsMonthly {
                        hint("Renta, suscripciones, la luz: se anota sola el mismo día de cada mes.")
                    } else if expense?.isRepeat == true {
                        hint("Se anotó solo, de un gasto fijo.")
                    }
                }
                .listRowBackground(Theme.surface)

                if expense?.isRepeat == true, original != nil {
                    Section {
                        Button("Dejar de repetir cada mes") { stopRepeating() }
                            .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.brass)
                            .accessibilityIdentifier("dejar-de-repetir")
                    } footer: {
                        hint("Los meses ya anotados se quedan; el siguiente ya no llega.")
                    }
                    .listRowBackground(Theme.surface)
                }

                if expense != nil {
                    Section {
                        Button("Borrar gasto", role: .destructive) { confirmingDelete = true }
                            .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .accessibilityIdentifier("borrar-gasto")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .ticketForm()
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle(expense == nil ? "Nuevo gasto" : "Editar gasto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(.ticket(13, relativeTo: .footnote))
                        .accessibilityIdentifier("hoja-cancelar")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                        .disabled(!canSave)
                        .accessibilityIdentifier("hoja-guardar")
                }
            }
            .confirmationDialog("¿Borrar este gasto?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Borrar", role: .destructive) {
                    if let expense {
                        if let onDelete { onDelete(expense) } else { context.delete(expense) }
                    }
                    dismiss()
                }
            }
        }
        .onAppear(perform: load)
        // Swiping the sheet away must not throw away what was typed.
        .interactiveDismissDisabled(hasChanges)
        .onChange(of: merchant) { _, new in
            // Change the merchant and the category you last used for it fills in,
            // but only while the field is empty — never overwrite a typed one. Only for a new
            // expense: opening an uncategorized one must not quietly file it.
            guard expense == nil, category.trimmingCharacters(in: .whitespaces).isEmpty,
                  let remembered = MerchantCatalog.suggestion(for: new, history: pastExpenses)
            else { return }
            category = remembered
        }
    }

    /// Free-text field, plus the categories already in use so they stay spelled
    /// one way instead of fragmenting into near-duplicates.
    private var categoryRow: some View {
        let known = CategoryMemory.known(in: pastExpenses)
        return HStack {
            field("Categoría (opcional)", text: $category, prompt: "Despensa, transporte…",
                  identifier: "categoria")
                .textInputAutocapitalization(.words)
            if !known.isEmpty {
                Menu {
                    ForEach(known, id: \.self) { name in
                        Button(name) { category = name }
                    }
                    if !category.isEmpty {
                        Divider()
                        Button("Quitar categoría", role: .destructive) { category = "" }
                    }
                } label: {
                    Label("Categorías usadas", systemImage: "chevron.up.chevron.down")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    /// The fixed expense a copy came from: same merchant and amount, still repeating.
    private var original: Expense? {
        guard let expense, expense.isRepeat == true else { return nil }
        let merchant = expense.merchant, amount = expense.amount
        let candidates = try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate {
            $0.repeatsMonthly == true && $0.merchant == merchant
        }))
        return candidates?.first { $0.amount == amount }
    }

    private func stopRepeating() {
        guard let original else { return }
        original.repeatsMonthly = nil
        original.repeatsThrough = nil
        original.repeatDay = nil
        dismiss()
    }

    private func load() {
        pastExpenses = allPastExpenses
        guard let expense else {
            if let initialDate { date = initialDate }
            amountFocused = true
            return
        }
        // A bare "$" from Wallet is the month's currency; anything else keeps its own.
        currency = CurrencyResolver.isoCode(for: expense.currencyMarker,
                                            primary: CurrencyPreference.current)
            ?? CurrencyPreference.current
        isRefund = expense.amount < 0
        amountText = expense.amount.magnitude
            .formatted(.number.precision(.fractionLength(2)).grouping(.never))
        merchant = expense.merchant
        repeatsMonthly = expense.repeatsMonthly == true
        card = expense.card ?? ""
        category = expense.category ?? ""
        date = expense.date
    }

    /// Turning it on starts counting from the expense's own month; turning it off stops it.
    private func setRepeats(_ expense: Expense) {
        if repeatsMonthly {
            // From now on: marking an old expense must not backfill months already lived (and
            // maybe already logged by hand).
            if expense.repeatsMonthly != true { expense.repeatsThrough = max(date, Date.now) }
            expense.repeatsMonthly = true
            expense.repeatDay = Calendar.current.component(.day, from: date)
        } else {
            expense.repeatsMonthly = nil
            expense.repeatsThrough = nil
            expense.repeatDay = nil
        }
    }

    private func save() {
        guard let parsed else { return }
        let name = merchant.trimmingCharacters(in: .whitespaces)
        let cardName = card.trimmingCharacters(in: .whitespaces)
        let categoryName = category.trimmingCharacters(in: .whitespaces)
        let value = isRefund ? -parsed.value.magnitude : parsed.value.magnitude
        // Saved as its ISO code, never "$": a bare "$" would follow the month's currency and
        // change meaning if that is switched later.
        if let expense {
            expense.amount = value
            let before = CurrencyResolver.isoCode(for: expense.currencyMarker,
                                                  primary: CurrencyPreference.current)
            if before != currency { expense.currencyMarker = currency }
            expense.merchant = name
            expense.card = cardName.isEmpty ? nil : cardName
            expense.category = categoryName.isEmpty ? nil : categoryName
            expense.date = date
            if expense.isRepeat != true { setRepeats(expense) }
        } else {
            let new = Expense(
                amount: value,
                currencyMarker: currency,
                merchant: name,
                card: cardName.isEmpty ? nil : cardName,
                date: date,
                category: categoryName.isEmpty ? nil : categoryName
            )
            setRepeats(new)
            context.insert(new)
        }
        dismiss()
    }
}

#Preview("Nuevo") {
    ExpenseEditorView(expense: nil)
        .modelContainer(for: Expense.self, inMemory: true)
        .preferredColorScheme(.dark)
}
