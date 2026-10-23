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
    @AppStorage(PaymentPlace.key) private var savesPlace = false
    @State private var adding = false
    @State private var editing: Expense?
    @State private var importing = false
    /// A tapped calendar day narrows the list to it.
    @State private var selectedDay: Int?
    /// The category tapped in «En qué se va»: the list shows only its expenses.
    @State private var selectedCategory: CategoryShare?
    /// The expense row left open by a swipe, showing «Borrar».
    @State private var openRow: AnyHashable?
    @AppStorage(UnreadNotice.textKey) private var unreadText = ""
    @AppStorage(UnreadNotice.dateKey) private var unreadDate = 0.0
    @AppStorage(WhereItGoesStyle.key) private var whereItGoesStyle = WhereItGoesStyle.bar.rawValue
    /// What was just deleted, kept a few seconds so it can come back.
    @State private var lastDeleted: DeletedExpense?
    @State private var importMessage: String?
    /// What is being searched, as typed or dictated: «uber de octubre arriba de 200».
    @State private var searchText = ""
    /// The category the on-device model took the search words to mean, when they matched
    /// nothing as written («cafecitos» → «Café»).
    /// Fixed expenses whose first charge is still to come (`FixedPlan`).
    @AppStorage(FixedPlan.key) private var storedPlans = ""
    @State private var showingFixed = false

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
        let shownExpenses = monthExpenses.filter { expense in
            (selectedDay.map { Calendar.current.component(.day, from: expense.date) == $0 } ?? true)
                && (selectedCategory?.contains(expense.category) ?? true)
        }
        let summary = MonthSummarizer.summarize(amounts, inMonthOf: viewed, primary: primaryCurrency)
        // A month that is over is measured at its last second: all of the budget was due.
        // This month, the fixed expenses still to come are set apart from «Hoy puedes gastar».
        let reserved = isCurrent ? FixedOutlook.reserved(originals: expenses.filter { $0.repeatsMonthly == true },
                                                         plans: FixedPlan.decode(storedPlans),
                                                         primary: primaryCurrency, now: now) : 0
        // What today already spent comes off today alone, not off the days still to come.
        let spentToday = isCurrent ? MonthSummarizer.dayTotal(amounts, onDayOf: now, primary: primaryCurrency) : 0
        let pace = BudgetPace(budget: BudgetStore.amount(from: storedBudget),
                              spent: summary.primary.amount, spentToday: spentToday, reserved: reserved,
                              on: isCurrent ? now : MonthNavigator.closingMoment(of: viewed))
        let searching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let listed = searching ? searchResults : shownExpenses
        let groups = DayGroup.split(listed)
        let health = CaptureHealth(lastCapture: latestCaptures.first?.date, now: now)
        let fact = isCurrent ? MonthNote.facts(expenses, now: now, primary: primaryCurrency,
                                               budget: BudgetStore.amount(from: storedBudget)).first : nil

        NavigationStack {
            // Not a `List`: a list snaps a row to its new height, and the carousel's height has
            // to ease with the list below it (it leapt and wobbled, measured frame by frame).
            ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if searching {
                    SearchHeaderRow(count: listed.count)
                        .ticketRow(bottom: 8)
                } else {
                    HeroTotal(summary: summary, viewed: viewed, now: now, isCurrentMonth: isCurrent,
                              pace: pace)
                        // With a budget the verdict sits right under the figure, one step away.
                        .ticketRow(bottom: pace != nil && !expenses.isEmpty ? 8 : 20)

                    if isCurrent, let code = CurrencySuggestion.switchTo(
                        markers: monthExpenses.map(\.currencyMarker), primary: primaryCurrency,
                        offered: CurrencyPreference.offered) {
                        CurrencySuggestionRow(code: code) { setPrimary(code) }
                            .ticketRow(bottom: 20)
                    }
                }
                if expenses.isEmpty {
                    // A budget with nothing spent yet still has its days to show.
                    if let pace {
                        BudgetPage(spent: summary.primary, pace: pace, isCurrentMonth: isCurrent,
                                   onSetBudget: { showingBudget = true })
                            .ticketRow(bottom: 20)
                    }
                    EmptyTicket { showingSetup = true }
                        .ticketRow()
                } else {
                    if !searching {
                        MonthCarousel(
                            calendarModel: MonthCalendar.make(amounts, inMonthOf: viewed,
                                                              primary: primaryCurrency, today: now),
                            selectedDay: selectedDay,
                            onSelectDay: { day in
                                withAnimation(.snappy) { selectedDay = day; selectedCategory = nil }
                            },
                            spent: summary.primary,
                            pace: pace,
                            isCurrentMonth: isCurrent,
                            shares: CategoryShare.top(summary.categories),
                            returned: CategoryShare.returned(summary.categories),
                            note: fact?.line,
                            selectedCategory: selectedCategory,
                            onSelectCategory: { line in selectedCategory = line; selectedDay = nil },
                            onSetBudget: { showingBudget = true },
                            currency: primaryCurrency
                        )
                        // Edge to edge: each page keeps its own margin, so a swipe shows a gap
                        // between them instead of two pages touching.
                        .ticketRow(bottom: isCurrent ? 0 : 20, horizontal: 0)

                        // The Wallet line stays between the carousel and the list, not under «Hoy»:
                        // it is about the capture, not about today's expenses (owner, 2026-10-21).
                        if isCurrent {
                            CaptureHealthRow(health: health, unread: unreadNotice(after: latestCaptures.first?.date),
                                             openGuide: {
                                                 // Seen: tapping the warning is the last time it shows.
                                                 UnreadNotice.clear()
                                                 showingSetup = true
                                             })
                                .ticketRow()
                        }

                        if let day = selectedDay {
                            FilterRow(title: "Día \(day)", count: shownExpenses.count) {
                                withAnimation(.snappy) { selectedDay = nil }
                            }
                            .ticketRow()
                        }
                        if let line = selectedCategory {
                            FilterRow(title: line.isRest ? "Otras" : line.category ?? "Sin categoría",
                                      count: shownExpenses.count) {
                                withAnimation(.snappy) { selectedCategory = nil }
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
                    ForEach(groups) { group in
                        // A thin brass line where a new day starts: «Hoy · 19 oct», «Ayer», «vie 17 oct».
                        DayDivider(day: group.day, total: group.total(in: primaryCurrency), now: now)
                            .ticketRow()
                        ForEach(group.items) { expense in
                            // The divider already draws the line above a day's first row.
                            LedgerRow(expense: expense, primaryCurrency: primaryCurrency,
                                      perforated: expense.id != group.items.first?.id)
                                // A tap, not a Button: a button also fires when a swipe lets go
                                // on it, and a tap gives up as soon as the finger moves. While
                                // a row is open, a tap on another only closes it, as in a list.
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if openRow != nil { openRow = nil } else { editing = expense }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .ticketRow()
                            .swipeToDelete(id: expense.persistentModelID, openRow: $openRow) {
                                pendingDelete = expense
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
            .padding(.top, 8)
            .padding(.bottom, 24)
            }
            // Scrolling closes a row left open by a swipe, as in a system list.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting, openRow != nil { openRow = nil }
            }
            .modifier(BottomSearch(text: $searchText))
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
                        Toggle(isOn: Binding(get: { savesPlace }, set: { on in
                            savesPlace = on
                            if on { PaymentPlace.requestPermission() }
                        })) {
                            Label("Guardar dónde pagas", systemImage: "mappin.and.ellipse")
                        }
                        Picker(selection: Binding(get: { primaryCurrency }, set: { setPrimary($0) })) {
                            ForEach(CurrencyPreference.offered, id: \.self) { code in
                                Text(CurrencyPreference.name(code)).tag(code)
                            }
                        } label: {
                            Label("Moneda principal", systemImage: "dollarsign.circle")
                        }
                        .pickerStyle(.menu)
                        Picker(selection: $whereItGoesStyle) {
                            ForEach(WhereItGoesStyle.allCases) { style in
                                Label(style.title, systemImage: style.icon).tag(style.rawValue)
                            }
                        } label: {
                            Label("En qué se va", systemImage: "square.grid.2x2")
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
                // ‹ month › is one piece of glass; search sits apart at the other end.
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Mes anterior", systemImage: "chevron.left") { monthOffset = offset - 1 }
                        .disabled(offset <= earliest)
                    Text(viewed, format: .dateTime.month(.abbreviated).year())
                        .font(.ticket(15, weight: .medium, relativeTo: .body))
                        .tracking(2)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 4)
                    Button("Mes siguiente", systemImage: "chevron.right") { monthOffset = offset + 1 }
                        .disabled(offset >= 0)
                }
                // Search lives down here with the months, as a button that opens into a field
                // (iOS 26), not as a bar across the top of the ticket.
                if #available(iOS 26, *) {
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
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
                            spentToday: MonthSummarizer.dayTotal(amounts, onDayOf: now, primary: primaryCurrency),
                            reserved: FixedOutlook.reserved(originals: expenses.filter { $0.repeatsMonthly == true },
                                                            plans: FixedPlan.decode(storedPlans),
                                                            primary: primaryCurrency, now: now))
            }
            .confirmsDelete(of: $pendingDelete, primaryCurrency: primaryCurrency, undoable: true) {
                delete($0)
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
            .onChange(of: viewed) { _, _ in selectedDay = nil; selectedCategory = nil }
            // Only the mosaic picks a category: with another view there is no block to undo it.
            .onChange(of: whereItGoesStyle) { _, _ in selectedCategory = nil }
            .modifier(Feedback(expenseCount: expenses.count, newest: expenses.first?.date,
                               isOver: isCurrent && isOver(pace)))
            .overlay(alignment: .bottom) { undoOverlay }
            .modifier(KeepsTime(now: $now, context: context))
            .modifier(CatalogsSheet(isPresented: $showingCatalogs))
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
    @AppStorage(UserCatalog.hiddenCategoriesKey) private var hidden = ""

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) { CatalogSettingsView() }
            .onChange(of: sources) { _, value in push(value, UserCatalog.sourcesKey) }
            .onChange(of: defaultSource) { _, value in push(value, UserCatalog.defaultSourceKey) }
            .onChange(of: hidden) { _, value in push(value, UserCatalog.hiddenCategoriesKey) }
            .onChange(of: categories) { _, value in
                push(value, UserCatalog.categoriesKey)
                CentavoShortcuts.updateAppShortcutParameters()
            }
    }

    private func push(_ value: String, _ key: String) {
        if Store.syncsBudget { BudgetSync.push(value, for: key) }
    }
}

/// The search: a button in the bottom bar that opens into a field on iOS 26; on older
/// systems, the usual field under the title.
private struct BottomSearch: ViewModifier {
    @Binding var text: String
    private let prompt = "Busca tus gastos"

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .searchable(text: $text, prompt: prompt)
                .searchToolbarBehavior(.minimize)
        } else {
            content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .automatic),
                               prompt: prompt)
        }
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
            .task(id: now) {
                try? RecurringExpenses.logDue(in: context, now: now)
                try? ExpenseRecorder.repairBankMerchants(in: context)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.significantTimeChangeNotification)) { _ in
                now = .now
            }
    }
}

private extension ExpenseListView {
    // Pulled out of `body`: the CI's compiler gave up type-checking it all in one expression.
    var importAlertShown: Binding<Bool> {
        Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
    }

    /// Every expense the search asks for, from any month, newest first.
    var searchResults: [Expense] {
        let query = ExpenseSearch.query(from: searchText, now: now)
        return expenses.filter { ExpenseSearch.matches($0.searchable, query) }
    }

    /// The unread notice, if it came after the last payment the capture saved and less than
    /// two days ago: it goes once a payment comes in right, once tapped, or on its own.
    func unreadNotice(after lastCapture: Date?) -> String? {
        guard !unreadText.isEmpty else { return nil }
        let date = Date(timeIntervalSinceReferenceDate: unreadDate)
        guard now.timeIntervalSince(date) < 2 * 24 * 3600 else { return nil }
        return lastCapture.map { date > $0 } ?? true ? unreadText : nil
    }

    func isOver(_ pace: BudgetPace?) -> Bool {
        guard let pace else { return false }
        return pace.remaining < 0
    }

    @ViewBuilder var undoOverlay: some View {
        if let deleted = lastDeleted {
            UndoBar(text: "Borraste \(deleted.displayName ?? deleted.merchant)") { restore(deleted) }
                .padding(.horizontal, Theme.horizontalPadding)
                // Right above the bottom bar: the safe area already ends at the bar.
                .padding(.bottom, 12)
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
    /// A line of the ticket: the side margins and the space under it.
    func ticketRow(bottom: CGFloat = 0, horizontal: CGFloat = Theme.horizontalPadding) -> some View {
        self
            // Exactly the screen's width less the margins, as a list row was: a long name
            // can't widen the line past the screen.
            .containerRelativeFrame(.horizontal, alignment: .leading) { length, _ in
                max(length - 2 * horizontal, 0)
            }
            .padding(.horizontal, horizontal)
            .padding(.bottom, bottom)
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

    @State private var counted: Double = 0

    private var allowanceValue: Double { NSDecimalNumber(decimal: allowance ?? 0).doubleValue }

    /// The figure on its way up: whole money, like the final one.
    private var countedText: String {
        let amount = Decimal(counted.rounded(.down))
        if let iso = summary.primary.isoCode {
            return amount.formatted(currencyStyle(iso).precision(.fractionLength(0)))
        }
        return summary.primary.label + amount.formatted(.number.precision(.fractionLength(0)))
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
                    // Grey like every other caption, so the brass figure under it leads.
                    .foregroundStyle(Theme.muted)
                // Counts up from zero when the screen opens, and rolls to the new figure after
                // every payment.
                Text(countedText)
                    .accessibilityIdentifier("hoy-puedes-gastar")
                    .accessibilityLabel(allowanceText)
                    .font(.ticket(54, weight: .medium, relativeTo: .largeTitle))
                    .tracking(-2)
                    .foregroundStyle(Theme.brass)
                    // The «$» carries its own air on the left (3 pt at this size, measured): pulled
                    // back so the figure lines up with «Hoy puedes gastar» above it.
                    .padding(.leading, -3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: counted))
                    .onAppear {
                        guard !reduceMotion else { counted = allowanceValue; return }
                        withAnimation(.snappy(duration: 0.9)) { counted = allowanceValue }
                    }
                    .onChange(of: allowanceValue) { _, value in
                        withAnimation(reduceMotion ? nil : .snappy) { counted = value }
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
            // Adding currencies together would be a lie, so they ride along separately, under the
            // month's total; with «Hoy puedes gastar» on top they would only crowd it (each one
            // still shows in its own row of the list).
            if allowance == nil, !summary.others.isEmpty {
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
    /// The dashed line on top; a day's first row has the divider there instead.
    var perforated = true

    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 15

    private var isRefund: Bool { expense.amount < 0 }

    /// The category's icon on a small tile, the same icons as «En qué se va».
    private var categoryTile: some View {
        let category = expense.category.flatMap { $0.isEmpty ? nil : $0 }
        return Image(systemName: category.map {
            CategoryStyle.icon(for: $0, custom: UserCatalog.decode(storedCategories))
        } ?? "questionmark")
            .resizable()
            .scaledToFit()
            .fontWeight(.medium)
            .foregroundStyle(category == nil ? Theme.muted : Theme.brass)
            .frame(width: iconSize, height: iconSize)
            .frame(width: tileSize, height: tileSize)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private var meta: String? {
        let parts = [isRefund ? "Devolución" : nil, expense.isFixed ? "Fijo" : nil,
                     expense.category, expense.card]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
                    merchantText
                    metaText
                    amountText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    categoryTile
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            merchantText
                            metaText
                        }
                        Spacer(minLength: 8)
                        amountText
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .overlay(alignment: .top) { if perforated { Perforation() } }
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

    var body: some View {
        Text(count == 0 ? "Sin resultados" : "\(count) \(count == 1 ? "gasto" : "gastos")")
            .font(.ticket(12, weight: .semibold, relativeTo: .footnote))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Theme.brass)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityIdentifier("resultados-busqueda")
    }
}

/// «Día 12 · 2 gastos · Ver todo el mes» (or «Ropa · 2 gastos») over the list while a day
/// or a category is picked.
private struct FilterRow: View {
    let title: String
    let count: Int
    let clear: () -> Void

    var body: some View {
        HStack {
            Text("\(title) · \(count) \(count == 1 ? "gasto" : "gastos")")
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

/// The expenses of one day, in the order they were listed.
struct DayGroup: Identifiable {
    let day: Date
    let items: [Expense]
    var id: Date { day }

    static func split(_ expenses: [Expense], calendar: Calendar = .current) -> [DayGroup] {
        var groups: [DayGroup] = []
        for expense in expenses {
            let day = calendar.startOfDay(for: expense.date)
            if let last = groups.last, last.day == day {
                groups[groups.count - 1] = DayGroup(day: day, items: last.items + [expense])
            } else {
                groups.append(DayGroup(day: day, items: [expense]))
            }
        }
        return groups
    }

    /// What went that day in the month's currency (refunds subtract); others ride apart.
    func total(in primary: String) -> String? {
        let mine = items.filter { CurrencyResolver.isoCode(for: $0.currencyMarker, primary: primary) == primary }
        // A day only in other money still says how much: «USD 24.99».
        guard !mine.isEmpty else {
            guard let first = items.first else { return nil }
            let code = CurrencyResolver.isoCode(for: first.currencyMarker, primary: primary)
            let same = items.filter { CurrencyResolver.isoCode(for: $0.currencyMarker, primary: primary) == code }
            let sum = same.reduce(Decimal(0)) { $0 + $1.amount }
            let number = sum.magnitude.formatted(.number.precision(.fractionLength(2)))
            let label = String((code ?? first.currencyMarker ?? "").prefix(4))
            return (sum < 0 ? "+" : "") + (label.isEmpty ? number : "\(label) \(number)")
        }
        let sum = mine.reduce(Decimal(0)) { $0 + $1.amount }
        // Money that came back reads like the ledger's refunds: «+$230.00».
        return (sum < 0 ? "+" : "") + formatMoney(sum.magnitude, isoCode: primary, label: primary)
    }
}

/// Where a day starts in the list: a short brass line, the day, a hairline, the day's total.
private struct DayDivider: View {
    let day: Date
    let total: String?
    let now: Date

    private var label: String {
        let calendar = Calendar.current
        let date = day.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_MX")))
        if calendar.isDate(day, inSameDayAs: now) { return "Hoy · " + date }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Ayer · " + date }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            .locale(Locale(identifier: "es_MX")))
    }

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(Theme.brass).frame(width: 14, height: 3)
            Text(label)
                .font(.ticket(10, weight: .semibold, relativeTo: .caption2))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.brass)
                .lineLimit(1)
            Rectangle().fill(Theme.brass.opacity(0.25)).frame(height: 1)
            if let total {
                Text(total)
                    .font(.ticket(10, relativeTo: .caption2))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
