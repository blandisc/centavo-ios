import CentavoCore
import SwiftData
import SwiftUI

/// The first time Al día opens empty: four short pages that show before they ask.
///
/// 1. What it does, as a live demo: a Wallet notice lands and «Hoy puedes gastar» goes down.
/// 2. The month: currency and budget on one page, with quick amounts and the daily figure
///    answering every keystroke.
/// 3. Fixed expenses, with one-tap suggestions and how much they take off each day.
/// 4. Connecting Wallet: the chain «pagas → Atajos → Al día», then the guide.
///
/// Every page can be skipped and whatever was filled in is kept. One wide «Continuar» at the
/// bottom moves on (it rides above the number pad, so no keyboard bar is needed); the dots
/// above it show where the person is.
struct OnboardingView: View {
    /// Called when it is done; `openGuide` asks for the Wallet guide right after.
    let finish: (_ openGuide: Bool) -> Void

    @Environment(\.modelContext) private var context
    @AppStorage(BudgetStore.key) private var storedBudget = ""
    @AppStorage(CurrencyPreference.key) private var storedCurrency = ""
    @State private var page = Self.firstPage
    /// Which way the last move went, so the pages slide the right way.
    @State private var forward = true
    @State private var currency = CurrencyPreference.current
    @State private var budgetText = ""
    @State private var fixed: [FixedDraft] = []
    @State private var draftName = ""
    @State private var draftAmount = ""
    @State private var draftDay = 1
    @State private var added = 0
    @FocusState private var focused: Field?
    @ScaledMetric(relativeTo: .body) private var pointIconWidth = Theme.Size.iconColumnNarrow

    private enum Field { case budget, name, amount }
    private let pages = 4

    /// Debug only: open on a given page (`-centavo-bienvenida-pagina 2`) for screenshots.
    private static var firstPage: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let at = args.firstIndex(of: "-centavo-bienvenida-pagina"), at + 1 < args.count {
            return Int(args[at + 1]) ?? 0
        }
        #endif
        return 0
    }

    var body: some View {
        NavigationStack {
            // One page at a time, moved only by the buttons. A swipeable TabView let a tap in
            // the middle of its animation leave it on one page while the counter said another.
            Group {
                switch page {
                case 0: welcome
                case 1: budgetPage
                case 2: fixedPage
                default: walletPage
                }
            }
            .id(page)
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Bienvenida")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if page > 0 {
                        Button("Anterior", systemImage: "chevron.left") {
                            focused = nil
                            go(to: page - 1)
                        }
                        .accessibilityIdentifier("bienvenida-anterior")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if page < pages - 1 {
                        Button("Omitir") { save(); finish(false) }
                            .font(.ticket(.footnote))
                            .accessibilityIdentifier("bienvenida-omitir")
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: page)
            .sensoryFeedback(.success, trigger: added)
        }
        .interactiveDismissDisabled()
    }

    /// The dots, then the one wide button that moves on. On the last page the choice is
    /// inside the page, so only the dots stay.
    private var bottomBar: some View {
        VStack(spacing: Theme.Space.m) {
            StepDots(current: page, of: pages)
                .accessibilityHidden(true)
            if page < pages - 1 {
                Button {
                    focused = nil
                    go(to: page + 1)
                } label: {
                    PrimaryButtonLabel(page == 0 ? "Empezar" : "Continuar")
                }
                .ticketProminent()
                .accessibilityIdentifier("bienvenida-siguiente")
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.s)
        .background(Theme.background)
    }

    private func go(to target: Int) {
        guard (0..<pages).contains(target), target != page else { return }
        forward = target > page
        withAnimation(Theme.Motion.page) { page = target }
    }

    // MARK: Pages

    private var welcome: some View {
        page(title: "Al día", symbol: "calendar.day.timeline.left",
             lead: "Te dice cuánto puedes gastar hoy. Cada compra con Wallet se anota sola.") {
            WelcomeDemo(currency: currency)
                .onboardingRise(2)
            VStack(spacing: Theme.Space.none) {
                point("wallet.pass", "En línea o acercando el teléfono: sin anotar nada.")
                pointDivider
                point("calendar", "Lo que no gastas hoy, lo tienes mañana.")
                pointDivider
                point("lock", "Sin cuenta ni servidor: tus gastos viven en tu iPhone y tu iCloud.")
            }
            .padding(.horizontal, Theme.Space.ml)
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ticketPanel()
            .onboardingRise(3)
        }
    }

    private var budgetPage: some View {
        page(title: "Tu mes", symbol: "target",
             lead: "Cuánto quieres gastar al mes. Con eso, Al día te dice cuánto puedes gastar cada día.") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Picker("Moneda", selection: $currency) {
                    ForEach(CurrencyPreference.offered, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("bienvenida-moneda")
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    AmountInputField("Presupuesto", text: $budgetText, prompt: suggestions[1].formatted(),
                                     size: .compact, identifier: "bienvenida-presupuesto")
                        .focused($focused, equals: .budget)
                    dailyAnswer
                }
                .padding(Theme.Space.ml)
                .selectableCard(selected: focused == .budget)
                quickAmounts
            }
            .onboardingRise(2)
            NoteText("Lo que no gastes un día se suma al siguiente. Puedes cambiar el monto cuando quieras en «Más».",
                     color: Theme.faint)
                .onboardingRise(3)
        }
        .sensoryFeedback(.selection, trigger: currency)
    }

    /// Common budgets for the currency, one tap each.
    private var suggestions: [Decimal] {
        currency == "MXN" ? [5_000, 8_000, 12_000, 20_000] : [1_000, 2_000, 3_000, 5_000]
    }

    private var quickAmounts: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(suggestions, id: \.self) { value in
                let chosen = budget == value
                Button {
                    withAnimation(Theme.Motion.quick) { budgetText = NSDecimalNumber(decimal: value).stringValue }
                } label: {
                    Text("\((value / 1_000).formatted()) mil")
                        .font(.ticket(.footnoteStrong))
                        .foregroundStyle(chosen ? Theme.onBrass : Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
                        .background(chosen ? Theme.brass : Theme.surface,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value.formatted(currencyStyle(currency).precision(.fractionLength(0))))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: budget)
    }

    private var budget: Decimal? {
        guard let value = AmountParser.parse(budgetText)?.value, value > 0 else { return nil }
        return value
    }

    /// The answer the whole app is about, growing as the budget is typed: what each day gets
    /// (not today's carried figure, which mid-month would add up the days already gone).
    @ViewBuilder private var dailyAnswer: some View {
        if let pace = BudgetPace(budget: budget, spent: 0, reserved: fixedTotal, on: .now),
           pace.dailyBase > 0 {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Text("Al día:")
                    .font(.ticket(.footnote))
                    .foregroundStyle(Theme.muted)
                Text(pace.dailyBase.formatted(currencyStyle(currency).precision(.fractionLength(0))))
                    .font(.ticket(.heading))
                    .foregroundStyle(Theme.brass)
                    .contentTransition(.numericText(value: NSDecimalNumber(decimal: pace.dailyBase).doubleValue))
                    .animation(Theme.Motion.quick, value: budgetText)
                    .accessibilityIdentifier("bienvenida-por-dia")
            }
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        } else {
            Text("Escribe un monto o elige uno abajo.")
                .font(.ticket(.footnote))
                .foregroundStyle(Theme.faint)
        }
    }

    private var fixedTotal: Decimal { fixed.reduce(0) { $0 + $1.amount } }

    /// Common fixed expenses not added yet: a tap fills the name and asks for the amount.
    private var fixedSuggestions: [String] {
        let taken = Set(fixed.map { $0.name.lowercased() })
        return ["Renta", "Luz", "Internet", "Celular", "Netflix", "Spotify", "Gimnasio", "Agua"]
            .filter { !taken.contains($0.lowercased()) }
    }

    private var fixedPage: some View {
        page(title: "Gastos fijos", symbol: "repeat",
             lead: "La renta, la luz y las suscripciones se anotan solas cada mes, y se apartan de lo que puedes gastar.") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(fixedSuggestions, id: \.self) { name in
                            TicketChip(name, selected: draftName == name) {
                                withAnimation(Theme.Motion.quick) { draftName = name }
                                focused = .amount
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, Theme.Space.screen, for: .scrollContent)
                .padding(.horizontal, -Theme.Space.screen)
                VStack(spacing: Theme.Space.s) {
                    TextField("Qué es", text: $draftName,
                              prompt: Text("Renta, Netflix…").foregroundStyle(Theme.faint))
                        .textInputAutocapitalization(.words)
                        .focused($focused, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focused = .amount }
                        .accessibilityIdentifier("bienvenida-fijo-nombre")
                    Divider().overlay(Theme.hairline)
                    TextField("Cuánto", text: $draftAmount,
                              prompt: Text("Monto").foregroundStyle(Theme.faint))
                        .keyboardType(.decimalPad)
                        .focused($focused, equals: .amount)
                        .groupsThousands($draftAmount)
                        .accessibilityIdentifier("bienvenida-fijo-monto")
                    Divider().overlay(Theme.hairline)
                    Stepper("El día \(draftDay) de cada mes", value: $draftDay, in: 1...31)
                        .foregroundStyle(Theme.ink)
                }
                .font(.ticket(.field))
                .padding(Theme.Space.ml)
                .selectableCard(selected: focused == .name || focused == .amount)
                Button(action: addFixed) {
                    LinkActionLabel("Agregar", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .disabled(draftValue == nil
                          || draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("bienvenida-fijo-agregar")
            }
            .onboardingRise(2)
            if !fixed.isEmpty {
                VStack(spacing: Theme.Space.none) {
                    ForEach(Array(fixed.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { pointDivider }
                        fixedRow(item)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if budget != nil {
                        pointDivider
                        fixedEffect
                    }
                }
                .padding(.horizontal, Theme.Space.ml)
                .padding(.vertical, Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ticketPanel()
            } else {
                NoteText("También puedes marcar como fijo cualquier gasto que ya anotaste.",
                         color: Theme.faint)
                    .onboardingRise(3)
            }
        }
    }

    /// What the fixed expenses leave for each day, so adding one shows what it costs.
    @ViewBuilder private var fixedEffect: some View {
        if let pace = BudgetPace(budget: budget, spent: 0, reserved: fixedTotal, on: .now) {
            HStack(alignment: .firstTextBaseline) {
                Text("Te quedan al día").font(.ticket(.footnote)).foregroundStyle(Theme.muted)
                Spacer(minLength: Theme.Space.s)
                Text(max(pace.dailyBase, 0).formatted(currencyStyle(currency).precision(.fractionLength(0))))
                    .font(.ticket(.bodyStrong))
                    .foregroundStyle(Theme.brass)
                    .contentTransition(.numericText())
            }
            .padding(.vertical, Theme.Space.xxs)
            .accessibilityElement(children: .combine)
        }
    }

    private var walletPage: some View {
        page(title: "Conecta Wallet", symbol: "wallet.pass",
             lead: "Una automatización de Atajos le avisa a Al día de cada compra. Se hace una vez y toma unos 2 minutos.") {
            WalletChain()
                .onboardingRise(2)
            VStack(spacing: Theme.Space.none) {
                point("hand.tap", "Te guiamos toque por toque, con capturas reales de Atajos.")
                if GuideCompanion.isSupported {
                    pointDivider
                    point("pip", "Una ventanita flotante te acompaña dentro de Atajos para que no tengas que ir y venir.")
                }
            }
            .padding(.horizontal, Theme.Space.ml)
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ticketPanel()
            .onboardingRise(3)
            VStack(spacing: Theme.Space.m) {
                Button {
                    save(); finish(true)
                } label: {
                    PrimaryButtonLabel("Configurar ahora", systemImage: "wallet.pass")
                }
                .ticketProminent()
                .accessibilityIdentifier("bienvenida-configurar")
                SecondaryButton("Después", identifier: "bienvenida-despues") { save(); finish(false) }
                HintText("Si lo dejas para después, lo encuentras en «Más › Configurar atajo».")
            }
            .onboardingRise(4)
        }
    }

    // MARK: Pieces

    /// Every page's shell: an emblem, a step caption, the title and lead, then the content,
    /// each block rising in after the one above it.
    private func page<Content: View>(title: String, symbol: String, lead: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                StepHeader(step: page + 1, of: pages, title: title, systemImage: symbol)
                    .onboardingRise(0)
                Text(lead)
                    .font(.ticket(.body))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingRise(1)
                content()
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var pointDivider: some View {
        Divider()
            .overlay(Theme.hairline)
            .padding(.vertical, Theme.Space.xxs)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Image(systemName: icon).foregroundStyle(Theme.brass).frame(width: pointIconWidth)
            Text(text).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
        .font(.ticket(.callout))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fixedRow(_ item: FixedDraft) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                // Written as in the month's list.
                Text(item.name)
                    .font(.ticket(.bodyMedium))
                    .tracking(Theme.Tracking.name)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(item.amount.formatted(currencyStyle(currency).precision(.fractionLength(2)))) · día \(item.day)")
                    .font(.ticket(.footnote))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: Theme.Space.s)
            Button("Quitar \(item.name)", systemImage: "xmark.circle.fill") {
                withAnimation(Theme.Motion.quick) { fixed.removeAll { $0.id == item.id } }
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(Theme.faint)
            .frame(minWidth: Theme.Size.tapTarget, minHeight: Theme.Size.tapTarget)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Space.xxs)
    }

    // MARK: Saving

    private var draftValue: Decimal? {
        guard let value = AmountParser.parse(draftAmount)?.value, value > 0 else { return nil }
        return value
    }

    private func addFixed() {
        guard let value = draftValue else { return }
        withAnimation(Theme.Motion.toggle) {
            fixed.append(FixedDraft(name: draftName.trimmingCharacters(in: .whitespaces),
                                    amount: value, day: draftDay))
        }
        added += 1
        draftName = ""; draftAmount = ""; draftDay = 1
        focused = nil
    }

    /// Whatever was filled in is kept, even when the rest is skipped.
    private func save() {
        // A fixed expense typed in but never «Agregar»-ed still counts.
        if draftValue != nil, !draftName.trimmingCharacters(in: .whitespaces).isEmpty { addFixed() }
        storedCurrency = currency
        if let budget {
            storedBudget = BudgetStore.stored(budget)
        }
        for item in fixed {
            let date = RecurringSchedule.firstDate(day: item.day, now: .now)
            let expense = Expense(amount: item.amount, currencyMarker: currency, merchant: item.name,
                                  date: date, category: MerchantCatalog.category(for: item.name))
            expense.repeatsMonthly = true
            expense.repeatsThrough = date
            expense.repeatDay = item.day
            context.insert(expense)
        }
        try? context.save()
    }
}

/// A fixed expense typed on the welcome, saved as a repeating expense when it closes.
private struct FixedDraft: Identifiable {
    let id = UUID()
    let name: String
    let amount: Decimal
    let day: Int
}

#Preview { OnboardingView { _ in }.ticketPreview() }
