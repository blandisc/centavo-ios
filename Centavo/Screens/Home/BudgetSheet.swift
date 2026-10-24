import CentavoCore
import SwiftUI

/// Where the monthly budget is set. One number, saved on the phone.
struct BudgetSheet: View {
    @Binding var stored: String
    let currency: String
    /// What this month already spent in `currency`, so the preview matches the main screen.
    var spent: Decimal = 0
    /// The part of `spent` that went today: it comes off today alone.
    var spentToday: Decimal = 0
    /// Fixed expenses still to come this month, set apart as on the main screen.
    var reserved: Decimal = 0

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
                    AmountInputField("Presupuesto", text: $text, prompt: "0", identifier: "presupuesto-monto")
                        .focused($focused)
                } header: {
                    Text("Tope de gasto cada mes (\(currency))").ticketCaption()
                } footer: {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        if let amount {
                            Text(BudgetStore.dailyPreview(amount, spent: spent, spentToday: spentToday,
                                                     reserved: reserved, currency: currency))
                                .font(.ticket(.footnote))
                                .foregroundStyle(Theme.brass)
                                .accessibilityIdentifier("presupuesto-al-dia")
                        }
                        Text("Con esto Al día te muestra cuánto llevas gastado, cuánto te queda y hasta dónde deberías ir a estas alturas del mes. Solo cuenta gastos en \(currency).")
                            .font(.ticket(.detail))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .listRowBackground(Theme.surface)

                if BudgetStore.amount(from: stored) != nil {
                    Section {
                        Button("Quitar presupuesto", role: .destructive) {
                            stored = ""
                            dismiss()
                        }
                        .font(.ticket(.detail))
                        .tracking(Theme.Tracking.action)
                        .textCase(.uppercase)
                        .accessibilityIdentifier("quitar-presupuesto")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .ticketForm()
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Presupuesto")
            .saveBar(amount.map { formatMoney($0, isoCode: currency, label: currency) + " al mes" } ?? "Falta el monto",
                     enabled: amount != nil, action: save)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(.ticket(.footnote))
                        .accessibilityIdentifier("hoja-cancelar")
                }
            }
        }
        .presentationDetents([.medium, .large])
        // A typed number is not thrown away by a stray swipe down.
        .interactiveDismissDisabled(amount != BudgetStore.amount(from: stored))
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
