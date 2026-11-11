import CentavoCore
import SwiftData
import SwiftUI

/// «Más › Gastos fijos»: what comes back on its own (rent on the 1st, the cleaning every
/// Monday, Netflix on the 15th), when it comes next, and what this month still has coming,
/// which «Hoy puedes gastar» already sets apart.
struct FixedExpensesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Expense> { $0.repeatsMonthly == true }) private var originals: [Expense]
    @Query(filter: #Predicate<Expense> { $0.isRepeat == true }) private var copies: [Expense]
    @AppStorage(FixedPlan.key) private var storedPlans = ""
    @AppStorage(CurrencyPreference.key) private var storedCurrency = ""
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @AppStorage(UserCatalog.categoryColorsKey) private var storedCategoryColors = ""
    /// The new fixed expense being written, with the name of a suggestion if one was tapped.
    @State private var adding: NewFixed?
    @State private var editing: Expense?
    /// A fixed expense still to start, opened to change it.
    @State private var editingPlan: FixedPlan?
    /// A fixed expense about to stop or be deleted, waiting for the answer.
    @State private var confirming: FixedItem?
    @State private var saveProblem: String?

    private var primary: String { CurrencyPreference.resolve(storedCurrency) }
    private var items: [FixedItem] { FixedOutlook.items(originals: originals, plans: FixedPlan.decode(storedPlans)) }

    private func money(_ amount: Decimal, _ currency: String) -> String {
        let iso = CurrencyResolver.isoCode(for: currency, primary: primary)
        return formatMoney(amount, isoCode: iso, label: currency)
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

    /// Common fixed expenses, one tap each, not already there.
    private var suggestions: [String] {
        ["Renta", "Luz", "Internet", "Celular", "Netflix", "Spotify", "Gimnasio", "Agua", "Gas"]
            .filter { name in !items.contains { UserCatalog.same($0.name, name) } }
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
                    if !items.isEmpty {
                        HintText("Toca uno para cambiarlo. Desliza a la izquierda para que deje de repetirse; lo ya anotado se queda.")
                    }
                }
                .listRowBackground(Theme.surface)

                if !suggestions.isEmpty {
                    Section {
                        suggestionChips
                            .listRowBackground(Color.clear)
                    } header: {
                        Text(items.isEmpty ? "Empieza con uno" : "¿Te falta alguno?").ticketCaption()
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
            .confirmsRemoval(of: $confirming, question: { item in
                let running = item.original != nil
                return TicketQuestion(title: running ? "¿Dejar de repetir este gasto fijo?" : "¿Borrar este gasto fijo?",
                                      figure: money(item.amount, item.currency),
                                      name: item.name,
                                      detail: item.ruleText,
                                      note: running ? "Lo ya anotado se queda; los siguientes ya no llegan."
                                        : "Todavía no se anota nada; ya no empezará.",
                                      verb: running ? "Dejar de repetir" : "Borrar")
            }) { item in
                if let original = item.original {
                    stop(original)
                } else if let plan = item.plan {
                    remove(plan)
                }
            }
            .alert("No se guardó", isPresented: Binding(get: { saveProblem != nil }, set: { if !$0 { saveProblem = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: { Text(saveProblem ?? "") }
            .sheet(item: $adding) { FixedPlanSheet(initialName: $0.name) }
            .sheet(item: $editing) { ExpenseEditorView(expense: $0) }
            .sheet(item: $editingPlan) { FixedPlanSheet(editing: $0) }
            .onAppear { try? RecurringExpenses.logDue(in: context) }
        }
    }

    /// The same row as the month's list: the category's tile, the name, the amount, and under
    /// it how it repeats and when it comes next (brass while it is still to come this month).
    private func row(_ item: FixedItem) -> some View {
        let category = (item.original?.category ?? item.plan?.category).flatMap { $0.isEmpty ? nil : $0 }
        let colors = CatalogColors(categories: storedCategoryColors, sources: "")
        let tile = CategoryIconTile(
            icon: category.map { CategoryStyle.icon(for: $0, custom: UserCatalog.decode(storedCategories)) } ?? "repeat",
            color: category.map(colors.category), background: Theme.raised)
        return ExpenseRowLayout(name: item.name, tile: tile) {
            VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                ExpenseMetaText(([category, item.ruleText].compactMap { $0 }).joined(separator: " · "))
                if let next = item.next {
                    Text((item.original == nil ? "Empieza: " : "Próximo: ")
                         + next.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)
                            .locale(Locale(identifier: "es_MX"))))
                        .font(.ticket(.hint))
                        .foregroundStyle(item.coming.isEmpty ? Theme.muted : Theme.brass)
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

    /// What the screen is for, said once at the top: a new person did not know (owner, 2026-10-29).
    private var explainer: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            StepEmblem(systemImage: "repeat")
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Lo que pagas siempre")
                    .font(.ticket(.headline))
                    .foregroundStyle(Theme.ink)
                Text("La renta, la luz, tus suscripciones. Anótalos una vez: Al día los registra solos el día que toca y desde hoy los aparta de lo que puedes gastar.")
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
                summaryFigure("Por venir", money(coming, primary), brass: true)
            }
            NoteText("Lo que está por venir ya se apartó de «Hoy puedes gastar».", color: Theme.faint)
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fijos-resumen")
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                ForEach(suggestions, id: \.self) { name in
                    TicketChip(name, systemImage: "plus", identifier: "sugerencia-fijo-\(name)") {
                        adding = NewFixed(name: name)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        // The first chip on the headers' line (the row's own inset); they scroll to the edge.
        .scrollClipDisabled()
    }

    private func summaryFigure(_ label: String, _ amount: String, brass: Bool = false) -> some View {
        VStack(alignment: brass ? .trailing : .leading, spacing: Theme.Space.xxxs) {
            Text(label).ticketKey()
            Text(amount)
                .font(.ticket(.headline))
                .foregroundStyle(brass ? Theme.brass : Theme.ink)
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
            saveProblem = "Al día no pudo dejar de repetirlo. Intenta otra vez."
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
    @State private var problem: String?
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
        guard let value = AmountParser.parse(amountText)?.value, value > 0 else { return nil }
        return value
    }

    private var name: String { merchant.trimmingCharacters(in: .whitespaces) }

    /// The first charge's moment: 9:00 of the day picked, like the welcome's fixed expenses.
    private var firstDate: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: firstDay) ?? firstDay
    }

    private var latest: Date { Calendar.current.date(byAdding: .year, value: 1, to: AppClock.now) ?? AppClock.now }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountInputField("Monto", text: $amountText, prompt: "0.00", identifier: "fijo-monto")
                        .focused($amountFocused)
                } header: {
                    Text("Monto (\(currency))").ticketCaption()
                }
                .listRowBackground(Theme.surface)

                Section {
                    TextField("Qué es", text: $merchant,
                              prompt: Text("Renta, limpieza, Netflix…").foregroundStyle(Theme.faint))
                        .font(.ticket(.field))
                        .foregroundStyle(Theme.ink)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("fijo-nombre")
                } header: {
                    Text("Qué es").ticketCaption()
                }
                .listRowBackground(Theme.surface)

                Section {
                    Picker(selection: categoryChoice) {
                        Text("Sin categoría").tag("")
                        ForEach(categories, id: \.self) { name in
                            Label(name, systemImage: CategoryStyle.icon(for: name, custom: customCategories)).tag(name)
                        }
                    } label: {
                        SectionLabel("Categoría")
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.brass)
                    .accessibilityIdentifier("fijo-categoria")
                    Picker(selection: $card) {
                        Text("Sin especificar").tag("")
                        ForEach(PaymentChoices.names(sources: sources, known: knownCards, current: card),
                                id: \.self) { name in
                            Label(name, systemImage: PaymentChoices.icon(for: name, sources: sources)).tag(name)
                        }
                    } label: {
                        SectionLabel("Forma de pago")
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.brass)
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
                    HintText(FixedWording.howItRepeats(rule, from: firstDate) + " "
                             + (firstDate > AppClock.now
                                ? "Hasta su primer cobro no se anota nada."
                                : "El primer cobro ya llegó: se anota con su fecha, y los que hayan llegado después."))
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .scrollDismissesKeyboard(.immediately)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle(editing == nil ? "Nuevo gasto fijo" : "Gasto fijo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        if hasChanges { askingDiscard = true } else { dismiss() }
                    }
                    .font(.ticket(.footnote))
                    .accessibilityIdentifier("hoja-cancelar")
                }
            }
            .saveBar(amount == nil ? "Falta el monto" : name.isEmpty ? "Falta qué es"
                        : "\(name) · " + FixedWording.howItRepeats(rule, from: firstDate).components(separatedBy: ":").first!,
                     enabled: amount != nil && !name.isEmpty, action: save)
            .onAppear(perform: load)
            .alert("No se guardó", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: { Text(problem ?? "") }
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
            problem = "Este gasto fijo ya empezó mientras lo cambiabas. Ciérralo y ábrelo otra vez en «Gastos fijos» para cambiarlo."
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
                problem = "Al día no pudo guardar el gasto fijo. Intenta otra vez."
                return
            }
            // It started: it is no longer a plan.
            if editing != nil { FixedPlan.save(others) }
            try? RecurringExpenses.logDue(in: context)
        } else if let editing {
            FixedPlan.save(FixedPlan.saved.map { $0.id == editing.id ? plan : $0 })
        } else {
            FixedPlan.save(others + [plan])
        }
        dismiss()
    }
}
