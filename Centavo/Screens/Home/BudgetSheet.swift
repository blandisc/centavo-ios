import CentavoCore
import SwiftUI

/// Where the monthly budget is set. One number, saved on the phone.
struct BudgetSheet: View {
    @Binding var stored: String
    let currency: String

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var amount: Decimal? {
        guard let value = AmountParser.parse(text)?.value, value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Presupuesto", text: $text, prompt: Text("0"))
                        .font(.largeTitle.weight(.semibold).monospacedDigit())
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .accessibilityIdentifier("presupuesto-monto")
                } header: {
                    Text("Tope de gasto cada mes (\(currency))")
                } footer: {
                    Text("Con esto Centavo te muestra cuánto llevas gastado, cuánto te queda y hasta dónde deberías ir a estas alturas del mes. Solo cuenta gastos en \(currency) y se queda en tu iPhone.")
                }

                if BudgetStore.amount(from: stored) != nil {
                    Section {
                        Button("Quitar presupuesto", role: .destructive) {
                            stored = ""
                            dismiss()
                        }
                        .accessibilityIdentifier("quitar-presupuesto")
                    }
                }
            }
            .navigationTitle("Presupuesto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .accessibilityIdentifier("hoja-cancelar")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .disabled(amount == nil)
                        .accessibilityIdentifier("hoja-guardar")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if let current = BudgetStore.amount(from: stored) {
                text = current.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            }
            focused = true
        }
    }

    private func save() {
        guard let amount else { return }
        stored = BudgetStore.stored(amount)
        dismiss()
    }
}
