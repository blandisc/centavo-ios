import CentavoCore
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
    @State private var merchant = ""
    @State private var card = ""
    @State private var category = ""
    @State private var date = Date.now
    @State private var repeatsMonthly = false
    @State private var confirmingDelete = false
    @FocusState private var amountFocused: Bool
    @FocusState private var merchantFocused: Bool
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
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
    @ScaledMetric(relativeTo: .body) private var iconHeight: CGFloat = 22

    /// Whether something was typed or changed since the sheet opened.
    private var hasChanges: Bool {
        guard let expense else {
            let changedCard = UserCatalog.same(card, defaultSource) ? "" : card
            return !(amountText + merchant + changedCard + category).trimmingCharacters(in: .whitespaces).isEmpty
        }
        return parsed?.value != expense.amount.magnitude || isRefund != (expense.amount < 0)
            || merchant != expense.merchant || card != (expense.card ?? "")
            || category != (expense.category ?? "") || date != expense.date
            || repeatsMonthly != (expense.repeatsMonthly == true)
    }

    private var parsed: ParsedAmount? { AmountParser.parse(amountText) }
    /// The offered currencies, plus this expense's own if it came in another (Wallet abroad).
    private var currencies: [String] {
        CurrencyPreference.offered.contains(currency)
            ? CurrencyPreference.offered : CurrencyPreference.offered + [currency]
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
        TextField(title, text: text, prompt: Text(prompt).foregroundStyle(Theme.faint))
            .font(.ticket(17, relativeTo: .body))
            .tracking(0.6)
            .foregroundStyle(Theme.ink)
            .accessibilityIdentifier(identifier)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.ticket(11, relativeTo: .caption2))
            .tracking(0.6)
            .foregroundStyle(Theme.faint)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Monto", text: $amountText,
                              prompt: Text("0.00").foregroundStyle(Theme.faint))
                        .font(.ticket(44, weight: .medium, relativeTo: .largeTitle))
                        .tracking(-1.5)
                        .foregroundStyle(Theme.ink)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .groupsThousands($amountText)
                        .accessibilityIdentifier("monto")
                    // The decimal pad has no minus key, so a refund is a switch rather than a sign.
                    Toggle(isOn: $isRefund) {
                        Text("Es una devolución")
                            .font(.ticket(12, relativeTo: .footnote))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    .tint(Theme.brass)
                    .accessibilityIdentifier("devolucion")
                    // The decimal pad cannot type "USD" or "€", so the currency is a choice.
                    Picker("Moneda", selection: $currency) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("moneda")
                } header: {
                    Text("Monto").ticketCaption()
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
                    if let shown = expense?.displayName, merchant == expense?.merchant {
                        hint("Se muestra como «\(shown)». Si cambias el nombre, se muestra el tuyo.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    categoryGrid
                } header: {
                    Text("Categoría (opcional)").ticketCaption()
                } footer: {
                    if let expense, expense.hasSuggestedCategory, category == expense.category {
                        hint("Sugerida por Al día con tus gastos de ejemplo. Elige otra si no te queda; la que elijas se recuerda.")
                    } else if let remembered = CategoryMemory.category(for: merchant, in: pastExpenses) {
                        hint("La última vez en \(merchant.trimmingCharacters(in: .whitespaces)) fue \(remembered).")
                    } else if let suggested = MerchantCatalog.category(for: merchant) {
                        hint("Sugerida para \(merchant.trimmingCharacters(in: .whitespaces)): \(suggested). Cámbiala si no te queda.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    sourceGrid
                } header: {
                    Text("¿Con qué pagaste? (opcional)").ticketCaption()
                } footer: {
                    if paymentSources.isEmpty {
                        hint("Agrega tus tarjetas una vez (BBVA, Nu…). La que marques como predeterminada "
                             + "en «Más › Tarjetas y categorías» ya vendrá elegida.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    DatePicker(selection: $date, in: ...Date.now) {
                        Text("Fecha")
                            .font(.ticket(12, relativeTo: .footnote))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    if expense?.isRepeat != true {
                        Toggle(isOn: $repeatsMonthly) {
                            Text("Se repite cada mes")
                                .font(.ticket(12, relativeTo: .footnote))
                                .tracking(1.2)
                                .textCase(.uppercase)
                        }
                        .tint(Theme.brass)
                        .accessibilityIdentifier("se-repite")
                    }
                } footer: {
                    if repeatsMonthly {
                        hint("Renta, suscripciones, la luz: se anota sola el mismo día de cada mes.")
                    } else if expense?.isRepeat == true {
                        hint("Se anotó solo, de un gasto fijo.")
                    }
                }
                .listRowBackground(Theme.surface)

                if expense?.isRepeat == true, original != nil {
                    Section {
                        Button("Dejar de repetir cada mes") { stopRepeating() }
                            .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.brass)
                            .accessibilityIdentifier("dejar-de-repetir")
                    } footer: {
                        hint("Los meses ya anotados se quedan; el siguiente ya no llega.")
                    }
                    .listRowBackground(Theme.surface)
                }

                if expense != nil {
                    Section {
                        Button("Borrar gasto", role: .destructive) { confirmingDelete = true }
                            .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                            .tracking(1.6)
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
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle(expense == nil ? "Nuevo gasto" : "Editar gasto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(.ticket(13, relativeTo: .footnote))
                        .accessibilityIdentifier("hoja-cancelar")
                }
                // Above the keyboard, where the sheet opens: the whole expense in one sentence.
                ToolbarItemGroup(placement: .keyboard) {
                    if expense == nil {
                        Spacer()
                        Button("Dilo en una frase", systemImage: "text.bubble") { askingSentence = true }
                            .labelStyle(.titleAndIcon)
                            .font(.ticket(13, relativeTo: .footnote))
                            .disabled(readingSentence)
                            .accessibilityIdentifier("en-una-frase")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                        .disabled(!canSave)
                        .accessibilityIdentifier("hoja-guardar")
                }
            }
            .alert("Dilo en una frase", isPresented: $askingSentence) {
                TextField("230 de tacos ayer, en efectivo", text: $sentence)
                    .accessibilityIdentifier("frase")
                Button("Llenar") { Task { await fillFromSentence() } }
                Button("Cancelar", role: .cancel) { sentence = "" }
            } message: {
                Text("Cuánto, dónde, qué día y cómo pagaste. Revisa lo que llené antes de guardar.")
            }
            .confirmationDialog("¿Borrar este gasto?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Borrar", role: .destructive) {
                    if let expense {
                        if let onDelete { onDelete(expense) } else { context.delete(expense) }
                    }
                    dismiss()
                }
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
                  let remembered = MerchantCatalog.suggestion(for: new, history: pastExpenses)
            else { return }
            category = remembered
        }
    }

    /// Places already paid at, one tap away while the name is typed.
    private var merchantSuggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(MerchantSuggestions.matches(for: merchant, history: pastExpenses), id: \.self) { name in
                    Button(name) { merchant = name }
                        .font(.ticket(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
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
                                          custom: customCategories, current: category)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(names, id: \.self) { name in
                categoryChip(name, icon: CategoryStyle.icon(for: name, custom: customCategories),
                             selected: category == name) {
                    category = category == name ? "" : name
                }
            }
            categoryChip("Nueva categoría", icon: "plus", selected: false) { creating = .category }
        }
        .padding(.vertical, 6)
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
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(names, id: \.self) { name in
                let icon = sources.first { UserCatalog.same($0.name, name) }?.icon
                    ?? (UserCatalog.same(name, "Efectivo") ? "banknote" : "creditcard")
                categoryChip(name, icon: icon, selected: UserCatalog.same(card, name), kind: "tarjeta") {
                    card = UserCatalog.same(card, name) ? "" : name
                }
            }
            categoryChip("Agregar tarjeta", icon: "plus", selected: false, kind: "tarjeta") { creating = .source }
        }
        .padding(.vertical, 6)
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
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.body)
                    // Every icon in the same box, so the names line up.
                    .frame(height: iconHeight)
                    .foregroundStyle(selected ? Theme.onBrass : Theme.brass)
                    .accessibilityHidden(true)
                Text(name)
                    .font(.ticket(11, relativeTo: .caption))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(selected ? Theme.onBrass : Theme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 4)
                .background(selected ? Theme.brass : Theme.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if !selected { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline) }
                }
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
        amountText = expense.amount.magnitude
            .formatted(.number.precision(.fractionLength(2)).grouping(.never))
        merchant = expense.merchant
        repeatsMonthly = expense.repeatsMonthly == true
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

    /// Turning it on starts counting from the expense's own month; turning it off stops it.
    private func setRepeats(_ expense: Expense) {
        if repeatsMonthly {
            // From now on: marking an old expense must not backfill months already lived (and
            // maybe already logged by hand).
            if expense.repeatsMonthly != true { expense.repeatsThrough = max(date, Date.now) }
            expense.repeatsMonthly = true
            expense.repeatDay = Calendar.current.component(.day, from: date)
        } else {
            expense.repeatsMonthly = nil
            expense.repeatsThrough = nil
            expense.repeatDay = nil
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
            // A name typed here is how it reads; Wallet's gets its readable one again.
            if name != expense.merchant { expense.displayName = MerchantName.readable(name) }
            expense.merchant = name
            expense.card = cardName.isEmpty ? nil : cardName
            // Another category is a choice; keeping the suggested one leaves it a suggestion.
            if categoryName != (expense.category ?? "") { expense.categorySource = nil }
            expense.category = categoryName.isEmpty ? nil : categoryName
            expense.date = date
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
            setRepeats(new)
            context.insert(new)
        }
        dismiss()
    }
}

#Preview("Nuevo") {
    ExpenseEditorView(expense: nil)
        .modelContainer(for: Expense.self, inMemory: true)
        .preferredColorScheme(.dark)
}
