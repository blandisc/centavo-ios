import CentavoCore
import SwiftUI

/// Where the monthly budget is set: one number, and how «Hoy puedes gastar» treats what a day
/// leaves over. Saved on the phone.
struct BudgetSheet: View {
    @Binding var stored: String
    /// `AllowanceMode`'s raw value; empty until one is chosen.
    @Binding var storedMode: String
    let currency: String
    /// This month measured against a budget with a rule (`TodayBudget`), so the preview
    /// matches the main screen.
    var pace: (Decimal, AllowanceMode) -> BudgetPace? = { BudgetPace(budget: $0, spent: 0, mode: $1, on: .now) }

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var mode = AllowanceMode.carry
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
                            Text(BudgetStore.dailyPreview(pace(amount, mode), currency: currency))
                                .font(.ticket(.footnote))
                                .foregroundStyle(Theme.brass)
                                .accessibilityIdentifier("presupuesto-al-dia")
                        }
                        NoteText("Con esto Al día te muestra cuánto llevas gastado, cuánto te queda y hasta dónde deberías ir a estas alturas del mes. Solo cuenta gastos en \(currency).")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    Picker("Hoy puedes gastar", selection: $mode) {
                        ForEach(AllowanceMode.allCases, id: \.self) { option in
                            VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                                Text(option.title)
                                    .font(.ticket(.callout))
                                    .foregroundStyle(Theme.ink)
                                Text(option.explanation)
                                    .font(.ticket(.detail))
                                    .foregroundStyle(Theme.muted)
                            }
                            .tag(option)
                            .accessibilityIdentifier("modo-\(option.rawValue)")
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Hoy puedes gastar").ticketCaption()
                }
                .listRowBackground(Theme.surface)

                if BudgetStore.amount(from: stored) != nil {
                    Section {
                        DestructiveRowButton("Quitar presupuesto", identifier: "quitar-presupuesto") {
                            stored = ""
                            dismiss()
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .ticketForm()
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Presupuesto del mes")
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
        .interactiveDismissDisabled(amount != BudgetStore.amount(from: stored)
                                    || mode != AllowanceMode(stored: storedMode))
        .onAppear {
            if let current = BudgetStore.amount(from: stored) {
                text = current.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            }
            mode = AllowanceMode(stored: storedMode)
            focused = true
        }
    }

    private func save() {
        guard let amount else { return }
        stored = BudgetStore.stored(amount)
        storedMode = mode.rawValue
        dismiss()
    }
}
