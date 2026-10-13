import CentavoCore
import SwiftData
import SwiftUI

/// Sheet to add a manual expense (`expense == nil`) or correct an existing one.
struct ExpenseEditorView: View {
    let expense: Expense?
    /// Where a new expense's date starts (the end of the month being browsed); `nil` is now.
    var initialDate: Date?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Expense.date, order: .reverse) private var history: [Expense]
    @State private var amountText = ""
    @State private var isRefund = false
    @State private var merchant = ""
    @State private var card = ""
    @State private var category = ""
    @State private var date = Date.now
    @State private var confirmingDelete = false
    @FocusState private var amountFocused: Bool

    private var parsed: ParsedAmount? { AmountParser.parse(amountText) }
    /// A zero amount is never a real expense, so it cannot be saved.
    private var canSave: Bool {
        guard let parsed, parsed.value != 0 else { return false }
        return !merchant.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var pastExpenses: [CategorizedExpense] {
        history.map {
            CategorizedExpense(merchant: $0.merchant, category: $0.category, date: $0.date)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Monto", text: $amountText, prompt: Text("0.00"))
                        .font(.largeTitle.weight(.semibold).monospacedDigit())
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .accessibilityIdentifier("monto")
                    // The decimal pad has no minus key, so a refund is a switch rather than a sign.
                    Toggle("Es una devolución", isOn: $isRefund)
                        .accessibilityIdentifier("devolucion")
                } footer: {
                    Text("Otra moneda: escribe USD 20 o € 20.")
                }

                Section {
                    TextField("Comercio", text: $merchant, prompt: Text("Nombre del comercio"))
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("comercio")
                    categoryRow
                } footer: {
                    if let remembered = CategoryMemory.category(for: merchant, in: pastExpenses) {
                        Text("La última vez en \(merchant.trimmingCharacters(in: .whitespaces)) fue \(remembered).")
                    }
                }

                Section {
                    DatePicker("Fecha", selection: $date, in: ...Date.now)
                    TextField("Tarjeta o efectivo (opcional)", text: $card,
                              prompt: Text("BBVA, Nu, efectivo…"))
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("tarjeta")
                }

                if expense != nil {
                    Section {
                        Button("Borrar gasto", role: .destructive) { confirmingDelete = true }
                            .accessibilityIdentifier("borrar-gasto")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(expense == nil ? "Nuevo gasto" : "Editar gasto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .accessibilityIdentifier("hoja-cancelar")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("hoja-guardar")
                }
            }
            .confirmationDialog("¿Borrar este gasto?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Borrar", role: .destructive) {
                    if let expense { context.delete(expense) }
                    dismiss()
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: merchant) { _, new in
            // Change the merchant and the category you last used for it fills in,
            // but only while the field is empty — never overwrite a typed one.
            guard category.trimmingCharacters(in: .whitespaces).isEmpty,
                  let remembered = CategoryMemory.category(for: new, in: pastExpenses)
            else { return }
            category = remembered
        }
    }

    /// Free-text field, plus the categories already in use so they stay spelled
    /// one way instead of fragmenting into near-duplicates.
    private var categoryRow: some View {
        let known = CategoryMemory.known(in: pastExpenses)
        return HStack {
            TextField("Categoría (opcional)", text: $category,
                      prompt: Text("Despensa, transporte…"))
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("categoria")
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
                }
            }
        }
    }

    private func load() {
        guard let expense else {
            if let initialDate { date = initialDate }
            amountFocused = true
            return
        }
        isRefund = expense.amount < 0
        amountText = expense.amount.magnitude
            .formatted(.number.precision(.fractionLength(2)).grouping(.never))
        merchant = expense.merchant
        card = expense.card ?? ""
        category = expense.category ?? ""
        date = expense.date
    }

    private func save() {
        guard let parsed else { return }
        let name = merchant.trimmingCharacters(in: .whitespaces)
        let cardName = card.trimmingCharacters(in: .whitespaces)
        let categoryName = category.trimmingCharacters(in: .whitespaces)
        let value = isRefund ? -parsed.value.magnitude : parsed.value.magnitude
        // "89 pesos" is not a currency; only keep a marker that looks like one.
        let typedMarker = parsed.currencyMarker.flatMap { CurrencyResolver.recognizes($0) ? $0 : nil }
        if let expense {
            expense.amount = value
            if let marker = typedMarker { expense.currencyMarker = marker }
            expense.merchant = name
            expense.card = cardName.isEmpty ? nil : cardName
            expense.category = categoryName.isEmpty ? nil : categoryName
            expense.date = date
        } else {
            context.insert(Expense(
                amount: value,
                currencyMarker: typedMarker ?? "$",
                merchant: name,
                card: cardName.isEmpty ? nil : cardName,
                date: date,
                category: categoryName.isEmpty ? nil : categoryName
            ))
        }
        dismiss()
    }
}

#Preview("Nuevo") {
    ExpenseEditorView(expense: nil)
        .modelContainer(for: Expense.self, inMemory: true)
}
