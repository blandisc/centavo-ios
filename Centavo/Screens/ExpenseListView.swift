import CentavoCore
import CoreData
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The only screen: a month's total, a swipeable calendar/budget, then that month's payments.
///
/// The look is the approved "Noche ticket" (dark, brass, receipt type). The structure is
/// Apple's: a real navigation bar and bottom bar (Liquid Glass on iOS 26), a `List` with
/// swipe-to-delete, system menus and sheets.
///
/// This view is the frame (bars, sheets, what syncs); what scrolls is `HomeContent`, which asks
/// the store for the month on screen only and works its numbers out in `HomeModel`, once per
/// change instead of on every redraw.
struct ExpenseListView: View {
    /// The newest and the oldest expense, one row each (audit 2026-11-02: it used to load every
    /// expense just to count them). How many there are is asked of the store as a count.
    @Query(HomeModel.newest(1)) private var newestRows: [Expense]
    @Query(HomeModel.oldest) private var oldestRows: [Expense]
    @State private var storeCount = 0

    /// How many expenses there are, counted by the store (`fetchCount`), not loaded.
    private func countStore() {
        storeCount = (try? context.fetchCount(FetchDescriptor<Expense>())) ?? storeCount
    }
    /// The newest payment the Wallet automation saved (only it keeps the raw text). Asked of
    /// the store, one row, instead of scanning every expense on each redraw.
    @Query(Self.latestCapture) private var latestCaptures: [Expense]
    @AppStorage(WalletWatch.lastArrivalKey) private var walletArrival: Double = 0

    /// Before the remembered arrival existed, only the store knew: carry it over once, so
    /// deleting those payments later can't make Wallet look disconnected.
    private func rememberWalletArrival() {
        guard walletArrival <= 0, let newest = latestCaptures.first?.date else { return }
        WalletWatch.noteArrival(newest)
    }

    private static var latestCapture: FetchDescriptor<Expense> {
        var descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.rawAmount != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// The search, the row left open by a swipe and the screen's numbers, worked out once.
    @State private var model = HomeModel()
    @AppStorage(UnreadNotice.textKey) private var unreadText = ""
    @AppStorage(UnreadNotice.dateKey) private var unreadDate = 0.0
    @AppStorage(WhereItGoesStyle.key) private var whereItGoesStyle = WhereItGoesStyle.bar.rawValue
    /// What was just deleted, kept a few seconds so it can come back.
    @State private var lastDeleted: DeletedExpense?
    @State private var importMessage: String?
    /// A change made here (delete, undo, a category) that couldn't be saved.
    @State private var saveProblem: String?
    /// Fixed expenses whose first charge is still to come (`FixedPlan`).
    @AppStorage(FixedPlan.key) private var storedPlans = ""
    /// How «Hoy puedes gastar» treats what a day leaves over (`AllowanceMode`).
    @AppStorage(AllowanceMode.key) private var storedMode = ""
    @State private var showingFixed = false
    @State private var showingSettings = false
    @State private var backupWarning: String?
    /// «Cómo funciona», and where its «Pruébalo» goes once it has closed.
    @State private var showingTutorial = false
    @State private var afterTutorial: TutorialDestination?
    /// Where the welcome said to go, opened once it has gone (two covers can't overlap).
    @State private var afterOnboarding: OnboardingExit?
    @AppStorage(WalletWatch.key) private var ignoresWallet = false
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @AppStorage(UserCatalog.hiddenCategoriesKey) private var storedHiddenCategories = ""
    @AppStorage(UserCatalog.sourcesKey) private var storedSources = ""
    @AppStorage(UserCatalog.categoryColorsKey) private var storedCategoryColors = ""
    @AppStorage(UserCatalog.sourceColorsKey) private var storedSourceColors = ""
    /// What of the screen's entrance has already played (`Entrance`).
    @State private var entrance = Entrance()
    /// The list's width, measured. Each line takes it from here and not from
    /// `containerRelativeFrame`, which kept the landscape width after turning the phone back
    /// upright and left the whole screen wider and pushed off to the left (owner, 2026-10-27).
    @State private var listWidth: CGFloat?

    private var primaryCurrency: String { CurrencyPreference.resolve(storedCurrency) }
    /// Months are written the way the days of the list are, whatever the phone's language.
    static let mexico = Locale(identifier: "es_MX")

    /// Changes the currency the month adds up in. The budget is a bare number, and 8,000
    /// pesos must not quietly become 8,000 dollars, so it asks about it.
    private func setPrimary(_ code: String) {
        if code != primaryCurrency, BudgetStore.amount(from: storedBudget) != nil {
            currencyChanged = true
        }
        storedCurrency = code
    }

    var body: some View {
        // You can browse back as far as the oldest expense, and no further; deleting it pulls the
        // limit forward.
        let earliest = MonthNavigator.earliestOffset(oldest: oldestRows.first?.date, now: now)
        let offset = min(0, max(monthOffset, earliest))
        let isCurrent = offset == 0
        let viewed = MonthNavigator.month(offsetBy: offset, from: now)
        let lastCapture = WalletWatch.lastCapture(stored: walletArrival, newestInStore: latestCaptures.first?.date)

        NavigationStack {
            HomeContent(
                model: model, viewed: viewed, now: now, isCurrent: isCurrent,
                storeIsEmpty: newestRows.isEmpty,
                stamp: StoreStamp(count: storeCount, newest: newestRows.first?.date),
                settings: HomeSettings(budget: storedBudget, plans: storedPlans, currency: primaryCurrency,
                                       mode: storedMode, whereItGoesStyle: whereItGoesStyle,
                                       ignoresWallet: ignoresWallet, backupWarning: backupWarning),
                catalog: model.catalog(categories: storedCategories, hidden: storedHiddenCategories,
                                       sources: storedSources, categoryColors: storedCategoryColors,
                                       sourceColors: storedSourceColors),
                lastCapture: lastCapture, unread: unreadNotice(after: lastCapture),
                selectedDay: selectedDay, selectedCategory: selectedCategory,
                entrance: entrance, listWidth: listWidth, actions: actions
            )
            .equatable()
            // Scrolling closes a row left open by a swipe, as in a system list.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting, model.openRow != nil { model.openRow = nil }
            }
            .modifier(BottomSearch(text: Bindable(model).searchText) { model.query = $0 })
            // An edit can make an expense match the search or stop matching.
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                model.storeSaved()
            }
            .modifier(CountsStore(newest: newestRows.first?.persistentModelID,
                                  oldest: oldestRows.first?.persistentModelID, recount: countStore))
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: storedBudget) { _, budget in
                if Store.syncsBudget { BudgetSync.push(budget) }
            }
            .onChange(of: storedCurrency) { _, code in
                if Store.syncsBudget { BudgetSync.push(code, for: CurrencyPreference.key) }
            }
            .onChange(of: storedMode) { _, mode in
                if Store.syncsBudget { BudgetSync.push(mode, for: AllowanceMode.key) }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // The app's signature (2026-10-29): lowercase, bigger than a sheet's title,
                    // with a brass full stop. «Al día. Punto.»
                    Text("al día\(Text(".").foregroundStyle(Theme.brass))")
                        .font(.ticket(.subheading))
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel("Al día")
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // The view, at the menu's first level as it was (owner, 2026-10-30).
                        Section("Vista") {
                            Picker("Vista", selection: $whereItGoesStyle) {
                                ForEach(WhereItGoesStyle.allCases) { style in
                                    Label(style.title, systemImage: style.icon).tag(style.rawValue)
                                }
                            }
                            .pickerStyle(.inline)
                        }
                        Section {
                            Button("Presupuesto del mes", systemImage: "target") { showingBudget = true }
                            Button("Gastos fijos", systemImage: "repeat") { showingFixed = true }
                            Button("Pagos y categorías", systemImage: "creditcard") { showingCatalogs = true }
                        }
                        Section {
                            Button("Configurar atajo", systemImage: "wallet.pass") { showingSetup = true }
                            Button("Cómo funciona", systemImage: "play.rectangle") { showingTutorial = true }
                            Button("Ajustes", systemImage: "gearshape") { showingSettings = true }
                        }
                    } label: {
                        Label("Más", systemImage: "ellipsis")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Anotar gasto", systemImage: "plus") { adding = true }
                }
                // ‹ › up top since «Mi dinero» put tabs at the bottom (2026-10-31). Only the
                // arrows: the ticket's head already names the month, and the signature must
                // keep its place in the middle. Search stays down there, beside the tabs.
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Mes anterior", systemImage: "chevron.left") { monthOffset = offset - 1 }
                        .disabled(offset <= earliest)
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
            // The widgets' «+» and «Fijar presupuesto» (`centavo://anotar`, `centavo://presupuesto`).
            .onOpenURL { url in
                guard url.scheme == "centavo" else { return }
                switch url.host() {
                case "anotar": adding = true
                case "presupuesto": showingBudget = true
                default: break
                }
            }
            .onChange(of: storedBudget) { WidgetBridge.refresh() }
            .onChange(of: storedPlans) { WidgetBridge.refresh() }
            .onChange(of: storedCurrency) { WidgetBridge.refresh() }
            // The widgets get the new rule with the snapshot, and redraw.
            .onChange(of: storedMode) { WidgetBridge.refresh() }
            .sheet(isPresented: $adding) {
                // Adding while looking at a past month puts the expense in that month.
                ExpenseEditorView(expense: nil,
                                  initialDate: isCurrent ? nil : MonthNavigator.closingMoment(of: viewed))
            }
            .sheet(item: $editing) { ExpenseEditorView(expense: $0, onDelete: { delete($0) }) }
            .sheet(isPresented: $showingBudget) {
                BudgetSheet(stored: $storedBudget, storedMode: $storedMode, currency: primaryCurrency) { budget, mode in
                    // This month, asked of the store: only its rows and the fixed expenses.
                    TodayBudget.pace(budget: budget,
                                     rows: (try? context.fetch(HomeModel.monthRows(of: now))) ?? [],
                                     originals: (try? context.fetch(HomeModel.originals)) ?? [],
                                     plans: FixedPlan.decode(storedPlans),
                                     primary: primaryCurrency, month: now, now: now, mode: mode)
                }
            }
            .confirmsDelete(of: $pendingDelete, primaryCurrency: primaryCurrency, undoable: true) {
                delete($0)
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                importMessage = importFile(result)
            }
            .modifier(SaveProblemAlert(problem: $saveProblem))
            .alert("Importar CSV", isPresented: importAlertShown) {
                Button("Listo", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
            // A new month, by the arrows or by midnight on the 1st, starts unfiltered.
            .onChange(of: viewed) { _, _ in selectedDay = nil; selectedCategory = nil }
            // Another view starts unfiltered: what was picked may not be on it.
            .onChange(of: whereItGoesStyle) { _, _ in selectedCategory = nil }
            .modifier(Feedback(expenseCount: storeCount, newest: newestRows.first?.date))
            .overlay(alignment: .bottom) { undoOverlay }
            .modifier(KeepsTime(now: $now, context: context))
            .modifier(CatalogsSheet(isPresented: $showingCatalogs))
            .sheet(isPresented: $showingFixed) { FixedExpensesView() }
            .modifier(BackupWatch(warning: $backupWarning, now: now, settingsShown: showingSettings))
            .sheet(isPresented: $showingSettings) {
                SettingsView(currency: primaryCurrency, setCurrency: setPrimary,
                             health: CaptureHealth(lastCapture: lastCapture, now: now),
                             openGuide: { afterSettings { showingSetup = true } },
                             importCSV: { afterSettings { importing = true } })
            }
            .onChange(of: storedPlans) { _, value in
                if Store.syncsBudget { BudgetSync.push(value, for: FixedPlan.key) }
            }
            .modifier(BudgetCurrencyCheck(isPresented: $currencyChanged, currency: primaryCurrency,
                                          onReview: { showingBudget = true }))
            .task {
                rememberWalletArrival()
                // Siri learns the categories it can be asked about («¿Cuánto llevo en Café?»).
                CentavoShortcuts.updateAppShortcutParameters()
                // Never chosen: settle it once, from what the payments are in (pesos if none),
                // so it cannot drift with the phone's settings.
                if !CurrencyPreference.offered.contains(storedCurrency) {
                    let latest = (try? context.fetch(HomeModel.newest(100))) ?? []
                    storedCurrency = CurrencySuggestion.dominant(
                        markers: latest.map(\.currencyMarker),
                        primary: CurrencyPreference.fallback,
                        offered: CurrencyPreference.offered) ?? CurrencyPreference.fallback
                }
                if GuideDebug.opensAtLaunch { showingSetup = true }
                openRequestedSheet()
                guard !onboarded else { return }
                // A reinstall or a new phone: the expenses are still coming from iCloud.
                let setUpElsewhere = Store.syncsBudget && BudgetSync.hasSetupElsewhere
                if newestRows.isEmpty && Onboarding.isAllowed && !setUpElsewhere {
                    showingOnboarding = true
                } else {
                    onboarded = true
                }
            }
            .fullScreenCover(isPresented: $showingOnboarding, onDismiss: openAfterOnboarding) {
                OnboardingView { exit in
                    onboarded = true
                    if Store.syncsBudget { BudgetSync.markOnboarded() }
                    afterOnboarding = exit
                    showingOnboarding = false
                }
            }
            .fullScreenCover(isPresented: $showingTutorial, onDismiss: openAfterTutorial) {
                TutorialView { afterTutorial = $0 }
            }
        }
        // Measured on the whole screen, not on the scroll view: the scroll view takes its
        // content's width, so a width read there stayed at the landscape one. Its size is
        // already inside the sides kept clear in landscape (the Dynamic Island).
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
    }

    /// What the scrolling part asks of the frame: sheets to open, filters to set, an expense to
    /// change. Each one sets this view's state, so they do the same whenever they are called.
    private var actions: HomeActions {
        HomeActions(
            selectDay: { day in
                // The list changes at once: easing it left the old rows fading over the new
                // ones, under the calendar, for half a second.
                Theme.Motion.instantly { selectedDay = day; selectedCategory = nil }
            },
            selectCategory: { line in
                Theme.Motion.instantly { selectedCategory = line; selectedDay = nil }
            },
            clearDay: { Theme.Motion.instantly { selectedDay = nil } },
            clearCategory: { Theme.Motion.instantly { selectedCategory = nil } },
            add: { adding = true },
            setBudget: { showingBudget = true },
            setup: { showingSetup = true },
            openSettings: { showingSettings = true },
            openGuideFromWarning: {
                // Seen: tapping the warning is the last time it shows.
                UnreadNotice.clear()
                showingSetup = true
            },
            setPrimary: { setPrimary($0) },
            edit: { editing = $0 },
            askDelete: { pendingDelete = $0 },
            setCategory: { setCategory($0, of: $1) },
            change: { expense, edit in
                edit(expense)
                persist()
            },
            logAgain: { logAgain($0) }
        )
    }
}

/// The frame's settings the scrolling part reads.
private struct HomeSettings: Equatable {
    let budget: String
    let plans: String
    let currency: String
    let mode: String
    let whereItGoesStyle: String
    let ignoresWallet: Bool
    /// The daily backup failed or is days late (`DailyBackup.warning`); `nil` while it's fine.
    let backupWarning: String?
}

/// What the scrolling part can ask of the frame (`ExpenseListView.actions`).
private struct HomeActions {
    let selectDay: (Int?) -> Void
    let selectCategory: (CategoryShare?) -> Void
    let clearDay: () -> Void
    let clearCategory: () -> Void
    let add: () -> Void
    let setBudget: () -> Void
    let setup: () -> Void
    let openSettings: () -> Void
    let openGuideFromWarning: () -> Void
    let setPrimary: (String) -> Void
    let edit: (Expense) -> Void
    let askDelete: (Expense) -> Void
    let setCategory: (String, Expense) -> Void
    /// A change from the row's menu («No es repetida», «Sí cuenta», «No cuenta»), saved right
    /// then; if it fails, it's said (2026-11-02, second audit: it was saved with `try?`).
    let change: (Expense, (Expense) -> Void) -> Void
    let logAgain: (Expense) -> Void
}

/// What scrolls: the hero, the carousel and the month's days (or a search's results).
///
/// It asks the store for the month on screen, and for the last few months only when the note
/// needs them. It only redraws when what it shows changes (`Equatable`): a sheet opening or the
/// frame redrawing for another reason leaves it alone.
private struct HomeContent: View, Equatable {
    let model: HomeModel
    let viewed: Date
    let now: Date
    let isCurrent: Bool
    /// No expense at all, in any month.
    let storeIsEmpty: Bool
    let stamp: StoreStamp
    let settings: HomeSettings
    let catalog: CategoryCatalog
    let lastCapture: Date?
    let unread: String?
    let selectedDay: Int?
    let selectedCategory: CategoryShare?
    let entrance: Entrance
    let listWidth: CGFloat?
    let actions: HomeActions

    @Query private var monthRows: [Expense]
    @Query private var recentRows: [Expense]
    @Query(HomeModel.originals) private var originals: [Expense]
    @Environment(\.modelContext) private var context

    init(model: HomeModel, viewed: Date, now: Date, isCurrent: Bool, storeIsEmpty: Bool, stamp: StoreStamp,
         settings: HomeSettings, catalog: CategoryCatalog, lastCapture: Date?, unread: String?,
         selectedDay: Int?, selectedCategory: CategoryShare?, entrance: Entrance, listWidth: CGFloat?,
         actions: HomeActions) {
        self.model = model
        self.viewed = viewed
        self.now = now
        self.isCurrent = isCurrent
        self.storeIsEmpty = storeIsEmpty
        self.stamp = stamp
        self.settings = settings
        self.catalog = catalog
        self.lastCapture = lastCapture
        self.unread = unread
        self.selectedDay = selectedDay
        self.selectedCategory = selectedCategory
        self.entrance = entrance
        self.listWidth = listWidth
        self.actions = actions
        _monthRows = Query(HomeModel.monthRows(of: viewed))
        _recentRows = Query(HomeModel.recentRows(now: now, isCurrent: isCurrent))
    }

    /// Everything but `actions`: they only set the frame's state, the same on every redraw.
    nonisolated static func == (lhs: HomeContent, rhs: HomeContent) -> Bool {
        lhs.model === rhs.model && lhs.viewed == rhs.viewed && lhs.now == rhs.now
            && lhs.isCurrent == rhs.isCurrent && lhs.storeIsEmpty == rhs.storeIsEmpty
            && lhs.stamp == rhs.stamp && lhs.settings == rhs.settings && lhs.catalog == rhs.catalog
            && lhs.lastCapture == rhs.lastCapture && lhs.unread == rhs.unread
            && lhs.selectedDay == rhs.selectedDay && lhs.selectedCategory == rhs.selectedCategory
            && lhs.entrance === rhs.entrance && lhs.listWidth == rhs.listWidth
    }

    var body: some View {
        let primary = settings.currency
        let month = model.month(
            MonthInputs(viewed: viewed, now: now, isCurrent: isCurrent, budget: settings.budget,
                        plans: settings.plans, currency: primary, mode: settings.mode,
                        selectedDay: selectedDay, selectedCategory: selectedCategory),
            rows: monthRows, originals: originals)
        let searching = model.isSearching
        let search = searching ? model.search(now: now, stamp: stamp, in: context) : nil
        // The note is only on this month's carousel; past the budget, the plan above already says
        // where the month closes.
        let showsCarousel = !searching && !storeIsEmpty
        let note = showsCarousel && isCurrent && (month.pace?.remaining ?? 0) >= 0
            ? model.note(rows: recentRows, now: now, primary: primary, budget: settings.budget)
            : nil

        // Not a `List`: a list snaps a row to its new height, and the carousel's height has
        // to ease with the list below it (it leapt and wobbled, measured frame by frame).
        ScrollView {
            // The top (hero, carousel, filters) is not lazy: it is a handful of views, and a lazy
            // one dropped them when scrolled far, taking the carousel's page and the entrance with
            // it. Only the days below are lazy.
            VStack(alignment: .leading, spacing: Theme.Space.none) {
                HomeHeader(
                    month: month, searchCount: search?.count, storeIsEmpty: storeIsEmpty,
                    viewed: viewed, now: now, isCurrent: isCurrent, currency: primary, note: note,
                    selectedDay: selectedDay, selectedCategory: selectedCategory,
                    // Each page keeps its own height: with the bar out of the carousel, «En qué
                    // se va» is much shorter than the calendar and matching them left a hole
                    // under it (2026-10-29).
                    equalHeights: false,
                    showsCapture: isCurrent && (!settings.ignoresWallet || unread != nil),
                    health: CaptureHealth(lastCapture: lastCapture, now: now), unread: unread,
                    backupWarning: isCurrent ? settings.backupWarning : nil,
                    entrance: entrance, model: model, actions: actions
                )
                HomeLedger(groups: search?.groups ?? month.groups, primaryCurrency: primary, now: now,
                           catalog: catalog, model: model, actions: actions)
            }
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
            .environment(\.listWidth, listWidth)
            // A tap anywhere else lets the picked day or category go, its card with it (owner,
            // 2026-10-30). Rows, bars and buttons take their own taps first.
            .contentShape(Rectangle())
            .onTapGesture {
                if selectedDay != nil { actions.clearDay() }
                if selectedCategory != nil { actions.clearCategory() }
            }
        }
        // A warning the moment the budget is blown.
        .sensoryFeedback(.warning, trigger: isCurrent && (month.pace?.remaining ?? 0) < 0) { old, new in
            !old && new
        }
        .onChange(of: searching) { _, isOn in if !isOn { model.searchClosed() } }
    }
}

/// The top of the ticket: the hero, the overspend plan, the carousel, the Wallet line and the
/// filter in use; or, while searching, how many it found.
private struct HomeHeader: View {
    let month: HomeMonth
    /// How many the search found; `nil` when not searching.
    let searchCount: Int?
    let storeIsEmpty: Bool
    let viewed: Date
    let now: Date
    let isCurrent: Bool
    let currency: String
    let note: String?
    let selectedDay: Int?
    let selectedCategory: CategoryShare?
    let equalHeights: Bool
    let showsCapture: Bool
    let health: CaptureHealth
    let unread: String?
    let backupWarning: String?
    let entrance: Entrance
    let model: HomeModel
    let actions: HomeActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A sideways swipe anywhere at the top of the screen (the figure, the boleto, its line, the
    /// calendar, the Wallet line): the calendar (to the left) or back (owner, 2026-10-30, a third
    /// time: hard to hit). UIKit's sideways pan, alongside the carousel's own scroll and the
    /// buttons under it; up and down is still the screen's scroll.
    /// The pages follow the finger and glide on when it lets go (`CarouselMotion`).
    private var pageSwipe: SidewaysPan {
        SidewaysPan(ratio: Theme.Size.pageSwipeRatio, alongside: true, holdsScroll: true, changed: { dx in
            // Holding the boleto and sliding reads its days: not a page turn.
            if model.scrubbing { model.swipeBlocked = true }
            guard !model.swipeBlocked else { return }
            model.carousel.drag = dx
        }) { dx, velocity in
            defer { model.swipeBlocked = false }
            guard !model.swipeBlocked, !model.scrubbing else {
                model.carousel.go(to: model.carousel.page, reduceMotion: reduceMotion)
                return
            }
            model.carousel.release(dx, velocity: velocity, reduceMotion: reduceMotion)
        }
    }

    /// "$846": whole money in the month's currency, for the barcode's figures.
    private func wholeMoney(_ amount: Decimal) -> String {
        let total = month.summary.primary
        if let iso = total.isoCode {
            return amount.formatted(currencyStyle(iso).precision(.fractionLength(0)))
        }
        return total.label + amount.formatted(.number.precision(.fractionLength(0)))
    }

    var body: some View {
        let summary = month.summary
        let pace = month.pace
        // Inside a stack with no spacing, as the lines were before: the layout is the same.
        VStack(alignment: .leading, spacing: Theme.Space.none) {
            if let searchCount {
                SearchHeaderRow(count: searchCount) { model.searchText = $0 }
                    .ticketRow(bottom: Theme.Space.s)
            } else if !(storeIsEmpty && pace == nil) {
                // With nothing spent and no budget, a giant «$0.00» says nothing: the empty
                // ticket below asks for the first step instead.
                // The ticket's head: the date, and the folio on the same line (owner, 2026-10-29).
                // A section's distance from what follows: the head is the ticket's, not the figure's.
                ReceiptHead(date: isCurrent ? now : viewed, isCurrent: isCurrent, payments: month.code.payments)
                    .ticketRow(bottom: Theme.Space.xxl)
                HeroTotal(summary: summary, viewed: viewed, now: now, isCurrentMonth: isCurrent,
                          pace: pace, entrance: entrance)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The boleto follows close (owner, 2026-10-30: «mira el espacio»); the carousel adds
                    // its own room to swipe on.
                    .ticketRow(bottom: Theme.Space.s)

                if let code = month.currencySwitch {
                    CurrencySuggestionRow(code: code) { actions.setPrimary(code) }
                        .ticketRow(bottom: Theme.Space.xl)
                }
            }
            if storeIsEmpty {
                // A budget with nothing spent yet still has its days to show.
                if let pace {
                    BudgetPage(spent: summary.primary, pace: pace, isCurrentMonth: isCurrent,
                               entrance: entrance, onSetBudget: actions.setBudget)
                        .ticketRow(bottom: Theme.Space.xl)
                }
                EmptyTicket(hasBudget: pace != nil, onAdd: actions.add,
                            onBudget: actions.setBudget, onSetup: actions.setup)
                    .ticketRow()
            } else if searchCount == nil {
                // Under the figure, the carousel in every view (owner, 2026-10-30): on the left the
                // boleto with its line right under it («Llevas $X de $Y · $Z/día», «Ver cuenta»)
                // and «En qué se va» in Lista or Mosaico; on the right only the calendar.
                MonthCarousel(
                    calendarModel: month.calendar,
                    selectedDay: selectedDay,
                    onSelectDay: actions.selectDay,
                    spent: summary.primary,
                    pace: pace,
                    isCurrentMonth: isCurrent,
                    outside: summary.outside,
                    shares: month.shares,
                    returned: month.returned,
                    note: note,
                    selectedCategory: selectedCategory,
                    onSelectCategory: actions.selectCategory,
                    entrance: entrance,
                    equalHeights: equalHeights,
                    onSetBudget: actions.setBudget,
                    currency: currency,
                    budgetHeader: AnyView(VStack(alignment: .leading, spacing: Theme.Space.s) {
                        MonthCodeView(code: month.code, selectedDay: selectedDay, onSelectDay: actions.selectDay,
                                      onScrubbing: { model.scrubbing = $0 }, wholeMoney: wholeMoney,
                                      month: viewed, entrance: entrance)
                        BudgetPage(spent: summary.primary, pace: pace, isCurrentMonth: isCurrent,
                                   outside: summary.outside, entrance: entrance, onSetBudget: actions.setBudget,
                                   currency: currency, now: now, part: .top, showsTrack: false,
                                   averagePerDay: month.code.averagePerDay)
                    }),
                    now: now,
                    motion: model.carousel
                )
                // Edge to edge: each page keeps its own margin, so a swipe shows a gap
                // between them instead of two pages touching.
                .ticketRow(bottom: isCurrent ? Theme.Space.none : Theme.Space.xl, horizontal: Theme.Space.none)

                // The Wallet line stays between the carousel and the list, not under «Hoy»:
                // it is about the capture, not about today's expenses (owner, 2026-10-21).
                if showsCapture {
                    CaptureHealthRow(health: health, unread: unread, openGuide: actions.openGuideFromWarning)
                        .ticketRow()
                }
                if let backupWarning {
                    BackupWarningRow(text: backupWarning, open: actions.openSettings)
                        .ticketRow()
                }

                if let day = selectedDay {
                    FilterRow(title: "Día \(day)", count: month.shownCount, total: month.shownTotal,
                              clear: actions.clearDay)
                        .ticketRow()
                }
                if let line = selectedCategory {
                    FilterRow(title: line.isRest ? "Otras" : line.category ?? "Sin categoría",
                              count: month.shownCount, total: month.shownTotal, clear: actions.clearCategory)
                        .ticketRow()
                }
                if !month.hasExpenses {
                    Text("Sin gastos este mes")
                        .font(.ticket(.footnote))
                        .tracking(Theme.Tracking.action)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.tallRow, alignment: .leading)
                        .overlay(alignment: .top) { Perforation() }
                        .ticketRow()
                }
            }
        }
        // The whole top of the screen turns the carousel's page with a sideways swipe.
        .contentShape(Rectangle())
        .gesture(pageSwipe)
    }
}

/// The days below: the month's (or the search's) expenses, day by day. Lazy: only the rows on
/// screen are built.
private struct HomeLedger: View {
    let groups: [DayGroup]
    let primaryCurrency: String
    let now: Date
    let catalog: CategoryCatalog
    let model: HomeModel
    let actions: HomeActions

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Space.none) {
            ForEach(groups) { group in
                // A thin brass line where a new day starts: «Hoy · 19 oct», «Ayer», «vie 17 oct».
                DayDivider(group: group, primaryCurrency: primaryCurrency, now: now)
                    .ticketRow()
                ForEach(group.items) { expense in
                    // The divider already draws the line above a day's first row.
                    LedgerRow(expense: expense, primaryCurrency: primaryCurrency, catalog: catalog,
                              perforated: expense.id != group.items.first?.id)
                        // A tap, not a Button: a button also fires when a swipe lets go
                        // on it, and a tap gives up as soon as the finger moves. While
                        // a row is open, a tap on another only closes it, as in a list.
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if model.openRow != nil { model.openRow = nil } else { actions.edit(expense) }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .ticketRow()
                    .swipeToDelete(id: expense.persistentModelID, openRow: Bindable(model).openRow) {
                        actions.askDelete(expense)
                    }
                    .contextMenu {
                        // One touch, without opening the sheet. The first time it is
                        // «Me lo reembolsan»; after that, the reason it had before.
                        if expense.maybeRepeated == true {
                            Button("No es repetida", systemImage: "checkmark.circle") {
                                actions.change(expense) { $0.maybeRepeated = nil }
                            }
                        }
                        if expense.isUncounted {
                            Button("Sí cuenta", systemImage: "checkmark.circle") {
                                actions.change(expense) { $0.markCounted() }
                            }
                        } else {
                            Button("No cuenta", systemImage: "nosign") {
                                actions.change(expense) { $0.markUncounted($0.reason ?? .reimbursed) }
                            }
                        }
                        Menu {
                            ForEach(catalog.choices(for: expense), id: \.self) { name in
                                Button {
                                    actions.setCategory(name, expense)
                                } label: {
                                    if expense.category == name {
                                        Label(name, systemImage: "checkmark")
                                    } else {
                                        Text(name)
                                    }
                                }
                            }
                        } label: {
                            Label("Categoría", systemImage: "tag")
                        }
                        Button("Anotar otra vez", systemImage: "arrow.counterclockwise") {
                            actions.logAgain(expense)
                        }
                        Button("Borrar gasto", systemImage: "trash", role: .destructive) {
                            actions.askDelete(expense)
                        }
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
        // With large text the button goes under the sentence instead of squeezing it.
        AdaptiveStack(spacing: Theme.Space.m, stackedSpacing: Theme.Space.s) {
            NoteText("Casi todos tus pagos de este mes son en \(CurrencyPreference.spoken(code)).")
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: apply) {
                Text("Sumar en \(CurrencyPreference.spoken(code))")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
                .font(.ticket(.label))
                .foregroundStyle(Theme.onBrass)
                .ticketProminent()
                .frame(minHeight: Theme.Size.tapTarget)
                .accessibilityIdentifier("sumar-en-moneda")
        }
        .padding(.horizontal, Theme.Space.ml)
        .padding(.vertical, Theme.Space.xs)
        .ticketOutline()
    }
}

/// «Pagos y categorías», and pushing what changes there to iCloud like the budget.
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
///
/// The words reach the list (`settle`) once typing pauses (`HomeModel.searchPause`), so a
/// search over every month runs once per word and not once per letter; clearing it is at once.
/// Each letter redraws only this modifier, not the screen.
private struct BottomSearch: ViewModifier {
    @Binding var text: String
    let settle: (String) -> Void
    private let prompt = "Comercio, mes o monto…"

    func body(content: Content) -> some View {
        searchable(content)
            .task(id: text) {
                let typed = text
                if !typed.trimmingCharacters(in: .whitespaces).isEmpty {
                    try? await Task.sleep(for: HomeModel.searchPause)
                    guard !Task.isCancelled else { return }
                }
                settle(typed)
            }
    }

    @ViewBuilder private func searchable(_ content: Content) -> some View {
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

/// A soft tap when an expense lands. (The warning the moment the budget is blown is in
/// `HomeContent`, which works the budget out.)
private struct Feedback: ViewModifier {
    let expenseCount: Int
    /// The latest expense's date. Only one dated just now is a payment that just landed;
    /// an import, an undo, a fixed expense's copy or one arriving from iCloud is older.
    let newest: Date?

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.success, trigger: expenseCount) { old, new in
                // From 0 is the first count at launch, not a payment landing now.
                old > 0 && new > old && (newest.map { Date.now.timeIntervalSince($0) < 120 } ?? false)
            }
    }
}

/// The backup's line in «Hoy» (`DailyBackup.warning`), read again as time passes and when
/// Ajustes closes. Pulled out of `body`: the CI's compiler gave up type-checking it all.
private struct BackupWatch: ViewModifier {
    @Binding var warning: String?
    let now: Date
    let settingsShown: Bool

    func body(content: Content) -> some View {
        content
            .task(id: now) { warning = DailyBackup.warning(now: now) }
            .onChange(of: settingsShown) { _, shown in if !shown { warning = DailyBackup.warning() } }
    }
}

/// A change made in «Hoy» that couldn't be saved, said out loud.
private struct SaveProblemAlert: ViewModifier {
    @Binding var problem: String?

    func body(content: Content) -> some View {
        content.alert("No se guardó", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text(problem ?? "") }
    }
}

/// Counts the expenses again whenever the store saves, a payment lands or the oldest one goes:
/// a count asked of the store, instead of every expense loaded to count them.
private struct CountsStore: ViewModifier {
    let newest: PersistentIdentifier?
    let oldest: PersistentIdentifier?
    let recount: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in recount() }
            // What iCloud brought in the background (it doesn't post `didSave` here).
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in recount() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { recount() } }
            .onChange(of: newest, initial: true) { recount() }
            .onChange(of: oldest) { recount() }
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
                // A budget or a fixed expense changed in «Más» also changes the widgets.
                if phase == .background { WidgetBridge.refresh() }
            }
            .task(id: now) {
                // Captures from before «$» was saved as its currency, pinned once (2026-11-02).
                try? ExpenseRecorder.pinBareDollars(in: context)
                try? RecurringExpenses.logDue(in: context, now: now)
                try? ExpenseRecorder.repairBankMerchants(in: context)
                WidgetBridge.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.significantTimeChangeNotification)) { _ in
                now = .now
            }
    }
}

private extension ExpenseListView {
    // Pulled out of `body`: the CI's compiler gave up type-checking it all in one expression.
    /// Every change made here is saved right then, not left to autosave; if it fails, it's said.
    @discardableResult
    func persist() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            saveProblem = "Al día no pudo guardar el cambio. Intenta otra vez; si sigue, cierra la app y vuelve a abrirla."
            return false
        }
    }

    var importAlertShown: Binding<Bool> {
        Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
    }

    /// The unread notice, if it came after the last payment the capture saved and less than
    /// two days ago: it goes once a payment comes in right, once tapped, or on its own.
    func unreadNotice(after lastCapture: Date?) -> String? {
        guard !unreadText.isEmpty else { return nil }
        let date = Date(timeIntervalSinceReferenceDate: unreadDate)
        guard now.timeIntervalSince(date) < 2 * 24 * 3600 else { return nil }
        return lastCapture.map { date > $0 } ?? true ? unreadText : nil
    }

    /// Debug only: screenshots of a sheet, `-centavo-abrir catalogos|fijos|ajustes|anotar|tutorial`.
    private func openRequestedSheet() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-centavo-abrir"), at + 1 < args.count else { return }
        switch args[at + 1] {
        case "catalogos": showingCatalogs = true
        case "fijos": showingFixed = true
        case "ajustes": showingSettings = true
        case "anotar": adding = true
        case "presupuesto": showingBudget = true
        case "tutorial": showingTutorial = true
        default: break
        }
        #endif
    }

    private func openAfterOnboarding() {
        let exit = afterOnboarding
        afterOnboarding = nil
        switch exit {
        case .guide: showingSetup = true
        case .tutorial: showingTutorial = true
        case .home, nil: break
        }
    }

    /// «Pruébalo» in «Cómo funciona»: what it asked for, once the stories are gone.
    private func openAfterTutorial() {
        guard let destination = afterTutorial else { return }
        afterTutorial = nil
        switch destination {
        case .budget: showingBudget = true
        case .guide: showingSetup = true
        case .settings: showingSettings = true
        }
    }

    /// Closes «Ajustes», then does what was asked from it: two sheets can't be up at once.
    private func afterSettings(_ action: @escaping () -> Void) {
        showingSettings = false
        Task { try? await Task.sleep(for: .milliseconds(450)); action() }
    }

    /// A category picked from the long press: a choice, remembered for the place, as in the sheet.
    private func setCategory(_ name: String, of expense: Expense) {
        let picked = expense.category == name ? nil : name
        expense.categorySource = picked == nil ? Expense.clearedCategory : nil
        expense.category = picked
        UserCatalog.learnCategory(picked, for: expense.merchant)
        persist()
    }

    /// The same expense again, now: the coffee of every morning without opening the sheet.
    private func logAgain(_ expense: Expense) {
        let copy = Expense(amount: expense.amount, currencyMarker: expense.currencyMarker,
                           merchant: expense.merchant, card: expense.card, date: .now,
                           category: expense.category)
        copy.displayName = expense.displayName
        context.insert(copy)
        persist()
    }

    @ViewBuilder var undoOverlay: some View {
        if let deleted = lastDeleted {
            UndoBar(text: "Borraste \(deleted.displayName ?? deleted.merchant)") { restore(deleted) }
                .padding(.horizontal, Theme.Space.screen)
                // Right above the bottom bar: the safe area already ends at the bar.
                .padding(.bottom, Theme.Space.m)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: deleted.id) {
                    // Said out loud, and with VoiceOver it stays long enough to reach it.
                    AccessibilityNotification.Announcement(
                        "Borraste \(deleted.displayName ?? deleted.merchant). Puedes deshacerlo.").post()
                    try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning
                                                        ? Theme.Motion.undoLongSeconds
                                                        : Theme.Motion.undoSeconds))
                    withAnimation { if lastDeleted?.id == deleted.id { lastDeleted = nil } }
                }
        }
    }

    func delete(_ expense: Expense) {
        let snapshot = DeletedExpense(expense)
        context.delete(expense)
        guard persist() else { return }
        countStore()
        // A search on screen is asked again, without the deleted expense.
        model.storeSaved()
        withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) { lastDeleted = snapshot }
    }

    func restore(_ deleted: DeletedExpense) {
        guard let expense = deleted.make() else { return }
        context.insert(expense)
        guard persist() else { return }
        model.storeSaved()
        countStore()
        withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) { lastDeleted = nil }
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
            // «Mi dinero»'s file has its own place (2026-11-01).
            if MoneyImport.parse(text, main: primaryCurrency).refusal == nil {
                return "Este archivo es de «Mi dinero», no de tus gastos: cárgalo en esa pestaña."
            }
            return "Ese archivo no es un CSV exportado de Al día (le falta el encabezado Fecha, Comercio, Monto, Moneda)."
        } catch {
            return "No se pudo guardar lo importado. Intenta de nuevo."
        }
    }
}

extension EnvironmentValues {
    /// The main list's width, measured, for what has to be exactly as wide (see `listWidth`).
    @Entry var listWidth: CGFloat?
}

private extension View {
    /// A line of the ticket: the side margins and the space under it.
    func ticketRow(bottom: CGFloat = 0, horizontal: CGFloat = Theme.Space.screen) -> some View {
        modifier(TicketRow(bottom: bottom, horizontal: horizontal))
    }
}

private struct TicketRow: ViewModifier {
    let bottom: CGFloat
    let horizontal: CGFloat
    @Environment(\.listWidth) private var listWidth

    /// Exactly the screen's width less the margins, as a list row was: a long name can't widen
    /// the line past the screen.
    private var width: CGFloat? {
        listWidth.map { max($0 - horizontal - horizontal, Theme.Space.none) }
    }

    func body(content: Content) -> some View {
        content
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, horizontal)
            .padding(.bottom, bottom)
    }
}

// MARK: - Pieces

/// The ticket's head over a perforation: «JUE 29 DE OCT» this month («SEP 2026» for another),
/// and at the other end «N.º 042», the month's payments, like the number printed on a ticket.
private struct ReceiptHead: View {
    let date: Date
    let isCurrent: Bool
    let payments: Int

    private var title: String {
        let style: Date.FormatStyle = isCurrent ? .dateTime.weekday(.abbreviated).day().month(.abbreviated)
            : .dateTime.month(.abbreviated).year()
        return date.formatted(style.locale(Locale(identifier: "es_MX"))).replacingOccurrences(of: ".", with: "")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.s)
            if payments > 0 {
                Text("N.º \(Text(String(format: "%03d", payments)).foregroundStyle(Theme.brass))")
                    .monospacedDigit()
                    .accessibilityLabel(payments == 1 ? "1 pago este mes" : "\(payments) pagos este mes")
                    .accessibilityIdentifier("folio")
            }
        }
        .font(.ticket(.microStrong))
        .tracking(Theme.Tracking.label)
        .textCase(.uppercase)
        .foregroundStyle(Theme.ink)
        .lineLimit(1)
        .padding(.bottom, Theme.Space.s)
        .overlay(alignment: .bottom) { Perforation() }
    }
}

private struct HeroTotal: View {
    let summary: MonthSummary
    let viewed: Date
    let now: Date
    let isCurrentMonth: Bool
    let pace: BudgetPace?
    /// Remembers the count-up, so it plays when the app opens and not when the row is rebuilt.
    let entrance: Entrance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(summary: MonthSummary, viewed: Date, now: Date, isCurrentMonth: Bool, pace: BudgetPace?,
         entrance: Entrance) {
        self.summary = summary
        self.viewed = viewed
        self.now = now
        self.isCurrentMonth = isCurrentMonth
        self.pace = pace
        self.entrance = entrance
        _counted = State(initialValue: entrance.heroFigure)
    }

    /// This month, with a budget not yet blown, the figure to decide by is what can still go
    /// today; the month's total becomes the line under it.
    private var allowance: Decimal? {
        guard isCurrentMonth, let pace, pace.remaining >= 0, !pace.isFixedOverBudget else { return nil }
        return pace.dailyAllowance
    }

    /// This month, within the budget, with fixed expenses that take all of it (second audit,
    /// 2026-11-02): by how much they pass it. Not «te pasaste»: nothing was overspent.
    private var fixedExcess: Decimal? {
        guard isCurrentMonth, let pace, pace.remaining >= 0 else { return nil }
        return pace.fixedOverBudgetShown
    }

    @State private var counted: Double = 0

    /// This month, past the budget: how far past it (the hero's figure then).
    private var overage: Decimal? {
        guard isCurrentMonth, let pace, pace.remaining < 0 else { return nil }
        // Rounded up, like «Para cerrar el mes»: never «$0» over a few centavos.
        return pace.overBudgetShown
    }

    private func wholeText(_ amount: Decimal) -> String {
        if let iso = summary.primary.isoCode {
            return amount.formatted(currencyStyle(iso).precision(.fractionLength(0)))
        }
        return summary.primary.label + amount.formatted(.number.precision(.fractionLength(0)))
    }

    /// Today already went past its share: the figure says by how much, in red.
    private var isOverToday: Bool { (allowance ?? 0) < 0 }

    private var allowanceValue: Double { NSDecimalNumber(decimal: (allowance ?? 0).magnitude).doubleValue }

    /// The figure on its way up: whole money, like the final one.
    private var countedText: String {
        let amount = Decimal(counted.rounded(.down))
        if let iso = summary.primary.isoCode {
            return amount.formatted(currencyStyle(iso).precision(.fractionLength(0)))
        }
        return summary.primary.label + amount.formatted(.number.precision(.fractionLength(0)))
    }

    private var allowanceText: String {
        let amount = (allowance ?? 0).magnitude
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
                + viewed.formatted(.dateTime.month(.abbreviated).year().locale(ExpenseListView.mexico))
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
        // The caption and the figure are one group, closer to each other than the sections are,
        // with a breath between them (owner, 2026-10-30).
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if allowance != nil {
                Text(isOverToday ? "Hoy te pasaste" : "Hoy puedes gastar")
                    // Read with the figure, as one sentence.
                    .accessibilityHidden(true)
                    // Grey like every other caption, so the brass figure under it leads.
                    .ticketCaption(strong: true)
                // Counts up from zero when the screen opens, and rolls to the new figure after
                // every payment.
                Text(countedText)
                    .accessibilityIdentifier("hoy-puedes-gastar")
                    .accessibilityLabel((isOverToday ? "Hoy te pasaste " : "Hoy puedes gastar ") + allowanceText)
                    .font(.ticket(.hero))
                    .tracking(Theme.Tracking.hero)
                    .foregroundStyle(isOverToday ? Theme.danger : Theme.brass)
                    // The «$» carries its own air on the left (3 pt at this size, measured): pulled
                    // back so the figure lines up with «Hoy puedes gastar» above it.
                    .padding(.leading, Theme.Space.outset)
                    .padding(.vertical, Theme.Space.heroTrim)
                    .lineLimit(1)
                    .minimumScaleFactor(Theme.MinimumScale.figure)
                    .contentTransition(.numericText(value: counted))
                    .onAppear {
                        // Starts from where it last counted to: a rebuilt row is already there.
                        defer { entrance.heroFigure = allowanceValue }
                        guard !reduceMotion else { counted = allowanceValue; return }
                        withAnimation(Theme.Motion.countUp) { counted = allowanceValue }
                    }
                    .onChange(of: allowanceValue) { _, value in
                        entrance.heroFigure = value
                        withAnimation(reduceMotion ? nil : Theme.Motion.quick) { counted = value }
                    }

            } else if let fixedExcess {
                FixedOverBudgetHero(excess: fixedExcess, text: wholeText(fixedExcess))
            } else if let overage {
                // The month went past its budget: the figure that matters now is by how much.
                Text("Te pasaste del presupuesto")
                    .ticketCaption(strong: true)
                Text(wholeText(overage))
                    .accessibilityIdentifier("te-pasaste")
                    .font(.ticket(.hero))
                    .tracking(Theme.Tracking.hero)
                    .foregroundStyle(Theme.danger)
                    .padding(.leading, Theme.Space.outset)
                    .padding(.vertical, Theme.Space.heroTrim)
                    .lineLimit(1)
                    .minimumScaleFactor(Theme.MinimumScale.figure)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : Theme.Motion.quick, value: overage)
            } else {
                Text(verbatim: caption).ticketCaption(strong: true)
                Text(totalText)
                    .accessibilityIdentifier("total-mes")
                    .font(.ticket(.hero))
                    .tracking(Theme.Tracking.hero)
                    .foregroundStyle(Theme.ink)
                    .padding(.vertical, Theme.Space.heroTrim)
                    .lineLimit(1)
                    .minimumScaleFactor(Theme.MinimumScale.figure)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : Theme.Motion.quick, value: summary.primary.amount)
            }
            // Adding currencies together would be a lie, so they ride along separately, under the
            // month's total; with «Hoy puedes gastar» on top they would only crowd it (each one
            // still shows in its own row of the list).
            if allowance == nil, fixedExcess == nil, !summary.others.isEmpty {
                // «aparte» said nothing on a first look (user research, 2026-10-29).
                Text(verbatim: "+ \(othersText) en \(summary.others.count > 1 ? "otras monedas" : "otra moneda")")
                    .accessibilityIdentifier("otras-monedas")
                    .font(.ticket(.footnote))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// «Tus fijos pasan el presupuesto por $3,000» (second audit, 2026-11-02): the fixed expenses
/// take the whole budget, so there is no «Hoy puedes gastar». Brass, not red: nothing was
/// overspent; the budget or the fixed expenses need a look.
private struct FixedOverBudgetHero: View {
    let excess: Decimal
    let text: String

    var body: some View {
        if excess > 0 {
            Text("Tus fijos pasan el presupuesto por")
                .accessibilityHidden(true)
                .ticketCaption(strong: true)
            Text(text)
                .accessibilityIdentifier("fijos-pasan")
                .accessibilityLabel("Tus fijos pasan el presupuesto por " + text)
                .font(.ticket(.hero))
                .tracking(Theme.Tracking.hero)
                .foregroundStyle(Theme.brass)
                .padding(.leading, Theme.Space.outset)
                .padding(.vertical, Theme.Space.heroTrim)
                .lineLimit(1)
                .minimumScaleFactor(Theme.MinimumScale.figure)
        } else {
            Text("Hoy puedes gastar")
                .accessibilityHidden(true)
                .ticketCaption(strong: true)
            Text(text)
                .accessibilityIdentifier("fijos-pasan")
                .accessibilityLabel("Tus fijos se llevan todo el presupuesto")
                .font(.ticket(.hero))
                .tracking(Theme.Tracking.hero)
                .foregroundStyle(Theme.brass)
                .padding(.leading, Theme.Space.outset)
                .padding(.vertical, Theme.Space.heroTrim)
                .lineLimit(1)
                .minimumScaleFactor(Theme.MinimumScale.figure)
            Text("Tus fijos se llevan todo el presupuesto")
                .font(.ticket(.detail))
                .foregroundStyle(Theme.muted)
        }
    }
}

/// The first screen with nothing in it (redone 2026-11-01): one clear first step (write an
/// expense down), and the two that make the app work by itself, each with its drawing. It plays
/// once when it appears — the ghost row prints, then the budget card, then Wallet's — and stays
/// still, so it never outshines «Anotar un gasto». With a budget set, the boleto is already above
/// and only Wallet's card stays.
private struct EmptyTicket: View {
    let hasBudget: Bool
    let onAdd: () -> Void
    let onBudget: () -> Void
    let onSetup: () -> Void

    private typealias Empty = Theme.Motion.Money.Empty

    var body: some View {
        // Only what moves follows the clock: the text and the button are drawn once.
        VStack(alignment: .leading, spacing: Theme.Space.ml) {
            Text("Tu mes empieza aquí")
                .font(.ticket(.bodyStrong))
                .tracking(Theme.Tracking.caption)
                .textCase(.uppercase)
            if !hasBudget { monthStrip }
            PlayOnceClock(until: Empty.end) { t in
                ghostRow(moneySpan(t, Empty.ghost.lowerBound, Empty.ghost.upperBound))
            }
            Text("Anota uno o conecta Wallet y cada compra se anotará sola.")
                .font(.ticket(.callout))
                .lineSpacing(Theme.Space.xxs)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onAdd) {
                PrimaryButtonLabel("Anotar un gasto", systemImage: "plus")
            }
            .ticketProminent()
            .accessibilityIdentifier("vacio-anotar")
            .padding(.top, Theme.Space.xs)
            PlayOnceClock(until: Empty.end) { t in steps(t) }
        }
        .padding(Theme.Space.xlx)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ticketOutline(.emphasis)
    }

    /// The month's days, empty and dashed; today outlined, breathing a few times, then at rest.
    private var monthStrip: some View {
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: .now)?.count ?? 30
        let today = calendar.component(.day, from: .now)
        return HStack(spacing: Theme.Size.monthBarCellGap) {
            ForEach(1...days, id: \.self) { day in
                RoundedRectangle(cornerRadius: Theme.Radius.bar)
                    .strokeBorder(day == today ? Theme.ink : Theme.hairline,
                                  style: StrokeStyle(lineWidth: day == today ? Theme.Stroke.emphasis : Theme.Stroke.hairline,
                                                     dash: day == today ? [] : Theme.Dash.dotted))
                    // Each breath fades down and back up, so the last one ends at rest.
                    .breathes(day == today, times: Empty.breaths, seconds: Empty.breathSeconds,
                              low: Theme.Opacity.unselected)
            }
        }
        .frame(height: Theme.Size.emptyStrip)
        .accessibilityHidden(true)
    }

    /// Where the first expense will land: printed once, then faint.
    private func ghostRow(_ shown: Double) -> some View {
        let lift = Theme.Size.entranceRise * CGFloat(1 - shown)
        return HStack(spacing: Theme.Space.m) {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .strokeBorder(Theme.outline, style: StrokeStyle(lineWidth: Theme.Stroke.hairline, dash: Theme.Dash.dotted))
                .frame(width: Theme.Size.rowTile, height: Theme.Size.rowTile)
            Text("Tu primer gasto")
                .font(.ticket(.bodyMedium))
                .tracking(Theme.Tracking.name)
                .textCase(.uppercase)
            Spacer(minLength: Theme.Space.s)
            Text("$0.00").font(.ticket(.body)).monospacedDigit()
        }
        .foregroundStyle(Theme.faint)
        .padding(.top, Theme.Space.s)
        .overlay(alignment: .top) { Perforation() }
        .opacity(Theme.Opacity.paceBehind * shown)
        .offset(y: -lift)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func steps(_ t: Double) -> some View {
        let wallet = moneySpan(t, Empty.wallet.lowerBound, Empty.wallet.upperBound)
        if hasBudget {
            EmptyStepCard(kind: .wallet, title: "Conectar Wallet", detail: "Cada pago con Apple Pay se anota solo.",
                          progress: wallet, wide: true, identifier: "vacio-wallet", action: onSetup)
        } else {
            let budget = moneySpan(t, Empty.budget.lowerBound, Empty.budget.upperBound)
            // Side by side when they fit; one under the other on a narrow phone or large text.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    budgetCard(budget, wide: false)
                    walletCard(wallet, wide: false)
                }
                VStack(spacing: Theme.Space.s) {
                    budgetCard(budget, wide: true)
                    walletCard(wallet, wide: true)
                }
            }
        }
    }

    private func budgetCard(_ progress: Double, wide: Bool) -> some View {
        EmptyStepCard(kind: .budget, title: "Fijar presupuesto", detail: "Para saber cuánto puedes gastar al día.",
                      progress: progress, wide: wide, identifier: "vacio-presupuesto", action: onBudget)
    }

    private func walletCard(_ progress: Double, wide: Bool) -> some View {
        EmptyStepCard(kind: .wallet, title: "Conectar Wallet", detail: "Cada pago con Apple Pay se anota solo.",
                      progress: progress, wide: wide, identifier: "vacio-wallet", action: onSetup)
    }
}

/// One of the empty screen's two steps: its drawing, its name and what it's for.
private struct EmptyStepCard: View {
    let kind: EmptyStepArt.Kind
    let title: String
    let detail: String
    let progress: Double
    let wide: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let layout = wide ? AnyLayout(HStackLayout(spacing: Theme.Space.m))
                              : AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.xs))
            layout {
                EmptyStepArt(kind: kind, progress: progress)
                    .frame(width: wide ? Theme.Size.moneyExcelArt : nil, height: Theme.Size.emptyStepArt)
                    .frame(maxWidth: wide ? nil : .infinity)
                    .background(Theme.ink.opacity(Theme.Opacity.moneyArtWash), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    Text(title).font(.ticket(.bodyStrong)).foregroundStyle(Theme.brass)
                    Text(detail).font(.ticket(.hint)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if wide { Spacer(minLength: Theme.Space.none) }
            }
            .padding(Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.hairline, lineWidth: Theme.Stroke.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct LedgerRow: View {
    let expense: Expense
    let primaryCurrency: String
    /// The categories' icons, read once for the whole list instead of once per row.
    let catalog: CategoryCatalog
    /// The dashed line on top; a day's first row has the divider there instead.
    var perforated = true

    private var isRefund: Bool { expense.amount < 0 }
    /// Grey and struck through, never brass: brass already means money that came back.
    private var isUncounted: Bool { expense.isUncounted }

    /// The category's icon on a small tile, the same icons as «En qué se va»: in the
    /// category's own color, grey when it has none or does not count.
    private var categoryTile: CategoryIconTile {
        let category = expense.category.flatMap { $0.isEmpty ? nil : $0 }
        return CategoryIconTile(icon: category.map(catalog.icon(for:)) ?? "questionmark",
                                color: category.flatMap { isUncounted ? nil : catalog.colors.category($0) })
    }

    /// «No cuenta» goes first, so the line says it and not only the strike; why it doesn't
    /// count is in the expense sheet (the list keeps one short line, owner 2026-10-29).
    /// VoiceOver hears the reason too, and «no cuenta para el presupuesto» with the amount.
    private func meta(spoken: Bool = false, withCard: Bool = true) -> String? {
        // A Wallet payment identical to one minutes before says so first (2026-11-02).
        let parts = [expense.maybeRepeated == true ? (spoken ? "¿repetida? Igual a otro pago de hace unos minutos" : "¿Repetida?") : nil,
                     isUncounted && !spoken ? "No cuenta" : nil, isUncounted && spoken ? expense.reason?.title : nil,
                     isRefund ? "Devolución" : nil, expense.isFixed ? "Fijo" : nil,
                     expense.category, withCard ? expense.card : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        // A no-break space before the dot: a wrapped line never starts with «·».
        return parts.isEmpty ? nil : parts.joined(separator: "\u{00A0}· ")
    }

    private var card: String? { expense.card.flatMap { $0.isEmpty ? nil : $0 } }

    /// The line under the name, the way of paying last as its own icon (a little card, filled)
    /// in its own color, and brass dots between the parts, like the rest of the ticket. The
    /// icon replaced the short name («Amex») at the owner's request (2026-10-31); VoiceOver
    /// still reads the name.
    private var metaLine: Text? {
        var parts = (meta(withCard: false)?.components(separatedBy: "\u{00A0}· ") ?? []).map { part in
            // «¿Repetida?» in brass: it asks for a look.
            part == "¿Repetida?" ? Text(part).foregroundStyle(Theme.brass) : Text(part)
        }
        if let card {
            let icon = catalog.sourceIcon(for: card)
            let filled = UIImage(systemName: icon + ".fill") == nil ? icon : icon + ".fill"
            parts.append(Text(Image(systemName: filled))
                .foregroundStyle(isUncounted ? Theme.muted : catalog.colors.source(card)))
        }
        guard let first = parts.first else { return nil }
        // A no-break space before the dot: a wrapped line never starts with «·».
        let dot = Text("\u{00A0}·").foregroundStyle(Theme.brass)
        return parts.dropFirst().reduce(first) { line, part in Text("\(line)\(dot) \(part)") }
    }

    @ViewBuilder private var metaText: some View {
        if let line = metaLine {
            ExpenseMetaText(line)
                .accessibilityLabel(meta(spoken: true) ?? "")
        }
    }

    private var amountText: some View {
        let amount = ledgerAmount(for: expense, primary: primaryCurrency)
        return Text(amount)
            .font(.ticket(.body))
            .strikethrough(isUncounted, color: Theme.muted)
            .foregroundStyle(isUncounted ? Theme.muted : isRefund ? Theme.brass : Theme.ink)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(isUncounted ? "\(amount), no cuenta para el presupuesto" : amount)
    }

    var body: some View {
        ExpenseRowLayout(name: expense.shownName, tile: categoryTile) {
            metaText
        } amount: {
            amountText
        }
        .overlay(alignment: .top) { if perforated { Perforation() } }
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
    return ExpenseListView().modelContainer(container).ticketPreview()
}

/// "Borraste Oxxo · Deshacer", for a few seconds after a delete.
private struct UndoBar: View {
    let text: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text(text)
                .font(.ticket(.detail))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            Button(action: undo) { LinkActionLabel("Deshacer", fillsWidth: false) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("deshacer-borrado")
        }
        .padding(.horizontal, Theme.Space.l)
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
                .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: Theme.Stroke.hairline) }
        }
    }
}

/// «3 gastos», over the results while searching; says so when the words were read as a category.
private struct SearchHeaderRow: View {
    let count: Int
    /// Puts an example in the search field.
    let tryExample: (String) -> Void

    /// What the search understands, one tap each: it reads phrases, not just names.
    private let examples = ["café", "uber de octubre", "más de 500"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(count == 0 ? "Sin resultados" : "\(count) \(count == 1 ? "gasto" : "gastos")")
                .font(.ticket(.label))
                .tracking(Theme.Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(Theme.brass)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
                .accessibilityIdentifier("resultados-busqueda")
            if count == 0 {
                NoteText("Prueba con un comercio, un mes o un monto:")
                HStack(spacing: Theme.Space.s) {
                    ForEach(examples, id: \.self) { example in
                        TicketChip(example) { tryExample(example) }
                    }
                }
            }
        }
    }
}

/// «Día 12 · 2 gastos · Ver todo el mes» (or «Ropa · 2 gastos») over the list while a day
/// or a category is picked.
private struct FilterRow: View {
    let title: String
    let count: Int
    /// What they add up to, «$310»; `nil` with nothing to add.
    var total: String?
    let clear: () -> Void

    var body: some View {
        HStack {
            Text("\(title) · \(count) \(count == 1 ? "gasto" : "gastos")" + (total.map { " · \($0)" } ?? ""))
                .font(.ticket(.label))
                .tracking(Theme.Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(Theme.brass)
            Spacer()
            Button("Ver todo el mes", action: clear)
                .font(.ticket(.detail))
                .foregroundStyle(Theme.muted)
                .frame(minHeight: Theme.Size.tapTarget)
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

    /// Neighbors of the same day go together, in the order given (`DayRuns`: one pass).
    static func split(_ expenses: [Expense], calendar: Calendar = .current) -> [DayGroup] {
        DayRuns.split(expenses, calendar: calendar, date: \.date).map { DayGroup(day: $0.day, items: $0.items) }
    }

    /// What went that day in the month's currency (refunds subtract, what doesn't count adds
    /// nothing); others ride apart.
    func total(in primary: String) -> String? {
        let mine = items.filter { CurrencyResolver.isoCode(for: $0.currencyMarker, primary: primary) == primary }
        // A day only in other money still says how much: «USD 24.99».
        guard !mine.isEmpty else {
            guard let first = items.first else { return nil }
            let code = CurrencyResolver.isoCode(for: first.currencyMarker, primary: primary)
            let same = items.filter { CurrencyResolver.isoCode(for: $0.currencyMarker, primary: primary) == code }
            let sum = same.reduce(Decimal(0)) { $0 + $1.counted }
            let number = sum.magnitude.formatted(.number.precision(.fractionLength(2)))
            let label = String((code ?? first.currencyMarker ?? "").prefix(4))
            return (sum < 0 ? "+" : "") + (label.isEmpty ? number : "\(label) \(number)")
        }
        let sum = mine.reduce(Decimal(0)) { $0 + $1.counted }
        // Money that came back reads like the ledger's refunds: «+$230.00».
        return (sum < 0 ? "+" : "") + formatMoney(sum.magnitude, isoCode: primary, label: primary)
    }
}

/// Where a day starts in the list: a short brass line, the day, a hairline, the day's total.
private struct DayDivider: View {
    let group: DayGroup
    let primaryCurrency: String
    let now: Date

    private var day: Date { group.day }
    /// Worked out here, so an edited amount redraws only its day's divider.
    private var total: String? { group.total(in: primaryCurrency) }

    private var label: String {
        let calendar = Calendar.current
        let date = day.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_MX")))
        if calendar.isDate(day, inSameDayAs: now) { return "Hoy · " + date }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Ayer · " + date }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            .locale(Locale(identifier: "es_MX")))
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var tick: some View {
        Capsule().fill(Theme.brass)
            .frame(width: Theme.Size.dayTick.width, height: Theme.Size.dayTick.height)
    }

    private var dayText: some View {
        Text(label)
            .font(.ticket(.microStrong))
            .tracking(Theme.Tracking.action)
            .textCase(.uppercase)
            .foregroundStyle(Theme.brass)
    }

    @ViewBuilder private var totalText: some View {
        if let total {
            Text(total)
                .font(.ticket(.micro))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
        }
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // With the largest text the day, the rule and the total don't fit on one line and
                // «HOY · 23 OCT» was cut to «HO…»: the day gets its own lines, the total under it.
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        tick
                        dayText.fixedSize(horizontal: false, vertical: true)
                    }
                    totalText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: Theme.Space.s) {
                    tick
                    // The day never gives way: the rule between it and the total shrinks first.
                    dayText.lineLimit(1).layoutPriority(1)
                    Rectangle().fill(Theme.brass.opacity(Theme.Opacity.rule))
                        .frame(height: Theme.Stroke.hairline)
                    // Nor does the total: an amount is never cut (audit 2026-11-02).
                    totalText.lineLimit(1).fixedSize()
                }
            }
        }
        .padding(.top, Theme.Space.ml)
        .padding(.bottom, Theme.Space.xxxs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("divisor-dia")
    }
}
