import CentavoCore
import SwiftData
import SwiftUI

/// Sheet to add a manual expense (`expense == nil`) or correct an existing one.
struct ExpenseEditorView: View {
    let expense: Expense?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Expense.date, order: .reverse) private var history: [Expense]
    @State private var amountText = ""
    @State private var merchant = ""
    @State private var card = ""
    @State private var category = ""
    @State private var date = Date.now
    @FocusState private var amountFocused: Bool

    private var parsed: ParsedAmount? { AmountParser.parse(amountText) }
    private var canSave: Bool {
        parsed != nil && !merchant.trimmingCharacters(in: .whitespaces).isEmpty
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
                    TextField("Monto", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .focused($amountFocused)
                    TextField("Comercio", text: $merchant)
                        .textInputAutocapitalization(.words)
                    categoryRow
                }
                Section {
                    DatePicker("Fecha", selection: $date, in: ...Date.now)
                    TextField("Tarjeta o efectivo (opcional)", text: $card)
                }
                if let expense {
                    Section {
                        Button("Borrar gasto", role: .destructive) {
                            context.delete(expense)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(expense == nil ? "Nuevo gasto" : "Editar gasto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(!canSave)
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
    }

    /// Free-text field, plus the categories already in use so they stay spelled
    /// one way instead of fragmenting into near-duplicates.
    private var categoryRow: some View {
        let known = CategoryMemory.known(in: pastExpenses)
        return HStack {
            TextField("Categoría (opcional)", text: $category)
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
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func load() {
        guard let expense else {
            amountFocused = true
            return
        }
        amountText = expense.amount.formatted(.number.precision(.fractionLength(2)).grouping(.never))
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
        if let expense {
            expense.amount = parsed.value
            if let marker = parsed.currencyMarker { expense.currencyMarker = marker }
            expense.merchant = name
            expense.card = cardName.isEmpty ? nil : cardName
            expense.category = categoryName.isEmpty ? nil : categoryName
            expense.date = date
        } else {
            context.insert(Expense(
                amount: parsed.value,
                currencyMarker: parsed.currencyMarker ?? "$",
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
