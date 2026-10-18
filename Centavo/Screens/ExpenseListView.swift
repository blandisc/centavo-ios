import CentavoCore
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The only screen: a month's total, a swipeable calendar/budget, then that month's payments.
///
/// The look is the approved "Noche ticket" (dark, brass, receipt type). The structure is
/// Apple's: a real navigation bar and bottom bar (Liquid Glass on iOS 26), a `List` with
/// swipe-to-delete, system menus and sheets.
struct ExpenseListView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    /// The newest payment the Wallet automation saved (only it keeps the raw text). Asked of
    /// the store, one row, instead of scanning every expense on each redraw.
    @Query(Self.latestCapture) private var latestCaptures: [Expense]

    private static var latestCapture: FetchDescriptor<Expense> {
        var descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.rawAmount != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(BudgetStore.key) private var storedBudget = ""
    @AppStorage(CurrencyPreference.key) private var storedCurrency = ""
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
    @State private var importing = false
    @State private var importMessage: String?

    private var primaryCurrency: String { CurrencyPreference.resolve(storedCurrency) }

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
                HeroTotal(summary: summary, viewed: viewed, now: now, isCurrentMonth: isCurrent,
                          pace: pace)
                    .ticketRow(bottom: 20)

                if expenses.isEmpty {
                    EmptyTicket { showingSetup = true }
                        .ticketRow()
                } else {
                    MonthCarousel(
                        calendarModel: MonthCalendar.make(amounts, inMonthOf: viewed,
                                                          primary: primaryCurrency, today: now),
                        spent: summary.primary,
                        pace: pace,
                        isCurrentMonth: isCurrent,
                        shares: CategoryShare.top(summary.categories),
                        onSetBudget: { showingBudget = true }
                    )
                    .ticketRow(bottom: isCurrent ? 4 : 20)

                    if isCurrent {
                        CaptureHealthRow(
                            health: CaptureHealth(lastCapture: latestCaptures.first?.date,
                                                  now: now),
                            openGuide: { showingSetup = true }
                        )
                        .ticketRow(bottom: 12)
                    }

                    if monthExpenses.isEmpty {
                        Text("Sin gastos este mes")
                            .font(.ticket(13, relativeTo: .footnote))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .overlay(alignment: .top) { Perforation() }
                            .ticketRow()
                    }
                    ForEach(monthExpenses) { expense in
                        Button { editing = expense } label: {
                            LedgerRow(expense: expense, primaryCurrency: primaryCurrency)
                        }
                        .buttonStyle(.plain)
                        .ticketRow()
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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: storedBudget) { _, budget in
                if Store.syncsBudget { BudgetSync.push(budget) }
            }
            .onChange(of: storedCurrency) { _, code in
                if Store.syncsBudget { BudgetSync.push(code, for: CurrencyPreference.key) }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Al día")
                        .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                        .tracking(2)
                        .textCase(.uppercase)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Presupuesto del mes", systemImage: "target") { showingBudget = true }
                        Picker(selection: Binding(get: { primaryCurrency },
                                                  set: { storedCurrency = $0 })) {
                            ForEach(CurrencyPreference.offered, id: \.self) { code in
                                Text(CurrencyPreference.name(code)).tag(code)
                            }
                        } label: {
                            Label("Moneda principal", systemImage: "dollarsign.circle")
                        }
                        .pickerStyle(.menu)
                        ShareLink(
                            item: ExpensesCSVFile(expenses: expenses, primaryCurrency: primaryCurrency),
                            preview: SharePreview("Gastos de Al día")
                        ) {
                            Label("Exportar CSV", systemImage: "square.and.arrow.up")
                        }
                        .disabled(expenses.isEmpty)
                        Button("Importar CSV", systemImage: "square.and.arrow.down") { importing = true }
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
                    Text(viewed, format: .dateTime.month(.abbreviated).year())
                        .font(.ticket(13, relativeTo: .footnote))
                        .tracking(2)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .fixedSize()
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
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                importMessage = importFile(result)
            }
            .alert("Importar CSV", isPresented: Binding(get: { importMessage != nil },
                                                        set: { if !$0 { importMessage = nil } })) {
                Button("Listo", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = .now }
            }
            // Fixed expenses whose day came while the app was closed log themselves here.
            .task(id: now) { try? RecurringExpenses.logDue(in: context, now: now) }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.significantTimeChangeNotification)) { _ in
                now = .now
            }
        }
    }
}

private extension ExpenseListView {
    /// Reads the chosen file and says plainly what happened.
    func importFile(_ result: Result<URL, Error>) -> String {
        guard case .success(let url) = result else { return "No se pudo abrir el archivo." }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            return "No se pudo leer el archivo."
        }
        do {
            let summary = try ExpenseImporter.importCSV(text, into: context)
            var parts = ["Se agregaron \(summary.added) gastos."]
            if summary.alreadyThere > 0 { parts.append("\(summary.alreadyThere) ya estaban.") }
            if summary.unreadable > 0 { parts.append("\(summary.unreadable) renglones no se pudieron leer.") }
            return parts.joined(separator: " ")
        } catch CSVImporter.Failure.notOurFile {
            return "Ese archivo no es un CSV exportado de Al día (le falta la fila Fecha, Comercio, Monto, Moneda)."
        } catch {
            return "No se pudo guardar lo importado. Intenta de nuevo."
        }
    }
}

private extension View {
    /// A list row that looks like part of the ticket: no card, no separator, side margins.
    func ticketRow(bottom: CGFloat = 0) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: Theme.horizontalPadding,
                                      bottom: bottom, trailing: Theme.horizontalPadding))
    }
}

// MARK: - Pieces

private struct HeroTotal: View {
    let summary: MonthSummary
    let viewed: Date
    let now: Date
    let isCurrentMonth: Bool
    let pace: BudgetPace?

    /// This month, with a budget not yet blown, the figure to decide by is what can still go
    /// today; the month's total becomes the line under it.
    private var allowance: Decimal? {
        guard isCurrentMonth, let pace, pace.remaining >= 0 else { return nil }
        return pace.dailyAllowance
    }

    private var allowanceText: String {
        let amount = allowance ?? 0
        if let iso = summary.primary.isoCode {
            return amount.formatted(.currency(code: iso).precision(.fractionLength(0)))
        }
        return summary.primary.label + amount.formatted(.number.precision(.fractionLength(0)))
    }

    /// "TOTAL MXN AL 13/10" this month; "TOTAL MXN · SEP 2026" for one that is over.
    private var caption: String {
        isCurrentMonth
            ? "Total \(summary.primary.label) al \(shortDate(now))"
            : "Total \(summary.primary.label) · "
                + viewed.formatted(.dateTime.month(.abbreviated).year())
    }

    private var totalText: AttributedString {
        let formatted = formatMoney(summary.primary.amount, isoCode: summary.primary.isoCode,
                                    label: summary.primary.label)
        let parts = MoneyText.splitCents(formatted,
                                         decimalSeparator: Locale.current.decimalSeparator ?? ".")
        var text = AttributedString(parts.head)
        var cents = AttributedString(parts.cents)
        cents.foregroundColor = Theme.muted
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
        VStack(alignment: .leading, spacing: 8) {
            if allowance != nil {
                Text("Hoy puedes gastar")
                    .font(.ticket(11, weight: .semibold, relativeTo: .caption))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.brass)
                Text(allowanceText)
                    .accessibilityIdentifier("hoy-puedes-gastar")
                    .font(.ticket(54, weight: .medium, relativeTo: .largeTitle))
                    .tracking(-2)
                    .foregroundStyle(Theme.brass)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: allowance)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: caption).ticketCaption()
                    Text(totalText)
                        .accessibilityIdentifier("total-mes")
                        .font(.ticket(17, weight: .medium, relativeTo: .headline))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else {
                Text(verbatim: caption).ticketCaption()
                Text(totalText)
                    .accessibilityIdentifier("total-mes")
                    .font(.ticket(54, weight: .medium, relativeTo: .largeTitle))
                    .tracking(-2)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
            if !summary.others.isEmpty {
                // Adding currencies together would be a lie, so they ride along separately.
                Text(verbatim: "+ \(othersText) aparte")
                    .accessibilityIdentifier("otras-monedas")
                    .font(.ticket(13, relativeTo: .footnote))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

private struct EmptyTicket: View {
    let onSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sin gastos todavía")
                .font(.ticket(15, weight: .semibold, relativeTo: .body))
                .tracking(1.6)
                .textCase(.uppercase)
            Text("Configura el atajo y cada pago con Apple Wallet se anotará solo. Lo demás, anótalo tú.")
                .font(.ticket(14, relativeTo: .callout))
                .lineSpacing(4)
                .foregroundStyle(Theme.muted)
            Button("Configurar atajo", action: onSetup)
                .buttonStyle(.bordered)
                .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                .padding(.top, 6)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.outline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
    }
}

private struct LedgerRow: View {
    let expense: Expense
    let primaryCurrency: String

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var dateWidth: CGFloat = 46

    private var isRefund: Bool { expense.amount < 0 }

    private var meta: String? {
        let parts = [isRefund ? "Devolución" : nil, expense.isFixed ? "Fijo" : nil,
                     expense.category, expense.card]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var dateText: some View {
        Text(shortDate(expense.date))
            .font(.ticket(12, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
    }

    private var merchantText: some View {
        // Up to three lines; the full name is in the expense sheet.
        Text(expense.merchant)
            .lineLimit(3)
            .font(.ticket(15, weight: .medium, relativeTo: .body))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder private var metaText: some View {
        if let meta {
            Text(meta)
                .font(.ticket(11, relativeTo: .caption2))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.leading)
        }
    }

    private var amountText: some View {
        Text(ledgerAmount(for: expense, primary: primaryCurrency))
            .font(.ticket(15, relativeTo: .body))
            .foregroundStyle(isRefund ? Theme.brass : Theme.ink)
            .lineLimit(1)
            .fixedSize()
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Side by side there is no room: stack it so nothing breaks mid-word.
                VStack(alignment: .leading, spacing: 4) {
                    dateText
                    merchantText
                    metaText
                    amountText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    dateText.frame(width: dateWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        merchantText
                        metaText
                    }
                    Spacer(minLength: 8)
                    amountText
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .overlay(alignment: .top) { Perforation() }
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
    return ExpenseListView().modelContainer(container).preferredColorScheme(.dark)
}
