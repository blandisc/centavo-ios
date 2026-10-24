import CentavoCore
import MapKit
import SwiftData
import SwiftUI

/// Sheet to add a manual expense (`expense == nil`) or correct an existing one.
struct ExpenseEditorView: View {
    let expense: Expense?
    /// Where a new expense's date starts (the end of the month being browsed); `nil` is now.
    var initialDate: Date?
    /// How the list deletes, so «Deshacer» works from here too. Without it, a plain delete.
    var onDelete: ((Expense) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Expense.date, order: .reverse) private var history: [Expense]
    @State private var amountText = ""
    /// The expense's currency. New ones start in the month's currency.
    @State private var currency = CurrencyPreference.current
    @State private var isRefund = false
    /// «Cuenta para el presupuesto», on unless it was left out.
    @State private var counts = true
    /// Why it doesn't count; kept while the switch goes back and forth.
    @State private var reason = UncountedReason.reimbursed
    @State private var merchant = ""
    @State private var card = ""
    @State private var category = ""
    @State private var date = Date.now
    @State private var repeatsMonthly = false
    /// How often it comes back, once «Se repite» is on.
    @State private var rule = RepeatRule.monthly
    @State private var confirmingDelete: Expense?
    @FocusState private var amountFocused: Bool
    @FocusState private var merchantFocused: Bool
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @AppStorage(UserCatalog.hiddenCategoriesKey) private var storedHidden = ""
    @AppStorage(UserCatalog.categoryRulesKey) private var storedRules = ""
    @AppStorage(UserCatalog.sourcesKey) private var storedSources = ""
    @AppStorage(UserCatalog.defaultSourceKey) private var defaultSource = ""
    @State private var creating: Creating?
    /// «230 de unos tacos ayer, en efectivo»: fills the sheet from one sentence.
    @State private var sentence = ""
    @State private var askingSentence = false
    @State private var readingSentence = false

    private enum Creating: String, Identifiable { case category, source; var id: String { rawValue } }
    private var customCategories: [LabeledIcon] { UserCatalog.decode(storedCategories) }
    private var paymentSources: [LabeledIcon] { UserCatalog.decode(storedSources) }
    /// Hidden and deleted categories: never filled in on their own.
    private var notAutoAssigned: [String] { UserCatalog.decodeNames(storedHidden) + UserCatalog.deletedNames }
    /// The category you chose for what is typed in «Comercio», if you ever did.
    private var rememberedCategory: String? {
        CategoryMemory.remembered(for: merchant, rules: CategoryRules(stored: storedRules),
                                  history: pastExpenses, hidden: notAutoAssigned)
    }
    @ScaledMetric(relativeTo: .body) private var iconHeight: CGFloat = Theme.Size.categorySymbol

    /// Whether something was typed or changed since the sheet opened.
    private var hasChanges: Bool {
        guard let expense else {
            let changedCard = UserCatalog.same(card, defaultSource) ? "" : card
            return !(amountText + merchant + changedCard + category).trimmingCharacters(in: .whitespaces).isEmpty
                || !counts
        }
        return parsed?.value != expense.amount.magnitude || isRefund != (expense.amount < 0)
            || counts == expense.isUncounted || (!counts && reason != (expense.reason ?? .reimbursed))
            || merchant != expense.merchant || card != (expense.card ?? "")
            || category != (expense.category ?? "") || date != expense.date
            || repeatsMonthly != (expense.repeatsMonthly == true)
            || (repeatsMonthly && rule != expense.rule)
    }

    private var parsed: ParsedAmount? { AmountParser.parse(amountText) }
    /// The offered currencies, plus this expense's own if it came in another (Wallet abroad).
    private var currencies: [String] {
        CurrencyPreference.offered.contains(currency)
            ? CurrencyPreference.offered : CurrencyPreference.offered + [currency]
    }
    /// What «Guardar» will keep, or what is still missing: «$230 · Tacos · Efectivo».
    private var saveSummary: String {
        guard let parsed, parsed.value != 0 else { return "Falta el monto" }
        let name = merchant.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "Falta el comercio" }
        let money = formatMoney(parsed.value.magnitude, isoCode: currency, label: currency)
        var parts = [(isRefund ? "+" : "") + money, name]
        let cardName = card.trimmingCharacters(in: .whitespaces)
        if !cardName.isEmpty { parts.append(cardName) }
        if !counts { parts.append("No cuenta") }
        return parts.joined(separator: " · ")
    }

    /// A zero amount is never a real expense, so it cannot be saved.
    private var canSave: Bool {
        guard let parsed, parsed.value != 0 else { return false }
        return !merchant.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Read once when the sheet opens: rebuilding it from the whole history on every key
    /// typed was felt with thousands of expenses.
    @State private var pastExpenses: [CategorizedExpense] = []

    private var allPastExpenses: [CategorizedExpense] {
        history.map(\.categorized)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String,
                       identifier: String) -> some View {
        TicketTextField(title, text: text, prompt: prompt, identifier: identifier)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountInputField("Monto", text: $amountText, prompt: "0.00", identifier: "monto")
                        .focused($amountFocused)
                    // The decimal pad has no minus key, so a refund is a switch rather than a sign.
                    Toggle(isOn: $isRefund) {
                        SectionLabel("Es una devolución")
                    }
                    .tint(Theme.brass)
                    .accessibilityIdentifier("devolucion")
                    // A work trip paid back, money to your own account: in the list, in no total.
                    Toggle(isOn: $counts) {
                        SectionLabel("Cuenta para el presupuesto")
                    }
                    .tint(Theme.brass)
                    .accessibilityIdentifier("cuenta-presupuesto")
                    if !counts {
                        Picker(selection: $reason) {
                            ForEach(UncountedReason.allCases) { Text($0.title).tag($0) }
                        } label: {
                            SectionLabel("Motivo")
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.brass)
                        .accessibilityIdentifier("motivo")
                    }
                    // The decimal pad cannot type "USD" or "€", so the currency is a choice.
                    Picker("Moneda", selection: $currency) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("moneda")
                } header: {
                    Text("Monto").ticketCaption()
                } footer: {
                    if !counts {
                        HintText("Se queda en la lista con su monto, pero no suma a lo que llevas ni a «Hoy puedes gastar».")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    field("Comercio", text: $merchant, prompt: "Nombre del comercio",
                          identifier: "comercio")
                        .textInputAutocapitalization(.words)
                        .focused($merchantFocused)
                    if merchantFocused, !MerchantSuggestions.matches(for: merchant, history: pastExpenses).isEmpty {
                        merchantSuggestions
                    }
                } header: {
                    Text("Comercio").ticketCaption()
                } footer: {
                    if let shown = expense?.displayName, shown != expense?.merchant, merchant == expense?.merchant {
                        HintText("Se muestra como «\(shown)». Si cambias el nombre, se muestra el tuyo.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    categoryGrid
                } header: {
                    Text("Categoría (opcional)").ticketCaption()
                } footer: {
                    if let expense, expense.hasSuggestedCategory, category == expense.category {
                        HintText("Sugerida por Al día con tus gastos de ejemplo. Elige otra si no te queda; la que elijas se recuerda.")
                    } else if let remembered = rememberedCategory {
                        HintText("La última vez en \(merchant.trimmingCharacters(in: .whitespaces)) fue \(remembered).")
                    } else if let suggested = CategoryMemory.suggestion(
                        for: merchant, rules: CategoryRules(stored: storedRules), history: pastExpenses,
                        hidden: notAutoAssigned) {
                        HintText("Sugerida para \(merchant.trimmingCharacters(in: .whitespaces)): \(suggested). Cámbiala si no te queda.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    sourceGrid
                } header: {
                    Text("¿Con qué pagaste? (opcional)").ticketCaption()
                } footer: {
                    if paymentSources.isEmpty {
                        HintText("Agrega tus tarjetas una vez (BBVA, Nu…). La que marques como predeterminada "
                             + "en «Más › Tarjetas y categorías» ya vendrá elegida.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    DatePicker(selection: $date, in: ...Date.now) {
                        SectionLabel("Fecha")
                    }
                    if expense?.isRepeat != true {
                        Toggle(isOn: $repeatsMonthly) {
                            SectionLabel("Se repite")
                        }
                        .tint(Theme.brass)
                        .accessibilityIdentifier("se-repite")
                        if repeatsMonthly {
                            RepeatRulePicker(rule: $rule)
                        }
                    }
                } footer: {
                    if repeatsMonthly {
                        HintText(FixedWording.howItRepeats(rule, from: date))
                    } else if expense?.isRepeat == true {
                        HintText("Se anotó solo, de un gasto fijo.")
                    }
                }
                .listRowBackground(Theme.surface)

                // The whole expense in one sentence, written or dictated. Last, so it covers and
                // moves nothing of the sheet as it was; a full row is a full tap target.
                if expense == nil {
                    Section {
                        Button("Dilo en una frase", systemImage: "text.bubble") { askingSentence = true }
                            .font(.ticket(.footnoteStrong))
                            .foregroundStyle(Theme.brass)
                            .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
                            .disabled(readingSentence)
                            .accessibilityIdentifier("en-una-frase")
                    } footer: {
                        HintText("«230 de tacos ayer, en efectivo» llena el monto, el comercio, el día y cómo pagaste.")
                    }
                    .listRowBackground(Theme.surface)
                }

                if expense?.isRepeat == true, original != nil {
                    Section {
                        Button("Dejar de repetir cada mes") { stopRepeating() }
                            .font(.ticket(.footnoteStrong))
                            .tracking(Theme.Tracking.caption)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.brass)
                            .accessibilityIdentifier("dejar-de-repetir")
                    } footer: {
                        HintText("Los meses ya anotados se quedan; el siguiente ya no llega.")
                    }
                    .listRowBackground(Theme.surface)
                }

                if let expense, let latitude = expense.latitude, let longitude = expense.longitude {
                    Section {
                        PlaceMap(expense: expense,
                                 coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                    } header: {
                        Text("Dónde").ticketCaption()
                    } footer: {
                        HintText("Dónde estaba tu iPhone al anotarse. En compras en línea es donde estabas tú.")
                    }
                    .listRowBackground(Theme.surface)
                }

                if expense != nil {
                    Section {
                        Button("Borrar gasto", role: .destructive) { confirmingDelete = expense }
                            .font(.ticket(.footnoteStrong))
                            .tracking(Theme.Tracking.caption)
                            .textCase(.uppercase)
                            .accessibilityIdentifier("borrar-gasto")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .ticketForm()
            // The number pad has no key to close it and covers half the sheet: scrolling down to
            // the categories or the card closes it.
            .scrollDismissesKeyboard(.immediately)
            // iOS 26 ignores the line above in a sheet's form: a drag does it there.
            .simultaneousGesture(DragGesture(minimumDistance: 24).onChanged { _ in
                if amountFocused { amountFocused = false }
                if merchantFocused { merchantFocused = false }
            })
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle(expense == nil ? "Nuevo gasto" : "Editar gasto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(.ticket(.footnote))
                        .accessibilityIdentifier("hoja-cancelar")
                }
            }
            .saveBar(saveSummary, enabled: canSave, action: save)
            .alert("Dilo en una frase", isPresented: $askingSentence) {
                TextField("230 de tacos ayer, en efectivo", text: $sentence)
                    .accessibilityIdentifier("frase")
                Button("Llenar") { Task { await fillFromSentence() } }
                Button("Cancelar", role: .cancel) { sentence = "" }
            } message: {
                Text("Cuánto, dónde, qué día y cómo pagaste. Revisa lo que llené antes de guardar.")
            }
            .confirmsDelete(of: $confirmingDelete, primaryCurrency: CurrencyPreference.current,
                            undoable: onDelete != nil) { expense in
                if let onDelete { onDelete(expense) } else { context.delete(expense) }
                dismiss()
            }
        }
        .onAppear(perform: load)
        .sheet(item: $creating) { kind in
            switch kind {
            case .category:
                LabeledIconSheet(title: "Nueva categoría", prompt: "Mascotas, Gimnasio…",
                                 icons: UserCatalog.categoryIcons,
                                 taken: customCategories.map(\.name) + CategoryStyle.common.map(\.name)) { saved in
                    storedCategories = UserCatalog.encode(customCategories + [saved])
                    UserCatalog.markDeleted(saved.name, false)
                    category = saved.name
                }
            case .source:
                LabeledIconSheet(title: "Nueva tarjeta", prompt: "BBVA, Nu, Efectivo…",
                                 icons: UserCatalog.sourceIcons, taken: paymentSources.map(\.name)) { saved in
                    storedSources = UserCatalog.encode(paymentSources + [saved])
                    if defaultSource.isEmpty { defaultSource = saved.name }
                    card = saved.name
                }
            }
        }
        // Swiping the sheet away must not throw away what was typed.
        .interactiveDismissDisabled(hasChanges)
        .onChange(of: merchant) { _, new in
            // Change the merchant and the category you last used for it fills in,
            // but only while the field is empty — never overwrite a typed one. Only for a new
            // expense: opening an uncategorized one must not quietly file it.
            guard expense == nil, category.trimmingCharacters(in: .whitespaces).isEmpty,
                  let remembered = CategoryMemory.suggestion(for: new, rules: CategoryRules(stored: storedRules),
                                                             history: pastExpenses,
                                                             hidden: notAutoAssigned)
            else { return }
            category = remembered
        }
    }

    /// Places already paid at, one tap away while the name is typed.
    private var merchantSuggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                ForEach(MerchantSuggestions.matches(for: merchant, history: pastExpenses), id: \.self) { name in
                    Button(name) {
                        merchant = name
                        // The merchant is done: the keyboard would only cover the categories.
                        merchantFocused = false
                    }
                        .font(.ticket(.footnote))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.Space.ml)
                        .frame(minHeight: Theme.Size.tapTarget)
                        .background(Theme.background, in: Capsule())
                        .overlay { Capsule().strokeBorder(Theme.hairline) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Usa este comercio")
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("comercios-sugeridos")
    }

    /// The usual categories with their icons, plus any other already used; one tap picks
    /// one, another tap clears it. «Otra» writes a new one.
    private var categoryGrid: some View {
        let names = CategoryStyle.offered(known: Array(CategoryMemory.known(in: pastExpenses).prefix(8)),
                                          custom: customCategories, current: category,
                                          hidden: UserCatalog.decodeNames(storedHidden))
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Size.categoryGridMinimum), spacing: Theme.Space.s)],
                         spacing: Theme.Space.s) {
            ForEach(names, id: \.self) { name in
                categoryChip(name, icon: CategoryStyle.icon(for: name, custom: customCategories),
                             selected: category == name) {
                    category = category == name ? "" : name
                }
            }
            categoryChip("Nueva categoría", icon: "plus", selected: false) { creating = .category }
        }
        .padding(.vertical, Theme.Space.xs)
    }

    /// The cards and cash set up in «Tarjetas y categorías», plus any other a payment came
    /// with (Wallet names the card). The default one is already chosen on a new expense.
    private var sourceGrid: some View {
        let sources = paymentSources
        // Cash needs no setting up: it is always one tap away.
        var names = sources.map(\.name)
        if !names.contains(where: { UserCatalog.same($0, "Efectivo") }) { names.append("Efectivo") }
        for name in knownCards + [card] where !name.isEmpty && !names.contains(where: { UserCatalog.same($0, name) }) {
            names.append(name)
        }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Size.categoryGridMinimum), spacing: Theme.Space.s)],
                         spacing: Theme.Space.s) {
            ForEach(names, id: \.self) { name in
                let icon = sources.first { UserCatalog.same($0.name, name) }?.icon
                    ?? (UserCatalog.same(name, "Efectivo") ? "banknote" : "creditcard")
                categoryChip(name, icon: icon, selected: UserCatalog.same(card, name), kind: "tarjeta") {
                    card = UserCatalog.same(card, name) ? "" : name
                }
            }
            categoryChip("Agregar tarjeta", icon: "plus", selected: false, kind: "tarjeta") { creating = .source }
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityIdentifier("tarjetas")
    }

    /// Cards from past payments, most used first.
    private var knownCards: [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for expense in history.prefix(300) {
            guard let name = expense.card?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
            counts[UserCatalog.fold(name), default: (name, 0)].count += 1
        }
        return counts.values.sorted { $0.count > $1.count }.prefix(4).map(\.name)
    }

    private func categoryChip(_ name: String, icon: String, selected: Bool, kind: String = "categoria",
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.xxs) {
                Image(systemName: icon)
                    .font(Theme.Symbol.regular)
                    // Every icon in the same box, so the names line up.
                    .frame(height: iconHeight)
                    .foregroundStyle(selected ? Theme.onBrass : Theme.brass)
                    .accessibilityHidden(true)
                Text(name)
                    .font(.ticket(.caption))
                    .lineLimit(1)
                    .minimumScaleFactor(Theme.MinimumScale.text)
                    .foregroundStyle(selected ? Theme.onBrass : Theme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Size.categoryTile)
            .padding(.horizontal, Theme.Space.xxs)
                .choiceTile(selected: selected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("\(kind)-\(name)")
    }

    /// The fixed expense a copy came from: same merchant and amount, still repeating.
    private var original: Expense? {
        guard let expense, expense.isRepeat == true else { return nil }
        let merchant = expense.merchant, amount = expense.amount
        let candidates = try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate {
            $0.repeatsMonthly == true && $0.merchant == merchant
        }))
        return candidates?.first { $0.amount == amount }
    }

    private func stopRepeating() {
        guard let original else { return }
        original.repeatsMonthly = nil
        original.repeatsThrough = nil
        original.repeatDay = nil
        dismiss()
    }

    private func load() {
        pastExpenses = allPastExpenses
        guard let expense else {
            if let initialDate { date = initialDate }
            card = defaultSource
            amountFocused = true
            return
        }
        // A bare "$" from Wallet is the month's currency; anything else keeps its own.
        currency = CurrencyResolver.isoCode(for: expense.currencyMarker,
                                            primary: CurrencyPreference.current)
            ?? CurrencyPreference.current
        isRefund = expense.amount < 0
        counts = !expense.isUncounted
        reason = expense.reason ?? .reimbursed
        amountText = expense.amount.magnitude
            .formatted(.number.precision(.fractionLength(2)).grouping(.never))
        merchant = expense.merchant
        repeatsMonthly = expense.repeatsMonthly == true
        rule = expense.rule
        card = expense.card ?? ""
        category = expense.category ?? ""
        date = expense.date
    }

    /// Fills the fields from `sentence`: the plain reading first, then the on-device model's
    /// where it is there and agrees with what was said. Nothing is saved until «Guardar».
    private func fillFromSentence() async {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !readingSentence else { return }
        readingSentence = true
        defer { readingSentence = false }
        let sources = paymentSources.map(\.name)
        guard let entry = await QuickExpense.read(text, sources: sources) else {
            amountFocused = true
            return
        }
        if let parsed = AmountParser.parse(entry.amountText) {
            amountText = parsed.value.magnitude.formatted(.number.precision(.fractionLength(0...2)))
            currency = ExpenseRecorder.spokenCurrency(parsed.currencyMarker, primary: CurrencyPreference.current)
        }
        if let name = entry.merchant { merchant = name }
        date = min(entry.date, .now)
        if let source = entry.source { card = source }
        sentence = ""
    }

    /// «Cuenta para el presupuesto»: off leaves it out for the chosen reason; back on counts it
    /// in full and keeps the reason for next time.
    private func setCounts(_ expense: Expense) {
        if counts {
            if expense.isUncounted { expense.markCounted() }
        } else if !expense.isUncounted || reason != (expense.reason ?? .reimbursed) {
            // Untouched, an expense that came without a reason (an old CSV) keeps none.
            expense.markUncounted(reason)
        }
    }

    /// Turning it on starts counting from the expense's own month; turning it off stops it.
    private func setRepeats(_ expense: Expense) {
        if repeatsMonthly {
            // From now on: marking an old expense must not backfill months already lived (and
            // maybe already logged by hand).
            if expense.repeatsMonthly != true { expense.repeatsThrough = max(date, Date.now) }
            expense.repeatsMonthly = true
            expense.repeatRule = rule.stored
            // The day of the month matters only to what repeats by months.
            expense.repeatDay = rule.kind == .months ? Calendar.current.component(.day, from: date) : nil
        } else {
            expense.repeatsMonthly = nil
            expense.repeatsThrough = nil
            expense.repeatDay = nil
            expense.repeatRule = nil
        }
    }

    private func save() {
        guard let parsed else { return }
        let name = merchant.trimmingCharacters(in: .whitespaces)
        let cardName = card.trimmingCharacters(in: .whitespaces)
        let categoryName = category.trimmingCharacters(in: .whitespaces)
        let value = isRefund ? -parsed.value.magnitude : parsed.value.magnitude
        // Saved as its ISO code, never "$": a bare "$" would follow the month's currency and
        // change meaning if that is switched later.
        if let expense {
            expense.amount = value
            let before = CurrencyResolver.isoCode(for: expense.currencyMarker,
                                                  primary: CurrencyPreference.current)
            if before != currency { expense.currencyMarker = currency }
            // A name typed here reads as typed, and the model leaves it alone.
            if name != expense.merchant { expense.displayName = name }
            expense.merchant = name
            expense.card = cardName.isEmpty ? nil : cardName
            // Another category is a choice; keeping the suggested one leaves it a suggestion,
            // and taking it off means none, not «suggest another».
            if categoryName != (expense.category ?? "") {
                expense.categorySource = categoryName.isEmpty ? Expense.clearedCategory : nil
                // The newest choice is what the next expense from here starts with, even when
                // this one is older than others from the same place.
                UserCatalog.learnCategory(categoryName, for: name)
            }
            expense.category = categoryName.isEmpty ? nil : categoryName
            expense.date = date
            setCounts(expense)
            if expense.isRepeat != true { setRepeats(expense) }
        } else {
            let new = Expense(
                amount: value,
                currencyMarker: currency,
                merchant: name,
                card: cardName.isEmpty ? nil : cardName,
                date: date,
                category: categoryName.isEmpty ? nil : categoryName
            )
            if !categoryName.isEmpty { UserCatalog.learnCategory(categoryName, for: name) }
            // A place picked from the suggestions reads as it did before.
            new.displayName = history.first { $0.merchant == name }?.displayName
            setCounts(new)
            setRepeats(new)
            context.insert(new)
            // Written down as it happens: where the iPhone is, if «Guardar dónde pagas» is on.
            if abs(date.timeIntervalSinceNow) < 15 * 60 {
                Task { @MainActor in
                    guard let place = await PaymentPlace.current() else { return }
                    new.latitude = place.latitude
                    new.longitude = place.longitude
                    try? context.save()
                }
            }
        }
        dismiss()
    }
}

#Preview("Nuevo") {
    ExpenseEditorView(expense: nil)
        .modelContainer(for: Expense.self, inMemory: true)
        .ticketPreview()
}

/// The map under an expense, as Wallet shows it under a charge, with the place's name.
private struct PlaceMap: View {
    let expense: Expense
    let coordinate: CLLocationCoordinate2D
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 400,
                                                           longitudinalMeters: 400)),
                interactionModes: []) {
                Marker(expense.displayName ?? expense.merchant, coordinate: coordinate)
                    .tint(Theme.brass)
            }
            .frame(height: Theme.Size.mapPreview)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel))
            .accessibilityLabel("Mapa de dónde se pagó")
            if let name = expense.placeName {
                Text(name)
                    .font(.ticket(.footnote))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("lugar")
            }
            Button("Quitar ubicación", role: .destructive) {
                expense.latitude = nil
                expense.longitude = nil
                expense.placeName = nil
                try? context.save()
            }
            .font(.ticket(.detail))
            .buttonStyle(.borderless)
            .frame(minHeight: Theme.Size.tapTarget)
        }
        .padding(.vertical, Theme.Space.xs)
        .task { await nameThePlace() }
    }

    /// The street and neighborhood, once, kept with the expense.
    private func nameThePlace() async {
        guard expense.placeName == nil else { return }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return }
        let parts = [mark.name, mark.subLocality, mark.locality].compactMap { $0 }
        var seen: [String] = []
        for part in parts where !seen.contains(part) { seen.append(part) }
        guard !seen.isEmpty else { return }
        expense.placeName = seen.joined(separator: ", ")
        try? context.save()
    }
}
