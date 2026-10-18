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
                    TextField("Presupuesto", text: $text,
                              prompt: Text("0").foregroundStyle(Theme.faint))
                        .font(.ticket(44, weight: .medium, relativeTo: .largeTitle))
                        .tracking(-1.5)
                        .foregroundStyle(Theme.ink)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .accessibilityIdentifier("presupuesto-monto")
                } header: {
                    Text("Tope de gasto cada mes (\(currency))").ticketCaption()
                } footer: {
                    Text("Con esto Al día te muestra cuánto llevas gastado, cuánto te queda y hasta dónde deberías ir a estas alturas del mes. Solo cuenta gastos en \(currency).")
                        .font(.ticket(12, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.surface)

                if BudgetStore.amount(from: stored) != nil {
                    Section {
                        Button("Quitar presupuesto", role: .destructive) {
                            stored = ""
                            dismiss()
                        }
                        .font(.ticket(12, relativeTo: .footnote))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .accessibilityIdentifier("quitar-presupuesto")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .ticketForm()
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Presupuesto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(.ticket(13, relativeTo: .footnote))
                        .accessibilityIdentifier("hoja-cancelar")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                        .disabled(amount == nil)
                        .accessibilityIdentifier("hoja-guardar")
                }
            }
        }
        .presentationDetents([.medium, .large])
        // A typed number is not thrown away by a stray swipe down.
        .interactiveDismissDisabled(text != (BudgetStore.amount(from: stored)?
            .formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) ?? ""))
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
