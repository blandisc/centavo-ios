import CentavoCore
import SwiftData
import SwiftUI

/// Sheet to add a manual expense (`expense == nil`) or correct an existing one.
struct ExpenseEditorView: View {
    let expense: Expense?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var merchant = ""
    @State private var card = ""
    @State private var date = Date.now
    @FocusState private var amountFocused: Bool

    private var parsed: ParsedAmount? { AmountParser.parse(amountText) }
    private var canSave: Bool {
        parsed != nil && !merchant.trimmingCharacters(in: .whitespaces).isEmpty
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
        date = expense.date
    }

    private func save() {
        guard let parsed else { return }
        let name = merchant.trimmingCharacters(in: .whitespaces)
        let cardName = card.trimmingCharacters(in: .whitespaces)
        if let expense {
            expense.amount = parsed.value
            if let marker = parsed.currencyMarker { expense.currencyMarker = marker }
            expense.merchant = name
            expense.card = cardName.isEmpty ? nil : cardName
            expense.date = date
        } else {
            context.insert(Expense(
                amount: parsed.value,
                currencyMarker: parsed.currencyMarker ?? "$",
                merchant: name,
                card: cardName.isEmpty ? nil : cardName,
                date: date
            ))
        }
        dismiss()
    }
}

#Preview("Nuevo") {
    ExpenseEditorView(expense: nil)
        .modelContainer(for: Expense.self, inMemory: true)
}
