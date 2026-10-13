import CentavoCore
import SwiftData
import SwiftUI
import UIKit

/// The only screen: a month's total, a swipeable calendar/budget, then that month's payments.
struct ExpenseListView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(BudgetStore.key) private var storedBudget = ""
    /// "Now" for the whole screen. Refreshed when the app comes back and when the clock
    /// jumps (midnight, a time-zone change), so the month and "today" never go stale.
    @State private var now = Date.now
    /// Months back from this one that are on screen: 0 is this month, -1 last month.
    @State private var monthOffset = 0
    @State private var pendingDelete: Expense?
    @State private var showingSetup = false
    @State private var showingBudget = false
    @State private var adding = false
    @State private var editing: Expense?

    /// The currency the headline total is in, taken from the device. No setting for it:
    /// changing it is changing your region.
    private var primaryCurrency: String {
        Locale.current.currency?.identifier ?? "MXN"
    }

    var body: some View {
        let amounts = expenses.map {
            ExpenseAmount(value: $0.amount, currencyMarker: $0.currencyMarker,
                          date: $0.date, category: $0.category)
        }
        // `expenses` is newest first, so the oldest is the last one. You can browse back
        // as far as that, and no further; deleting it pulls the limit forward.
        let earliest = MonthNavigator.earliestOffset(oldest: expenses.last?.date, now: now)
        let offset = min(0, max(monthOffset, earliest))
        let isCurrent = offset == 0
        let viewed = MonthNavigator.month(offsetBy: offset, from: now)
        let monthExpenses = expenses.filter { MonthNavigator.isSameMonth($0.date, as: viewed) }
        let summary = MonthSummarizer.summarize(amounts, inMonthOf: viewed, primary: primaryCurrency)
        // A month that is over is measured at its last second: all of the budget was due.
        let pace = BudgetPace(budget: BudgetStore.amount(from: storedBudget),
                              spent: summary.primary.amount,
                              on: isCurrent ? now : MonthNavigator.closingMoment(of: viewed))

        NavigationStack {
            List {
                HeroTotal(summary: summary, viewed: viewed, isCurrentMonth: isCurrent)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 4, trailing: 20))

                if expenses.isEmpty {
                    ContentUnavailableView {
                        Label("Sin gastos todavía", systemImage: "creditcard")
                    } description: {
                        Text("Configura el atajo y cada pago con Apple Wallet se anotará solo. Lo demás, anótalo tú.")
                    } actions: {
                        Button("Configurar atajo") { showingSetup = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        MonthCarousel(
                            calendarModel: MonthCalendar.make(amounts, inMonthOf: viewed,
                                                              primary: primaryCurrency, today: now),
                            spent: summary.primary,
                            pace: pace,
                            isCurrentMonth: isCurrent,
                            onSetBudget: { showingBudget = true }
                        )
                        .padding(.vertical, 6)
                    }

                    Section("Pagos") {
                        if monthExpenses.isEmpty {
                            Text("Sin gastos este mes")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(monthExpenses) { expense in
                            Button { editing = expense } label: {
                                LedgerRow(expense: expense, primaryCurrency: primaryCurrency)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Borrar", systemImage: "trash", role: .destructive) {
                                    pendingDelete = expense
                                }
                            }
                            .contextMenu {
                                Button("Borrar gasto", systemImage: "trash", role: .destructive) {
                                    pendingDelete = expense
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Centavo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Presupuesto del mes", systemImage: "target") { showingBudget = true }
                        ShareLink(
                            item: ExpensesCSVFile(expenses: expenses, primaryCurrency: primaryCurrency),
                            preview: SharePreview("Gastos de Centavo")
                        ) {
                            Label("Exportar CSV", systemImage: "square.and.arrow.up")
                        }
                        .disabled(expenses.isEmpty)
                        Button("Configurar atajo", systemImage: "questionmark.circle") {
                            showingSetup = true
                        }
                    } label: {
                        Label("Más", systemImage: "ellipsis")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Anotar gasto", systemImage: "plus") { adding = true }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Mes anterior", systemImage: "chevron.left") { monthOffset = offset - 1 }
                        .disabled(offset <= earliest)
                    Spacer()
                    Text(monthTitle(viewed))
                        .font(.headline)
                    Spacer()
                    Button("Mes siguiente", systemImage: "chevron.right") { monthOffset = offset + 1 }
                        .disabled(offset >= 0)
                }
            }
            .sheet(isPresented: $showingSetup) { SetupGuideView() }
            .sheet(isPresented: $adding) {
                // Adding while looking at a past month puts the expense in that month.
                ExpenseEditorView(expense: nil,
                                  initialDate: isCurrent ? nil : MonthNavigator.closingMoment(of: viewed))
            }
            .sheet(item: $editing) { ExpenseEditorView(expense: $0) }
            .sheet(isPresented: $showingBudget) {
                BudgetSheet(stored: $storedBudget, currency: primaryCurrency)
            }
            .confirmationDialog(
                "¿Borrar este gasto?",
                isPresented: Binding(get: { pendingDelete != nil },
                                     set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { expense in
                Button("Borrar", role: .destructive) { context.delete(expense) }
            } message: { expense in
                Text("\(expense.merchant) · \(ledgerAmount(for: expense, primary: primaryCurrency))")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = .now }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.significantTimeChangeNotification)) { _ in
                now = .now
            }
        }
    }
}

// MARK: - Pieces

private struct HeroTotal: View {
    let summary: MonthSummary
    let viewed: Date
    let isCurrentMonth: Bool

    private var totalText: AttributedString {
        let formatted = formatMoney(summary.primary.amount, isoCode: summary.primary.isoCode,
                                    label: summary.primary.label)
        let parts = MoneyText.splitCents(formatted,
                                         decimalSeparator: Locale.current.decimalSeparator ?? ".")
        var text = AttributedString(parts.head)
        var cents = AttributedString(parts.cents)
        cents.foregroundColor = .secondary
        text += cents
        text += AttributedString(parts.tail)
        return text
    }

    private var othersText: String {
        summary.others
            .map { "\($0.label) \($0.amount.formatted(.number.precision(.fractionLength(2))))" }
            .formatted(.list(type: .and, width: .narrow))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isCurrentMonth
                 ? "Total del mes (\(summary.primary.label))"
                 : "Total de \(monthName(viewed)) (\(summary.primary.label))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(totalText)
                .accessibilityIdentifier("total-mes")
                .font(.largeTitle.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !summary.others.isEmpty {
                // Adding currencies together would be a lie, so they ride along separately.
                Text(verbatim: "+ \(othersText) aparte")
                    .accessibilityIdentifier("otras-monedas")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LedgerRow: View {
    let expense: Expense
    let primaryCurrency: String

    @Environment(\.dynamicTypeSize) private var typeSize

    private var isRefund: Bool { expense.amount < 0 }

    private var meta: String {
        let parts = [shortDate(expense.date), isRefund ? "Devolución" : nil,
                     expense.category, expense.card]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private var amountStyle: AnyShapeStyle {
        isRefund ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(expense.merchant)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Text(meta)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    private var amountText: some View {
        Text(ledgerAmount(for: expense, primary: primaryCurrency))
            .font(.body.monospacedDigit())
            .foregroundStyle(amountStyle)
            .lineLimit(1)
            .fixedSize()
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Side by side there is no room: stack it so nothing breaks mid-word.
                VStack(alignment: .leading, spacing: 4) {
                    details
                    amountText
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    details
                    Spacer(minLength: 8)
                    amountText
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let container = try! ModelContainer(for: Expense.self, configurations: .init(isStoredInMemoryOnly: true))
    let context = container.mainContext
    context.insert(Expense(amount: 89, currencyMarker: "$", merchant: "Oxxo",
                           card: "BBVA", date: .now.addingTimeInterval(-86_400 * 4), category: "Despensa"))
    context.insert(Expense(amount: 1234.5, currencyMarker: "$", merchant: "Liverpool",
                           card: "BBVA", date: .now.addingTimeInterval(-86_400 * 3), category: "Ropa"))
    context.insert(Expense(amount: -230, currencyMarker: "$", merchant: "Liverpool",
                           date: .now.addingTimeInterval(-86_400), category: "Ropa"))
    context.insert(Expense(amount: 24.99, currencyMarker: "USD", merchant: "Steam", card: "BBVA"))
    return ExpenseListView().modelContainer(container)
}
