import CentavoCore
import Combine
import CoreData
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// «Hoy», the first of the app's two tabs (`RootView`): the month's figure, a swipeable
/// boleto/calendar, then that month's payments.
///
/// The look is the approved "Noche ticket" (dark, brass, receipt type). The structure is
/// Apple's: a real navigation bar and bottom bar (Liquid Glass on iOS 26), a `List` with
/// swipe-to-delete, system menus and sheets.
///
/// This view is the frame (bars, sheets, what syncs); what scrolls is `HomeContent`, which asks
/// the store for the month on screen only and works its numbers out in `HomeModel`, once per
/// change instead of on every redraw.
struct ExpenseListView: View {
    /// Goes up by one each time the «+» beside the tabs is tapped (`RootView`): opens «Anotar gasto».
    var addRequests = 0
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
    @AppStorage(CaptureArrival.sessionKey) private var guideOpened: Double = 0
    @AppStorage(CaptureArrival.firstKey) private var firstArrival: Double = 0

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
    /// When the budget changed (`BudgetHistory`): which one judges each month, and from what day.
    @AppStorage(BudgetHistory.key) private var storedHistory = ""
    @AppStorage(CurrencyPreference.key) private var storedCurrency = ""
    /// The welcome runs once, and only on an empty app (someone who already has expenses
    /// is not new).
    @AppStorage("onboarded") private var onboarded = false
    @State private var showingOnboarding = false
    /// iCloud brought this person's setup while the welcome was open: it closed without saving,
    /// and says why once it has gone (`welcomeFoundSetup`).
    @State private var welcomeFoundICloud = false
    @State private var showingICloudNotice = false
    /// "Now" for the whole screen. Refreshed when the app comes back and when the clock
    /// jumps (midnight, a time-zone change), so the month and "today" never go stale.
    @State private var now = AppClock.now
    /// Months back from this one that are on screen: 0 is this month, -1 last month.
    @State private var monthOffset = 0
    /// A past month whose last expense was just deleted while on it (2026-11-18): it stays
    /// reachable, empty, until the arrows leave it, instead of the screen jumping to this month.
    @State private var keptMonth: Date?
    @State private var pendingDelete: Expense?
    @State private var showingSetup = false
    @State private var showingBudget = false
    @State private var currencyChanged = false
    /// The fixed expenses left in the old currency when it changed, and that currency: they are
    /// no longer set apart from «Hoy puedes gastar» (2026-11-18).
    @State private var fixedLeftBehind = 0
    @State private var previousCurrency = ""
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
    /// The payments the capture couldn't write down (`UnreadNotice`), as kept. Read by hand and
    /// not with `@AppStorage`: its key has a dot (what keeps it out of the backup), and
    /// `UserDefaults` doesn't announce changes to such keys one by one. Read again on any
    /// change to the settings and when the app comes back (`reloadPending`).
    @State private var pendingStored = UserDefaults.standard.string(forKey: UnreadNotice.listKey) ?? ""
    /// The pending payment «Anotar» opened the sheet for, until the sheet closes.
    @State private var resolvingPending: PendingPayment?
    @AppStorage(WhereItGoesStyle.key) private var whereItGoesStyle = WhereItGoesStyle.bar.rawValue
    /// What was just deleted, kept a few seconds so it can come back.
    @State private var lastDeleted: DeletedExpense?
    /// What «Anotar otra vez» just wrote down, kept a few seconds so it can be taken back.
    @State private var lastCopy: CopiedExpense?
    @State private var importMessage: String?
    /// A file read whose rows include some that look repeated: asked about before saving.
    @State private var pendingImport: PendingImport?
    /// A change made here (delete, undo, a category) that couldn't be saved.
    @State private var saveProblem: SaveProblem?
    /// Fixed expenses whose first charge is still to come (`FixedPlan`).
    @AppStorage(FixedPlan.key) private var storedPlans = ""
    /// How «Hoy puedes gastar» treats what a day leaves over (`AllowanceMode`).
    @AppStorage(AllowanceMode.key) private var storedMode = ""
    @State private var showingFixed = false
    @State private var showingSettings = false
    /// Ajustes opens on «Respaldo», straight into restoring: the welcome's «Restaurar un respaldo».
    @State private var settingsOpensRestore = false
    /// When the welcome was left for «Restaurar un respaldo»: it counts as done only once a
    /// restore worked after this (`finishWelcomeRestore`, 2026-11-19).
    @State private var welcomeRestoreSince: Date?
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
    /// Counts are written the Mexican way, like every figure of the app («5,000»). Months and
    /// days are written in the person's language (`Locale.current`).
    static let mexico = Locale(identifier: "es_MX")

    /// Changes the currency the month adds up in. The budget is a bare number, and 8,000
    /// pesos must not quietly become 8,000 dollars, so it asks about it. The fixed expenses in
    /// the old currency stop being set apart from «Hoy puedes gastar»: it says so too, instead
    /// of the figure going up without a word (2026-11-18).
    private func setPrimary(_ code: String) {
        let old = primaryCurrency
        if code != old, BudgetStore.amount(from: storedBudget) != nil {
            let originals = (try? context.fetch(HomeModel.originals)) ?? []
            let items = FixedOutlook.items(originals: originals, plans: FixedPlan.decode(storedPlans), now: now)
            fixedLeftBehind = items.filter { CurrencyResolver.isoCode(for: $0.currency, primary: old) == old }.count
            previousCurrency = old
            currencyChanged = true
        }
        storedCurrency = code
    }

    /// As far back as the oldest expense, and no further; deleting it pulls the limit forward,
    /// unless it was the last one of the month on screen (`keptMonth`).
    private var earliestOffset: Int {
        // Only while something is left: with nothing at all, the empty screen is this month's.
        let kept = oldestRows.isEmpty ? nil : keptMonth
        let oldest = [oldestRows.first?.date, kept].compactMap { $0 }.min()
        return MonthNavigator.earliestOffset(oldest: oldest, now: now)
    }

    /// The month on screen, as an offset from this one.
    private var shownOffset: Int { min(0, max(monthOffset, earliestOffset)) }

    /// The month on screen, by its first instant: the same date for as long as the month is the
    /// same. It was `now` moved by whole months, a new date each time the app came back, and the
    /// picked day or category was let go as if the month had changed (2026-11-18).
    private func viewedMonth(_ offset: Int) -> Date {
        MonthNavigator.bounds(of: MonthNavigator.month(offsetBy: offset, from: now)).start
    }

    /// The arrows: to the month before or after, said out loud with its whole name, since the
    /// buttons only say «anterior» and «siguiente» (2026-11-18).
    private func goToMonth(_ offset: Int) {
        keptMonth = nil
        monthOffset = offset
        let name = viewedMonth(offset).formatted(.dateTime.month(.wide).year().locale(Locale.current))
        let said: String
        if offset == 0 { said = String(localized: "Este mes, \(name)") } else { said = name }
        AccessibilityNotification.Announcement(said).post()
    }

    var body: some View {
        let earliest = earliestOffset
        let offset = shownOffset
        let isCurrent = offset == 0
        let viewed = viewedMonth(offset)
        let lastCapture = WalletWatch.lastCapture(stored: walletArrival, newestInStore: latestCaptures.first?.date)
        let health = CaptureArrival.health(lastCapture: lastCapture, session: guideOpened, first: firstArrival, now: now)

        NavigationStack {
            // In stages: as one chain, the CI's compiler gave up type-checking it in reasonable time.
            let content = HomeContent(
                model: model, viewed: viewed, now: now, isCurrent: isCurrent,
                storeIsEmpty: newestRows.isEmpty,
                stamp: StoreStamp(count: storeCount, newest: newestRows.first?.date),
                settings: HomeSettings(budget: storedBudget, history: storedHistory, plans: storedPlans,
                                       currency: primaryCurrency,
                                       mode: storedMode, whereItGoesStyle: whereItGoesStyle,
                                       ignoresWallet: ignoresWallet, backupWarning: backupWarning),
                catalog: model.catalog(categories: storedCategories, hidden: storedHiddenCategories,
                                       sources: storedSources, categoryColors: storedCategoryColors,
                                       sourceColors: storedSourceColors),
                health: health,
                pending: isCurrent ? UnreadNotice.pending(stored: pendingStored, now: now) : [],
                selectedDay: selectedDay, selectedCategory: selectedCategory,
                entrance: entrance, listWidth: listWidth, actions: actions
            )
            .equatable()
            // Scrolling closes a row left open by a swipe, as in a system list.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting, model.openRow != nil { model.openRow = nil }
            }
            .modifier(TopSearch(text: Bindable(model).searchText) { model.query = $0 })
            .modifier(RefreshesOnSave(model: model))
            .modifier(CountsStore(newest: newestRows.first?.persistentModelID,
                                  oldest: oldestRows.first?.persistentModelID, recount: countStore))
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: storedBudget) { _, budget in
                // The sheet and the welcome already wrote the change down with its day; this is
                // for one that came from elsewhere (iCloud, a restored backup).
                // Only `settleHistory`, never «it was `old` until today»: after restoring a backup
                // with another budget and no list, that would date today a change that never
                // happened and judge the backup's months with this phone's old budget
                // (independent review, 2026-11-11). With no list the budget is «always» that one.
                BudgetStore.settleHistory()
                if Store.syncsBudget { BudgetSync.push(budget) }
            }
            .onChange(of: storedCurrency) { _, code in
                if Store.syncsBudget { BudgetSync.push(code, for: CurrencyPreference.key) }
            }
            .onChange(of: storedMode) { _, mode in
                if Store.syncsBudget { BudgetSync.push(mode, for: AllowanceMode.key) }
            }
            let withBars = content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // «Al día. Punto.»
                    Signature("al día", spoken: "Al día")
                        // The «+» is read after the whole list: from the top, VoiceOver offers it
                        // here, the first thing on the screen (2026-11-18).
                        .accessibilityAction(named: "Anotar gasto") { adding = true }
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
                            // One line each, no word broken in two (owner, 2026-11-11): the sheet already says
                            // «del mes», and the ways of paying are still inside «Categorías».
                            Button("Presupuesto", systemImage: "target") { showingBudget = true }
                            Button("Gastos fijos", systemImage: "repeat") { showingFixed = true }
                            Button("Categorías", systemImage: "creditcard") { showingCatalogs = true }
                        }
                        Section {
                            Button("Conectar Wallet", systemImage: "wallet.pass") { showingSetup = true }
                            Button("Cómo funciona", systemImage: "play.rectangle") { showingTutorial = true }
                            Button("Ajustes", systemImage: "gearshape") { showingSettings = true }
                        }
                    } label: {
                        Label("Más", systemImage: "ellipsis")
                    }
                }
                // Search up here and «+» down beside the tabs (owner, 2026-11-14): a button that
                // opens into a field, not a bar across the top of the ticket.
                if Features.money {
                    DefaultToolbarItem(kind: .search, placement: .topBarTrailing)
                } else {
                    // Without tabs iOS takes the search down to the bottom whatever is asked, and
                    // the «+» laid over it covered the field (iPhone SE, 2026-11-18). Both in the
                    // system's bottom bar instead, as Notes does: search, then the brass «+».
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button { adding = true } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(Theme.brass)
                        }
                        .accessibilityLabel("Anotar gasto")
                    }
                }
                // ‹ › up top since «Mi dinero» put tabs at the bottom (2026-10-31). Only the
                // arrows: the ticket's head already names the month, and the signature must
                // keep its place in the middle.
                ToolbarItemGroup(placement: .topBarLeading) {
                    // A tap goes back one month; a long press lists them all to jump (2026-11-19).
                    MonthJumpMenu(offset: offset, earliest: earliest, now: now) { goToMonth($0) }
                    Button("Mes siguiente", systemImage: "chevron.right") { goToMonth(offset + 1) }
                        .disabled(offset >= 0)
                }
            }
            .onChange(of: addRequests) { adding = true }
            .sheet(isPresented: $showingSetup) { SetupGuideView() }
            // The widgets' «+» and «Fijar presupuesto» (`centavo://anotar`, `centavo://presupuesto`).
            .onOpenURL { openLink($0) }
            .onChange(of: storedBudget) { WidgetBridge.refresh() }
            .onChange(of: storedHistory) { WidgetBridge.refresh() }
            .onChange(of: storedPlans) { WidgetBridge.refresh() }
            .onChange(of: storedCurrency) { WidgetBridge.refresh() }
            // The widgets get the new rule with the snapshot, and redraw.
            .onChange(of: storedMode) { WidgetBridge.refresh() }
            .sheet(isPresented: $adding, onDismiss: { resolvingPending = nil }) {
                // Adding while looking at a past month puts the expense in that month. A pending
                // payment being written down fills the sheet with what was read of it, and goes
                // from the list only when the sheet says it saved.
                // Read through a binding, in a view of its own: a sheet's content built here
                // still sees the state as it was before «Anotar» set it, the first time it opens,
                // and the sheet came up empty.
                NewExpenseSheet(pending: $resolvingPending,
                                initialDate: isCurrent ? nil : MonthNavigator.closingMoment(of: viewed),
                                primaryCurrency: primaryCurrency, saved: removePending)
            }
            // The intents and «Descartar» write the list straight to `UserDefaults`.
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: DispatchQueue.main)) { _ in reloadPending() }
            .onChange(of: now) { _, _ in reloadPending() }
            .sheet(item: $editing) { ExpenseEditorView(expense: $0, onDelete: { delete($0) }) }
            let withSheets = withBars
            .sheet(isPresented: $showingBudget) {
                BudgetSheet(stored: $storedBudget, storedMode: $storedMode, currency: primaryCurrency) { budget, mode in
                    // This month, asked of the store: only its rows and the fixed expenses.
                    TodayBudget.pace(budget: budget,
                                     rows: (try? context.fetch(HomeModel.monthRows(of: now))) ?? [],
                                     originals: (try? context.fetch(HomeModel.originals)) ?? [],
                                     plans: FixedPlan.decode(storedPlans),
                                     primary: primaryCurrency, month: now, now: now, mode: mode,
                                     history: storedHistory)
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
            .modifier(ImportQuestionAlert(pending: $pendingImport) { asked, repeated in
                importMessage = importText(asked.text, repeated: repeated)
            })
            // A new month, by the arrows or by midnight on the 1st, starts unfiltered.
            .onChange(of: viewed) { _, _ in selectedDay = nil; selectedCategory = nil }
            // Another view starts unfiltered: what was picked may not be on it.
            .onChange(of: whereItGoesStyle) { _, _ in selectedCategory = nil }
            .modifier(Feedback(expenseCount: storeCount, newest: newestRows.first?.date))
            .overlay(alignment: .bottom) { undoOverlay }
            .modifier(KeepsTime(now: $now, monthOffset: $monthOffset, context: context))
            withSheets
            .modifier(CatalogsSheet(isPresented: $showingCatalogs))
            .sheet(isPresented: $showingFixed) { FixedExpensesView() }
            .modifier(BackupWatch(warning: $backupWarning, now: now, settingsShown: showingSettings))
            .sheet(isPresented: $showingSettings, onDismiss: {
                settingsOpensRestore = false
                finishWelcomeRestore()
            }) {
                SettingsView(currency: primaryCurrency, setCurrency: setPrimary,
                             health: health,
                             openGuide: { afterSettings { showingSetup = true } },
                             importCSV: { afterSettings { importing = true } },
                             opensRestore: $settingsOpensRestore)
            }
            .onChange(of: storedPlans) { _, value in
                if Store.syncsBudget { BudgetSync.push(value, for: FixedPlan.key) }
            }
            .modifier(BudgetCurrencyCheck(isPresented: $currencyChanged, currency: primaryCurrency,
                                          fixedLeft: fixedLeftBehind, previous: previousCurrency,
                                          onReview: { showingBudget = true }, onFixed: { showingFixed = true }))
            .task {
                UnreadNotice.prepare()
                reloadPending()
                rememberWalletArrival()
                // A budget changed while the app was closed (iCloud) gets its day now.
                BudgetStore.settleHistory()
                // Siri learns the categories it can be asked about («¿Cuánto llevo en Café?»).
                CentavoShortcuts.updateAppShortcutParameters()
                // Decided before the currency: the welcome asks for it itself. A reinstall or a
                // new phone: the expenses are still coming from iCloud.
                let welcomes = !onboarded && newestRows.isEmpty && Onboarding.isAllowed
                    && !(Store.syncsBudget && BudgetSync.hasSetupElsewhere)
                // Never chosen: settle it once, from what the payments are in (pesos if none),
                // so it cannot drift with the phone's settings. Not under the welcome: written
                // now, it went up to iCloud and a welcome closed halfway never came back
                // (2026-11-18). Until it is chosen, `primaryCurrency` shows pesos all the same.
                if !welcomes { settleCurrency() }
                if GuideDebug.opensAtLaunch { showingSetup = true }
                openRequestedSheet()
                // A new expense half typed when iOS closed the app: its sheet again, once per
                // launch (2026-11-19). Not under the welcome, nor over a sheet already up: SwiftUI
                // can't show a second one, and «+» stayed stuck (independent review, 2026-11-19).
                if !ExpenseDraftStore.checkedThisLaunch {
                    ExpenseDraftStore.checkedThisLaunch = true
                    let reopens = !welcomes && ExpenseDraftStore.saved != nil
                    if reopens, !presentsSomething { adding = true }
                }
                // Done here before iCloud had the mark (2026-11-02): say so now, or a second phone
                // with only the currency in iCloud would start the welcome over (independent
                // review, 2026-11-18).
                guard !onboarded else {
                    if Store.syncsBudget { BudgetSync.markOnboarded() }
                    return
                }
                if welcomes {
                    // In place, not sliding up over a «Hoy» that was already drawn (2026-11-18).
                    var appears = Transaction()
                    appears.disablesAnimations = true
                    withTransaction(appears) { showingOnboarding = true }
                } else {
                    onboarded = true
                }
            }
            .modifier(SetupArrival(noticeShown: $showingICloudNotice, arrived: welcomeFoundSetup))
            .fullScreenCover(isPresented: $showingOnboarding, onDismiss: openAfterOnboarding) {
                OnboardingView { exit in
                    // «Restaurar un respaldo» saved nothing: done only once the restore works
                    // (2026-11-19). Marked now, a cancelled Face ID or file picker left an empty
                    // «Hoy» with no way back to the welcome, and told iCloud this iPhone was set up.
                    if exit == .restore {
                        welcomeRestoreSince = AppClock.now
                    } else {
                        onboarded = true
                        if Store.syncsBudget { BudgetSync.markOnboarded() }
                    }
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
            // Opening the guide no longer clears what is pending: only the person does.
            openGuideFromWarning: { showingSetup = true },
            ignoreWallet: { ignoresWallet = true },
            logPending: { logPending($0) },
            discardPending: { removePending($0.id) },
            discardAllPending: {
                UnreadNotice.clear()
                reloadPending()
            },
            setPrimary: { setPrimary($0) },
            edit: { editing = $0 },
            askDelete: { pendingDelete = $0 },
            setCategory: { setCategory($0, of: $1) },
            change: { expense, edit in
                edit(expense)
                persist()
            },
            logAgain: { logAgain($0, elsewhere: shownOffset != 0 || model.isSearching) }
        )
    }
}

/// «Mes anterior»: a tap goes one month back; held, the system menu lists every month from
/// this one back to the earliest with data, the one on screen checked, to jump straight there
/// (2026-11-19). Off on the earliest month, as the arrow was.
private struct MonthJumpMenu: View {
    let offset: Int
    let earliest: Int
    let now: Date
    let goTo: (Int) -> Void

    private var chosen: Binding<Int> {
        Binding(get: { offset }, set: { goTo($0) })
    }

    var body: some View {
        Menu {
            Picker("Ir al mes", selection: chosen) {
                ForEach(MonthNavigator.jumpOffsets(earliest: earliest), id: \.self) { month in
                    Text(name(month)).tag(month)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Mes anterior", systemImage: "chevron.left")
        } primaryAction: {
            goTo(offset - 1)
        }
        .disabled(offset <= earliest)
        .accessibilityHint("Mantén presionado para elegir otro mes")
    }

    /// «noviembre de 2026», in the iPhone's language.
    private func name(_ month: Int) -> String {
        let date = MonthNavigator.month(offsetBy: month, from: now)
        return date.formatted(.dateTime.month(.wide).year().locale(Locale.current))
    }
}

/// The frame's settings the scrolling part reads.
private struct HomeSettings: Equatable {
    let budget: String
    let history: String
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
    /// «No uso Wallet» on the warning or the empty screen's card: «Avisar si no llegan pagos» off.
    let ignoreWallet: () -> Void
    /// The payments the capture couldn't write down (`PendingPaymentsPanel`).
    let logPending: (PendingPayment) -> Void
    let discardPending: (PendingPayment) -> Void
    let discardAllPending: () -> Void
    let setPrimary: (String) -> Void
    let edit: (Expense) -> Void
    let askDelete: (Expense) -> Void
    let setCategory: (String, Expense) -> Void
    /// A change from the row's menu («No es repetida», «Sí cuenta», «No cuenta»), saved right
    /// then; if it fails, it's said (2026-11-02, second audit: it was saved with `try?`).
    let change: (Expense, (Expense) -> Void) -> Void
    /// «Anotar otra vez»: the copy is dated today, and says so when today is not on screen.
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
    let health: CaptureHealth
    /// Payments the capture couldn't write down, newest first; empty on a past month.
    let pending: [PendingPayment]
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
         settings: HomeSettings, catalog: CategoryCatalog, health: CaptureHealth, pending: [PendingPayment],
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
        self.health = health
        self.pending = pending
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
            && lhs.health == rhs.health && lhs.pending == rhs.pending
            && lhs.selectedDay == rhs.selectedDay && lhs.selectedCategory == rhs.selectedCategory
            && lhs.entrance === rhs.entrance && lhs.listWidth == rhs.listWidth
    }

    var body: some View {
        let primary = settings.currency
        let month = model.month(
            MonthInputs(viewed: viewed, now: now, isCurrent: isCurrent, budget: settings.budget,
                        history: settings.history, plans: settings.plans, currency: primary, mode: settings.mode,
                        selectedDay: selectedDay, selectedCategory: selectedCategory),
            rows: monthRows, originals: originals)
        let searching = model.isSearching
        let search = searching ? model.search(now: now, stamp: stamp, in: context) : nil
        // The note is only on this month's carousel; past the budget, the plan above already says
        // where the month closes.
        let showsCarousel = !searching && !storeIsEmpty
        let note = showsCarousel && isCurrent && (month.pace?.remaining ?? 0) >= 0
            ? model.note(rows: recentRows, now: now, primary: primary, budget: settings.budget,
                         reserved: month.pace?.reserved ?? 0)
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
                    showsCapture: isCurrent && !settings.ignoresWallet,
                    health: health, pending: pending,
                    backupWarning: isCurrent ? settings.backupWarning : nil,
                    entrance: entrance, model: model, actions: actions
                )
                HomeLedger(groups: search?.groups ?? month.groups, primaryCurrency: primary, now: now,
                           catalog: catalog, model: model, actions: actions)
            }
            .padding(.top, Theme.Space.s)
            .environment(\.listWidth, listWidth)
            // A tap anywhere else lets the picked day or category go, its card with it (owner,
            // 2026-10-30). Rows, bars and buttons take their own taps first.
            .contentShape(Rectangle())
            .onTapGesture {
                // Not while searching (2026-11-18): the filter is hidden then, and a tap to put
                // the keyboard away let it go unseen; it comes back when the search closes.
                guard !searching else { return }
                if selectedDay != nil { actions.clearDay() }
                if selectedCategory != nil { actions.clearCategory() }
            }
        }
        // Under the tabs, or under the «+»'s own bar without them (`RootView`), the list blurs the
        // way iOS does it under any bar.
        .scrollEdgeEffectStyle(.soft, for: .bottom)
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
    let showsCapture: Bool
    let health: CaptureHealth
    let pending: [PendingPayment]
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
            // Under the figure, the carousel in every view (owner, 2026-10-30): on the left the
            // boleto with its line right under it (the rhythm, the tear line «cuenta») and «En qué
            // se va» in Lista or Mosaico; on the right only the calendar. A budget with nothing
            // written down yet has it too, empty: its days to come dashed, today outlined, the
            // same as any other day of the month (owner, 2026-11-11).
            // Never while searching, the store empty or not (2026-11-18: an empty store with a
            // budget kept it under the search's results).
            if searchCount == nil, !storeIsEmpty || pace != nil {
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
                    onSetBudget: actions.setBudget,
                    currency: currency,
                    budgetHeader: AnyView(VStack(alignment: .leading, spacing: Theme.Space.s) {
                        MonthCodeView(code: month.code, selectedDay: selectedDay, onSelectDay: actions.selectDay,
                                      onScrubbing: { model.scrubbing = $0 }, wholeMoney: wholeMoney,
                                      month: viewed, entrance: entrance)
                        BudgetPage(spent: summary.primary, pace: pace, isCurrentMonth: isCurrent,
                                   outside: summary.outside, entrance: entrance, onSetBudget: actions.setBudget,
                                   part: .top)
                    }),
                    motion: model.carousel
                )
                // Edge to edge: each page keeps its own margin, so a swipe shows a gap
                // between them instead of two pages touching.
                .ticketRow(bottom: isCurrent ? Theme.Space.none : Theme.Space.xl, horizontal: Theme.Space.none)
            }
            // Payments the capture couldn't write down: said with or without expenses, above the
            // empty ticket too (the first payment may be the one that didn't read; 2026-11-11).
            if searchCount == nil, !pending.isEmpty {
                PendingPaymentsPanel(pending: pending, log: actions.logPending, discard: actions.discardPending,
                                     discardAll: actions.discardAllPending, openGuide: actions.openGuideFromWarning)
                    .ticketRow()
            }
            // While searching, only the results: with nothing in the store the empty ticket said
            // «Tu mes empieza aquí» under «Sin resultados» (2026-11-18).
            if searchCount == nil, storeIsEmpty {
                // A day picked on the empty calendar says so, and how to let it go (2026-11-18).
                filters
                // «Avisar si no llegan pagos» off: the empty screen stops asking to connect Wallet
                // too, as Ajustes says (2026-10-29).
                let wallet: WalletCard? = showsCapture ? WalletCard(health, pending: !pending.isEmpty) : nil
                EmptyTicket(hasBudget: pace != nil, wallet: wallet,
                            onAdd: actions.add, onBudget: actions.setBudget, onSetup: actions.setup,
                            onIgnoreWallet: actions.ignoreWallet)
                    .ticketRow()
            } else if searchCount == nil {
                // The Wallet line stays between the carousel and the list, not under «Hoy»:
                // it is about the capture, not about today's expenses (owner, 2026-10-21).
                // With payments pending, «Wallet sin conectar» or «sin pagos» would contradict the
                // notice above, which already leads to the guide: only the quiet line stays.
                if showsCapture, pending.isEmpty || health.isRecent {
                    CaptureHealthRow(health: health, openGuide: actions.openGuideFromWarning,
                                     ignoreWallet: actions.ignoreWallet)
                        .ticketRow()
                }
                if let backupWarning {
                    BackupWarningRow(text: backupWarning, open: actions.openSettings)
                        .ticketRow()
                }

                filters
                if !month.hasExpenses {
                    emptyLine("Sin gastos este mes")
                } else if selectedDay != nil, month.shownCount == 0 {
                    // A day with nothing in it left a blank under its filter (2026-11-18).
                    emptyLine("Sin gastos este día")
                }
            }
        }
        // The whole top of the screen turns the carousel's page with a sideways swipe.
        .contentShape(Rectangle())
        .gesture(pageSwipe)
    }

    /// The day or the category picked, over the list.
    @ViewBuilder private var filters: some View {
        if let day = selectedDay {
            FilterRow(title: String(localized: "Día \(day)"), count: month.shownCount, total: month.shownTotal,
                      clear: actions.clearDay)
                .ticketRow()
        }
        if let line = selectedCategory {
            FilterRow(title: Self.filterName(line),
                      count: month.shownCount, total: month.shownTotal, clear: actions.clearCategory)
                .ticketRow()
        }
    }

    /// The picked category's name: its own, or «Otras», «Sin categoría».
    private static func filterName(_ line: CategoryShare) -> String {
        if line.isRest { return String(localized: "Otras") }
        return line.category.map { CategoryStyle.shown($0) } ?? String(localized: "Sin categoría")
    }

    private func emptyLine(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .ticketCaption()
            .frame(maxWidth: .infinity, minHeight: Theme.Size.tallRow, alignment: .leading)
            .overlay(alignment: .top) { Perforation() }
            .ticketRow()
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
                                    let shown = CategoryStyle.shown(name)
                                    if expense.category == name {
                                        Label(shown, systemImage: "checkmark")
                                    } else {
                                        Text(shown)
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
                    // The menu's one-touch changes in VoiceOver's actions too: it doesn't reach
                    // a long press (2026-11-19). The category is in the sheet a tap opens.
                    .accessibilityActions { voiceOverActions(expense) }
                }
            }
        }
    }

    /// The row menu's quick changes, as VoiceOver actions. Apart: in the chain above it was one
    /// more closure for the CI's older type-checker.
    @ViewBuilder private func voiceOverActions(_ expense: Expense) -> some View {
        if expense.maybeRepeated == true {
            Button("No es repetida") { actions.change(expense) { $0.maybeRepeated = nil } }
        }
        if expense.isUncounted {
            Button("Sí cuenta") { actions.change(expense) { $0.markCounted() } }
        } else {
            Button("No cuenta") { actions.change(expense) { $0.markUncounted($0.reason ?? .reimbursed) } }
        }
        Button("Anotar otra vez") { actions.logAgain(expense) }
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
            NoteText("La mayoría de tus pagos de este mes son en \(CurrencyPreference.spoken(code)).")
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
                .frame(minHeight: Theme.Size.tapTarget) // ds-allow: botón prominente del sistema; su cápsula es el área de toque
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

/// The search: a button in the top bar that opens into a field.
///
/// The words reach the list (`settle`) once typing pauses (`HomeModel.searchPause`), so a
/// search over every month runs once per word and not once per letter; clearing it is at once.
/// Each letter redraws only this modifier, not the screen.
private struct TopSearch: ViewModifier {
    @Binding var text: String
    let settle: (String) -> Void
    private let prompt = String(localized: "Comercio, mes o monto…")

    func body(content: Content) -> some View {
        content
            .searchable(text: $text, prompt: prompt)
            .searchToolbarBehavior(.minimize)
            .task(id: text) {
                let typed = text
                if !typed.trimmingCharacters(in: .whitespaces).isEmpty {
                    try? await Task.sleep(for: HomeModel.searchPause)
                    guard !Task.isCancelled else { return }
                }
                settle(typed)
            }
    }
}

/// iCloud's settings arriving (`NSUbiquitousKeyValueStore`), and the notice that the welcome
/// closed because of them (2026-11-18). Apart from `body`: the CI's compiler is slow with it.
private struct SetupArrival: ViewModifier {
    @Binding var noticeShown: Bool
    let arrived: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(
                for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
                .receive(on: DispatchQueue.main)) { _ in arrived() }
            .alert("Tu configuración llegó de iCloud", isPresented: $noticeShown) {
                Button("Listo", role: .cancel) {}
            } message: {
                Text("Tus gastos pueden tardar unos minutos en llegar.")
            }
    }
}

/// After the main currency changes: the budget stays the same number, so offer to fix it; and
/// the fixed expenses left in the old currency are no longer set apart from it (2026-11-18).
private struct BudgetCurrencyCheck: ViewModifier {
    @Binding var isPresented: Bool
    let currency: String
    /// How many fixed expenses are in `previous`, the currency it was.
    let fixedLeft: Int
    let previous: String
    let onReview: () -> Void
    let onFixed: () -> Void

    /// Whole sentences for the catalog: the budget alone, or with the fixed expenses left behind.
    private var message: String {
        let now = CurrencyPreference.spoken(currency)
        let old = CurrencyPreference.spoken(previous)
        let count = fixedLeft
        if count == 1 {
            return String(localized: "Sigue siendo el mismo número, ahora en \(now). Tu gasto fijo sigue en \(old) y ya no se aparta de lo que puedes gastar.")
        }
        if count > 1 {
            return String(localized: "Sigue siendo el mismo número, ahora en \(now). Tus \(count) gastos fijos siguen en \(old) y ya no se apartan de lo que puedes gastar.")
        }
        return String(localized: "Sigue siendo el mismo número, ahora en \(now).")
    }

    func body(content: Content) -> some View {
        content.alert("¿Y tu presupuesto?", isPresented: $isPresented) {
            Button("Cambiarlo", action: onReview)
            if fixedLeft > 0 { Button("Ver gastos fijos", action: onFixed) }
            Button("Así está bien", role: .cancel) {}
        } message: {
            Text(message)
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
                old > 0 && new > old && (newest.map { AppClock.now.timeIntervalSince($0) < 120 } ?? false)
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
            // Off the main thread: it reads the keychain and asks iCloud about the newest file.
            .task(id: now) { warning = await Task.detached { DailyBackup.warning(now: now) }.value }
            .onChange(of: settingsShown) { _, shown in if !shown { warning = DailyBackup.warning() } }
    }
}

/// A change made in «Hoy» that couldn't be saved, said out loud.
private struct SaveProblemAlert: ViewModifier {
    @Binding var problem: SaveProblem?

    func body(content: Content) -> some View {
        content.problemAlert(problem: $problem)
    }
}

/// The sheet of a new expense, filled with a pending payment when «Anotar» opened it.
private struct NewExpenseSheet: View {
    @Binding var pending: PendingPayment?
    let initialDate: Date?
    let primaryCurrency: String
    let saved: (PendingPayment.ID) -> Void

    var body: some View {
        let payment = pending
        ExpenseEditorView(expense: nil, initialDate: initialDate,
                          prefill: payment?.prefill(primary: primaryCurrency),
                          onSave: payment.map { payment in { saved(payment.id) } },
                          keepsDraft: payment == nil)
    }
}

/// Every save, here or brought by iCloud, moves `HomeModel.revision`: the month's numbers and a
/// search on screen are worked out again (an edit can change a figure, or make an expense match
/// the search or stop matching).
private struct RefreshesOnSave: ViewModifier {
    let model: HomeModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in model.storeSaved() }
            // Posted off the main thread.
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                Task { @MainActor in model.storeSaved() }
            }
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
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                Task { @MainActor in recount() }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { recount() } }
            .onChange(of: newest, initial: true) { recount() }
            .onChange(of: oldest) { recount() }
    }
}

/// Keeps "now" fresh (coming back, midnight, a time-zone change) and logs the fixed expenses
/// whose day came while the app was closed.
private struct KeepsTime: ViewModifier {
    @Binding var now: Date
    /// A past month on screen stays on screen when the month turns (2026-11-18): at midnight on
    /// the 1st, or coming back in another month, September stayed «one month back» and became
    /// October under the person's eyes.
    @Binding var monthOffset: Int
    let context: ModelContext
    @Environment(\.scenePhase) private var scenePhase

    /// The next fixed expense still to come (a running one's next charge, or a plan's first).
    private func nextCharge() -> Date? {
        let originals = (try? context.fetch(HomeModel.originals)) ?? []
        let items = FixedOutlook.items(originals: originals, plans: FixedPlan.saved, now: now)
        return FixedWake.next(items.map(\.next), after: now)
    }

    /// The new «now», and the offset moved in the same update, so the month never flickers.
    private func advance() {
        let new = AppClock.now
        monthOffset = ViewedMonth.offset(monthOffset, from: now, to: new)
        now = new
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { advance() }
                // A budget or a fixed expense changed in «Más» also changes the widgets.
                if phase == .background { WidgetBridge.refresh() }
            }
            .task(id: now) {
                // Captures from before «$» was saved as its currency, pinned once (2026-11-02).
                _ = try? ExpenseRecorder.pinBareDollars(in: context)
                _ = try? RecurringExpenses.logDue(in: context, now: now)
                _ = try? ExpenseRecorder.repairBankMerchants(in: context)
                WidgetBridge.refresh()
                // With the app left open, nothing moved «now» when a fixed expense came due (rent
                // at 9:00): it wasn't logged and «Hoy puedes gastar» still set it apart until the
                // app was closed and opened (2026-11-18). Wakes right after the next one; a new
                // «now» before then (coming back, midnight) cancels this and works it out again.
                guard let wake = nextCharge() else { return }
                try? await Task.sleep(for: .seconds(wake.timeIntervalSince(now) + FixedWake.margin))
                guard !Task.isCancelled else { return }
                advance()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.significantTimeChangeNotification)) { _ in
                advance()
            }
    }
}

/// When «Hoy» wakes by itself to log a fixed expense whose moment came with the app open.
enum FixedWake {
    /// After the charge's own moment, so `logDue` (which logs what is due by «now») takes it.
    static let margin: TimeInterval = 1

    /// The soonest of `dates` still to come after `now`; `nil` with none.
    static func next(_ dates: [Date?], after now: Date) -> Date? {
        dates.compactMap { $0 }.filter { $0 > now }.min()
    }
}

/// Which offset keeps a past month on screen when «now» moves to another month.
enum ViewedMonth {
    /// This month (0) follows «now»; a past one stays the same month, never past this one.
    static func offset(_ offset: Int, from old: Date, to new: Date, calendar: Calendar = .current) -> Int {
        guard offset < 0 else { return offset }
        let from = MonthNavigator.bounds(of: old, calendar: calendar).start
        let to = MonthNavigator.bounds(of: new, calendar: calendar).start
        let months = calendar.dateComponents([.month], from: from, to: to).month ?? 0
        return min(offset - months, 0)
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
            saveProblem = SaveProblem(title: "No se guardó el cambio", detail: SaveProblem.unchangedPersisting)
            return false
        }
    }

    var importAlertShown: Binding<Bool> {
        Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
    }

    /// «Anotar» on a pending payment: the sheet of a new expense, filled with what was read.
    /// The payment stays pending until that sheet saves; «Cancelar» leaves it there.
    private func logPending(_ payment: PendingPayment) {
        resolvingPending = payment
        adding = true
    }

    /// Written down or discarded: off the list, and off the screen without waiting to be told.
    private func removePending(_ id: UUID) {
        UnreadNotice.remove(id)
        reloadPending()
    }

    /// The list as it is kept now.
    private func reloadPending() {
        let stored = UserDefaults.standard.string(forKey: UnreadNotice.listKey) ?? ""
        if stored != pendingStored { pendingStored = stored }
    }

    /// Something is already up over «Hoy»: a cover, a sheet, an alert or the file picker.
    private var presentsSomething: Bool {
        let covers = showingOnboarding || showingTutorial
        let sheets = adding || editing != nil || showingSettings || showingSetup || showingBudget
            || showingFixed || showingCatalogs || importing || pendingDelete != nil
        let alerts = importMessage != nil || pendingImport != nil || saveProblem != nil || currencyChanged
            || showingICloudNotice
        return covers || sheets || alerts
    }

    /// The widgets' «+» and «Fijar presupuesto». Only over a bare «Hoy» (2026-11-18): over
    /// another sheet SwiftUI can't show a second one, the flag stayed on and the sheet came up by
    /// itself later, once the person had closed theirs. What they had open stays as it was.
    private func openLink(_ url: URL) {
        guard url.scheme == "centavo", !presentsSomething else { return }
        switch url.host() {
        case "anotar": adding = true
        case "presupuesto": showingBudget = true
        default: break
        }
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
        let foundICloud = welcomeFoundICloud
        if foundICloud {
            welcomeFoundICloud = false
            showingICloudNotice = true
        }
        let exit = afterOnboarding
        afterOnboarding = nil
        switch exit {
        case .guide: showingSetup = true
        case .tutorial: showingTutorial = true
        // Ajustes › Respaldo, already asking to restore (2026-11-19). Not when iCloud brought
        // the setup meanwhile: the data is coming from there, and its notice is what shows (an
        // alert and a sheet asked at once; independent review, 2026-11-19).
        case .restore:
            guard !foundICloud else { break }
            settingsOpensRestore = true
            showingSettings = true
        case .home, nil: break
        }
    }

    /// Never chosen: settled once, from what the payments are in (pesos if none), so it cannot
    /// drift with the phone's settings.
    private func settleCurrency() {
        guard !CurrencyPreference.offered.contains(storedCurrency) else { return }
        let latest = (try? context.fetch(HomeModel.newest(100))) ?? []
        storedCurrency = CurrencySuggestion.dominant(
            markers: latest.map(\.currencyMarker),
            primary: CurrencyPreference.fallback,
            offered: CurrencyPreference.offered) ?? CurrencyPreference.fallback
    }

    /// Ajustes closed after the welcome's «Restaurar un respaldo» (2026-11-19). Restored: the
    /// welcome is done and the currency comes from the restored payments, as at launch, without
    /// waiting for the next one (the backup doesn't carry it). Not restored (Face ID, the file
    /// picker or the backup cancelled, or it failed): nothing is marked, and an app still empty
    /// shows the welcome again at the next launch.
    private func finishWelcomeRestore() {
        guard let since = welcomeRestoreSince else { return }
        welcomeRestoreSince = nil
        let restoredAt = UserDefaults.standard.object(forKey: DailyBackup.restoredKey) as? Date
        guard let restoredAt, restoredAt >= since else { return }
        onboarded = true
        if Store.syncsBudget { BudgetSync.markOnboarded() }
        settleCurrency()
    }

    /// A second iPhone whose iCloud came late (2026-11-18): the welcome opened because iCloud had
    /// nothing yet, and the setup arrived while it was up. It goes without saving, as if iCloud
    /// had come first: filled in, it typed the rent in a second time and wrote its budget and
    /// currency over the other iPhone's. Not once the welcome saved (`onboarded`): that is this
    /// phone's own setup. The expenses may still be on their way, so only iCloud's settings count.
    private func welcomeFoundSetup() {
        guard showingOnboarding, !onboarded, Store.syncsBudget, BudgetSync.hasSetupElsewhere else { return }
        onboarded = true
        BudgetSync.markOnboarded()
        afterOnboarding = nil
        welcomeFoundICloud = true
        showingOnboarding = false
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
    /// `elsewhere`: a past month or a search is on screen, so the copy (dated today) doesn't show
    /// up where the person is looking.
    private func logAgain(_ expense: Expense, elsewhere: Bool) {
        let copy = Expense(amount: expense.amount, currencyMarker: expense.currencyMarker,
                           merchant: expense.merchant, card: expense.card, date: AppClock.now,
                           category: expense.category)
        copy.displayName = expense.displayName
        context.insert(copy)
        guard persist() else { return }
        // A tap in a menu is easy to make by mistake: it can be taken back (audit 2026-11-02).
        withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) {
            lastDeleted = nil
            lastCopy = CopiedExpense(expense: copy, name: copy.displayName ?? copy.merchant, dated: elsewhere)
        }
    }

    /// «Deshacer» on «Anotaste otra vez»: the copy goes, the original stays.
    private func undoCopy(_ copied: CopiedExpense) {
        // Already deleted another way (its row, a sync): only the bar goes.
        guard copied.expense.modelContext != nil, !copied.expense.isDeleted else {
            withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) { lastCopy = nil }
            return
        }
        context.delete(copied.expense)
        guard persist() else { return }
        countStore()
        model.storeSaved()
        withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) { lastCopy = nil }
    }

    @ViewBuilder var undoOverlay: some View {
        if let copied = lastCopy {
            UndoBar(text: copied.text, identifier: "deshacer-copia") { undoCopy(copied) }
                .modifier(UndoBarPlacement(id: copied.id, spoken: copied.spoken,
                                           reduceMotion: reduceMotion) {
                    if lastCopy?.id == copied.id { lastCopy = nil }
                })
        } else if let deleted = lastDeleted {
            let name = deleted.displayName ?? deleted.merchant
            UndoBar(text: String(localized: "Borraste \(name)")) { restore(deleted) }
                .modifier(UndoBarPlacement(id: deleted.id,
                                           spoken: String(localized: "Borraste \(name). Puedes deshacerlo."),
                                           reduceMotion: reduceMotion) {
                    if lastDeleted?.id == deleted.id { lastDeleted = nil }
                })
        }
    }

    func delete(_ expense: Expense) {
        let snapshot = DeletedExpense(expense)
        // Deleting a past month's last expense leaves that month on screen, empty, instead of
        // jumping to this one under «Deshacer» (2026-11-18).
        let viewed = viewedMonth(shownOffset)
        if shownOffset < 0, MonthNavigator.isSameMonth(expense.date, as: viewed) { keptMonth = viewed }
        context.delete(expense)
        guard persist() else { return }
        countStore()
        // A search on screen is asked again, without the deleted expense.
        model.storeSaved()
        withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) {
            lastCopy = nil
            lastDeleted = snapshot
        }
    }

    func restore(_ deleted: DeletedExpense) {
        guard let expense = deleted.make() else { return }
        context.insert(expense)
        guard persist() else { return }
        model.storeSaved()
        countStore()
        withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) { lastDeleted = nil }
    }

    /// Reads the chosen file and says plainly what happened. `nil` when there's a question to
    /// answer first (`pendingImport`): rows that look like expenses already here, with another
    /// name or card. Nothing is saved until it is answered.
    func importFile(_ result: Result<URL, Error>) -> String? {
        guard case .success(let url) = result else { return String(localized: "No se pudo abrir el archivo.") }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        // In whatever encoding the spreadsheet saved it: Excel's «CSV» is Windows-1252 and its
        // «Unicode» UTF-16 (2026-11-18).
        guard let data = try? Data(contentsOf: url), let text = CSVImporter.text(from: data) else {
            return String(localized: "No se pudo leer el archivo. Guárdalo como CSV UTF-8 desde Excel y vuelve a intentar.")
        }
        if let doubtful = try? ExpenseImporter.preview(text, in: context).leftOut, doubtful > 0 {
            pendingImport = PendingImport(text: text, question: .init(looksRepeated: doubtful))
            return nil
        }
        return importText(text, repeated: .leaveOut)
    }

    /// Saves what the file brings and says how many came in, were already here or were left out.
    func importText(_ text: String, repeated: ExpenseImporter.Repeated) -> String {
        do {
            return try ExpenseImporter.importCSV(text, into: context, repeated: repeated).text
        } catch CSVImporter.Failure.notOurFile {
            // «Mi dinero»'s file has its own place (2026-11-01).
            if Features.money, MoneyImport.parse(text, main: primaryCurrency).refusal == nil {
                return String(localized: "Este archivo es de «Mi dinero», no de tus gastos: cárgalo en esa pestaña.")
            }
            return String(localized: "Ese archivo no es un CSV exportado de Al día (le falta el encabezado Fecha, Comercio, Monto, Moneda).",
                          comment: "Fecha, Comercio, Monto, Moneda are the CSV's column names: keep them in Spanish")
        } catch {
            return String(localized: "No se pudo guardar lo importado. Intenta de nuevo.")
        }
    }
}

/// A CSV read and waiting for its one question (2026-11-11).
struct PendingImport: Equatable {
    var text: String
    var question: ExpenseImporter.Question
}

/// «12 parecen repetidos… ¿Agregarlos también?»: «Solo los nuevos» is the default.
private struct ImportQuestionAlert: ViewModifier {
    @Binding var pending: PendingImport?
    let answer: (PendingImport, ExpenseImporter.Repeated) -> Void

    func body(content: Content) -> some View {
        content.alert("Importar CSV",
                      isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                      presenting: pending) { asked in
            Button(ExpenseImporter.Question.onlyNew) { answer(asked, .leaveOut) }
                .keyboardShortcut(.defaultAction)
            Button(ExpenseImporter.Question.all) { answer(asked, .add) }
        } message: { asked in
            Text(asked.question.message)
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

/// The head of «Hoy»'s ticket (`TicketHead`): «JUE 29 DE OCT» this month («SEP 2026» for
/// another), and at the other end «N.º 042», the month's payments.
private struct ReceiptHead: View {
    let date: Date
    let isCurrent: Bool
    let payments: Int

    private var title: String {
        if isCurrent { return TicketHead.day(date) }
        return date.formatted(.dateTime.month(.abbreviated).year().locale(Locale.current))
            .replacingOccurrences(of: ".", with: "")
    }

    /// What VoiceOver says for the folio.
    private var spoken: String {
        let count = payments
        if count == 1 { return String(localized: "1 pago este mes") }
        return String(localized: "\(count) pagos este mes")
    }

    var body: some View {
        TicketHead(title: title, number: payments, spoken: spoken,
                   titleIdentifier: "fecha-ticket", folioIdentifier: "folio")
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
        guard isCurrentMonth, let pace, !pace.isOverspent, !pace.isFixedOverBudget else { return nil }
        return pace.dailyAllowance
    }

    /// This month, within the budget, with fixed expenses that take all of it (second audit,
    /// 2026-11-02): by how much they pass it. Not «te pasaste»: nothing was overspent, even once
    /// the fixed ones are charged (independent review; `BudgetPace.isOverspent`).
    private var fixedExcess: Decimal? {
        guard isCurrentMonth, let pace, !pace.isOverspent else { return nil }
        return pace.fixedOverBudgetShown
    }

    @State private var counted: Double = 0

    /// This month, past the budget: how far past it (the hero's figure then).
    private var overage: Decimal? {
        guard isCurrentMonth, let pace, pace.isOverspent else { return nil }
        // Rounded up, like «Para cerrar el mes»: never «$0» over a few centavos.
        return pace.overspentShown
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
        let label = summary.primary.label
        if isCurrentMonth {
            let day = shortDate(now)
            return String(localized: "Total \(label) al \(day)")
        }
        let month = viewed.formatted(.dateTime.month(.abbreviated).year().locale(Locale.current))
        return String(localized: "Total \(label) · \(month)")
    }

    /// `caption` as VoiceOver says it: a comma, not the drawn «·» (2026-11-18).
    private var spokenCaption: String {
        guard !isCurrentMonth else { return caption }
        let label = summary.primary.label
        let month = viewed.formatted(.dateTime.month(.abbreviated).year().locale(Locale.current))
        return String(localized: "Total \(label), \(month)")
    }

    /// Over the figure: today still has room, or went past it.
    private var allowanceTitle: String {
        if isOverToday { return String(localized: "Hoy te pasaste") }
        return String(localized: "Hoy puedes gastar")
    }

    /// The caption and the figure, said as one sentence.
    private var spokenAllowance: String {
        let amount = allowanceText
        if isOverToday { return String(localized: "Hoy te pasaste \(amount)") }
        return String(localized: "Hoy puedes gastar \(amount)")
    }

    /// «+ USD 24.99 en otra moneda», under the month's total.
    private var othersLine: String {
        let others = othersText
        if summary.others.count > 1 { return String(localized: "+ \(others) en otras monedas") }
        return String(localized: "+ \(others) en otra moneda")
    }

    private var totalText: AttributedString {
        let formatted = formatMoney(summary.primary.amount, isoCode: summary.primary.isoCode,
                                    label: summary.primary.label)
        // Money is written the Mexican way («.») in any region, a bare marker too (2026-11-18:
        // with «,» the cents never greyed out).
        let parts = MoneyText.splitCents(formatted, decimalSeparator: ".")
        var text = AttributedString(parts.head)
        var cents = AttributedString(parts.cents)
        cents.foregroundColor = Theme.muted
        text += cents
        text += AttributedString(parts.tail)
        return text
    }

    private var othersText: String {
        summary.others
            .map { "\($0.label) \(plainAmount($0.amount))" }
            .formatted(.list(type: .and, width: .narrow))
    }

    var body: some View {
        // The caption and the figure are one group, closer to each other than the sections are,
        // with a breath between them (owner, 2026-10-30).
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if allowance != nil {
                Text(allowanceTitle)
                    // Read with the figure, as one sentence.
                    .accessibilityHidden(true)
                    // Grey like every other caption, so the brass figure under it leads.
                    .ticketCaption(strong: true)
                // Counts up from zero when the screen opens, and rolls to the new figure after
                // every payment.
                Text(countedText)
                    .accessibilityIdentifier("hoy-puedes-gastar")
                    .accessibilityLabel(spokenAllowance)
                    .heroFigure()
                    .foregroundStyle(isOverToday ? Theme.danger : Theme.brass)
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
                    .heroFigure()
                    .foregroundStyle(Theme.danger)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : Theme.Motion.quick, value: overage)
            } else {
                Text(verbatim: caption).ticketCaption(strong: true)
                    .accessibilityLabel(spokenCaption)
                Text(totalText)
                    .accessibilityIdentifier("total-mes")
                    .heroFigure()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : Theme.Motion.quick, value: summary.primary.amount)
            }
            // Adding currencies together would be a lie, so they ride along separately, under the
            // month's total; with «Hoy puedes gastar» on top they would only crowd it (each one
            // still shows in its own row of the list).
            if allowance == nil, fixedExcess == nil, !summary.others.isEmpty {
                // «aparte» said nothing on a first look (user research, 2026-10-29).
                Text(othersLine)
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
                .accessibilityLabel(String(localized: "Tus fijos pasan el presupuesto por \(text)"))
                .heroFigure()
                .foregroundStyle(Theme.brass)
        } else {
            Text("Hoy puedes gastar")
                .accessibilityHidden(true)
                .ticketCaption(strong: true)
            Text(text)
                .accessibilityIdentifier("fijos-pasan")
                .accessibilityLabel("Tus fijos se llevan todo el presupuesto")
                .heroFigure()
                .foregroundStyle(Theme.brass)
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
/// The empty screen's Wallet card: «Conectar Wallet» until the guide was opened, then what is
/// happening with the first payment (2026-11-18), so it never asks to connect what was just
/// connected.
struct WalletCard: Equatable {
    let title: String
    let detail: String
    /// «No uso Wallet» goes under it: it asks to connect or check Wallet (2026-11-19).
    let offersOptOut: Bool

    /// `nil`: no card. With payments the capture couldn't read (`pending`), Wallet is plainly
    /// connected and the notice above already leads to the guide: «Conectar Wallet» or «Esperando
    /// tu primer pago» under it said the opposite (2026-11-18).
    init?(_ health: CaptureHealth, pending: Bool = false) {
        // What iOS 26's automation can catch, said the same way as the welcome (`CaptureCopy`).
        switch health {
        case .never:
            guard !pending else { return nil }
            title = String(localized: "Conectar Wallet")
            detail = CaptureCopy.connect
            offersOptOut = true
        case .waiting:
            guard !pending else { return nil }
            title = String(localized: "Esperando tu primer pago")
            detail = CaptureCopy.waiting
            offersOptOut = false
        case .silent:
            title = String(localized: "El atajo no ha anotado nada")
            detail = CaptureCopy.silent
            offersOptOut = true
        // Payments came and were all deleted: the arrival is remembered (`WalletWatch`), and the
        // card said «Conectar Wallet» as if it never had been (2026-11-18).
        case .first(let date), .recent(let date):
            let when = AppClock.relative(date)
            title = String(localized: "Wallet conectado")
            detail = String(localized: "Último pago \(when).")
            offersOptOut = false
        case .quiet(let days):
            title = String(localized: "Sin pagos de Wallet desde hace \(days) días")
            detail = CaptureCopy.quiet
            offersOptOut = true
        }
    }
}

private struct EmptyTicket: View {
    let hasBudget: Bool
    /// `nil` with «Avisar si no llegan pagos» off: no card asks to connect Wallet (2026-11-18).
    /// Also `nil` when it would contradict the payments pending above (`WalletCard.init`).
    let wallet: WalletCard?
    let onAdd: () -> Void
    let onBudget: () -> Void
    let onSetup: () -> Void
    /// «No uso Wallet» (`WalletCard.offersOptOut`), asked first (`walletOptOut`).
    let onIgnoreWallet: () -> Void

    private typealias Empty = Theme.Motion.Money.Empty
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var askingOptOut = false

    private var lead: String {
        if wallet == nil { return String(localized: "Anota tu primer gasto y aparecerá aquí.") }
        return CaptureCopy.emptyLead
    }

    var body: some View {
        // Only what moves follows the clock: the text and the button are drawn once.
        VStack(alignment: .leading, spacing: Theme.Space.ml) {
            Text("Tu mes empieza aquí")
                .ticketCaption(strong: true)
            if !hasBudget { monthStrip }
            // Only a drawing (hidden from VoiceOver): with the largest text it had no room and
            // broke «TU PRIMER GASTO» into pieces (2026-11-18).
            if !typeSize.isAccessibilitySize {
                PlayOnceClock(until: Empty.end) { t in
                    ghostRow(moneySpan(t, Empty.ghost.lowerBound, Empty.ghost.upperBound))
                }
            }
            Text(lead)
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
            steps
            if wallet?.offersOptOut == true {
                SecondaryButton("No uso Wallet", identifier: "vacio-no-uso-wallet") { askingOptOut = true }
                    .accessibilityHint("Deja de pedirte que conectes Wallet")
            }
        }
        .padding(Theme.Space.xlx)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ticketOutline(.emphasis)
        .walletOptOut(isAsking: $askingOptOut, confirm: onIgnoreWallet)
    }

    /// The month's days, empty and dashed; today outlined, breathing a few times, then at rest.
    private var monthStrip: some View {
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: AppClock.now)?.count ?? 30
        let today = calendar.component(.day, from: AppClock.now)
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
                .rowName()
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

    /// The cards are built once; only each one's drawing follows the clock (audit 2026-11-02:
    /// one clock around both cards rebuilt their buttons and layout 30 times a second).
    @ViewBuilder private var steps: some View {
        let wallet = Empty.wallet
        if self.wallet == nil {
            if !hasBudget { budgetCard(Empty.budget, wide: true) }
        } else if hasBudget {
            walletCard(wallet, wide: true)
        } else {
            let budget = Empty.budget
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

    private func budgetCard(_ progress: ClosedRange<Double>, wide: Bool) -> some View {
        EmptyStepCard(kind: .budget, title: String(localized: "Fijar presupuesto"),
                      detail: String(localized: "Para saber cuánto puedes gastar al día."),
                      progress: progress, wide: wide, identifier: "vacio-presupuesto", action: onBudget)
    }

    private func walletCard(_ progress: ClosedRange<Double>, wide: Bool) -> some View {
        EmptyStepCard(kind: .wallet, title: self.wallet?.title ?? "", detail: self.wallet?.detail ?? "",
                      progress: progress, wide: wide, identifier: "vacio-wallet", action: onSetup)
    }
}

/// One of the empty screen's two steps: its drawing, its name and what it's for.
private struct EmptyStepCard: View {
    let kind: EmptyStepArt.Kind
    let title: String
    let detail: String
    /// When, on the empty screen's clock, this card's drawing plays.
    let progress: ClosedRange<Double>
    let wide: Bool
    let identifier: String
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The drawing beside the words; with the largest text, over them, so the words have the
    /// card's whole width (2026-11-18: «presup/uesto» and «Conecta/r» broke in two).
    private var sideBySide: Bool { wide && !typeSize.isAccessibilitySize }

    var body: some View {
        Button(action: action) {
            let layout = sideBySide ? AnyLayout(HStackLayout(spacing: Theme.Space.m))
                                    : AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.xs))
            layout {
                PlayOnceClock(until: Theme.Motion.Money.Empty.end) { t in
                    EmptyStepArt(kind: kind, progress: moneySpan(t, progress.lowerBound, progress.upperBound))
                }
                    .frame(width: sideBySide ? Theme.Size.moneyExcelArt : nil, height: Theme.Size.emptyStepArt)
                    .frame(maxWidth: sideBySide ? nil : .infinity)
                    .background(Theme.ink.opacity(Theme.Opacity.moneyArtWash), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    Text(title).font(.ticket(.bodyStrong)).foregroundStyle(Theme.brass)
                    Text(detail).font(.ticket(.hint)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if sideBySide { Spacer(minLength: Theme.Space.none) }
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
    @Environment(\.dynamicTypeSize) private var typeSize

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
        var parts: [String?] = []
        // A Wallet payment identical to one minutes before says so first (2026-11-02).
        if expense.maybeRepeated == true {
            if spoken {
                parts.append(String(localized: "¿repetida? Igual a otro pago de hace unos minutos"))
            } else {
                parts.append(Self.repeatedTag)
            }
        }
        if isUncounted {
            parts.append(spoken ? expense.reason?.title : String(localized: "No cuenta"))
        }
        if isRefund { parts.append(String(localized: "Devolución")) }
        if expense.isFixed { parts.append(String(localized: "Fijo")) }
        // The app's own names in the iPhone's language; stored in Spanish (2026-11-18).
        parts.append(expense.category.map { CategoryStyle.shown($0) })
        if withCard { parts.append(expense.card.map { CategoryStyle.shown($0) }) }
        let shown = parts.compactMap { $0 }.filter { !$0.isEmpty }
        // A no-break space before the dot: a wrapped line never starts with «·». VoiceOver hears
        // commas instead, as in every other sentence it reads (2026-11-18): the dot came out as
        // «punto medio» or an odd pause.
        let separator = spoken ? ", " : "\u{00A0}· "
        return shown.isEmpty ? nil : shown.joined(separator: separator)
    }

    /// «¿Repetida?», which the line draws as a warning.
    private static var repeatedTag: String { String(localized: "¿Repetida?") }

    private var card: String? { expense.card.flatMap { $0.isEmpty ? nil : $0 } }

    /// The line under the name, the way of paying last as its own icon (a little card, filled)
    /// in its own color, and brass dots between the parts, like the rest of the ticket. The
    /// icon replaced the short name («Amex») at the owner's request (2026-10-31); VoiceOver
    /// still reads the name.
    private var metaLine: Text? {
        let parts = (meta(withCard: false)?.components(separatedBy: "\u{00A0}· ") ?? []).map { part in
            // «¿Repetida?» asks for a look: the warning mark in front, its words in ink.
            part == Self.repeatedTag ? WarningText.inline(part) : Text(part)
        }
        let dot = Text("\u{00A0}·").foregroundStyle(Theme.brass)
        guard let card else {
            guard let first = parts.first else { return nil }
            return joined(parts.dropFirst(), after: first, dot: dot)
        }
        let icon = catalog.sourceIcon(for: card)
        let filled = UIImage(systemName: icon + ".fill") == nil ? icon : icon + ".fill"
        let mark = Text(Image(systemName: filled))
            .foregroundStyle(isUncounted ? Theme.muted : catalog.colors.source(card))
        guard let first = parts.first else { return mark }
        let line = joined(parts.dropFirst(), after: first, dot: dot)
        // With the largest text the card's icon stays on the line of the word before it: alone
        // on a line of its own it read as a stray (iPhone SE, 2026-11-18).
        let gap = typeSize.isAccessibilitySize ? "\u{00A0}" : " "
        return Text("\(line)\(dot)\(gap)\(mark)")
    }

    /// The parts after `first`, each after a brass dot. A no-break space before the dot: a
    /// wrapped line never starts with «·».
    private func joined(_ rest: ArraySlice<Text>, after first: Text, dot: Text) -> Text {
        rest.reduce(first) { line, part in Text("\(line)\(dot) \(part)") }
    }

    @ViewBuilder private var metaText: some View {
        if let line = metaLine {
            ExpenseMetaText(line)
                .accessibilityLabel(meta(spoken: true) ?? "")
        }
    }

    private var amountText: some View {
        let amount = ledgerAmount(for: expense, primary: primaryCurrency)
        // Said with the currency's name in English: «$» alone is read «dollars» (2026-11-19).
        let said = spokenLedgerAmount(for: expense, primary: primaryCurrency)
        return Text(amount)
            .font(.ticket(.body))
            .strikethrough(isUncounted, color: Theme.muted)
            .foregroundStyle(isUncounted ? Theme.muted : isRefund ? Theme.brass : Theme.ink)
            .lineLimit(1)
            // Whole beside the name. Under it, with the largest text, it may shrink instead
            // (2026-11-18): «USD 1,234.50» at AX5 ran off an iPhone SE's right edge, uncut.
            .minimumScaleFactor(Theme.MinimumScale.figure)
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
            .accessibilityLabel(isUncounted ? String(localized: "\(said), no cuenta para el presupuesto") : said)
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
                           card: "BBVA", date: AppClock.now.addingTimeInterval(-86_400 * 4), category: "Despensa"))
    context.insert(Expense(amount: 1234.5, currencyMarker: "$", merchant: "Liverpool",
                           card: "BBVA", date: AppClock.now.addingTimeInterval(-86_400 * 3), category: "Ropa"))
    context.insert(Expense(amount: -230, currencyMarker: "$", merchant: "Liverpool",
                           date: AppClock.now.addingTimeInterval(-86_400), category: "Ropa"))
    context.insert(Expense(amount: 24.99, currencyMarker: "USD", merchant: "Steam", card: "BBVA"))
    return ExpenseListView().modelContainer(container).ticketPreview()
}

/// What «Anotar otra vez» wrote down, while its «Deshacer» is on screen.
struct CopiedExpense: Identifiable {
    let id = UUID()
    let expense: Expense
    let name: String
    /// Said with its date: from a past month or a search the copy, dated today, lands out of
    /// sight, and the list looked the same as before (2026-11-18). The person tapped again.
    var dated = false

    var text: String {
        let name = name
        if dated { return String(localized: "Anotaste otra vez \(name) con fecha de hoy") }
        return String(localized: "Anotaste otra vez \(name)")
    }

    var spoken: String {
        let name = name
        if dated { return String(localized: "Anotaste otra vez \(name) con fecha de hoy. Puedes deshacerlo.") }
        return String(localized: "Anotaste otra vez \(name). Puedes deshacerlo.")
    }
}

/// Where the undo bar sits and how it comes and goes: right above the bottom bar, said out loud,
/// gone after a few seconds (longer with VoiceOver). Slides up, or only fades with «Reducir
/// movimiento».
private struct UndoBarPlacement: ViewModifier {
    let id: UUID
    let spoken: String
    let reduceMotion: Bool
    let expire: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    /// The app is in front. The countdown runs only then (2026-11-18): the clock kept going in
    /// the background, and coming back after a few seconds the bar was already gone, unseen,
    /// with a delete that could no longer be undone.
    @State private var inFront = true
    /// Each return to the app starts the countdown over, said again.
    @State private var round = 0

    private struct Countdown: Hashable {
        let id: UUID
        let round: Int
    }

    /// Longer with VoiceOver, and with the largest text, which is slower to read (2026-11-18).
    private var seconds: Double {
        UIAccessibility.isVoiceOverRunning || typeSize.isAccessibilitySize
            ? Theme.Motion.undoLongSeconds : Theme.Motion.undoSeconds
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Space.screen)
            // Right above the bottom bar: the safe area already ends at the bar.
            .padding(.bottom, Theme.Space.m)
            // Read before the list under it, not after its last row (2026-11-18).
            .accessibilitySortPriority(1)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .onChange(of: scenePhase) { _, phase in
                let front = phase == .active
                guard front != inFront else { return }
                inFront = front
                round += 1
            }
            .task(id: Countdown(id: id, round: round)) {
                // Away: waits, with the bar still there, until the app is in front again.
                guard inFront else { return }
                let total = seconds
                // A delete from the expense's sheet comes as the sheet closes, and VoiceOver's
                // own word for the screen changing cut the announcement short: said once the
                // sheet is gone (2026-11-18).
                let wait = UIAccessibility.isVoiceOverRunning ? Theme.Motion.undoAnnounceDelay : 0
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                AccessibilityNotification.Announcement(spoken).post()
                try? await Task.sleep(for: .seconds(total - wait))
                guard !Task.isCancelled else { return }
                withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) { expire() }
            }
    }
}

/// "Borraste Oxxo · Deshacer", for a few seconds after a delete (or «Anotaste otra vez»).
private struct UndoBar: View {
    let text: String
    var identifier = "deshacer-borrado"
    let undo: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    /// With the largest text «Deshacer» goes under the words, which wrap instead of being cut
    /// to «Bor…» (2026-11-18).
    private var stacked: Bool { typeSize.isAccessibilitySize }

    private var layout: AnyLayout {
        stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.none))
                : AnyLayout(HStackLayout(spacing: Theme.Space.m))
    }

    /// A capsule on one line; on two or more, the card's curve, so the corners don't cut the words.
    private var shape: AnyShape {
        stacked ? AnyShape(RoundedRectangle(cornerRadius: Theme.Radius.card)) : AnyShape(Capsule())
    }

    var body: some View {
        layout {
            Text(text)
                .font(.ticket(.detail))
                .foregroundStyle(Theme.ink)
                .lineLimit(stacked ? nil : 1)
                .fixedSize(horizontal: false, vertical: stacked)
            if !stacked { Spacer(minLength: Theme.Space.s) }
            Button(action: undo) { LinkActionLabel("Deshacer", fillsWidth: false) }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, stacked ? Theme.Space.sm : Theme.Space.none)
        .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
        .glassEffect(.regular, in: shape)
    }
}

/// «3 gastos», over the results while searching; says so when the words were read as a category.
private struct SearchHeaderRow: View {
    let count: Int
    /// Puts an example in the search field.
    let tryExample: (String) -> Void

    /// What the search understands, one tap each: it reads phrases, not just names, in Spanish
    /// and in English (2026-11-19: an iPhone in English offered them in Spanish).
    private let examples = [String(localized: "café"), String(localized: "uber de octubre"),
                            String(localized: "más de 500")]

    /// «5,000», like every other figure of the app (2026-11-18: it said «5000»).
    private var countText: String { count.formatted(.number.locale(ExpenseListView.mexico)) }

    /// «Sin resultados», «1 gasto», «12 gastos»: each a whole sentence for the catalog.
    private var title: String {
        if count == 0 { return String(localized: "Sin resultados") }
        if count == 1 { return String(localized: "1 gasto") }
        return String(localized: "\(countText) gastos")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel(title)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
                .accessibilityIdentifier("resultados-busqueda")
            if count == 0 {
                NoteText("Prueba con un comercio, un mes o un monto:")
                // They wrap to a new line with a large text size instead of running off.
                WrapLayout {
                    ForEach(examples, id: \.self) { example in
                        TicketChip(example) { tryExample(example) }
                    }
                }
            }
        }
    }
}

/// «Día 12 · 2 gastos · $310 — Quitar filtro ✕» (or «Ropa · 2 gastos») over the list while a
/// day or a category is picked. What informs is grey, like a section's caption; what is tapped
/// is brass, as in the rest of the app (owner, 2026-11-11: it was the other way round).
private struct FilterRow: View {
    let title: String
    let count: Int
    /// What they add up to, «$310»; `nil` with nothing to add.
    var total: String?
    let clear: () -> Void

    /// «Día 12 · 2 gastos · $310»: whole lines for the catalog.
    private var summary: String {
        let name = title
        let number = count
        if let total {
            if number == 1 { return String(localized: "\(name) · 1 gasto · \(total)") }
            return String(localized: "\(name) · \(number) gastos · \(total)")
        }
        if number == 1 { return String(localized: "\(name) · 1 gasto") }
        return String(localized: "\(name) · \(number) gastos")
    }

    var body: some View {
        // With accessibility type the way out goes under the summary instead of squeezing it.
        AdaptiveStack(spacing: Theme.Space.s, stackedSpacing: Theme.Space.none) {
            SectionLabel(summary, color: Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: clear) {
                Text("Quitar filtro \(Image(systemName: "xmark"))")
                    .font(.ticket(.footnoteStrong))
                    .foregroundStyle(Theme.brass)
            }
            .buttonStyle(.tapTarget)
            // The summary wraps before the way out does.
            .layoutPriority(1)
            .accessibilityLabel("Quitar filtro")
            // The name it had as «Ver todo el mes»: the tests know it by it.
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
    /// nothing); others ride apart. `spoken`: for VoiceOver, the currency by its name in English
    /// («230.00 Mexican pesos»), the same text in Spanish (2026-11-19).
    func total(in primary: String, spoken: Bool = false) -> String? {
        let mine = items.filter { CurrencyResolver.isoCode(for: $0.currencyMarker, primary: primary) == primary }
        // A day only in other money still says how much: «USD 24.99».
        guard !mine.isEmpty else {
            guard let first = items.first else { return nil }
            let code = CurrencyResolver.isoCode(for: first.currencyMarker, primary: primary)
            let same = items.filter { CurrencyResolver.isoCode(for: $0.currencyMarker, primary: primary) == code }
            let sum = same.reduce(Decimal(0)) { $0 + $1.counted }
            let number = plainAmount(sum.magnitude)
            let label = String((code ?? first.currencyMarker ?? "").prefix(4))
            let sign = sum < 0 ? "+" : ""
            if spoken, !saysMoneyAsWritten, let code {
                return sign + spokenMoney(sum.magnitude, isoCode: code, label: code)
            }
            return sign + (label.isEmpty ? number : "\(label) \(number)")
        }
        let sum = mine.reduce(Decimal(0)) { $0 + $1.counted }
        // Money that came back reads like the ledger's refunds: «+$230.00».
        let sign = sum < 0 ? "+" : ""
        if spoken { return sign + spokenMoney(sum.magnitude, isoCode: primary, label: primary) }
        return sign + formatMoney(sum.magnitude, isoCode: primary, label: primary)
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
    /// With one expense the day's total is that expense's amount, right under it: printed once,
    /// in its row (owner, 2026-11-11). VoiceOver still hears it with the day (`spoken`).
    private var showsTotal: Bool { group.items.count > 1 }
    private var spoken: String {
        [spokenLabel, group.total(in: primaryCurrency, spoken: true)].compactMap { $0 }.joined(separator: ", ")
    }

    /// The day as VoiceOver says it: «Hoy, 23 oct», with a comma and not the drawn «·»
    /// (2026-11-18). Any other day is already words only.
    private var spokenLabel: String {
        let calendar = Calendar.current
        let date = shortDate
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Hoy, \(date)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return String(localized: "Ayer, \(date)") }
        return label
    }

    /// «Hoy» or «Ayer» when the day is one of them.
    private var nearName: String? {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Hoy") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return String(localized: "Ayer", comment: "Hoy (main screen): day header in the list with the largest text, on its own line over the date: the day before today")
        }
        return nil
    }

    /// «23 oct», after «Hoy» or «Ayer».
    private var shortDate: String {
        day.formatted(.dateTime.day().month(.abbreviated).locale(Locale.current))
    }

    private var label: String {
        let calendar = Calendar.current
        let date = shortDate
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Hoy · \(date)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return String(localized: "Ayer · \(date)") }
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            .locale(Locale.current)
        // Another year says which (a search over every month, 2026-11-18): two «vie 17 oct»
        // could be years apart.
        guard calendar.isDate(day, equalTo: now, toGranularity: .year) else { return day.formatted(style.year()) }
        return day.formatted(style)
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var tick: some View {
        Capsule().fill(Theme.brass)
            .frame(width: Theme.Size.dayTick.width, height: Theme.Size.dayTick.height)
    }

    private var dayText: some View { dayWords(label) }

    private func dayWords(_ words: String) -> some View {
        Text(words)
            .font(.ticket(.microStrong))
            .tracking(Theme.Tracking.action)
            .textCase(.uppercase)
            .foregroundStyle(Theme.brass)
    }

    @ViewBuilder private var totalText: some View {
        if showsTotal, let total {
            Text(total)
                .font(.ticket(.micro))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
        }
    }

    /// With the largest text: the day on one line while it fits; if not, «Hoy» over «20 nov»
    /// without the dot, which hung alone at the end of the first line (iPhone SE, 2026-11-18).
    /// Any other day just wraps between its words.
    @ViewBuilder private var stackedDay: some View {
        if let nearName {
            ViewThatFits(in: .horizontal) {
                dayText.lineLimit(1)
                VStack(alignment: .leading, spacing: Theme.Space.none) {
                    dayWords(nearName)
                    dayWords(shortDate)
                }
            }
        } else {
            dayText.fixedSize(horizontal: false, vertical: true)
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
                        stackedDay
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("divisor-dia")
    }
}
