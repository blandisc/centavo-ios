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
    @AppStorage(BudgetStore.key) private var storedBudget = ""
    @AppStorage(CurrencyPreference.key) private var storedCurrency = ""
    /// The welcome runs once, and only on an empty app (someone who already has expenses
    /// is not new).
    @AppStorage("onboarded") private var onboarded = false
    @State private var showingOnboarding = false
    /// "Now" for the whole screen. Refreshed when the app comes back and when the clock
    /// jumps (midnight, a time-zone change), so the month and "today" never go stale.
    @State private var now = Date.now
    /// Months back from this one that are on screen: 0 is this month, -1 last month.
    @State private var monthOffset = 0
    @State private var pendingDelete: Expense?
    @State private var showingSetup = false
    @State private var showingBudget = false
    @State private var currencyChanged = false
    @State private var showingCatalogs = false
    @State private var adding = false
    @State private var editing: Expense?
    @State private var importing = false
    /// A tapped calendar day narrows the list to it.
    @State private var selectedDay: Int?
    /// What was just deleted, kept a few seconds so it can come back.
    @State private var lastDeleted: DeletedExpense?
    @State private var importMessage: String?
    /// What is being searched, as typed or dictated: «uber de octubre arriba de 200».
    @State private var searchText = ""
    /// The category the on-device model took the search words to mean, when they matched
    /// nothing as written («cafecitos» → «Café»).
    @State private var searchCategory: String?
    @AppStorage(MonthNote.storedKey) private var storedNote = ""
    /// Fixed expenses whose first charge is still to come (`FixedPlan`).
    @AppStorage(FixedPlan.key) private var storedPlans = ""
    @State private var showingFixed = false
    @State private var checkingModel = false

    private var primaryCurrency: String { CurrencyPreference.resolve(storedCurrency) }

    /// Changes the currency the month adds up in. The budget is a bare number, and 8,000
    /// pesos must not quietly become 8,000 dollars, so it asks about it.
    private func setPrimary(_ code: String) {
        if code != primaryCurrency, BudgetStore.amount(from: storedBudget) != nil {
            currencyChanged = true
        }
        storedCurrency = code
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
        let shownExpenses = selectedDay.map { day in
            monthExpenses.filter { Calendar.current.component(.day, from: $0.date) == day }
        } ?? monthExpenses
        let summary = MonthSummarizer.summarize(amounts, inMonthOf: viewed, primary: primaryCurrency)
        // A month that is over is measured at its last second: all of the budget was due.
        // This month, the fixed expenses still to come are set apart from «Hoy puedes gastar».
        let reserved = isCurrent ? FixedOutlook.reserved(originals: expenses.filter { $0.repeatsMonthly == true },
                                                         plans: FixedPlan.decode(storedPlans),
                                                         primary: primaryCurrency, now: now) : 0
        let pace = BudgetPace(budget: BudgetStore.amount(from: storedBudget),
                              spent: summary.primary.amount, reserved: reserved,
                              on: isCurrent ? now : MonthNavigator.closingMoment(of: viewed))
        let searching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let listed = searching ? searchResults : shownExpenses
        let fact = isCurrent ? MonthNote.facts(expenses, now: now, primary: primaryCurrency,
                                               budget: BudgetStore.amount(from: storedBudget)).first : nil

        NavigationStack {
            List {
                if searching {
                    SearchHeaderRow(count: listed.count, category: searchCategory)
                        .ticketRow(bottom: 8)
                } else {
                    HeroTotal(summary: summary, viewed: viewed, now: now, isCurrentMonth: isCurrent,
                              pace: pace)
                        .ticketRow(bottom: 20)

                    if isCurrent, let code = CurrencySuggestion.switchTo(
                        markers: monthExpenses.map(\.currencyMarker), primary: primaryCurrency,
                        offered: CurrencyPreference.offered) {
                        CurrencySuggestionRow(code: code) { setPrimary(code) }
                            .ticketRow(bottom: 20)
                    }
                }
                if expenses.isEmpty {
                    EmptyTicket { showingSetup = true }
                        .ticketRow()
                } else {
                    if !searching {
                        MonthCarousel(
                            calendarModel: MonthCalendar.make(amounts, inMonthOf: viewed,
                                                              primary: primaryCurrency, today: now),
                            selectedDay: selectedDay,
                            onSelectDay: { day in withAnimation(.snappy) { selectedDay = day } },
                            spent: summary.primary,
                            pace: pace,
                            isCurrentMonth: isCurrent,
                            shares: CategoryShare.top(summary.categories),
                            note: fact.map { MonthNote.text(for: $0, stored: storedNote) },
                            onSetBudget: { showingBudget = true },
                            currency: primaryCurrency
                        )
                        // Edge to edge: each page keeps its own margin, so a swipe shows a gap
                        // between them instead of two pages touching.
                        .ticketRow(bottom: isCurrent ? 4 : 20, horizontal: 0)

                        if isCurrent {
                            CaptureHealthRow(
                                health: CaptureHealth(lastCapture: latestCaptures.first?.date,
                                                      now: now),
                                openGuide: { showingSetup = true }
                            )
                            .ticketRow(bottom: 12)
                        }

                        if let day = selectedDay {
                            DayFilterRow(day: day, count: shownExpenses.count) {
                                withAnimation(.snappy) { selectedDay = nil }
                            }
                            .ticketRow()
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
                    }
                    ForEach(listed) { expense in
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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Uber de octubre arriba de 200")
            .task(id: searchText) { await understandSearch() }
            .task(id: fact.map(MonthNote.identity)) { if let fact { await MonthNote.reword(fact) } }
            .task(id: expenses.count) { await MerchantReview.run(in: context) }
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
                        Button("Gastos fijos", systemImage: "repeat") { showingFixed = true }
                        Button("Tarjetas y categorías", systemImage: "creditcard") { showingCatalogs = true }
                        Picker(selection: Binding(get: { primaryCurrency }, set: { setPrimary($0) })) {
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
                        #if DEBUG
                        Button("Probar el modelo", systemImage: "cpu") { checkingModel = true }
                        #endif
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
                        .font(.ticket(15, weight: .medium, relativeTo: .body))
                        .tracking(2)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
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
            .sheet(item: $editing) { ExpenseEditorView(expense: $0, onDelete: { delete($0) }) }
            .sheet(isPresented: $showingBudget) {
                BudgetSheet(stored: $storedBudget, currency: primaryCurrency,
                            spent: isCurrent ? summary.primary.amount
                                : MonthSummarizer.summarize(amounts, inMonthOf: now,
                                                            primary: primaryCurrency).primary.amount,
                            reserved: FixedOutlook.reserved(originals: expenses.filter { $0.repeatsMonthly == true },
                                                            plans: FixedPlan.decode(storedPlans),
                                                            primary: primaryCurrency, now: now))
            }
            .confirmationDialog(
                "¿Borrar este gasto?",
                isPresented: deleteDialogShown,
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { expense in
                Button("Borrar", role: .destructive) { delete(expense) }
            } message: { expense in
                Text("\(expense.shownName) · \(ledgerAmount(for: expense, primary: primaryCurrency))")
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                importMessage = importFile(result)
            }
            .alert("Importar CSV", isPresented: importAlertShown) {
                Button("Listo", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
            // A new month, by the arrows or by midnight on the 1st, starts unfiltered.
            .onChange(of: viewed) { _, _ in selectedDay = nil }
            .modifier(Feedback(expenseCount: expenses.count, newest: expenses.first?.date,
                               isOver: isCurrent && isOver(pace)))
            .overlay(alignment: .bottom) { undoOverlay }
            .modifier(KeepsTime(now: $now, context: context))
            .modifier(CatalogsSheet(isPresented: $showingCatalogs))
            .modifier(ModelCheckSheet(isPresented: $checkingModel))
            .sheet(isPresented: $showingFixed) { FixedExpensesView() }
            .onChange(of: storedPlans) { _, value in
                if Store.syncsBudget { BudgetSync.push(value, for: FixedPlan.key) }
            }
            .modifier(BudgetCurrencyCheck(isPresented: $currencyChanged, currency: primaryCurrency,
                                          onReview: { showingBudget = true }))
            .task {
                // Siri learns the categories it can be asked about («¿Cuánto llevo en Café?»).
                CentavoShortcuts.updateAppShortcutParameters()
                // Never chosen: settle it once, from what the payments are in (pesos if none),
                // so it cannot drift with the phone's settings.
                if !CurrencyPreference.offered.contains(storedCurrency) {
                    storedCurrency = CurrencySuggestion.dominant(
                        markers: expenses.prefix(100).map(\.currencyMarker),
                        primary: CurrencyPreference.fallback,
                        offered: CurrencyPreference.offered) ?? CurrencyPreference.fallback
                }
                guard !onboarded else { return }
                // A reinstall or a new phone: the expenses are still coming from iCloud.
                let setUpElsewhere = Store.syncsBudget && BudgetSync.hasSetupElsewhere
                if expenses.isEmpty && Onboarding.isAllowed && !setUpElsewhere {
                    showingOnboarding = true
                } else {
                    onboarded = true
                }
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView { openGuide in
                    onboarded = true
                    if Store.syncsBudget { BudgetSync.markOnboarded() }
                    showingOnboarding = false
                    if openGuide {
                        Task { try? await Task.sleep(for: .milliseconds(500)); showingSetup = true }
                    }
                }
            }
        }
    }
}

/// Most of this month's payments are in another currency than the one the month adds up in:
/// one tap to add up in theirs.
private struct CurrencySuggestionRow: View {
    let code: String
    let apply: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Casi todos tus pagos de este mes son en \(CurrencyPreference.spoken(code)).")
                .font(.ticket(12, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Sumar en \(CurrencyPreference.spoken(code))", action: apply)
                .font(.ticket(12, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Theme.onBrass)
                .buttonStyle(.borderedProminent)
                .tint(Theme.brass)
                .frame(minHeight: 44)
                .accessibilityIdentifier("sumar-en-moneda")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.outline, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }
}

/// «Tarjetas y categorías», and pushing what changes there to iCloud like the budget.
private struct CatalogsSheet: ViewModifier {
    @Binding var isPresented: Bool
    @AppStorage(UserCatalog.sourcesKey) private var sources = ""
    @AppStorage(UserCatalog.defaultSourceKey) private var defaultSource = ""
    @AppStorage(UserCatalog.categoriesKey) private var categories = ""

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) { CatalogSettingsView() }
            .onChange(of: sources) { _, value in push(value, UserCatalog.sourcesKey) }
            .onChange(of: defaultSource) { _, value in push(value, UserCatalog.defaultSourceKey) }
            .onChange(of: categories) { _, value in
                push(value, UserCatalog.categoriesKey)
                CentavoShortcuts.updateAppShortcutParameters()
            }
    }

    private func push(_ value: String, _ key: String) {
        if Store.syncsBudget { BudgetSync.push(value, for: key) }
    }
}

/// After the main currency changes: the budget stays the same number, so offer to fix it.
private struct BudgetCurrencyCheck: ViewModifier {
    @Binding var isPresented: Bool
    let currency: String
    let onReview: () -> Void

    func body(content: Content) -> some View {
        content.alert("¿Y tu presupuesto?", isPresented: $isPresented) {
            Button("Cambiarlo", action: onReview)
            Button("Así está bien", role: .cancel) {}
        } message: {
            Text("Sigue siendo el mismo número, ahora en \(CurrencyPreference.spoken(currency)).")
        }
    }
}

/// A soft tap when an expense lands; a warning the moment the budget is blown.
private struct Feedback: ViewModifier {
    let expenseCount: Int
    /// The latest expense's date. Only one dated just now is a payment that just landed;
    /// an import, an undo, a fixed expense's copy or one arriving from iCloud is older.
    let newest: Date?
    let isOver: Bool

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.success, trigger: expenseCount) { old, new in
                new > old && (newest.map { Date.now.timeIntervalSince($0) < 120 } ?? false)
            }
            .sensoryFeedback(.warning, trigger: isOver) { old, new in !old && new }
    }
}

/// Keeps "now" fresh (coming back, midnight, a time-zone change) and logs the fixed expenses
/// whose day came while the app was closed.
private struct KeepsTime: ViewModifier {
    @Binding var now: Date
    let context: ModelContext
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = .now }
            }
            .task(id: now) { try? RecurringExpenses.logDue(in: context, now: now) }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.significantTimeChangeNotification)) { _ in
                now = .now
            }
    }
}

private extension ExpenseListView {
    // Pulled out of `body`: the CI's compiler gave up type-checking it all in one expression.
    var deleteDialogShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    var importAlertShown: Binding<Bool> {
        Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
    }

    /// Every expense the search asks for, from any month, newest first.
    var searchResults: [Expense] {
        var query = ExpenseSearch.query(from: searchText, now: now)
        if let searchCategory {
            query.words = []
            query.category = searchCategory
        }
        return expenses.filter { ExpenseSearch.matches($0.searchable, query) }
    }

    /// When the words match nothing as written, the on-device model may know which category
    /// they mean. Without it, the search is the plain one.
    func understandSearch() async {
        searchCategory = nil
        let query = ExpenseSearch.query(from: searchText, now: now)
        guard !query.words.isEmpty, LocalModel.isReady, searchResults.isEmpty else { return }
        // Waits for the typing to stop.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let history = expenses.prefix(500).map(\.categorized)
        let custom = UserCatalog.decode(UserDefaults.standard.string(forKey: UserCatalog.categoriesKey) ?? "")
        let candidates = CategoryPick.candidates(CategoryStyle.common.map(\.name), custom.map(\.name),
                                                 CategoryMemory.known(in: Array(history)))
        let picked = await LocalModel.category(for: query.words.joined(separator: " "), candidates: candidates)
        guard !Task.isCancelled else { return }
        searchCategory = picked
    }

    func isOver(_ pace: BudgetPace?) -> Bool {
        guard let pace else { return false }
        return pace.remaining < 0
    }

    @ViewBuilder var undoOverlay: some View {
        if let deleted = lastDeleted {
            UndoBar(text: "Borraste \(deleted.displayName ?? deleted.merchant)") { restore(deleted) }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.bottom, 76)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: deleted.id) {
                    try? await Task.sleep(for: .seconds(6))
                    withAnimation { if lastDeleted?.id == deleted.id { lastDeleted = nil } }
                }
        }
    }

    func delete(_ expense: Expense) {
        let snapshot = DeletedExpense(expense)
        context.delete(expense)
        withAnimation(.snappy) { lastDeleted = snapshot }
    }

    func restore(_ deleted: DeletedExpense) {
        context.insert(deleted.make())
        withAnimation(.snappy) { lastDeleted = nil }
    }

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
            var parts = [summary.added == 1 ? "Se agregó 1 gasto." : "Se agregaron \(summary.added) gastos."]
            if summary.alreadyThere > 0 {
                parts.append(summary.alreadyThere == 1 ? "1 ya estaba." : "\(summary.alreadyThere) ya estaban.")
            }
            if summary.unreadable > 0 {
                parts.append(summary.unreadable == 1 ? "1 renglón no se pudo leer."
                             : "\(summary.unreadable) renglones no se pudieron leer.")
            }
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
    func ticketRow(bottom: CGFloat = 0, horizontal: CGFloat = Theme.horizontalPadding) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: horizontal,
                                      bottom: bottom, trailing: horizontal))
    }
}

// MARK: - Pieces

private struct HeroTotal: View {
    let summary: MonthSummary
    let viewed: Date
    let now: Date
    let isCurrentMonth: Bool
    let pace: BudgetPace?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// This month, with a budget not yet blown, the figure to decide by is what can still go
    /// today; the month's total becomes the line under it.
    private var allowance: Decimal? {
        guard isCurrentMonth, let pace, pace.remaining >= 0 else { return nil }
        return pace.dailyAllowance
    }

    private var allowanceText: String {
        let amount = allowance ?? 0
        if let iso = summary.primary.isoCode {
            return amount.formatted(currencyStyle(iso).precision(.fractionLength(0)))
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
                    .animation(reduceMotion ? nil : .snappy, value: allowance)
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
                    .animation(reduceMotion ? nil : .snappy, value: summary.primary.amount)
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
        Text(expense.shownName)
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

/// Everything needed to bring a deleted expense back exactly as it was.
private struct DeletedExpense: Identifiable {
    let id = UUID()
    let amount: Decimal, currencyMarker: String?, merchant: String, card: String?
    let date: Date, category: String?, rawAmount: String?
    let repeatsMonthly: Bool?, repeatsThrough: Date?, isRepeat: Bool?
    let displayName: String?, categorySource: String?, repeatRule: String?, repeatDay: Int?

    init(_ e: Expense) {
        amount = e.amount; currencyMarker = e.currencyMarker; merchant = e.merchant; card = e.card
        date = e.date; category = e.category; rawAmount = e.rawAmount
        repeatsMonthly = e.repeatsMonthly; repeatsThrough = e.repeatsThrough; isRepeat = e.isRepeat
        displayName = e.displayName; categorySource = e.categorySource
        repeatRule = e.repeatRule; repeatDay = e.repeatDay
    }

    func make() -> Expense {
        let e = Expense(amount: amount, currencyMarker: currencyMarker, merchant: merchant, card: card,
                        date: date, category: category, rawAmount: rawAmount)
        e.repeatsMonthly = repeatsMonthly; e.repeatsThrough = repeatsThrough; e.isRepeat = isRepeat
        e.displayName = displayName; e.categorySource = categorySource
        e.repeatRule = repeatRule; e.repeatDay = repeatDay
        return e
    }
}

/// "Borraste Oxxo · Deshacer", for a few seconds after a delete.
private struct UndoBar: View {
    let text: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.ticket(12, relativeTo: .footnote))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Deshacer", action: undo)
                .font(.ticket(12, weight: .semibold, relativeTo: .footnote))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Theme.brass)
                .frame(minHeight: 44)
                .accessibilityIdentifier("deshacer-borrado")
        }
        .padding(.horizontal, 16)
        .modifier(UndoBarSurface())
    }
}

/// Liquid Glass where the system has it (iOS 26+), the ticket's surface before that.
private struct UndoBarSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(Theme.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: 1) }
        }
    }
}

/// «3 gastos», over the results while searching; says so when the words were read as a category.
private struct SearchHeaderRow: View {
    let count: Int
    let category: String?

    var body: some View {
        Text(category.map { "\(count) \(count == 1 ? "gasto" : "gastos") en \($0)" }
             ?? (count == 0 ? "Sin resultados" : "\(count) \(count == 1 ? "gasto" : "gastos")"))
            .font(.ticket(12, weight: .semibold, relativeTo: .footnote))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Theme.brass)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityIdentifier("resultados-busqueda")
    }
}

/// "Día 12 · 2 gastos · Ver todo el mes" over the list while a day is picked.
private struct DayFilterRow: View {
    let day: Int
    let count: Int
    let clear: () -> Void

    var body: some View {
        HStack {
            Text("Día \(day) · \(count) \(count == 1 ? "gasto" : "gastos")")
                .font(.ticket(12, weight: .semibold, relativeTo: .footnote))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.brass)
            Spacer()
            Button("Ver todo el mes", action: clear)
                .font(.ticket(12, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 44)
                .accessibilityIdentifier("ver-todo-el-mes")
        }
    }
}

/// Whether the welcome may show. The demo modes (screenshots and UI tests) skip it unless
/// asked with `-centavo-onboarding`.
enum Onboarding {
    static var isAllowed: Bool {
        #if DEBUG
        if DemoData.isRequested {
            return ProcessInfo.processInfo.arguments.contains("-centavo-onboarding")
        }
        #endif
        return true
    }
}
