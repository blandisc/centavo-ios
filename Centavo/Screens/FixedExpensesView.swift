import CentavoCore
import SwiftData
import SwiftUI

/// «··· › Gastos fijos»: what comes back on its own (rent on the 1st, the cleaning every
/// Monday, Netflix on the 15th), when it comes next, and what this month still has coming,
/// which «Hoy puedes gastar» already sets apart.
struct FixedExpensesView: View {
    @Environment(\.dismiss) private var dismiss
    /// With VoiceOver the swipe is in its actions: the footer says so (2026-11-19).
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Expense> { $0.repeatsMonthly == true }) private var originals: [Expense]
    @Query(filter: #Predicate<Expense> { $0.isRepeat == true }) private var copies: [Expense]
    @AppStorage(FixedPlan.key) private var storedPlans = ""
    @AppStorage(CurrencyPreference.key) private var storedCurrency = ""
    @AppStorage(BudgetStore.key) private var storedBudget = ""
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @AppStorage(UserCatalog.categoryColorsKey) private var storedCategoryColors = ""
    /// The new fixed expense being written, with the name of a suggestion if one was tapped.
    @State private var adding: NewFixed?
    @State private var editing: Expense?
    /// A fixed expense still to start, opened to change it.
    @State private var editingPlan: FixedPlan?
    /// A fixed expense about to stop or be deleted, waiting for the answer.
    @State private var confirming: FixedItem?
    @State private var saveProblem: SaveProblem?

    private var primary: String { CurrencyPreference.resolve(storedCurrency) }
    /// Without a budget there is no «Hoy puedes gastar» to set anything apart from (2026-11-18).
    private var hasBudget: Bool { BudgetStore.amount(from: storedBudget) != nil }

    private var explainerText: String {
        if hasBudget {
            return String(localized: "La renta, la luz, tus suscripciones. Anótalos una vez: Al día los registra solos el día que toca y desde hoy los aparta de lo que puedes gastar.")
        }
        return String(localized: "La renta, la luz, tus suscripciones. Anótalos una vez: Al día los registra solos el día que toca.")
    }

    /// Under the month's bar: what is set apart, or what a budget would do.
    private var setApartNote: String? {
        guard hasBudget else { return String(localized: "Con un presupuesto, Al día aparta lo que falta de tus fijos.") }
        guard coming > 0 else { return nil }
        return String(localized: "Lo que está por venir ya se apartó de «Hoy puedes gastar».")
    }

    /// Over the suggestions: none yet, or some already there.
    private var suggestionsHeader: String {
        if items.isEmpty { return String(localized: "Empieza con uno") }
        return String(localized: "¿Te falta alguno?")
    }
    private var items: [FixedItem] { FixedOutlook.items(originals: originals, plans: FixedPlan.decode(storedPlans)) }

    private func money(_ amount: Decimal, _ currency: String) -> String {
        let iso = CurrencyResolver.isoCode(for: currency, primary: primary)
        return formatMoney(amount, isoCode: iso, label: currency, main: primary)
    }

    /// What already arrived this month, in the main currency.
    private var arrived: Decimal {
        (originals + copies)
            .filter { MonthNavigator.isSameMonth($0.date, as: AppClock.now) && $0.date <= AppClock.now }
            .filter { CurrencyResolver.isoCode(for: $0.currencyMarker, primary: primary) == primary }
            .reduce(Decimal(0)) { $0 + $1.counted }
    }

    private var coming: Decimal {
        FixedOutlook.reserved(originals: originals, plans: FixedPlan.decode(storedPlans), primary: primary)
    }

    private struct NewFixed: Identifiable {
        let name: String
        var id: String { name }
    }

    /// A common fixed expense offered with one tap: `id` names it for the tests in any
    /// language, `name` is what is shown and written.
    private struct Suggestion: Hashable {
        let id: String
        let name: String
    }

    /// Common fixed expenses, one tap each, not already there.
    private var suggestions: [Suggestion] {
        Self.commonFixed.filter { suggestion in !items.contains { UserCatalog.same($0.name, suggestion.name) } }
    }

    private static var commonFixed: [Suggestion] {
        [Suggestion(id: "Renta", name: String(localized: "Renta")),
         Suggestion(id: "Luz", name: String(localized: "Luz")),
         Suggestion(id: "Internet", name: "Internet"),
         Suggestion(id: "Celular", name: String(localized: "Celular")),
         Suggestion(id: "Netflix", name: "Netflix"),
         Suggestion(id: "Spotify", name: "Spotify"),
         Suggestion(id: "Gimnasio", name: String(localized: "Gimnasio")),
         Suggestion(id: "Agua", name: String(localized: "Agua")),
         Suggestion(id: "Gas", name: String(localized: "Gas"))]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // The system's own row insets: on the line of the section headers and the
                    // rows' text on every iPhone (16 or 20 pt, depending on its width).
                    explainer
                        .listRowBackground(Color.clear)
                }

                if !items.isEmpty {
                    Section {
                        monthSummary
                    } header: {
                        Text("Este mes").ticketCaption()
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    ForEach(items) { item in
                        Button { open(item) } label: { row(item) }
                            .buttonStyle(.plain)
                            // No role: a destructive swipe would take the row out before the question.
                            .swipeActions(edge: .trailing) {
                                if item.original != nil {
                                    Button("Dejar de repetir", systemImage: "stop.circle") { confirming = item }
                                        .tint(Theme.danger)
                                } else if item.plan != nil {
                                    Button("Borrar", systemImage: "trash") { confirming = item }
                                        .tint(Theme.danger)
                                }
                            }
                    }
                    Button { adding = NewFixed(name: "") } label: {
                        LinkActionLabel("Agregar gasto fijo", systemImage: "plus", alignment: .leading)
                    }
                    .accessibilityIdentifier("agregar-fijo")
                } header: {
                    Text("Tus gastos fijos").ticketCaption()
                } footer: {
                    if !items.isEmpty, voiceOver {
                        HintText("Toca uno para cambiarlo. Para que deje de repetirse, usa las acciones de VoiceOver; lo ya anotado se queda.")
                    } else if !items.isEmpty {
                        HintText("Toca uno para cambiarlo. Desliza a la izquierda para que deje de repetirse; lo ya anotado se queda.")
                    }
                }
                .listRowBackground(Theme.surface)

                if !suggestions.isEmpty {
                    Section {
                        suggestionChips
                            .listRowBackground(Color.clear)
                    } header: {
                        Text(suggestionsHeader).ticketCaption()
                    }
                }
            }
            .ticketForm()
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Gastos fijos")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .font(.ticket(.footnoteStrong))
                        .accessibilityIdentifier("hoja-listo")
                }
            }
            .confirmsRemoval(of: $confirming, question: removalQuestion) { item in
                if let original = item.original {
                    stop(original)
                } else if let plan = item.plan {
                    remove(plan)
                }
            }
            .problemAlert(problem: $saveProblem)
            .sheet(item: $adding) { FixedPlanSheet(initialName: $0.name) }
            .sheet(item: $editing) { ExpenseEditorView(expense: $0) }
            .sheet(item: $editingPlan) { FixedPlanSheet(editing: $0) }
            .onAppear { _ = try? RecurringExpenses.logDue(in: context) }
        }
    }

    /// The same row as the month's list: the category's tile, the name, the amount, and under
    /// it how it repeats and when it comes next (ink while it is still to come this month; it only informs, so never brass).
    private func row(_ item: FixedItem) -> some View {
        let category = (item.original?.category ?? item.plan?.category).flatMap { $0.isEmpty ? nil : $0 }
        let colors = CatalogColors(categories: storedCategoryColors, sources: "")
        let tile = CategoryIconTile(
            icon: category.map { CategoryStyle.icon(for: $0, custom: UserCatalog.decode(storedCategories)) } ?? "repeat",
            color: category.map(colors.category), background: Theme.raised)
        // The app's own names in the iPhone's language; stored in Spanish (2026-11-18).
        let shownCategory: String? = category.map { CategoryStyle.shown($0) }
        let meta: String = [shownCategory, item.ruleText].compactMap { $0 }.joined(separator: " · ")
        let name: String = item.name
        let nextLine: String? = item.next.map { nextText($0, starts: item.original == nil) }
        return ExpenseRowLayout(name: name, tile: tile) {
            VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                ExpenseMetaText(meta)
                if let nextLine {
                    Text(nextLine)
                        .font(.ticket(.hint))
                        .foregroundStyle(item.coming.isEmpty ? Theme.muted : Theme.ink)
                }
            }
        } amount: {
            Text(money(item.amount, item.currency))
                .font(.ticket(.body))
                .foregroundStyle(Theme.ink)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    /// «Próximo: lun 3 nov», or «Empieza: …» for one still to start.
    private func nextText(_ next: Date, starts: Bool) -> String {
        let day = next.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale.current))
        if starts { return String(localized: "Empieza: \(day)") }
        return String(localized: "Próximo: \(day)")
    }

    /// What «Dejar de repetir» or «Borrar» asks first.
    private func removalQuestion(_ item: FixedItem) -> TicketQuestion {
        let figure = money(item.amount, item.currency)
        if item.original != nil {
            return TicketQuestion(title: String(localized: "¿Dejar de repetir este gasto fijo?"),
                                  figure: figure, name: item.name, detail: item.ruleText,
                                  note: String(localized: "Lo ya anotado se queda; los siguientes ya no llegan."),
                                  verb: String(localized: "Dejar de repetir"))
        }
        return TicketQuestion(title: String(localized: "¿Borrar este gasto fijo?"),
                              figure: figure, name: item.name, detail: item.ruleText,
                              note: String(localized: "Todavía no se anota nada; ya no empezará."),
                              verb: String(localized: "Borrar"))
    }

    /// What the screen is for, said once at the top: a new person did not know (owner, 2026-10-29).
    private var explainer: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            StepEmblem(systemImage: "repeat")
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Lo que pagas siempre")
                    .font(.ticket(.headline))
                    .foregroundStyle(Theme.ink)
                Text(explainerText)
                    .font(.ticket(.footnote))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }

    /// The month's fixed expenses as one bar: what already came (brass) and what is still to
    /// come (dotted), the part «Hoy puedes gastar» already sets apart.
    private var monthSummary: some View {
        let total = arrived + coming
        let share = total > 0 ? NSDecimalNumber(decimal: arrived / total).doubleValue : 0
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(money(total, primary))
                    .font(.ticket(.heading))
                    .foregroundStyle(Theme.ink)
                Text("en fijos")
                    .font(.ticket(.footnote))
                    .foregroundStyle(Theme.muted)
            }
            GeometryReader { proxy in
                HStack(spacing: Theme.Space.xxxs) {
                    RoundedRectangle(cornerRadius: Theme.Radius.tile)
                        .fill(Theme.brass)
                        .frame(width: proxy.size.width * share)
                    RoundedRectangle(cornerRadius: Theme.Radius.tile)
                        .strokeBorder(Theme.brassLow, style: StrokeStyle(lineWidth: Theme.Stroke.emphasis,
                                                                         dash: Theme.Dash.dotted))
                }
            }
            .frame(height: Theme.Size.legendDot)
            .accessibilityHidden(true)
            HStack {
                summaryFigure("Ya cobrado", money(arrived, primary))
                Spacer()
                summaryFigure("Por venir", money(coming, primary), trailing: true)
            }
            if let setApartNote {
                NoteText(setApartNote, color: Theme.faint)
            }
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fijos-resumen")
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                ForEach(suggestions, id: \.self) { suggestion in
                    TicketChip(suggestion.name, systemImage: "plus", identifier: "sugerencia-fijo-\(suggestion.id)") {
                        adding = NewFixed(name: suggestion.name)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        // The first chip on the headers' line (the row's own inset); they scroll to the edge.
        .scrollClipDisabled()
    }

    private func summaryFigure(_ label: LocalizedStringResource, _ amount: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: Theme.Space.xxxs) {
            Text(label).ticketKey()
            Text(amount)
                .font(.ticket(.headline))
                .foregroundStyle(Theme.ink)
        }
    }

    /// One already running opens as an expense; one still to start, in its own sheet.
    private func open(_ item: FixedItem) {
        if let original = item.original {
            editing = original
        } else if let plan = item.plan {
            editingPlan = plan
        }
    }

    /// What is already logged stays, the original still as a fixed charge; only what is to come stops.
    private func stop(_ original: Expense) {
        RecurringExpenses.stopRepeating(original)
        do { try context.save() } catch {
            context.rollback()
            saveProblem = SaveProblem(title: "No se dejó de repetir")
        }
    }

    private func remove(_ plan: FixedPlan) {
        FixedPlan.save(FixedPlan.decode(storedPlans).filter { $0.id != plan.id })
    }
}

/// «Agregar gasto fijo»: how much, what it is, how often and when it first comes. A first
/// charge that already came is logged now (with its date), and the ones after it that also
/// came; one still to come waits for its day. Category and card are optional: the category
/// starts as the one suggested for the name, like a new expense.
struct FixedPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @AppStorage(UserCatalog.hiddenCategoriesKey) private var storedHidden = ""
    @AppStorage(UserCatalog.sourcesKey) private var storedSources = ""
    @State private var amountText = ""
    @State private var problem: SaveProblem?
    @State private var merchant = ""
    @State private var rule = RepeatRule.monthly
    @State private var firstDay = AppClock.now
    @State private var category = ""
    /// Once a category is picked by hand, the name no longer changes it.
    @State private var pickedCategory = false
    @State private var card = ""
    /// «Cancelar» or a swipe down with something changed: «¿Descartar cambios?».
    @State private var askingDiscard = false
    /// Read once when the sheet opens, not a live query of every expense.
    @State private var pastExpenses: [CategorizedExpense] = []
    @State private var knownCategories: [String] = []
    @State private var knownCards: [String] = []
    @FocusState private var amountFocused: Bool
    /// The decimal pad has no return key: «Siguiente» beside the amount comes here (2026-11-18).
    @FocusState private var nameFocused: Bool

    /// `initialName`: a suggestion tapped on «Gastos fijos» («Renta»), already written.
    init(initialName: String = "") {
        self.initialName = initialName
        editing = nil
        _merchant = State(initialValue: initialName)
    }

    /// One still to start, to change: saving replaces it (same id), or starts it if its first
    /// charge is now today or before.
    init(editing plan: FixedPlan) {
        initialName = plan.merchant
        editing = plan
        _merchant = State(initialValue: plan.merchant)
        _amountText = State(initialValue: plan.amount)
        _rule = State(initialValue: plan.repeatRule)
        _firstDay = State(initialValue: plan.firstDate)
        _category = State(initialValue: plan.category ?? "")
        // Its category was already chosen: the name no longer changes it.
        _pickedCategory = State(initialValue: plan.category != nil)
        _card = State(initialValue: plan.card ?? "")
    }
    private let initialName: String
    private let editing: FixedPlan?

    /// Something typed or picked: «Cancelar» or a swipe down ask before throwing it away.
    private var hasChanges: Bool {
        if let editing {
            return amountText != editing.amount || merchant != editing.merchant || card != (editing.card ?? "")
                || category != (editing.category ?? "") || rule != editing.repeatRule || firstDay != editing.firstDate
        }
        return !amountText.isEmpty || merchant != initialName || !card.isEmpty || pickedCategory
    }

    private var currency: String { editing?.currency ?? CurrencyPreference.current }

    private var customCategories: [LabeledIcon] { UserCatalog.decode(storedCategories) }
    private var sources: [LabeledIcon] { UserCatalog.decode(storedSources) }

    /// The same categories the expense sheet offers.
    private var categories: [String] {
        CategoryStyle.offered(known: Array(knownCategories.prefix(8)), custom: customCategories,
                              current: category, hidden: UserCatalog.decodeNames(storedHidden))
    }

    private var categoryChoice: Binding<String> {
        Binding(get: { category }, set: { category = $0; pickedCategory = true })
    }

    private var amount: Decimal? {
        guard let value = AmountParser.parseTyped(amountText)?.value, value > 0 else { return nil }
        return value
    }

    private var name: String { merchant.trimmingCharacters(in: .whitespaces) }
    /// What the save bar says: what is missing, or «Renta · Cada mes, el día 1».
    private var saveSummary: String {
        if amount == nil { return String(localized: "Falta el monto") }
        if name.isEmpty { return String(localized: "Falta qué es") }
        let repeats = FixedWording.howItRepeats(rule, from: firstDate).components(separatedBy: ":").first ?? ""
        return "\(name) · \(repeats)"
    }

    /// The first charge's moment: 9:00 of the day picked, like the welcome's fixed expenses.
    private var firstDate: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: firstDay) ?? firstDay
    }

    /// What happens with the first charge. A quincena's is logged on its own date even when
    /// that is not the 15th nor the last day: said so, not found later as a charge of more
    /// (2026-11-18).
    private var firstChargeNote: String {
        let quincena = rule.kind == .semimonthly
        if firstDate > AppClock.now {
            if quincena {
                return String(localized: "Hasta su primer cobro no se anota nada. Ese día se anota, aunque no sea día 15 ni último.")
            }
            return String(localized: "Hasta su primer cobro no se anota nada.")
        }
        if quincena {
            return String(localized: "El primer cobro ya llegó: se anota con su fecha, aunque no sea día 15 ni último, y los que hayan llegado después.")
        }
        return String(localized: "El primer cobro ya llegó: se anota con su fecha, y los que hayan llegado después.")
    }

    /// What the category menu shows: the one picked, or that none is.
    private var categoryValue: String {
        if category.isEmpty { return String(localized: "Sin categoría") }
        return CategoryStyle.shown(category)
    }

    private var cardValue: String {
        if card.isEmpty { return String(localized: "Sin especificar") }
        return CategoryStyle.shown(card)
    }

    /// A new fixed expense, or one still to start being changed.
    private var barTitle: LocalizedStringResource {
        if editing == nil { return "Nuevo gasto fijo" }
        return "Gasto fijo"
    }

    private var latest: Date { Calendar.current.date(byAdding: .year, value: 1, to: AppClock.now) ?? AppClock.now }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Theme.Space.s) {
                        AmountInputField("Monto", text: $amountText, prompt: "0.00", identifier: "fijo-monto")
                            .focused($amountFocused)
                        NextKey(visible: amountFocused, identifier: "fijo-siguiente") { nameFocused = true }
                    }
                } header: {
                    Text("Monto (\(currency))").ticketCaption()
                }
                .listRowBackground(Theme.surface)

                Section {
                    TextField("Qué es", text: $merchant,
                              prompt: Text("Renta, limpieza, Netflix…").foregroundStyle(Theme.faint))
                        .ticketField()
                        .textInputAutocapitalization(.sentences)
                        // Names like «Netflix» or «Totalplay» are not in the dictionary (2026-11-18).
                        .autocorrectionDisabled()
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .accessibilityIdentifier("fijo-nombre")
                } header: {
                    Text("Qué es").ticketCaption()
                }
                .listRowBackground(Theme.surface)

                Section {
                    TicketMenuPicker("Categoría", selection: categoryChoice, value: categoryValue) {
                        Text("Sin categoría").tag("")
                        ForEach(categories, id: \.self) { name in
                            Label(CategoryStyle.shown(name), systemImage: CategoryStyle.icon(for: name, custom: customCategories))
                                .tag(name)
                        }
                    }
                    .accessibilityIdentifier("fijo-categoria")
                    TicketMenuPicker("Forma de pago", selection: $card, value: cardValue) {
                        Text("Sin especificar").tag("")
                        ForEach(PaymentChoices.names(sources: sources, known: knownCards, current: card),
                                id: \.self) { name in
                            Label(CategoryStyle.shown(name), systemImage: PaymentChoices.icon(for: name, sources: sources))
                                .tag(name)
                        }
                    }
                    .accessibilityIdentifier("fijo-tarjeta")
                } header: {
                    Text("Opcional").ticketCaption()
                } footer: {
                    HintText("Cada cobro llega con esta categoría y esta forma de pago.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    RepeatRulePicker(rule: $rule)
                    DatePicker(selection: $firstDay, in: ...latest, displayedComponents: .date) {
                        SectionLabel("Primer cobro")
                    }
                    .accessibilityIdentifier("fijo-primer-cobro")
                } header: {
                    Text("Cada cuándo").ticketCaption()
                } footer: {
                    HintText("\(FixedWording.howItRepeats(rule, from: firstDate)) \(firstChargeNote)")
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .scrollDismissesKeyboard(.immediately)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle(barTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        if hasChanges { askingDiscard = true } else { dismiss() }
                    }
                    .font(.ticket(.footnote))
                    .accessibilityIdentifier("hoja-cancelar")
                }
            }
            .saveBar(saveSummary,
                     enabled: amount != nil && !name.isEmpty, action: save)
            .onAppear(perform: load)
            .problemAlert(problem: $problem)
            .onChange(of: merchant) { _, new in
                guard !pickedCategory else { return }
                category = CategoryMemory.suggestion(for: new.trimmingCharacters(in: .whitespaces),
                                                     rules: UserCatalog.categoryRules, history: pastExpenses,
                                                     hidden: UserCatalog.notAutoAssigned) ?? ""
            }
        }
        .confirmsDiscard(hasChanges: hasChanges, isAsking: $askingDiscard) { dismiss() }
    }

    private func load() {
        let history = (try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        pastExpenses = history.map(\.categorized)
        knownCategories = CategoryMemory.known(in: pastExpenses)
        knownCards = PaymentChoices.mostUsedCards(history.prefix(300).map(\.card))
        amountFocused = editing == nil
    }

    private func save() {
        guard let amount else { return }
        // Started meanwhile (its day came, or another device started it): it is no longer a
        // plan, and saving would make a second one (independent review, 2026-11-02).
        if let editing, !FixedPlan.saved.contains(where: { $0.id == editing.id }) {
            problem = SaveProblem(title: "No se guardó el gasto fijo",
                                  detail: String(localized: "Ya empezó mientras lo cambiabas. Ciérralo y ábrelo otra vez en «Gastos fijos» para cambiarlo."))
            return
        }
        let categoryName = category.trimmingCharacters(in: .whitespaces)
        let cardName = card.trimmingCharacters(in: .whitespaces)
        var plan = FixedPlan(
            merchant: String(name.prefix(ExpenseRecorder.maxMerchantLength)),
            amount: "\(amount)",
            currency: currency,
            category: categoryName.isEmpty ? nil : categoryName,
            card: cardName.isEmpty ? nil : cardName,
            rule: rule.stored,
            firstDate: firstDate
        )
        if let editing {
            plan.id = editing.id
            // The day asked for («31») holds while the date is the same.
            if firstDay == editing.firstDate { plan.firstDate = editing.firstDate; plan.day = editing.day }
        }
        let others = FixedPlan.saved.filter { $0.id != editing?.id }
        // Picked by hand: the next expense from here starts with it too. Editing one, only if
        // it was changed (it opens already picked).
        let chosen = editing.map { !UserCatalog.same(categoryName, $0.category ?? "") } ?? pickedCategory
        if chosen, !categoryName.isEmpty { UserCatalog.learnCategory(categoryName, for: plan.merchant) }
        if plan.firstDate <= AppClock.now {
            context.insert(RecurringExpenses.original(from: plan))
            do {
                try context.save()
            } catch {
                context.rollback()
                problem = SaveProblem(title: "No se guardó el gasto fijo")
                return
            }
            // It started: it is no longer a plan.
            if editing != nil { FixedPlan.save(others) }
            _ = try? RecurringExpenses.logDue(in: context)
        } else if let editing {
            FixedPlan.save(FixedPlan.saved.map { $0.id == editing.id ? plan : $0 })
        } else {
            FixedPlan.save(others + [plan])
        }
        dismiss()
    }
}
