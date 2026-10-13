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
        VStack(alignment: .leading, spacing: 4) {
            SheetBar(title: "Presupuesto") {
                SheetAction(title: "Cancelar") { dismiss() }
            } trailing: {
                SheetAction(title: "Guardar", prominent: true, action: save)
                    .disabled(amount == nil)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tope de gasto cada mes (\(currency))").ticketCaption()
                TextField("Presupuesto", text: $text, prompt: Text("0").foregroundStyle(Theme.faint))
                    .font(.ticket(44, weight: .medium, relativeTo: .largeTitle))
                    .tracking(-1.5)
                    .foregroundStyle(Theme.ink)
                    .keyboardType(.decimalPad)
                    .focused($focused)
            }
            .padding(.vertical, 20)
            .overlay(alignment: .bottom) { Perforation() }

            Text("Con esto Centavo te muestra cuánto llevas gastado, cuánto te queda y hasta dónde deberías ir a estas alturas del mes. Solo cuenta gastos en \(currency) y se queda en tu iPhone.")
                .font(.ticket(12, relativeTo: .footnote))
                .lineSpacing(4)
                .foregroundStyle(Theme.muted)
                .padding(.top, 12)

            if BudgetStore.amount(from: stored) != nil {
                Button("Quitar presupuesto") {
                    stored = ""
                    dismiss()
                }
                .font(.ticket(12, relativeTo: .footnote))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
                .underline()
                .frame(minHeight: 44)
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .ticketSheet()
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
