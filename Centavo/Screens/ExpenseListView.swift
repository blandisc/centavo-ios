import CentavoCore
import SwiftData
import SwiftUI

/// The only screen: this month's total, then every payment newest first.
struct ExpenseListView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Environment(\.modelContext) private var context
    @State private var showingSetup = false
    @State private var adding = false
    @State private var editing: Expense?

    /// The currency the headline total is in, taken from the device. No setting for it:
    /// changing it is changing your region.
    private var primaryCurrency: String {
        Locale.current.currency?.identifier ?? "MXN"
    }

    private var summary: MonthSummary {
        MonthSummarizer.summarize(
            expenses.map {
                ExpenseAmount(value: $0.amount, currencyMarker: $0.currencyMarker, date: $0.date)
            },
            inMonthOf: .now,
            primary: primaryCurrency
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthTotalHeader(summary: summary)
                }
                Section {
                    ForEach(expenses) { expense in
                        Button { editing = expense } label: {
                            ExpenseRow(expense: expense, primaryCurrency: primaryCurrency)
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        offsets.map { expenses[$0] }.forEach(context.delete)
                    }
                }
            }
            .overlay {
                if expenses.isEmpty {
                    ContentUnavailableView {
                        Label("Sin gastos todavía", systemImage: "creditcard")
                    } description: {
                        Text("Configura el atajo y cada pago con Apple Wallet aparecerá aquí. Lo demás, agrégalo con «+».")
                    } actions: {
                        Button("Configurar atajo") { showingSetup = true }
                        Button("Agregar gasto") { adding = true }
                    }
                }
            }
            .navigationTitle("Centavo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // The guide and the export are both occasional, so they share a
                    // menu instead of each taking a spot in the bar.
                    Menu("Más", systemImage: "ellipsis.circle") {
                        Button("Configurar atajo", systemImage: "questionmark.circle") {
                            showingSetup = true
                        }
                        ShareLink(
                            item: ExpensesCSVFile(expenses: expenses,
                                                  primaryCurrency: primaryCurrency),
                            preview: SharePreview("Gastos de Centavo")
                        ) {
                            Label("Exportar CSV", systemImage: "square.and.arrow.up")
                        }
                        .disabled(expenses.isEmpty)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Agregar gasto", systemImage: "plus") { adding = true }
                }
            }
            .sheet(isPresented: $showingSetup) { SetupGuideView() }
            .sheet(isPresented: $adding) { ExpenseEditorView(expense: nil) }
            .sheet(item: $editing) { ExpenseEditorView(expense: $0) }
        }
    }
}

/// Formats money for the screen: the real currency style when the ISO code is known,
/// otherwise the marker Wallet sent in front of a plain number.
private func formatMoney(_ amount: Decimal, isoCode: String?, label: String) -> String {
    if let isoCode {
        return amount.formatted(.currency(code: isoCode))
    }
    let digits = amount.magnitude.formatted(.number.precision(.fractionLength(2)))
    return (amount < 0 ? "-" : "") + label + digits
}

private struct MonthTotalHeader: View {
    let summary: MonthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Este mes").font(.subheadline).foregroundStyle(.secondary)
            Text(formatMoney(summary.primary.amount,
                             isoCode: summary.primary.isoCode,
                             label: summary.primary.label))
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
            // Adding currencies together would be a lie, so they ride along separately.
            if !summary.others.isEmpty {
                Text("y además " + summary.others
                    .map { formatMoney($0.amount, isoCode: $0.isoCode, label: $0.label) }
                    .formatted(.list(type: .and)))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ExpenseRow: View {
    let expense: Expense
    let primaryCurrency: String

    private var amountText: String {
        let marker = expense.currencyMarker
        return formatMoney(
            expense.amount,
            isoCode: CurrencyResolver.isoCode(for: marker, primary: primaryCurrency),
            label: marker ?? primaryCurrency
        )
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchant)
                Text(expense.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amountText).monospacedDigit()
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Expense.self, configurations: .init(isStoredInMemoryOnly: true))
    container.mainContext.insert(Expense(amount: 89, currencyMarker: "$", merchant: "Oxxo", card: "BBVA"))
    container.mainContext.insert(Expense(amount: 1234.5, currencyMarker: "$", merchant: "Liverpool"))
    container.mainContext.insert(Expense(amount: -230, currencyMarker: "$", merchant: "Liverpool (reembolso)"))
    container.mainContext.insert(Expense(amount: 24.99, currencyMarker: "USD", merchant: "Steam"))
    return ExpenseListView().modelContainer(container)
}
