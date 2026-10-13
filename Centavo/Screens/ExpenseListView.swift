import CentavoCore
import SwiftData
import SwiftUI
import UIKit

/// The only screen: the month's total, a swipeable calendar/budget, then every payment newest first.
struct ExpenseListView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(BudgetStore.key) private var storedBudget = ""
    /// "Now" for the whole screen. Refreshed when the app comes back and when the clock
    /// jumps (midnight, a time-zone change), so the month and "today" never go stale.
    @State private var now = Date.now
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
        let summary = MonthSummarizer.summarize(amounts, inMonthOf: now, primary: primaryCurrency)
        let pace = BudgetPace(budget: BudgetStore.amount(from: storedBudget),
                              spent: summary.primary.amount, on: now)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    TopBar(
                        now: now,
                        csv: ExpensesCSVFile(expenses: expenses, primaryCurrency: primaryCurrency),
                        canExport: !expenses.isEmpty,
                        onBudget: { showingBudget = true },
                        onSetup: { showingSetup = true }
                    )
                    HeroTotal(summary: summary, now: now)
                    if expenses.isEmpty {
                        EmptyTicket { showingSetup = true }
                    } else {
                        MonthCarousel(
                            calendarModel: MonthCalendar.make(amounts, inMonthOf: now,
                                                              primary: primaryCurrency, today: now),
                            spent: summary.primary,
                            pace: pace,
                            onSetBudget: { showingBudget = true }
                        )
                        Ledger(expenses: expenses, primaryCurrency: primaryCurrency,
                               onEdit: { editing = $0 }, onDelete: { pendingDelete = $0 })
                    }
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.top, 8)
            }
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { addButton }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSetup) { SetupGuideView() }
            .sheet(isPresented: $adding) { ExpenseEditorView(expense: nil) }
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

    private var addButton: some View {
        Button { adding = true } label: {
            Label {
                Text("Anotar gasto").tracking(1.4).textCase(.uppercase)
            } icon: {
                Image(systemName: "plus").fontWeight(.bold)
            }
            .font(.ticket(14, weight: .semibold, relativeTo: .callout))
            .lineLimit(1)
            .foregroundStyle(Theme.onBrass)
            .padding(.horizontal, 24)
            .frame(minHeight: 52)
            .background(Theme.brass, in: Capsule())
            .shadow(color: .black.opacity(0.55), radius: 15, y: 12)
        }
        .buttonStyle(.plain)
        // A floating button that grows with the text would swallow the screen.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background {
            // The rows fade out behind the button instead of being cut by it.
            LinearGradient(colors: [Theme.background.opacity(0), Theme.background],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Pieces

private struct TopBar: View {
    let now: Date
    let csv: ExpensesCSVFile
    let canExport: Bool
    let onBudget: () -> Void
    let onSetup: () -> Void

    private var title: some View {
        Text("Centavo")
            .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
            .tracking(2)
            .textCase(.uppercase)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }

    private var month: some View {
        Text(now, format: .dateTime.month(.abbreviated).year())
            .font(.ticket(13, relativeTo: .footnote))
            .tracking(2)
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(Theme.muted)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 14) { title; month }
                VStack(alignment: .leading, spacing: 2) { title; month }
            }
            Spacer(minLength: 8)
            Menu {
                Button("Presupuesto del mes", systemImage: "target", action: onBudget)
                ShareLink(item: csv, preview: SharePreview("Gastos de Centavo")) {
                    Label("Exportar CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(!canExport)
                Button("Configurar atajo", systemImage: "questionmark.circle", action: onSetup)
            } label: {
                Label("Más", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
    }
}

private struct HeroTotal: View {
    let summary: MonthSummary
    let now: Date

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
            Text(verbatim: "Total \(summary.primary.label) al \(shortDate(now))").ticketCaption()
            Text(totalText)
                .accessibilityIdentifier("total-mes")
                .font(.ticket(54, weight: .medium, relativeTo: .largeTitle))
                .tracking(-2)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
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
            Button(action: onSetup) {
                Text("Configurar atajo")
                    .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.brass)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(Capsule().stroke(Theme.brass, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
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

private struct Ledger: View {
    let expenses: [Expense]
    let primaryCurrency: String
    let onEdit: (Expense) -> Void
    let onDelete: (Expense) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(expenses) { expense in
                Button { onEdit(expense) } label: {
                    LedgerRow(expense: expense, primaryCurrency: primaryCurrency)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Borrar gasto", systemImage: "trash", role: .destructive) {
                        onDelete(expense)
                    }
                }
            }
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
        let parts = [isRefund ? "Devolución" : nil, expense.category, expense.card]
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
        Text(expense.merchant)
            .font(.ticket(15, weight: .medium, relativeTo: .body))
            .tracking(0.4)
            .textCase(.uppercase)
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
