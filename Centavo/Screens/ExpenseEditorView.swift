import CentavoCore
import MapKit
import SwiftData
import SwiftUI

/// Sheet to add a manual expense (`expense == nil`) or correct an existing one.
///
/// The common first (2026-10-29): amount with its currency, merchant, category, card. What is
/// rarely touched (the type, the date, «Se repite», where) waits in «Más detalles», which opens
/// by itself when the expense already has one of those set.
struct ExpenseEditorView: View {
    let expense: Expense?
    /// Where a new expense's date starts (the end of the month being browsed); `nil` is now.
    var initialDate: Date?
    /// How the list deletes, so «Deshacer» works from here too. Without it, a plain delete.
    var onDelete: ((Expense) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var amountText = ""
    /// The expense's currency. New ones start in the month's currency.
    @State private var currency = CurrencyPreference.current
    /// A refund is saved as a negative amount (the decimal pad has no minus key).
    @State private var isRefund = false
    /// Counts toward the budget unless «Tipo» is «No cuenta».
    @State private var counts = true
    /// Why it doesn't count; kept while «Tipo» goes back and forth.
    @State private var reason = UncountedReason.reimbursed
    @State private var merchant = ""
    @State private var card = ""
    @State private var category = ""
    @State private var date = Date.now
    @State private var repeatsMonthly = false
    /// How often it comes back, once «Se repite» is on.
    @State private var rule = RepeatRule.monthly
    @State private var confirmingDelete: Expense?
    @State private var confirmingStop = false
    /// «Más detalles»: open by itself when the expense has something set there.
    @State private var showsDetails = false
    /// «Ver todas»: the whole category list instead of the short one.
    @State private var showsAllCategories = false
    @FocusState private var amountFocused: Bool
    @FocusState private var merchantFocused: Bool
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @AppStorage(UserCatalog.hiddenCategoriesKey) private var storedHidden = ""
    @AppStorage(UserCatalog.categoryRulesKey) private var storedRules = ""
    @AppStorage(UserCatalog.categoryColorsKey) private var storedCategoryColors = ""
    @AppStorage(UserCatalog.sourceColorsKey) private var storedSourceColors = ""
    @AppStorage(UserCatalog.sourcesKey) private var storedSources = ""
    @AppStorage(UserCatalog.defaultSourceKey) private var defaultSource = ""
    @State private var creating: Creating?
    /// «230 de unos tacos ayer, en efectivo»: fills the sheet from one sentence.
    @State private var sentence = ""
    @State private var askingSentence = false
    @State private var readingSentence = false
    /// Said when a sentence had no amount in it, instead of doing nothing.
    @State private var sentenceProblem: String?

    // Read once when the sheet opens, or when «Comercio» changes: rebuilding them from the
    // whole history on every key typed was felt with thousands of expenses (audit R10).
    @State private var pastExpenses: [CategorizedExpense] = []
    @State private var knownCategories: [String] = []
    @State private var knownCards: [String] = []
    @State private var merchantMatches: [String] = []
    /// The category you chose for what is typed in «Comercio», if you ever did.
    @State private var rememberedCategory: String?
    /// What a new expense from that merchant starts with: yours, else the catalog's guess.
    @State private var suggestedCategory: String?
    /// Categories that stay in the short list once they were in it (the expense's own, one
    /// picked from «Ver todas»), so a tap never makes a tile jump away.
    @State private var pinnedCategories: [String] = []
    /// The fixed expense a copy came from, found once.
    @State private var original: Expense?

    private enum Creating: String, Identifiable { case category, source; var id: String { rawValue } }

    /// «Tipo»: one choice instead of two switches. Refund and «No cuenta» keep their meaning:
    /// a refund is a negative amount; «No cuenta» stays in the list with nothing counted.
    private enum Kind: Hashable, CaseIterable {
        case expense, refund, uncounted
        var title: String {
            switch self {
            case .expense: "Gasto"
            case .refund: "Devolución"
            case .uncounted: "No cuenta"
            }
        }
    }

    private var kind: Binding<Kind> {
        Binding(get: { !counts ? .uncounted : isRefund ? .refund : .expense }, set: { new in
            switch new {
            case .expense:
                isRefund = false
                counts = true
            case .refund:
                isRefund = true
                counts = true
            case .uncounted:
                counts = false
                // A stored refund that doesn't count keeps its sign; a new one is an expense.
                isRefund = (expense?.amount ?? 0) < 0
            }
        })
    }

    private var customCategories: [LabeledIcon] { UserCatalog.decode(storedCategories) }
    private var paymentSources: [LabeledIcon] { UserCatalog.decode(storedSources) }
    private var colors: CatalogColors {
        CatalogColors(categories: storedCategoryColors, sources: storedSourceColors)
    }
    /// Hidden and deleted categories: never filled in on their own.
    private var notAutoAssigned: [String] { UserCatalog.decodeNames(storedHidden) + UserCatalog.deletedNames }
    @ScaledMetric(relativeTo: .body) private var iconHeight: CGFloat = Theme.Size.categorySymbol

    /// Whether something was typed or changed since the sheet opened.
    private var hasChanges: Bool {
        guard let expense else {
            let changedCard = UserCatalog.same(card, defaultSource) ? "" : card
            return !(amountText + merchant + changedCard + category).trimmingCharacters(in: .whitespaces).isEmpty
                || !counts || isRefund
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

    private var trimmedMerchant: String { merchant.trimmingCharacters(in: .whitespaces) }
    private var trimmedCategory: String { category.trimmingCharacters(in: .whitespaces) }
    /// The name it is saved with: the merchant, or with none typed, the category («Comida»).
    private var savedName: String { trimmedMerchant.isEmpty ? trimmedCategory : trimmedMerchant }

    /// What «Guardar» will keep, or what is still missing: «$230 · Tacos · Efectivo».
    private var saveSummary: String {
        guard let parsed, parsed.value != 0 else { return "Falta el monto" }
        guard !savedName.isEmpty else { return "Falta el comercio" }
        let money = formatMoney(parsed.value.magnitude, isoCode: currency, label: currency)
        var parts = [(isRefund ? "+" : "") + money, savedName]
        let cardName = card.trimmingCharacters(in: .whitespaces)
        if !cardName.isEmpty { parts.append(cardName) }
        if !counts { parts.append("No cuenta") }
        return parts.joined(separator: " · ")
    }

    /// A zero amount is never a real expense, so it cannot be saved. The merchant can be left
    /// out when a category says what it was.
    private var canSave: Bool {
        guard let parsed, parsed.value != 0 else { return false }
        return !savedName.isEmpty
    }

    /// What «Más detalles» holds, said on its row while it is closed: «Hoy · Gasto».
    private var detailsSummary: String {
        var parts = [Calendar.current.isDateInToday(date) ? "Hoy"
                     : date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_MX")))]
        parts.append(kind.wrappedValue.title)
        if repeatsMonthly || expense?.isRepeat == true { parts.append("Fijo") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                merchantSection
                categorySection
                sourceSection
                detailsSection

                if showsDetails, let expense, let latitude = expense.latitude, let longitude = expense.longitude {
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

                if expense?.isRepeat == true, original != nil {
                    Section {
                        Button("Dejar de repetir") { confirmingStop = true }
                            .font(.ticket(.footnoteStrong))
                            .tracking(Theme.Tracking.caption)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.brass)
                            .accessibilityIdentifier("dejar-de-repetir")
                    } footer: {
                        HintText("Lo ya anotado se queda; el siguiente ya no llega.")
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
                    } footer: {
                        walletOrigin
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
                Text("Cuánto, dónde, qué día y cómo pagaste: «230 de tacos ayer, en efectivo». Revisa lo que llené antes de guardar.")
            }
            .confirmationDialog("¿Dejar de repetir «\(expense?.displayName ?? expense?.merchant ?? "")»?",
                                isPresented: $confirmingStop, titleVisibility: .visible) {
                Button("Dejar de repetir", role: .destructive) { stopRepeating() }
                Button("Conservar", role: .cancel) {}
            } message: {
                Text("Lo ya anotado se queda; el siguiente ya no llega.")
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
                                 taken: customCategories.map(\.name) + CategoryStyle.common.map(\.name),
                                 colorKind: .category,
                                 siblings: customCategories.map(\.name) + CategoryStyle.common.map(\.name)) { saved in
                    storedCategories = UserCatalog.encode(customCategories + [saved])
                    UserCatalog.markDeleted(saved.name, false)
                    category = saved.name
                    pinnedCategories.append(saved.name)
                }
            case .source:
                LabeledIconSheet(title: "Nueva tarjeta", prompt: "BBVA, Nu, Efectivo…",
                                 icons: UserCatalog.sourceIcons, taken: paymentSources.map(\.name),
                                 colorKind: .source,
                                 siblings: PaymentChoices.names(sources: paymentSources, known: knownCards,
                                                                current: "")) { saved in
                    storedSources = UserCatalog.encode(paymentSources + [saved])
                    if defaultSource.isEmpty { defaultSource = saved.name }
                    card = saved.name
                }
            }
        }
        // Swiping the sheet away must not throw away what was typed.
        .interactiveDismissDisabled(hasChanges)
        .onChange(of: merchant) { _, new in
            refreshMerchant(new)
            // Change the merchant and the category you last used for it fills in,
            // but only while the field is empty — never overwrite a typed one. Only for a new
            // expense: opening an uncategorized one must not quietly file it.
            guard expense == nil, trimmedCategory.isEmpty, let suggestedCategory else { return }
            category = suggestedCategory
        }
        .onChange(of: amountText) { sentenceProblem = nil }
    }

    // MARK: Sections

    private var amountSection: some View {
        Section {
            AdaptiveStack {
                AmountInputField("Monto", text: $amountText, prompt: "0.00", identifier: "monto")
                    .focused($amountFocused)
                HStack(spacing: Theme.Space.s) {
                    currencyMenu
                    // The decimal pad has no return key, and a keyboard bar does not show in
                    // this sheet: while the amount is typed, «Siguiente» lives in its row.
                    if amountFocused {
                        Button("Siguiente", systemImage: "arrow.right") { merchantFocused = true }
                            .labelStyle(.iconOnly)
                            .font(.ticket(.footnoteStrong))
                            .foregroundStyle(Theme.brass)
                            .frame(minWidth: Theme.Size.tapTarget, minHeight: Theme.Size.tapTarget)
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("siguiente-teclado")
                    } else if expense == nil {
                        sentenceButton
                    }
                }
            }
        } header: {
            Text("Monto").ticketCaption()
        } footer: {
            if let sentenceProblem {
                NoteText(sentenceProblem)
                    .accessibilityIdentifier("frase-sin-monto")
            }
        }
        .listRowBackground(Theme.surface)
    }

    /// The decimal pad cannot type "USD" or "€", so the currency is a choice next to the amount.
    private var currencyMenu: some View {
        Menu {
            Picker("Moneda", selection: $currency) {
                ForEach(currencies, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack(spacing: Theme.Space.xxs) {
                Text(currency)
                    .font(.ticket(.label))
                    .tracking(Theme.Tracking.label)
                Image(systemName: "chevron.down")
                    .font(Theme.Symbol.regular)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.brass)
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: Theme.Size.tapTarget)
            .background(Theme.background, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.hairline) }
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel("Moneda")
        .accessibilityValue(currency)
        .accessibilityIdentifier("moneda")
    }

    /// The whole expense in one sentence, written or dictated.
    private var sentenceButton: some View {
        Button { askingSentence = true } label: {
            Image(systemName: "text.bubble")
                .font(Theme.Symbol.regular)
                .foregroundStyle(Theme.brass)
                .frame(minWidth: Theme.Size.tapTarget, minHeight: Theme.Size.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(readingSentence)
        .accessibilityLabel("Dilo en una frase")
        .accessibilityHint("«230 de tacos ayer, en efectivo» llena el monto, el comercio, el día y cómo pagaste.")
        .accessibilityIdentifier("en-una-frase")
    }

    private var merchantSection: some View {
        Section {
            TicketTextField("Comercio", text: $merchant, prompt: "Nombre del comercio", identifier: "comercio")
                .textInputAutocapitalization(.words)
                .focused($merchantFocused)
                .submitLabel(.done)
            if merchantFocused, !merchantMatches.isEmpty {
                merchantSuggestions
            }
        } header: {
            Text("Comercio").ticketCaption()
        } footer: {
            if let shown = expense?.displayName, shown != expense?.merchant, merchant == expense?.merchant {
                HintText("Se muestra como «\(shown)». Si cambias el nombre, se muestra el tuyo.")
            } else if trimmedMerchant.isEmpty, !trimmedCategory.isEmpty {
                HintText("Sin comercio, se guarda como «\(trimmedCategory)».")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var categorySection: some View {
        Section {
            categoryGrid
        } header: {
            Text("Categoría").ticketCaption()
        } footer: {
            if let expense, expense.hasSuggestedCategory, category == expense.category {
                HintText("Sugerida por Al día. Elige otra si no te queda; se recuerda.")
            } else if let rememberedCategory {
                HintText("La última vez en \(trimmedMerchant) fue \(rememberedCategory).")
            } else if let suggestedCategory {
                HintText("Sugerida para \(trimmedMerchant): \(suggestedCategory). Cámbiala si no te queda.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var sourceSection: some View {
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
    }

    /// «Tipo», «Fecha» and «Se repite»: closed until asked for, or open when they are set.
    private var detailsSection: some View {
        Section {
            Button {
                withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) {
                    showsDetails.toggle()
                }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    SectionLabel("Más detalles")
                    Spacer(minLength: Theme.Space.s)
                    if !showsDetails {
                        Text(detailsSummary)
                            .font(.ticket(.footnote))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.trailing)
                    }
                    Image(systemName: showsDetails ? "chevron.down" : "chevron.right")
                        .font(Theme.Symbol.regular)
                        .imageScale(.small)
                        .foregroundStyle(Theme.brass)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Theme.Size.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsDetails ? "Abierto" : detailsSummary)
            .accessibilityHint(showsDetails ? "Oculta el tipo, la fecha y si se repite"
                               : "Muestra el tipo, la fecha y si se repite")
            .accessibilityIdentifier("mas-detalles")

            if showsDetails {
                // A menu on the whole row, like the currency: the picker's own menu opened only
                // from its value at the far end.
                Menu {
                    Picker("Tipo", selection: kind) {
                        ForEach(Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack {
                        SectionLabel("Tipo")
                        Spacer(minLength: Theme.Space.s)
                        Text(kind.wrappedValue.title)
                            .font(.ticket(.body))
                            .foregroundStyle(Theme.brass)
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(Theme.faint)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Theme.Size.tapTarget)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("tipo")
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
                DatePicker(selection: $date, in: ...Date.now) {
                    SectionLabel("Fecha")
                }
                .accessibilityIdentifier("fecha")
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
            }
        } footer: {
            if showsDetails {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    switch kind.wrappedValue {
                    case .refund:
                        HintText("Una devolución resta de lo que llevas.")
                    case .uncounted:
                        HintText("Se queda en la lista con su monto, pero no suma a lo que llevas ni a «Hoy puedes gastar».")
                    case .expense:
                        EmptyView()
                    }
                    if repeatsMonthly {
                        HintText(FixedWording.howItRepeats(rule, from: date))
                    } else if expense?.isRepeat == true {
                        HintText("Se anotó solo, de un gasto fijo.")
                    }
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    /// «Llegó de Wallet · 28 oct 14:32», and the text exactly as it came, under what Wallet sent.
    @ViewBuilder private var walletOrigin: some View {
        if let expense, expense.rawAmount != nil || expense.rawNotice != nil {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HintText("Llegó de Wallet · " + Self.stamp(expense.date))
                if let notice = expense.rawNotice?.trimmingCharacters(in: .whitespacesAndNewlines), !notice.isEmpty {
                    HintText("«\(notice)»")
                } else if let raw = expense.rawAmount {
                    HintText("Monto como llegó: \(raw)")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("llego-de-wallet")
        }
    }

    /// «28 oct 14:32», in es-MX whatever the phone's language.
    static func stamp(_ date: Date) -> String {
        let day = date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_MX")))
        let time = date.formatted(Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: .current, calendar: .current))
        return "\(day) \(time)"
    }

    /// Places already paid at, one tap away while the name is typed.
    private var merchantSuggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                ForEach(merchantMatches, id: \.self) { name in
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

    /// The suggested one and the ones used most, then «Ver todas» for the rest; one tap picks
    /// one, another tap clears it. «Nueva categoría» writes a new one.
    private var categoryGrid: some View {
        let offered = CategoryStyle.offered(known: Array(knownCategories.prefix(8)),
                                            custom: customCategories, current: category,
                                            hidden: UserCatalog.decodeNames(storedHidden))
        let split = CategoryShortlist.split(offered: offered, mostUsed: knownCategories,
                                            pinned: [suggestedCategory ?? ""] + pinnedCategories + [category])
        let names = showsAllCategories ? offered : split.shown
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Size.categoryGridMinimum), spacing: Theme.Space.s)],
                         spacing: Theme.Space.s) {
            ForEach(names, id: \.self) { name in
                categoryChip(name, icon: CategoryStyle.icon(for: name, custom: customCategories),
                             selected: category == name, tint: colors.category(name)) {
                    category = category == name ? "" : name
                    if showsAllCategories, !category.isEmpty { pinnedCategories.append(name) }
                }
            }
            if !split.rest.isEmpty {
                categoryChip(showsAllCategories ? "Ver menos" : "Ver todas",
                             icon: showsAllCategories ? "chevron.up" : "ellipsis", selected: false,
                             identifier: "ver-todas-categorias") {
                    withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) {
                        showsAllCategories.toggle()
                    }
                }
                .accessibilityHint(showsAllCategories ? "Muestra solo las más usadas"
                                   : "\(split.rest.count) categorías más")
            }
            categoryChip("Nueva categoría", icon: "plus", selected: false) { creating = .category }
        }
        .padding(.vertical, Theme.Space.xs)
    }

    /// The cards and cash set up in «Tarjetas y categorías», plus any other a payment came
    /// with (Wallet names the card). The default one is already chosen on a new expense.
    private var sourceGrid: some View {
        let sources = paymentSources
        let names = PaymentChoices.names(sources: sources, known: knownCards, current: card)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Size.categoryGridMinimum), spacing: Theme.Space.s)],
                         spacing: Theme.Space.s) {
            ForEach(names, id: \.self) { name in
                categoryChip(name, icon: PaymentChoices.icon(for: name, sources: sources),
                             selected: UserCatalog.same(card, name), kind: "tarjeta", tint: colors.source(name)) {
                    card = UserCatalog.same(card, name) ? "" : name
                }
            }
            categoryChip("Agregar tarjeta", icon: "plus", selected: false, kind: "tarjeta") { creating = .source }
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityIdentifier("tarjetas")
    }

    /// `tint`: the icon's color, the category's or card's own; brass for the actions.
    private func categoryChip(_ name: String, icon: String, selected: Bool, kind: String = "categoria",
                              tint: Color = Theme.brass, identifier: String? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.xxs) {
                Image(systemName: icon)
                    .font(Theme.Symbol.regular)
                    // Every icon in the same box, so the names line up.
                    .frame(height: iconHeight)
                    .foregroundStyle(selected ? Theme.onBrass : tint)
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
        .accessibilityIdentifier(identifier ?? "\(kind)-\(name)")
    }

    // MARK: Reading and saving

    private func stopRepeating() {
        guard let original else { return }
        original.repeatsMonthly = nil
        original.repeatsThrough = nil
        original.repeatDay = nil
        dismiss()
    }

    /// The merchant's matches and remembered category, once per change of «Comercio».
    private func refreshMerchant(_ typed: String) {
        let rules = CategoryRules(stored: storedRules)
        merchantMatches = MerchantSuggestions.matches(for: typed, history: pastExpenses)
        rememberedCategory = CategoryMemory.remembered(for: typed, rules: rules, history: pastExpenses,
                                                       hidden: notAutoAssigned)
        suggestedCategory = rememberedCategory
            ?? CategoryMemory.suggestion(for: typed, rules: rules, history: pastExpenses, hidden: notAutoAssigned)
    }

    private func load() {
        // One read of the history when the sheet opens, not a live query redrawn on every key.
        let history = (try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        pastExpenses = history.map(\.categorized)
        knownCategories = CategoryMemory.known(in: pastExpenses)
        knownCards = PaymentChoices.mostUsedCards(history.prefix(300).map(\.card))
        guard let expense else {
            if let initialDate { date = initialDate }
            card = defaultSource
            refreshMerchant("")
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
        pinnedCategories = [category]
        date = expense.date
        original = originalOfCopy(expense)
        refreshMerchant(expense.merchant)
        // Anything set in «Más detalles» is shown, not hidden behind it.
        showsDetails = isRefund || !counts || repeatsMonthly || expense.isRepeat == true
            || (expense.latitude != nil && expense.longitude != nil)
    }

    /// The fixed expense a copy came from: same merchant and amount, still repeating.
    private func originalOfCopy(_ expense: Expense) -> Expense? {
        guard expense.isRepeat == true else { return nil }
        let merchant = expense.merchant, amount = expense.amount
        let candidates = try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate {
            $0.repeatsMonthly == true && $0.merchant == merchant
        }))
        return candidates?.first { $0.amount == amount }
    }

    /// Fills the fields from `sentence` by plain rules. Nothing is saved until «Guardar». A
    /// sentence with no amount says so, instead of doing nothing.
    private func fillFromSentence() async {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !readingSentence else { return }
        readingSentence = true
        defer { readingSentence = false }
        let sources = paymentSources.map(\.name)
        guard let entry = await QuickExpense.read(text, sources: sources),
              let parsed = AmountParser.parse(entry.amountText) else {
            sentenceProblem = "No encontré un monto en «\(text)». Escríbelo arriba."
            sentence = ""
            amountFocused = true
            return
        }
        amountText = parsed.value.magnitude.formatted(.number.precision(.fractionLength(0...2)))
        currency = ExpenseRecorder.spokenCurrency(parsed.currencyMarker, primary: CurrencyPreference.current)
        // After the amount: changing it clears the problem line.
        sentenceProblem = nil
        if let name = entry.merchant { merchant = name }
        date = min(entry.date, .now)
        if let source = entry.source { card = source }
        sentence = ""
    }

    /// «No cuenta»: leaves it out for the chosen reason; counting again counts it in full and
    /// keeps the reason for next time.
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
        let name = savedName
        // With no merchant typed the category names it; that is not a merchant to learn.
        let typedMerchant = !trimmedMerchant.isEmpty
        let cardName = card.trimmingCharacters(in: .whitespaces)
        let categoryName = trimmedCategory
        let value = isRefund ? -parsed.value.magnitude : parsed.value.magnitude
        // Saved as its ISO code, never "$": a bare "$" would follow the month's currency and
        // change meaning if that is switched later.
        if let expense {
            expense.amount = value
            let before = CurrencyResolver.isoCode(for: expense.currencyMarker,
                                                  primary: CurrencyPreference.current)
            if before != currency { expense.currencyMarker = currency }
            // A name typed here reads as typed, and the model leaves it alone.
            if name != expense.merchant {
                expense.displayName = name
                // What Wallet sends with the old name from now on comes in with this one.
                if typedMerchant { UserCatalog.learnRename(expense.merchant, to: name) }
            }
            expense.merchant = name
            expense.card = cardName.isEmpty ? nil : cardName
            // Another category is a choice; keeping the suggested one leaves it a suggestion,
            // and taking it off means none, not «suggest another».
            if categoryName != (expense.category ?? "") {
                expense.categorySource = categoryName.isEmpty ? Expense.clearedCategory : nil
                // The newest choice is what the next expense from here starts with, even when
                // this one is older than others from the same place.
                if typedMerchant { UserCatalog.learnCategory(categoryName, for: name) }
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
            if typedMerchant, !categoryName.isEmpty { UserCatalog.learnCategory(categoryName, for: name) }
            // A place picked from the suggestions reads as it did before.
            if typedMerchant {
                var same = FetchDescriptor<Expense>(predicate: #Predicate { $0.merchant == name },
                                                    sortBy: [SortDescriptor(\.date, order: .reverse)])
                same.fetchLimit = 1
                new.displayName = (try? context.fetch(same))?.first?.displayName
            }
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

/// The ways to pay offered to pick from, the same in the expense sheet and «Nuevo gasto fijo».
enum PaymentChoices {
    /// The ones set up, cash (always there, nothing to set up), then cards past payments came
    /// with, then the current one; each name once.
    static func names(sources: [LabeledIcon], known: [String], current: String) -> [String] {
        var names = sources.map(\.name)
        if !names.contains(where: { UserCatalog.same($0, "Efectivo") }) { names.append("Efectivo") }
        for name in known + [current] where !name.isEmpty && !names.contains(where: { UserCatalog.same($0, name) }) {
            names.append(name)
        }
        return names
    }

    static func icon(for name: String, sources: [LabeledIcon]) -> String {
        sources.first { UserCatalog.same($0.name, name) }?.icon
            ?? (UserCatalog.same(name, "Efectivo") ? "banknote" : "creditcard")
    }

    /// Cards from past payments, most used first.
    static func mostUsedCards(_ cards: [String?], limit: Int = 4) -> [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for card in cards {
            guard let name = card?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
            counts[UserCatalog.fold(name), default: (name, 0)].count += 1
        }
        return counts.values.sorted { $0.count > $1.count }.prefix(limit).map(\.name)
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
