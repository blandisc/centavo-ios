import SwiftData
import SwiftUI

/// The only screen: this month's total, then every payment newest first.
struct ExpenseListView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Environment(\.modelContext) private var context
    @State private var showingSetup = false

    private var monthTotal: Decimal {
        let calendar = Calendar.current
        return expenses
            .filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Este mes").font(.subheadline).foregroundStyle(.secondary)
                        Text(monthTotal, format: .number.precision(.fractionLength(2)))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 8)
                }
                Section {
                    ForEach(expenses) { expense in
                        ExpenseRow(expense: expense)
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
                        Text("Configura el atajo y cada pago con Apple Wallet aparecerá aquí.")
                    } actions: {
                        Button("Configurar atajo") { showingSetup = true }
                    }
                }
            }
            .navigationTitle("Centavo")
            .toolbar {
                Button("Configurar atajo", systemImage: "questionmark.circle") { showingSetup = true }
            }
            .sheet(isPresented: $showingSetup) { SetupGuideView() }
        }
    }
}

private struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchant)
                Text(expense.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(expense.currencyMarker ?? "")\(expense.amount.formatted(.number.precision(.fractionLength(2))))")
                .monospacedDigit()
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Expense.self, configurations: .init(isStoredInMemoryOnly: true))
    container.mainContext.insert(Expense(amount: 89, currencyMarker: "$", merchant: "Oxxo", card: "BBVA"))
    container.mainContext.insert(Expense(amount: 1234.5, currencyMarker: "$", merchant: "Liverpool"))
    return ExpenseListView().modelContainer(container)
}
