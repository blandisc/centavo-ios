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
    /// What a new expense starts filled with: a Wallet payment the capture couldn't write down
    /// (`PendingPayment.prefill`). What it doesn't know keeps the sheet's own start.
    var prefill: ExpensePrefill?
    /// How the list deletes, so «Deshacer» works from here too. Without it, a plain delete.
    var onDelete: ((Expense) -> Void)?
    /// Called once a new expense is saved, and only then (never on «Cancelar» or a failed save).
    var onSave: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var amountText = ""
    /// The amount as the sheet showed it on opening: left as it was, the amount isn't rewritten
    /// (0.125 shown as «0.13» became 0.13 when only the category changed).
    @State private var loadedAmountText: String?
    /// What a new expense's sheet held once it opened (after `prefill`, if any, filled it): it
    /// has changes only once the person touches something, so «Cancelar» on a sheet nobody
    /// touched just closes. Kept for every new one, not only a prefilled one: a currency, a
    /// date or «Se repite» changed alone closed without asking (2026-11-18).
    @State private var openedState: String?
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
    @State private var date = AppClock.now
    /// The date was picked (by hand or in a sentence). A new one left alone is saved at the
    /// moment of «Guardar»: opened at 23:58 on the 31st and saved after midnight, it landed in
    /// the month that had ended and seemed lost (2026-11-18).
    @State private var dateChosen = false
    @State private var repeatsMonthly = false
    /// How often it comes back, once «Se repite» is on.
    @State private var rule = RepeatRule.monthly
    @State private var confirmingDelete: Expense?
    /// «Borrar gasto» on a fixed expense still repeating: its own question, which says it stops.
    @State private var confirmingFixedDelete: Expense?
    @State private var confirmingStop = false
    /// «Se repite» turned off on a fixed expense still repeating, and «Dejar de repetir» said
    /// yes to: «Guardar» goes on and stops it as that button does (2026-11-18).
    @State private var stopConfirmed = false
    /// A new expense already saved: a second tap on «Guardar» while the sheet goes down saved
    /// it twice (2026-11-18).
    @State private var savedOnce = false
    /// «Cancelar» or a swipe down with something changed: «¿Descartar cambios?».
    @State private var askingDiscard = false
    /// A save that didn't go through: said, and the sheet stays open with what was typed.
    @State private var saveProblem: SaveProblem?
    /// «Más detalles»: open by itself when the expense has something set there.
    @State private var showsDetails = false
    /// «Ver todas»: the whole category list instead of the short one.
    @State private var showsAllCategories = false
    /// «Ver menos» fading the rest before their room closes.
    @State private var fadingCategories = false
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
    /// Said when what was pasted in the amount named a currency this sheet doesn't offer.
    /// Only emptying the amount clears it: the field's own rewrite of the paste is a change too.
    @State private var pasteProblem: String?

    // Read once when the sheet opens, or when «Comercio» changes: rebuilding them from the
    // whole history on every key typed was felt with thousands of expenses (audit R10).
    @AppStorage(BudgetStore.key) private var storedBudget = ""
    @State private var pastExpenses: [CategorizedExpense] = []
    /// The merchants of `pastExpenses`, folded once for the suggestions.
    @State private var merchantIndex = MerchantSuggestions.Index()
    @State private var knownCategories: [String] = []
    @State private var knownCards: [String] = []
    @State private var merchantMatches: [String] = []
    /// The category you chose for what is typed in «Comercio», if you ever did.
    @State private var rememberedCategory: String?
    /// What a new expense from that merchant starts with: yours, else the catalog's guess.
    @State private var suggestedCategory: String?
    /// The category was filled in from the merchant, not picked: another merchant changes it,
    /// and saving doesn't teach it as a choice («Uber» filled «Transporte», the name was fixed
    /// to «Oxxo» and Oxxo was learned as Transporte, 2026-11-18).
    @State private var categoryAutofilled = false
    /// What each merchant was last filed under, read once with the history: «Comercio» looks
    /// it up on every key instead of going over every expense again (2026-11-18).
    @State private var latestCategories: [String: String] = [:]
    /// Categories that stay in the short list once they were in it (the expense's own, one
    /// picked from «Ver todas»), so a tap never makes a tile jump away.
    @State private var pinnedCategories: [String] = []
    /// The fixed expense a copy came from, found once.
    @State private var original: Expense?
    /// «Quitar ubicación» was tapped: the place goes on «Guardar», and «Cancelar» keeps it.
    @State private var removesPlace = false
    /// The other expenses from this same merchant (the texts in `merchantTexts`), read once:
    /// the ones a correction made here can also reach, if asked.
    @State private var siblings: [Expense] = []
    @State private var merchantTexts: [String] = []
    /// «Cambiar también los otros»: off until someone turns it on.
    @State private var changesOthers = false

    private enum Creating: String, Identifiable { case category, source; var id: String { rawValue } }

    /// «Tipo»: one choice instead of two switches. Refund and «No cuenta» keep their meaning:
    /// a refund is a negative amount; «No cuenta» stays in the list with nothing counted.
    private enum Kind: Hashable, CaseIterable {
        case expense, refund, uncounted
        var title: String {
            switch self {
            case .expense: String(localized: "Gasto")
            case .refund: String(localized: "Devolución")
            case .uncounted: String(localized: "No cuenta")
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

    /// What a new expense's fields hold, to compare with how the sheet opened.
    private var fieldsState: String {
        let flags = ["\(counts)", "\(isRefund)", "\(repeatsMonthly)", "\(date.timeIntervalSinceReferenceDate)"]
        return ([amountText, currency, merchant, card, category] + flags).joined(separator: "\u{1F}")
    }

    /// Whether something was typed or changed since the sheet opened.
    private var hasChanges: Bool {
        guard let expense else {
            if let openedState { return fieldsState != openedState }
            let changedCard = UserCatalog.same(card, defaultSource) ? "" : card
            return !(amountText + merchant + changedCard + category).trimmingCharacters(in: .whitespaces).isEmpty
                || !counts || isRefund
        }
        // In parts: one long chain is slow for the CI's older type-checker.
        let amountChanged = (amountText != loadedAmountText && parsed?.value != expense.amount.magnitude)
            || isRefund != (expense.amount < 0)
        let kindChanged = counts == expense.isUncounted || (!counts && reason != (expense.reason ?? .reimbursed))
        let namesChanged = merchant != expense.merchant || card != (expense.card ?? "")
            || category != (expense.category ?? "")
        // The currency as `load` read it: changed alone, «Cancelar» closed without asking (2026-11-18).
        let loadedCurrency = CurrencyResolver.isoCode(for: expense.currencyMarker, primary: CurrencyPreference.current)
            ?? CurrencyPreference.current
        let repeatsChanged = repeatsMonthly != (expense.repeatsMonthly == true) || (repeatsMonthly && rule != expense.rule)
        let whenChanged = currency != loadedCurrency || date != expense.date
        let contentChanged = amountChanged || kindChanged || namesChanged
        return contentChanged || whenChanged || repeatsChanged || removesPlace
    }

    /// The correction being made to this expense's name or category, as it would reach the
    /// others from the same merchant; `nil` when neither changed.
    private var backfill: MerchantBackfill? {
        guard let expense, !trimmedMerchant.isEmpty, !siblings.isEmpty else { return nil }
        let renamed = savedName != expense.merchant
        let choseCategory = trimmedCategory != (expense.category ?? "")
        guard renamed || choseCategory else { return nil }
        // A name the owner gave before goes on the ones that arrived before it; a suggestion
        // nobody confirmed is not passed on.
        return MerchantBackfill(texts: merchantTexts,
                                name: renamed || merchantTexts.count > 1 ? savedName : nil,
                                category: choseCategory || !expense.hasSuggestedCategory ? trimmedCategory : nil,
                                replacing: expense.category)
    }

    /// «230.» (a point just pressed) reads as 230 here: «Guardar» stays on (2026-11-18).
    private var parsed: ParsedAmount? { AmountParser.parseTyped(amountText) }
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
        // What is wrong with the amount, said apart: «0» or an unreadable one said «Falta el
        // monto» with something typed in view (2026-11-18).
        guard let parsed else {
            if amountText.contains(where: \.isNumber) { return String(localized: "No se entiende el monto") }
            return String(localized: "Falta el monto")
        }
        guard parsed.value != 0 else { return String(localized: "El monto no puede ser cero") }
        guard !savedName.isEmpty else { return String(localized: "Falta el comercio") }
        // With its code when it isn't the main currency: pesos next to dollars read as «MX$230.00»,
        // never a bare «$» (2026-11-02, 2026-11-18).
        let money = formatMoney(parsed.value.magnitude, isoCode: currency, label: currency,
                                main: CurrencyPreference.current)
        var parts = [(isRefund ? "+" : "") + money, savedName]
        let cardName = card.trimmingCharacters(in: .whitespaces)
        if !cardName.isEmpty { parts.append(cardName) }
        if !counts { parts.append(String(localized: "No cuenta")) }
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
        let day: String
        if AppClock.isToday(date) {
            day = String(localized: "Hoy")
        } else {
            day = date.formatted(.dateTime.day().month(.abbreviated).locale(Locale.current))
        }
        var parts = [day]
        parts.append(kind.wrappedValue.title)
        if repeatsMonthly || expense?.isRepeat == true { parts.append(String(localized: "Fijo")) }
        return parts.joined(separator: " · ")
    }

    /// What VoiceOver says of «Más detalles»: open, or what it holds while closed.
    private var detailsValue: String {
        if showsDetails { return String(localized: "Abierto") }
        return detailsSummary
    }

    private var detailsHint: String {
        if showsDetails { return String(localized: "Oculta el tipo, la fecha y si se repite") }
        return String(localized: "Muestra el tipo, la fecha y si se repite")
    }

    /// The sheet's title: a new expense or one being corrected.
    private var barTitle: LocalizedStringResource {
        if expense == nil { return "Nuevo gasto" }
        return "Editar gasto"
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { form in
            Form {
                amountSection
                merchantSection
                categorySection
                othersSection
                sourceSection
                detailsSection

                if showsDetails, !removesPlace, let expense, let latitude = expense.latitude, let longitude = expense.longitude {
                    Section {
                        PlaceMap(expense: expense,
                                 coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                 onRemove: { removesPlace = true })
                    } header: {
                        Text("Dónde").ticketCaption()
                    } footer: {
                        HintText("Dónde estaba tu iPhone al anotarse. En compras en línea es donde estabas tú.")
                    }
                    .listRowBackground(Theme.surface)
                }

                if let expense, expense.maybeRepeated == true {
                    Section {
                        Button {
                            expense.maybeRepeated = nil
                            persist()
                        } label: { LinkActionLabel("No es repetida, son dos") }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("no-es-repetida")
                    } header: {
                        Text("¿Repetida?").ticketCaption()
                    } footer: {
                        HintText("Llegó igual a otro pago de hace unos minutos. Si es el mismo, bórrala; si fueron dos compras, toca arriba.")
                    }
                    .listRowBackground(Theme.surface)
                }

                if expense?.isRepeat == true, original != nil {
                    Section {
                        Button { confirmingStop = true } label: { LinkActionLabel("Dejar de repetir") }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("dejar-de-repetir")
                    } footer: {
                        HintText("Lo ya anotado se queda; el siguiente ya no llega.")
                    }
                    .listRowBackground(Theme.surface)
                }

                if expense != nil {
                    Section {
                        DestructiveRowButton("Borrar gasto", identifier: "borrar-gasto") {
                            // A fixed expense still repeating stops with it: its question says so.
                            if expense?.repeatsMonthly == true {
                                confirmingFixedDelete = expense
                            } else {
                                confirmingDelete = expense
                            }
                        }
                    } footer: {
                        walletOrigin
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .ticketForm()
            // On a smaller iPhone, with the keyboard up, the merchant's suggestions ended under
            // «Guardar» and a tap on one landed on the bar (found on iOS 26, 2026-11-12): the
            // form brings the merchant to the top, so they are always in view.
            .onChange(of: merchantFocused) { _, focused in if focused { reveal(merchant: form) } }
            // The number pad has no key to close it and covers half the sheet: scrolling down to
            // the categories or the card closes it.
            .scrollDismissesKeyboard(.immediately)
            // iOS 26 ignores the line above in a sheet's form: a drag does it there.
            .simultaneousGesture(DragGesture(minimumDistance: 24).onChanged { drag in
                // Only up or down: sideways is the merchant's suggestions scrolling, and closing
                // the keyboard took them away mid-swipe (2026-11-18).
                guard abs(drag.translation.height) > abs(drag.translation.width) else { return }
                if amountFocused { amountFocused = false }
                if merchantFocused { merchantFocused = false }
            })
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
            .saveBar(saveSummary, enabled: canSave && !savedOnce, action: save)
            .problemAlert(problem: $saveProblem)
            .alert("Dilo en una frase", isPresented: $askingSentence) {
                TextField("230 de tacos ayer, en efectivo", text: $sentence) // ds-allow: campo dentro de una alerta del sistema; la alerta pone su letra
                    .accessibilityIdentifier("frase")
                Button("Llenar") { Task { await fillFromSentence() } }
                Button("Cancelar", role: .cancel) { sentence = "" }
            } message: {
                Text("Cuánto, dónde, qué día y cómo pagaste: «230 de tacos ayer, en efectivo». Revisa lo que se llenó antes de guardar.")
            }
            .confirmsRemoval(isPresented: $confirmingStop, question: {
                TicketQuestion(title: String(localized: "¿Dejar de repetir este gasto fijo?"),
                               name: expense?.displayName ?? expense?.merchant ?? "",
                               note: String(localized: "Lo ya anotado se queda; el siguiente ya no llega."),
                               verb: String(localized: "Dejar de repetir"))
            }, onConfirm: confirmStop)
            .confirmsRemoval(of: $confirmingFixedDelete, question: fixedDeleteQuestion, onConfirm: deleteExpense)
            .confirmsDelete(of: $confirmingDelete, primaryCurrency: CurrencyPreference.current,
                            undoable: onDelete != nil, onDelete: deleteExpense)
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
                    storedCategories = UserCatalog.encode(customCategories + [saved], keepingUnreadFrom: storedCategories)
                    UserCatalog.markDeleted(saved.name, false)
                    category = saved.name
                    categoryAutofilled = false
                    pinnedCategories.append(saved.name)
                }
            case .source:
                LabeledIconSheet(title: "Forma de pago", prompt: "BBVA, Nu, Efectivo…",
                                 icons: UserCatalog.sourceIcons, taken: paymentSources.map(\.name),
                                 colorKind: .source,
                                 siblings: PaymentChoices.names(sources: paymentSources, known: knownCards,
                                                                current: "")) { saved in
                    storedSources = UserCatalog.encode(paymentSources + [saved], keepingUnreadFrom: storedSources)
                    if defaultSource.isEmpty { defaultSource = saved.name }
                    card = saved.name
                }
            }
        }
        // Swiping the sheet away, or «Cancelar», must not throw away what was typed: they ask.
        .confirmsDiscard(hasChanges: hasChanges, isAsking: $askingDiscard) { dismiss() }
        .onChange(of: merchant) { _, new in
            refreshMerchant(new)
            // Change the merchant and the category you last used for it fills in, while the
            // field is empty or holds only what was filled in for the merchant before — never
            // overwrite a picked one. Only for a new expense: opening an uncategorized one must
            // not quietly file it.
            guard expense == nil, trimmedCategory.isEmpty || categoryAutofilled else { return }
            category = suggestedCategory ?? ""
            categoryAutofilled = suggestedCategory != nil
        }
        .onChange(of: amountText) { _, new in
            sentenceProblem = nil
            if new.isEmpty { pasteProblem = nil }
        }
    }

    // MARK: Sections

    private var amountSection: some View {
        Section {
            AdaptiveStack {
                AmountInputField("Monto", text: $amountText, prompt: "0.00", identifier: "monto",
                                 onPaste: takePasted)
                    .focused($amountFocused)
                    // The figure gives way, not «MXN ⌄» (2026-11-18).
                    .layoutPriority(1)
                HStack(spacing: Theme.Space.s) {
                    currencyMenu
                    // The decimal pad has no return key, and a keyboard bar does not show in
                    // this sheet: while the amount is typed, «Siguiente» lives in its row.
                    nextKey
                }
            }
            // In words and always in view on a new expense (owner, 2026-11-11): as an icon beside
            // the amount, hidden while the keyboard was up, hardly anyone found it.
            if expense == nil { sentenceButton }
        } header: {
            Text("Monto").ticketCaption()
        } footer: {
            if let sentenceProblem {
                NoteText(sentenceProblem)
                    .accessibilityIdentifier("frase-sin-monto")
            } else if let pasteProblem {
                NoteText(pasteProblem)
                    .accessibilityIdentifier("pegado-sin-moneda")
            }
        }
        .listRowBackground(Theme.surface)
    }

    /// «Hoy puedes gastar» is named only where there is one: with a budget (2026-11-18).
    private var uncountedHint: String {
        if BudgetStore.amount(from: storedBudget) != nil {
            return String(localized: "Se queda en la lista con su monto, pero no suma a lo que llevas ni a «Hoy puedes gastar».")
        }
        return String(localized: "Se queda en la lista con su monto, pero no suma a lo que llevas.")
    }

    /// «USD 25.00» or «-$50» pasted in the amount: the field keeps the figure, and the sheet
    /// keeps the rest (2026-11-18: the currency and the sign were lost). A minus is money that
    /// came back, shown open so it is seen before saving. A bare «$» is the main currency.
    private func takePasted(_ pasted: ParsedAmount) {
        if pasted.value < 0 {
            isRefund = true
            counts = true
            showsDetails = true
        }
        guard let marker = pasted.currencyMarker, !CurrencyResolver.isAmbiguous(marker) else { return }
        let code = CurrencyResolver.isoCode(for: marker, primary: CurrencyPreference.current)
        if let code, currencies.contains(code) {
            currency = code
            pasteProblem = nil
        } else {
            pasteProblem = String(localized: "No reconocí la moneda de lo que pegaste. Elígela junto al monto.")
        }
    }

    /// «Siguiente», shown only while the amount is typed. Its room is always kept: put in and
    /// taken out, it pushed «MXN ⌄» aside each time the keyboard came and went (2026-11-18).
    private var nextKey: some View {
        Button("Siguiente", systemImage: "arrow.right") { merchantFocused = true }
            .labelStyle(.iconOnly)
            .font(.ticket(.footnoteStrong))
            .foregroundStyle(Theme.brass)
            // The arrow on the card's edge, mirroring «0.00»; the target stays 44.
            .frame(minWidth: Theme.Size.tapTarget, minHeight: Theme.Size.tapTarget,
                   alignment: .trailing)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .opacity(amountFocused ? Theme.Opacity.visible : Theme.Opacity.hidden)
            .allowsHitTesting(amountFocused)
            .accessibilityHidden(!amountFocused)
            .animation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion), value: amountFocused)
            .accessibilityIdentifier("siguiente-teclado")
    }

    /// The decimal pad cannot type "USD" or "€", so the currency is a choice next to the amount.
    private var currencyMenu: some View {
        Menu {
            Picker("Moneda", selection: $currency) {
                CurrencyOptions(codes: currencies)
            }
        } label: {
            HStack(spacing: Theme.Space.xxs) {
                Text(currency)
                    .font(.ticket(.label))
                    .tracking(Theme.Tracking.label)
                Image(systemName: "chevron.down") // ds-allow: parte de «MXN ⌄»: lleva el color de la moneda
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
        // «pesos», not «M X N» spelled out (2026-11-18).
        .accessibilityValue(CurrencyPreference.spoken(currency))
        .accessibilityIdentifier("moneda")
    }

    /// The whole expense in one sentence, written or dictated: a row of its own under the amount.
    private var sentenceButton: some View {
        Button { askingSentence = true } label: {
            LinkActionLabel("Dilo en una frase", systemImage: "text.bubble", alignment: .leading)
        }
        .buttonStyle(.borderless)
        .disabled(readingSentence)
        .accessibilityHint("«230 de tacos ayer, en efectivo» llena el monto, el comercio, el día y cómo pagaste.")
        .accessibilityIdentifier("en-una-frase")
    }

    private var merchantSection: some View {
        Section {
            TicketTextField("Comercio", text: $merchant, prompt: String(localized: "Nombre del comercio"), identifier: "comercio")
                .textInputAutocapitalization(.words)
                // «Oxxo» and «Rappi» are not in the dictionary: corrected, they no longer match
                // what Wallet sends (2026-11-18).
                .autocorrectionDisabled()
                .focused($merchantFocused)
                .submitLabel(.done)
                .id(Self.merchantRow)
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
        // Worked out once per drawing: every row below needs it.
        let split = categorySplit
        let fill = categoryFill(split)
        let more = Array(split.rest.dropFirst(fill))
        return Section {
            // «Ver más» adds the rest as a row of its own, which the list slides in once, under the
            // ones in view (which never move), and «Nueva» and «Ver más» ride down. Grown frame by
            // frame inside one row, the whole form laid itself out again on every frame and
            // stuttered (owner, 2026-11-04).
            categoryGrid(split, fill: fill)
                .categoryRow(top: Theme.Space.xl, bottom: Theme.Space.none)
            if showsAllCategories, !more.isEmpty {
                moreCategories(more)
                    .categoryRow(top: Theme.Space.s, bottom: Theme.Space.none)
            }
            categoryActions(more: more.count)
                .categoryRow(top: Theme.Space.s, bottom: Theme.Space.xl)
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

    /// «Cambiar también los otros 6 gastos»: shown only while this correction (a new name, another
    /// category) would change other expenses that arrived with the same text. Nothing changes
    /// unless it is turned on, and all of it is saved with this expense, in one save.
    @ViewBuilder private var othersSection: some View {
        if let backfill, let expense {
            let count = backfill.pending(in: siblings).count
            if count > 0 {
                Section {
                    Toggle(isOn: $changesOthers) {
                        SectionLabel(MerchantBackfill.offer(count))
                    }
                    .tint(Theme.brass)
                    .accessibilityIdentifier("cambiar-los-otros")
                } footer: {
                    HintText("Los que llegaron como «\(expense.merchant)» quedan como este. El que tenga otra categoría puesta por ti la conserva.")
                }
                .listRowBackground(Theme.surface)
            }
        }
    }

    private var sourceSection: some View {
        Section {
            sourceGrid
        } header: {
            Text("Forma de pago · opcional").ticketCaption()
        } footer: {
            if paymentSources.isEmpty {
                HintText("Agrega tus formas de pago una vez (BBVA, Nu…). La que dejes por defecto en «··· › Categorías» ya vendrá elegida.")
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
                    RowChevron(.discloses(showsDetails))
                }
                .frame(minHeight: Theme.Size.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(detailsValue)
            .accessibilityHint(detailsHint)
            .accessibilityIdentifier("mas-detalles")

            if showsDetails {
                // A menu on the whole row, like the currency: the picker's own menu opened only
                // from its value at the far end, and wrote it in the iPhone's typeface.
                TicketMenuPicker("Tipo", selection: kind, value: kind.wrappedValue.title) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("tipo")
                if !counts {
                    TicketMenuPicker("Motivo", selection: $reason, value: reason.title) {
                        ForEach(UncountedReason.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("motivo")
                }
                DatePicker(selection: chosenDate, in: ...AppClock.now) {
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
                        HintText(uncountedHint)
                    case .expense:
                        EmptyView()
                    }
                    if repeatsMonthly {
                        HintText(FixedWording.howItRepeats(rule, from: date))
                        if let started = expense, started.repeatsMonthly == true {
                            // The original is the first charge too: its amount is that charge's.
                            let firstCharge = started.date.formatted(.dateTime.day().month(.wide).locale(Locale.current))
                            HintText("Cambiar el monto cambia también el primer cobro, del \(firstCharge). Para un aumento, deja de repetir este y agrega uno nuevo.")
                        }
                    } else if let copyHint {
                        HintText(copyHint)
                    }
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    /// Under «Más detalles» of a copy of a fixed expense. A stopped original is one of its own
    /// copies, but it was written by hand: «Se anotó solo» was not true of it (2026-11-18).
    private var copyHint: String? {
        guard let expense, expense.isRepeat == true else { return nil }
        let stoppedOriginal = expense.fixedID != nil && expense.fixedOf == expense.fixedID
        if stoppedOriginal { return String(localized: "Fue un gasto fijo; ya no se repite.") }
        return String(localized: "Se anotó solo, de un gasto fijo.")
    }

    /// «Llegó de Wallet · 28 oct 14:32», and the text exactly as it came, under what Wallet sent.
    @ViewBuilder private var walletOrigin: some View {
        if let expense, expense.rawAmount != nil || expense.rawNotice != nil {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HintText("Llegó de Wallet · \(Self.stamp(expense.date))")
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

    /// «28 oct 14:32», the day in the iPhone's language and the time on a 24-hour clock.
    static func stamp(_ date: Date) -> String {
        let day = date.formatted(.dateTime.day().month(.abbreviated).locale(Locale.current))
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
                    TicketChip(name) {
                        merchant = name
                        // The merchant is done: the keyboard would only cover the categories.
                        merchantFocused = false
                    }
                    .accessibilityHint("Usa este comercio")
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("comercios-sugeridos")
    }

    /// The suggested one and the ones used most first, the rest behind «Ver más».
    private var categorySplit: (shown: [String], rest: [String]) {
        let offered = CategoryStyle.offered(known: Array(knownCategories.prefix(8)),
                                            custom: customCategories, current: category,
                                            hidden: UserCatalog.decodeNames(storedHidden))
        return CategoryShortlist.split(offered: offered, mostUsed: knownCategories,
                                       pinned: [suggestedCategory ?? ""] + pinnedCategories + [category])
    }

    /// How many fit side by side, measured from the grid: what of the rest fills the last row
    /// of the ones in view.
    @State private var categoryColumns = 1
    private var categoryGridColumns: [GridItem] { CategoryTile.columns(for: typeSize) }
    /// One per row with accessibility sizes (`CategoryTile.columns`), whatever was measured.
    private var columnsInView: Int { typeSize.isAccessibilitySize ? 1 : categoryColumns }

    /// How many of the rest fit in the last row of the ones in view: they show there from the
    /// start, and the others go in a row of their own behind «Ver más».
    private func categoryFill(_ split: (shown: [String], rest: [String])) -> Int {
        let columns = columnsInView
        let open = (columns - split.shown.count % columns) % columns
        return min(open, split.rest.count)
    }

    /// The suggested one and the ones used most, then «Ver más» for the rest; one tap picks
    /// one, another tap clears it.
    private func categoryGrid(_ split: (shown: [String], rest: [String]), fill: Int) -> some View {
        let names = split.shown + split.rest.prefix(fill)
        return LazyVGrid(columns: categoryGridColumns, spacing: Theme.Space.s) {
            // The last row is always full: what of the rest fits there shows from the start, so no
            // square is left empty until a category is picked (owner, 2026-11-11).
            ForEach(names, id: \.self) { categoryButton($0) }
        }
        .onGeometryChange(for: Int.self) { proxy in
            Int((proxy.size.width + Theme.Space.s) / (Theme.Size.categoryGridMinimum + Theme.Space.s))
        } action: { categoryColumns = max($0, 1) }
    }

    private func moreCategories(_ names: [String]) -> some View {
        ArrivingRow(leaving: fadingCategories) { shown in
            LazyVGrid(columns: categoryGridColumns, spacing: Theme.Space.s) {
                ForEach(Array(names.enumerated()), id: \.element) { index, name in
                    categoryButton(name).arriving(shown: shown, order: index)
                }
            }
        }
    }

    private func categoryButton(_ name: String) -> some View {
        categoryChip(name, icon: CategoryStyle.icon(for: name, custom: customCategories),
                     selected: category == name, tint: colors.category(name)) {
            category = category == name ? "" : name
            categoryAutofilled = false
            if showsAllCategories, !category.isEmpty { pinnedCategories.append(name) }
        }
    }

    /// «Nueva categoría» writes a new one; «Ver más» opens the rest. A row of their own under
    /// the grid.
    private func categoryActions(more count: Int) -> some View {
        HStack(spacing: Theme.Space.s) {
            Button { creating = .category } label: {
                LinkActionLabel("Nueva", systemImage: "plus", fillsWidth: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nueva categoría")
            .accessibilityIdentifier("categoria-Nueva categoría")
            Spacer(minLength: Theme.Space.s)
            if count > 0 {
                Button {
                    // Opening, the room opens at once and the rest shows once it is there; closing,
                    // the rest fades first and the room closes after, so nothing draws over what moves.
                    if showsAllCategories {
                        withAnimation(Theme.Motion.animation(Theme.Motion.revealOut, reduceMotion: reduceMotion)) {
                            fadingCategories = true
                        } completion: {
                            withAnimation(Theme.Motion.animation(Theme.Motion.fold, reduceMotion: reduceMotion)) {
                                showsAllCategories = false
                            }
                            fadingCategories = false
                        }
                    } else {
                        withAnimation(Theme.Motion.animation(Theme.Motion.fold, reduceMotion: reduceMotion)) {
                            showsAllCategories = true
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Space.xs) {
                        // Swapped at once: blended while the button moves, both read as one blur.
                        Text(moreTitle(count))
                            .contentTransition(.identity)
                        Image(systemName: "chevron.down") // ds-allow: parte de «Ver 6 más ⌄»
                            .rotationEffect(.degrees(showsAllCategories ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .font(.ticket(.footnoteStrong))
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: Theme.Size.tapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(moreHint(count))
                .accessibilityIdentifier("ver-todas-categorias")
            }
        }
    }

    /// «Ver 6 más» or «Ver menos», on the button that opens the rest of the categories.
    private func moreTitle(_ count: Int) -> String {
        if showsAllCategories { return String(localized: "Ver menos") }
        return String(localized: "Ver \(count) más")
    }

    private func moreHint(_ count: Int) -> String {
        if showsAllCategories { return String(localized: "Muestra solo las más usadas") }
        return String(localized: "\(count) categorías más")
    }

    /// The cards and cash set up in «Pagos y categorías», plus any other a payment came
    /// with (Wallet names the card). The default one is already chosen on a new expense.
    private var sourceGrid: some View {
        let sources = paymentSources
        let names = PaymentChoices.names(sources: sources, known: knownCards, current: card)
        return LazyVGrid(columns: CategoryTile.columns(for: typeSize), spacing: Theme.Space.s) {
            ForEach(names, id: \.self) { name in
                categoryChip(name, icon: PaymentChoices.icon(for: name, sources: sources),
                             selected: UserCatalog.same(card, name), kind: "tarjeta", tint: colors.source(name)) {
                    card = UserCatalog.same(card, name) ? "" : name
                }
            }
            categoryChip("Nueva", icon: "plus", selected: false, isAction: true, identifier: "nueva-forma-de-pago") {
                creating = .source
            }
            .accessibilityLabel("Nueva forma de pago")
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityIdentifier("tarjetas")
    }

    /// `tint`: the icon's color, the category's or card's own. `isAction` for «Ver todas»,
    /// «Nueva categoría» and «Agregar».
    private func categoryChip(_ name: String, icon: String, selected: Bool, kind: String = "categoria",
                              tint: Color = Theme.brass, isAction: Bool = false, identifier: String? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CategoryTile(name: name, icon: icon, color: tint, selected: selected, isAction: isAction)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? "\(kind)-\(name)")
    }

    // MARK: Reading and saving

    private func stopRepeating() {
        guard let original else { return }
        // The original keeps counting as the fixed charge it was (`RecurringExpenses.stopRepeating`).
        RecurringExpenses.stopRepeating(original)
        if persist() { dismiss() }
    }

    /// «Dejar de repetir» said yes to: on a copy, its original stops; on the original itself,
    /// with «Se repite» turned off, «Guardar» goes on and stops it the same way.
    private func confirmStop() {
        if expense?.repeatsMonthly == true {
            stopConfirmed = true
            save()
        } else {
            stopRepeating()
        }
    }

    /// The date as «Más detalles» changes it: picked, it is kept as it is on «Guardar».
    private var chosenDate: Binding<Date> {
        Binding(get: { date }, set: { new in
            date = new
            dateChosen = true
        })
    }

    private func deleteExpense(_ expense: Expense) {
        if let onDelete {
            onDelete(expense)
            dismiss()
        } else {
            context.delete(expense)
            if persist() { dismiss() }
        }
    }

    /// «¿Borrar este gasto fijo?»: one still repeating stops with it, and the question says so;
    /// the plain one read as any expense's (2026-11-18).
    private func fixedDeleteQuestion(_ expense: Expense) -> TicketQuestion {
        let note: String
        if onDelete != nil {
            note = String(localized: "Deja de repetirse. Este cobro se borra; los siguientes ya anotados se quedan. Podrás deshacerlo unos segundos.")
        } else {
            note = String(localized: "Deja de repetirse. Este cobro se borra; los siguientes ya anotados se quedan. No se puede deshacer.")
        }
        return TicketQuestion(title: String(localized: "¿Borrar este gasto fijo?"),
                              figure: ledgerAmount(for: expense, primary: CurrencyPreference.current),
                              name: expense.shownName,
                              note: note)
    }

    /// Said once the sheet is down, for VoiceOver: the list's own focus change would cut it off
    /// if said while the sheet goes (2026-11-18: saving said nothing at all).
    /// With a budget, today's figure follows, worked out from what was just saved:
    /// «Anotado: $89.00 · Oxxo. Hoy puedes gastar $180.», as Siri says it.
    private func announceSaved(_ text: String) {
        guard voiceOver else { return }
        var today: String?
        if let budget = MonthStatus.savedBudget {
            today = try? MonthStatus.todaySentence(in: context, budget: budget)
        }
        let spoken = [text + ".", today].compactMap { $0 }.joined(separator: " ")
        Task { @MainActor in
            try? await Task.sleep(for: Self.announceAfter)
            AccessibilityNotification.Announcement(spoken).post()
        }
    }

    /// Every change someone makes is saved right then, not left to autosave: if it fails, it's
    /// said and nothing half-done stays behind.
    @discardableResult
    private func persist() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            saveProblem = SaveProblem(title: "No se guardó el gasto", detail: SaveProblem.unchangedPersisting)
            return false
        }
    }

    /// The merchant's matches and remembered category, once per change of «Comercio».
    private static let merchantRow = "comercio-renglon"
    /// The keyboard's rise: the form is moved once it is up, or the system's own scroll undoes it.
    private static let keyboardRise = Duration.milliseconds(350)
    /// The sheet's way down, and a beat for VoiceOver to land on the list.
    private static let announceAfter = Duration.milliseconds(700)

    private func reveal(merchant form: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: Self.keyboardRise)
            guard merchantFocused else { return }
            withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) {
                form.scrollTo(Self.merchantRow, anchor: .top)
            }
        }
    }

    private func refreshMerchant(_ typed: String) {
        let rules = CategoryRules(stored: storedRules)
        merchantMatches = MerchantSuggestions.matches(for: typed, in: merchantIndex)
        rememberedCategory = CategoryMemory.remembered(for: typed, rules: rules, latest: latestCategories,
                                                       hidden: notAutoAssigned)
        // With nothing remembered only the catalog is left: an empty history spares a second
        // pass over every expense on every key (2026-11-18, with 5,000 expenses).
        suggestedCategory = rememberedCategory
            ?? CategoryMemory.suggestion(for: typed, rules: rules, history: [], hidden: notAutoAssigned)
    }

    private func load() {
        // One read of the history when the sheet opens, not a live query redrawn on every key.
        let history = (try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        pastExpenses = history.map(\.categorized)
        merchantIndex = MerchantSuggestions.Index(pastExpenses)
        latestCategories = CategoryMemory.latest(in: pastExpenses)
        knownCategories = CategoryMemory.known(in: pastExpenses)
        knownCards = PaymentChoices.mostUsedCards(history.prefix(300).map(\.card))
        guard let expense else {
            if let initialDate { date = initialDate }
            card = defaultSource
            dateChosen = initialDate != nil
            guard let prefill else {
                refreshMerchant("")
                openedState = fieldsState
                amountFocused = true
                return
            }
            if let when = prefill.date {
                date = when
                dateChosen = true
            }
            if let name = prefill.card?.trimmingCharacters(in: .whitespaces), !name.isEmpty { card = name }
            if let code = prefill.currency { currency = code }
            isRefund = prefill.isRefund
            // «Tipo» is under «Más detalles»: open, so a refund is seen as one.
            showsDetails = prefill.isRefund
            merchant = prefill.merchant ?? ""
            refreshMerchant(merchant)
            // The category this shop usually gets, set here and not by `onChange(of: merchant)`
            // after: what the sheet opens with is not a change the person made.
            if let suggestedCategory {
                category = suggestedCategory
                categoryAutofilled = true
            }
            amountText = prefill.amountText ?? ""
            openedState = fieldsState
            // Only what is missing asks for the keyboard: the amount, when the notice had none.
            amountFocused = amountText.isEmpty
            return
        }
        // A bare "$" from Wallet is the month's currency; anything else keeps its own.
        currency = CurrencyResolver.isoCode(for: expense.currencyMarker,
                                            primary: CurrencyPreference.current)
            ?? CurrencyPreference.current
        isRefund = expense.amount < 0
        counts = !expense.isUncounted
        reason = expense.reason ?? .reimbursed
        // Grouped as the field itself writes it («1,234.13»): compared as loaded, the field's own
        // regrouping read as a retyped amount from 1,000 up and rewrote 1,234.125 as 1,234.13.
        amountText = AmountTyping.grouped(expense.amount.magnitude
            .formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(AmountTyping.written)))
        loadedAmountText = amountText
        merchant = expense.merchant
        repeatsMonthly = expense.repeatsMonthly == true
        rule = expense.rule
        card = expense.card ?? ""
        category = expense.category ?? ""
        pinnedCategories = [category]
        date = expense.date
        original = originalOfCopy(expense)
        // A fixed expense and its copies are not a merchant's payments: they follow their plan.
        if !expense.isFixed {
            merchantTexts = MerchantRules.texts(for: expense.merchant, renames: UserCatalog.merchantRenames)
            let texts = Set(merchantTexts)
            siblings = history.filter {
                $0 !== expense && !$0.isFixed && texts.contains(MerchantKey.normalized($0.merchant))
            }
        }
        refreshMerchant(expense.merchant)
        // Anything set in «Más detalles» is shown, not hidden behind it.
        showsDetails = isRefund || !counts || repeatsMonthly || expense.isRepeat == true
            || (expense.latitude != nil && expense.longitude != nil)
    }

    /// The fixed expense a copy came from, by its id (`RecurringExpenses.original(of:in:)`).
    private func originalOfCopy(_ expense: Expense) -> Expense? {
        RecurringExpenses.original(of: expense, in: context)
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
            sentenceProblem = String(localized: "No hay un monto en «\(text)». Escríbelo arriba.")
            sentence = ""
            amountFocused = true
            return
        }
        // Written as the field writes it, whatever the region: «1.234,5» (Spain) read as 1.23.
        amountText = AmountTyping.text(for: parsed.value, decimals: 0...2)
        currency = ExpenseRecorder.spokenCurrency(parsed.currencyMarker, primary: CurrencyPreference.current)
        // After the amount: changing it clears the problem line.
        sentenceProblem = nil
        if let name = entry.merchant { merchant = name }
        // Only a day said moves it: «230 de tacos» keeps the month being browsed, or a date
        // already picked (2026-11-18).
        if entry.daySaid {
            date = min(entry.date, AppClock.now)
            dateChosen = true
        }
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
    ///
    /// - `dateUnchanged`: the date wasn't moved. A fixed expense already repeating by the same
    ///   rule keeps the day asked for: rent «día 31» first charged on Nov 30 went to the 30th on
    ///   any save, even one that only changed the amount (2026-11-18).
    /// - Turned off on an original still repeating, it stops as «Dejar de repetir» does
    ///   (`RecurringExpenses.stopRepeating`): with its fields only emptied, the rent became
    ///   everyday spending and «Hoy puedes gastar» dropped at once (2026-11-18).
    static func setRepeats(_ expense: Expense, repeats: Bool, rule: RepeatRule, date: Date,
                           dateUnchanged: Bool = false) {
        guard repeats else {
            if expense.repeatsMonthly == true {
                RecurringExpenses.stopRepeating(expense)
            } else {
                expense.repeatsMonthly = nil
                expense.repeatsThrough = nil
                expense.repeatDay = nil
                expense.repeatRule = nil
            }
            return
        }
        let keepsDay = dateUnchanged && expense.repeatsMonthly == true && expense.rule == rule
        let asked = keepsDay ? expense.repeatDay : nil
        let day = rule.kind == .months ? (asked ?? Calendar.current.component(.day, from: date)) : nil
        expense.repeatsThrough = RecurringExpenses.repeatsThrough(
            for: date, rule: rule, day: day, wasRepeating: expense.repeatsMonthly == true,
            current: expense.repeatsThrough)
        expense.repeatsMonthly = true
        expense.repeatRule = rule.stored
        // The day of the month matters only to what repeats by months.
        expense.repeatDay = day
    }

    private func save() {
        guard let parsed, !savedOnce else { return }
        // «Se repite» turned off on a fixed expense still repeating: asked first, as «Dejar de
        // repetir» is (2026-11-18).
        if let expense, expense.repeatsMonthly == true, !repeatsMonthly, !stopConfirmed {
            confirmingStop = true
            return
        }
        let name = savedName
        // With no merchant typed the category names it; that is not a merchant to learn.
        let typedMerchant = !trimmedMerchant.isEmpty
        let cardName = card.trimmingCharacters(in: .whitespaces)
        let categoryName = trimmedCategory
        let value = isRefund ? -parsed.value.magnitude : parsed.value.magnitude
        // Saved as its ISO code, never "$": a bare "$" would follow the month's currency and
        // change meaning if that is switched later.
        if let expense {
            // The amount as it was, unless it was typed again (only the sign may change).
            let magnitude = amountText == loadedAmountText ? expense.amount.magnitude : parsed.value.magnitude
            expense.amount = isRefund ? -magnitude : magnitude
            let before = CurrencyResolver.isoCode(for: expense.currencyMarker,
                                                  primary: CurrencyPreference.current)
            if before != currency { expense.currencyMarker = currency }
            // What this correction teaches, read before the expense changes under it.
            let sent = expense.merchant
            let renamed = name != sent
            let choseCategory = categoryName != (expense.category ?? "")
            let categoryIsTheirs = choseCategory || !expense.hasSuggestedCategory
            let others = changesOthers ? (backfill?.pending(in: siblings) ?? []) : []
            // A name typed here reads as typed, and the model leaves it alone.
            if renamed { expense.displayName = name }
            expense.merchant = name
            expense.card = cardName.isEmpty ? nil : cardName
            // Another category is a choice; keeping the suggested one leaves it a suggestion,
            // and taking it off means none, not «suggest another».
            if choseCategory {
                expense.categorySource = categoryName.isEmpty ? Expense.clearedCategory : nil
            }
            expense.category = categoryName.isEmpty ? nil : categoryName
            let dateUnchanged = expense.date == date
            expense.date = date
            setCounts(expense)
            if expense.isRepeat != true {
                Self.setRepeats(expense, repeats: repeatsMonthly, rule: rule, date: date, dateUnchanged: dateUnchanged)
            }
            if removesPlace {
                expense.latitude = nil
                expense.longitude = nil
                expense.placeName = nil
            }
            // The others asked for, in the same save: all of it is kept, or none of it.
            for other in others { MerchantBackfill.apply(other.change, to: other.expense) }
            guard persist() else { return }
            // Only once it is saved: what Wallet sends as the old name comes in with this one
            // from now on, under this category. The newest choice wins, even when this expense
            // is older than others from the same place (`MerchantRules.learn`).
            if typedMerchant, renamed || choseCategory {
                UserCatalog.learnRule(sent: sent, name: name, category: categoryName,
                                      choseCategory: choseCategory, categoryIsTheirs: categoryIsTheirs)
            }
            announceSaved(String(localized: "Cambios guardados"))
        } else {
            // Left alone, the date is the moment of «Guardar», not of opening the sheet.
            if !dateChosen { date = AppClock.now }
            let summary = saveSummary
            let new = Expense(
                amount: value,
                currencyMarker: currency,
                merchant: name,
                card: cardName.isEmpty ? nil : cardName,
                date: date,
                category: categoryName.isEmpty ? nil : categoryName
            )
            // Only a category picked is learned: one filled in from the merchant is not a choice.
            if typedMerchant, !categoryName.isEmpty, !categoryAutofilled {
                UserCatalog.learnCategory(categoryName, for: name)
            }
            // A place picked from the suggestions reads as it did before.
            if typedMerchant {
                var same = FetchDescriptor<Expense>(predicate: #Predicate { $0.merchant == name },
                                                    sortBy: [SortDescriptor(\.date, order: .reverse)])
                same.fetchLimit = 1
                new.displayName = (try? context.fetch(same))?.first?.displayName
            }
            setCounts(new)
            Self.setRepeats(new, repeats: repeatsMonthly, rule: rule, date: date)
            savedOnce = true
            context.insert(new)
            guard persist() else {
                // Not saved: «Guardar» can be tried again with what was typed.
                savedOnce = false
                return
            }
            onSave?()
            announceSaved(String(localized: "Anotado: \(summary)"))
            // Written down as it happens: where the iPhone is, if «Guardar dónde pagas» is on.
            // After it's saved, so waiting for the place never holds the expense.
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
    /// Marks the place to go on «Guardar»; nothing changes until then.
    let onRemove: () -> Void
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
            DestructiveRowButton("Quitar ubicación", action: onRemove)
        }
        .padding(.vertical, Theme.Space.xs)
        .task { await nameThePlace() }
    }

    /// The street and neighborhood, once, kept with the expense.
    private func nameThePlace() async {
        guard expense.placeName == nil else { return }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let place = try? await request.mapItems.first else { return }
        // The short address is the street and neighborhood; the city follows when it isn't in it.
        let parts = [place.address?.shortAddress ?? place.name, place.addressRepresentations?.cityName]
            .compactMap { $0 }
        var seen: [String] = []
        for part in parts where !seen.contains(part) { seen.append(part) }
        guard !seen.isEmpty else { return }
        expense.placeName = seen.joined(separator: ", ")
        try? context.save()
    }
}

private extension View {
    /// A row of the category section: no separator, the form's side margins, and the vertical
    /// room given here so the grid's rows read as one.
    func categoryRow(top: CGFloat, bottom: CGFloat) -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: Theme.Space.xl, bottom: bottom, trailing: Theme.Space.xl))
    }
}

/// A row the list slides in. What it holds is told when to show (`shown`): the categories arrive
/// one by one while the room opens (`arriving`), and leave together, quickly, before it closes.
private struct ArrivingRow<Content: View>: View {
    var leaving: Bool
    @ViewBuilder var content: (Bool) -> Content
    @State private var arrived = false

    var body: some View {
        content(arrived && !leaving)
            .onAppear { arrived = true }
    }
}

private extension View {
    /// One of the categories «Ver más» brings: it fades in and settles down a few points into its
    /// place, a beat after the one before it, so the rest unfold as a wave that follows the room
    /// opening instead of all popping in at once (owner, 2026-11-15: «sale muy de repente»).
    /// Leaving, it takes the fold's own quick fade (`revealOut`), all together.
    func arriving(shown: Bool, order: Int) -> some View {
        modifier(Arriving(shown: shown, order: order))
    }
}

private struct Arriving: ViewModifier {
    let shown: Bool
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? Theme.Opacity.visible : Theme.Opacity.hidden)
            .scaleEffect(shown || reduceMotion ? Theme.Size.barFullScale : Theme.Size.chipArriveScale)
            .offset(y: shown || reduceMotion ? Theme.Space.none : Theme.Space.chipArriveDrop)
            .transaction { transaction in
                guard shown else { return }
                transaction.animation = reduceMotion ? Theme.Motion.revealIn
                    : Theme.Motion.chipArrive.delay(Theme.Motion.chipArriveStart + Double(order) * Theme.Motion.chipStagger)
            }
    }
}
