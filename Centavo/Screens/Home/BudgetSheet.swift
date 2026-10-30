import CentavoCore
import SwiftUI

/// «Tu presupuesto» (2.0, 2026-10-29): one number for the month and how «Hoy puedes gastar»
/// treats what a day leaves over, shown with a toy week instead of a sentence.
///
/// From top to bottom: the amount, what it gives a day while it is typed, then «Lo que no
/// gastas un día» with the two rules, the drawing of the one chosen and who it suits. The
/// same whatever the month looks like: it is where the budget is set, not a way out of
/// having spent too much. «Guardar» is up in the bar, where the number pad can't cover it.
struct BudgetSheet: View {
    @Binding var stored: String
    /// `AllowanceMode`'s raw value; empty until one is chosen.
    @Binding var storedMode: String
    let currency: String
    /// This month measured against a budget with a rule (`TodayBudget`), so the preview
    /// matches the main screen.
    var pace: (Decimal, AllowanceMode) -> BudgetPace? = { BudgetPace(budget: $0, spent: 0, mode: $1, on: .now) }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var mode = AllowanceMode.carry
    @FocusState private var focused: Bool

    private var amount: Decimal? {
        guard let value = AmountParser.parse(text)?.value, value > 0 else { return nil }
        return value
    }

    private var changed: Bool {
        amount != BudgetStore.amount(from: stored) || mode != AllowanceMode(stored: storedMode)
    }

    private func whole(_ value: Decimal) -> String {
        value.formatted(currencyStyle(currency).precision(.fractionLength(0)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountInputField("Presupuesto", text: $text, prompt: "0", identifier: "presupuesto-monto")
                        .focused($focused)
                } header: {
                    Text("Cada mes · \(currency)").ticketCaption()
                } footer: {
                    effect
                }
                .listRowBackground(Theme.surface)

                Section {
                    Picker("Lo que no gastas un día", selection: $mode.animation(
                        Theme.Motion.animation(Theme.Motion.fold, reduceMotion: reduceMotion))) {
                        ForEach(AllowanceMode.allCases, id: \.self) { option in
                            Text(option.shortTitle).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("modo")
                    AllowanceExplainer(mode: mode, currency: currency)
                        .padding(.top, Theme.Space.xs)
                } header: {
                    Text("Lo que no gastas un día").ticketCaption()
                } footer: {
                    HintText(mode.suits)
                        .contentTransition(.opacity)
                        .accessibilityIdentifier("modo-te-conviene")
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
            // Like the other sheets: moving the form puts the keyboard away, so «Quitar
            // presupuesto» is never left under the save bar.
            .scrollDismissesKeyboard(.immediately)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Tu presupuesto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(.ticket(.footnote))
                        .accessibilityIdentifier("hoja-cancelar")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .font(.ticket(.footnoteStrong))
                        .disabled(amount == nil)
                        .accessibilityIdentifier("hoja-guardar")
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        // A typed number is not thrown away by a stray swipe down.
        .interactiveDismissDisabled(changed)
        .onAppear {
            if let current = BudgetStore.amount(from: stored) {
                text = current.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            }
            mode = AllowanceMode(stored: storedMode)
            focused = BudgetStore.amount(from: stored) == nil
        }
    }

    /// What the number gives, while it is typed: a day's amount and what the month carries.
    @ViewBuilder private var effect: some View {
        // The day's amount is the same under both rules (budget less fixed, over the days of
        // the month); asked with «Se acumula» so «Se reparte» doesn't show today's share.
        if let amount, let pace = pace(amount, .carry) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Text("Al día:")
                    .foregroundStyle(Theme.muted)
                Text(whole(max(pace.dailyBase, 0)))
                    .foregroundStyle(Theme.brass)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("presupuesto-al-dia")
                if pace.spent > 0 {
                    Text("· llevas \(whole(pace.spent)) este mes")
                        .foregroundStyle(Theme.muted)
                }
            }
            .font(.ticket(.footnoteStrong))
            .animation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion), value: text)
        } else {
            Text("Lo que quieres gastar en todo el mes. Al día lo reparte en cada día.")
                .font(.ticket(.detail))
                .foregroundStyle(Theme.muted)
        }
    }

    private func save() {
        guard let amount else { return }
        stored = BudgetStore.stored(amount)
        storedMode = mode.rawValue
        dismiss()
    }
}
