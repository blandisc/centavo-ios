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
    /// A fixed expense about to stop or be deleted, waiting for the answer.
    @State private var confirming: FixedItem?

    private var primary: String { CurrencyPreference.resolve(storedCurrency) }
    private var items: [FixedItem] { FixedOutlook.items(originals: originals, plans: FixedPlan.decode(storedPlans)) }

    private func money(_ amount: Decimal, _ currency: String) -> String {
        let iso = CurrencyResolver.isoCode(for: currency, primary: primary)
        return formatMoney(amount, isoCode: iso, label: currency)
    }

    /// What already arrived this month, in the main currency.
    private var arrived: Decimal {
        (originals + copies)
            .filter { MonthNavigator.isSameMonth($0.date, as: .now) && $0.date <= .now }
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
                        Button { editing = item.original } label: { row(item) }
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
            .confirmationDialog(confirming.map { item in
                                    item.original != nil ? "¿Dejar de repetir «\(item.name)»?" : "¿Borrar «\(item.name)»?"
                                } ?? "",
                                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible, presenting: confirming) { item in
                if let original = item.original {
                    Button("Dejar de repetir", role: .destructive) { stop(original) }
                } else if let plan = item.plan {
                    Button("Borrar", role: .destructive) { remove(plan) }
                }
                Button("Conservar", role: .cancel) {}
            } message: { item in
                Text(item.original != nil ? "Lo ya anotado se queda; los siguientes ya no llegan."
                     : "Todavía no se anota nada; ya no empezará.")
            }
            .sheet(item: $adding) { FixedPlanSheet(initialName: $0.name) }
            .sheet(item: $editing) { ExpenseEditorView(expense: $0) }
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
            NoteText("Lo que está por venir ya no cuenta en «Hoy puedes gastar».", color: Theme.faint)
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

    /// What is already logged stays; only what is to come stops.
    private func stop(_ original: Expense) {
        original.repeatsMonthly = nil
        original.repeatsThrough = nil
        original.repeatDay = nil
        original.repeatRule = nil
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
    @State private var merchant = ""
    @State private var rule = RepeatRule.monthly
    @State private var firstDay = Date.now
    @State private var category = ""
    /// Once a category is picked by hand, the name no longer changes it.
    @State private var pickedCategory = false
    @State private var card = ""
    /// Read once when the sheet opens, not a live query of every expense.
    @State private var pastExpenses: [CategorizedExpense] = []
    @State private var knownCategories: [String] = []
    @State private var knownCards: [String] = []
    @FocusState private var amountFocused: Bool

    /// `initialName`: a suggestion tapped on «Gastos fijos» («Renta»), already written.
    init(initialName: String = "") {
        _merchant = State(initialValue: initialName)
    }

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

    private var latest: Date { Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountInputField("Monto", text: $amountText, prompt: "0.00", identifier: "fijo-monto")
                        .focused($amountFocused)
                } header: {
                    Text("Monto (\(CurrencyPreference.current))").ticketCaption()
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
                             + (firstDate > .now
                                ? "Hasta su primer cobro no se anota nada."
                                : "El primer cobro ya llegó: se anota con su fecha, y los que hayan llegado después."))
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .scrollDismissesKeyboard(.immediately)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Nuevo gasto fijo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(.ticket(.footnote))
                        .accessibilityIdentifier("hoja-cancelar")
                }
            }
            .saveBar(amount == nil ? "Falta el monto" : name.isEmpty ? "Falta qué es"
                        : "\(name) · " + FixedWording.howItRepeats(rule, from: firstDate).components(separatedBy: ":").first!,
                     enabled: amount != nil && !name.isEmpty, action: save)
            .onAppear(perform: load)
            .onChange(of: merchant) { _, new in
                guard !pickedCategory else { return }
                category = CategoryMemory.suggestion(for: new.trimmingCharacters(in: .whitespaces),
                                                     rules: UserCatalog.categoryRules, history: pastExpenses,
                                                     hidden: UserCatalog.notAutoAssigned) ?? ""
            }
        }
    }

    private func load() {
        let history = (try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        pastExpenses = history.map(\.categorized)
        knownCategories = CategoryMemory.known(in: pastExpenses)
        knownCards = PaymentChoices.mostUsedCards(history.prefix(300).map(\.card))
        amountFocused = true
    }

    private func save() {
        guard let amount else { return }
        let categoryName = category.trimmingCharacters(in: .whitespaces)
        let cardName = card.trimmingCharacters(in: .whitespaces)
        let plan = FixedPlan(
            merchant: String(name.prefix(ExpenseRecorder.maxMerchantLength)),
            amount: "\(amount)",
            currency: CurrencyPreference.current,
            category: categoryName.isEmpty ? nil : categoryName,
            card: cardName.isEmpty ? nil : cardName,
            rule: rule.stored,
            firstDate: firstDate
        )
        // Picked by hand: the next expense from here starts with it too.
        if pickedCategory, !categoryName.isEmpty { UserCatalog.learnCategory(categoryName, for: plan.merchant) }
        if plan.firstDate <= .now {
            context.insert(RecurringExpenses.original(from: plan))
            try? RecurringExpenses.logDue(in: context)
        } else {
            FixedPlan.save(FixedPlan.saved + [plan])
        }
        dismiss()
    }
}
