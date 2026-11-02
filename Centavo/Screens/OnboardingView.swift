import CentavoCore
import SwiftData
import SwiftUI

/// How the welcome ends: on the main screen, straight into the Wallet guide, or into «Cómo
/// funciona» (2026-11-01).
enum OnboardingExit { case home, guide, tutorial }

/// The first time Al día opens empty (redone 2026-11-01 in «Mi dinero»'s language): a step bar
/// with its name, a question for a title, a drawing that shows instead of telling, and the least
/// to fill in.
///
/// 1. Bienvenida: a Wallet notice lands, the figure goes down and today's cell fills.
/// 2. Tu mes: currency by its symbol, the budget, and the boleto split into the month's days.
/// 3. Gastos fijos: a calendar where each one is stamped on its day.
/// 4. Conecta Wallet: «pagas → Atajos → Al día». Setting it up goes to the guide, as before.
/// 5. The end: «Listo», and what each day gets.
///
/// Every step can be skipped and whatever was filled in is kept, saved once.
struct OnboardingView: View {
    let finish: (OnboardingExit) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// Saved once, whichever way it ends: saving twice would log the fixed expenses twice.
    @State private var saved = false
    /// The save at the end didn't go through: said on the last page.
    @State private var saveFailed = false
    @FocusState private var focused: Field?

    private enum Field { case budget, name, amount }
    /// The four steps and the end.
    private let pages = 5
    private let steps = 4

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
                case 3: walletPage
                default: donePage
                }
            }
            .id(page)
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            // The step bar stays put while the pages slide under it, and only fills its next part
            // (audit 2026-11-02: it slid away with each page).
            .safeAreaInset(edge: .top, spacing: Theme.Space.none) {
                StepBar(step: min(page + 1, steps), of: steps, label: Self.labels[min(page, Self.labels.count - 1)])
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.top, Theme.Space.xl)
                    .background(Theme.background)
            }
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("al día\(Text(".").foregroundStyle(Theme.brass))")
                        .font(.ticket(.subheading))
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel("Al día")
                }
                ToolbarItem(placement: .topBarLeading) {
                    if page > 0 && page < pages - 1 {
                        Button("Anterior", systemImage: "chevron.left") {
                            focused = nil
                            go(to: page - 1)
                        }
                        .accessibilityIdentifier("bienvenida-anterior")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if page < 3 {
                        Button("Omitir") { save(); finish(.home) }
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

    /// The one wide button that moves on. Wallet's page holds its own choice; the end, «Ver mi día».
    @ViewBuilder private var bottomBar: some View {
        if page != 3 {
            VStack(spacing: Theme.Space.m) {
                Button {
                    focused = nil
                    if page == pages - 1 { finish(.home) } else { go(to: page + 1) }
                } label: {
                    PrimaryButtonLabel(page == 0 ? "Empezar" : page == pages - 1 ? "Ver mi día" : "Continuar")
                }
                .ticketProminent()
                .accessibilityIdentifier("bienvenida-siguiente")
                if page == pages - 1 {
                    SecondaryButton("Cómo funciona · 1 min", identifier: "bienvenida-tutorial") { finish(.tutorial) }
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s)
            .background(Theme.background)
        }
    }

    /// Each page's name on the step bar; the end is «Listo».
    private static let labels = ["Bienvenida", "Tu mes", "Gastos fijos", "Conecta Wallet", "Listo"]

    private func go(to target: Int) {
        guard (0..<pages).contains(target), target != page else { return }
        // The way first, in its own update, so the page leaving already knows which side to go:
        // set together with the page, going back slid both pages the same way and they crossed.
        forward = target > page
        Task { @MainActor in
            withAnimation(Theme.Motion.animation(Theme.Motion.page, reduceMotion: reduceMotion)) { page = target }
        }
    }

    // MARK: Pages

    private var welcome: some View {
        page(title: "Cuánto puedes gastar hoy") {
            WelcomeDemo(currency: currency)
                .onboardingRise(2)
            // One line that doesn't lose cash (user research, 2026-10-29).
            Text("Cada compra con Apple Pay se anota sola; lo demás, con «+». Tú solo miras la cifra.")
                .font(.ticket(.callout))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .onboardingRise(3)
        }
    }

    private var budgetPage: some View {
        page(title: "¿Cuánto quieres gastar al mes?") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                currencyPills
                VStack(alignment: .leading, spacing: Theme.Space.m) {
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
            NoteText("Sin lo que vas a ahorrar. Lo que no gastes un día pasa al siguiente; lo cambias cuando quieras en «Más».",
                     color: Theme.faint)
                .onboardingRise(3)
        }
        .sensoryFeedback(.selection, trigger: currency)
    }

    /// The currency by its symbol, as in «Mi dinero»: the three the app adds up in.
    private var currencyPills: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(CurrencyPreference.offered, id: \.self) { code in
                let chosen = currency == code
                Button { currency = code } label: {
                    VStack(spacing: Theme.Space.xxxs) {
                        Text(MoneyCurrency.symbol(code)).font(.ticket(.bodyStrong))
                            .foregroundStyle(chosen ? Theme.brass : Theme.ink)
                        Text(MoneyCurrency.name(code)).font(.ticket(.micro)).textCase(.uppercase)
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.tallRow)
                    .background(chosen ? Theme.brass.opacity(Theme.Opacity.moneyCurrency) : .clear,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .strokeBorder(chosen ? Theme.brass : Theme.outline, lineWidth: Theme.Stroke.hairline)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MoneyCurrency.name(code))
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier(code == CurrencyPreference.offered.first ? "bienvenida-moneda" : "bienvenida-moneda-\(code)")
            }
        }
    }

    /// Common budgets for the currency, one tap each.
    private var suggestions: [Decimal] {
        currency == "MXN" ? [5_000, 8_000, 12_000, 20_000] : [1_000, 2_000, 3_000, 5_000]
    }

    private var quickAmounts: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(suggestions, id: \.self) { value in
                TicketChip("\((value / 1_000).formatted()) mil", selected: budget == value) {
                    withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) {
                        budgetText = NSDecimalNumber(decimal: value).stringValue
                    }
                }
                .accessibilityLabel(value.formatted(currencyStyle(currency).precision(.fractionLength(0))))
            }
        }
        .sensoryFeedback(.selection, trigger: budget)
    }

    private var budget: Decimal? {
        guard let value = AmountParser.parse(budgetText)?.value, value > 0 else { return nil }
        return value
    }

    /// What each day gets, as «Hoy» counts it: (budget − fixed) ÷ the month's days, rounded down.
    /// Not today's carried figure, which mid-month would add up the days already gone.
    private var pace: BudgetPace? { BudgetPace(budget: budget, spent: 0, reserved: fixedTotal, on: .now) }

    private func whole(_ value: Decimal) -> String {
        var input = value, output = Decimal()
        NSDecimalRound(&output, &input, 0, .down)
        return output.formatted(currencyStyle(currency).precision(.fractionLength(0)))
    }

    /// The answer the whole app is about: the month split into its days, as the boleto.
    @ViewBuilder private var dailyAnswer: some View {
        if let pace, let budget, pace.dailyBase > 0 {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                    Text(fixedTotal > 0 ? "(\(whole(budget)) − fijos) ÷ \(pace.daysInMonth) días ="
                                        : "\(whole(budget)) ÷ \(pace.daysInMonth) días =")
                        .font(.ticket(.footnote))
                        .foregroundStyle(Theme.muted)
                    Text(whole(pace.dailyBase))
                        .font(.ticket(.heading))
                        .foregroundStyle(Theme.brass)
                        .contentTransition(.numericText(value: NSDecimalNumber(decimal: pace.dailyBase).doubleValue))
                        .animation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion), value: budgetText)
                        .accessibilityIdentifier("bienvenida-por-dia")
                }
                WelcomeDaysStrip(days: pace.daysInMonth, filled: true)
            }
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Escribe un monto o elige uno abajo.")
                    .font(.ticket(.footnote))
                    .foregroundStyle(Theme.faint)
                WelcomeDaysStrip(days: Calendar.current.range(of: .day, in: .month, for: .now)?.count ?? 30, filled: false)
            }
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
        page(title: "¿Qué pagas cada mes?") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Se anotan solos cada mes y se apartan de lo que puedes gastar. Su día lo eliges en el calendario de abajo.")
                    .font(.ticket(.callout))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                // Out of the way while typing: they pushed «Agregar» under the keyboard.
                if focused != .name && focused != .amount {
                    WrapLayout {
                        ForEach(fixedSuggestions, id: \.self) { name in
                            TicketChip(name, selected: draftName == name) {
                                withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) {
                                    draftName = name
                                }
                                focused = .amount
                            }
                        }
                    }
                    .transition(.opacity)
                }
                VStack(spacing: Theme.Space.s) {
                    TextField("Qué es", text: $draftName,
                              prompt: Text("Renta, Netflix…").foregroundStyle(Theme.faint))
                        .textInputAutocapitalization(.words)
                        .focused($focused, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focused = .amount }
                        .accessibilityIdentifier("bienvenida-fijo-nombre")
                    Divider().overlay(Theme.hairline)
                    HStack {
                        TextField("Cuánto", text: $draftAmount,
                                  prompt: Text("Monto").foregroundStyle(Theme.faint))
                            .keyboardType(.decimalPad)
                            .focused($focused, equals: .amount)
                            .groupsThousands($draftAmount)
                            .accessibilityIdentifier("bienvenida-fijo-monto")
                        Text("el día \(draftDay)").foregroundStyle(Theme.muted)
                    }
                }
                .font(.ticket(.field))
                .padding(Theme.Space.ml)
                .selectableCard(selected: focused == .name || focused == .amount)
                Button(action: addFixed) {
                    LinkActionLabel("Agregar", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .disabled(draftValue == nil || draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("bienvenida-fijo-agregar")
                WelcomeFixedCalendar(stamped: Set(fixed.map(\.day)), chosen: $draftDay)
            }
            .animation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion), value: focused)
            .onboardingRise(2)
            if !fixed.isEmpty {
                VStack(spacing: Theme.Space.none) {
                    ForEach(Array(fixed.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { pointDivider }
                        fixedRow(item)
                            .transition(.opacity)
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
            }
        }
    }

    /// What the fixed expenses leave each day, or by how much they pass the budget: never a bare $0.
    @ViewBuilder private var fixedEffect: some View {
        if let pace, let budget {
            HStack(alignment: .firstTextBaseline) {
                if pace.dailyBase > 0 {
                    Text("Cada día tienes").font(.ticket(.footnote)).foregroundStyle(Theme.muted)
                    Spacer(minLength: Theme.Space.s)
                    Text(whole(pace.dailyBase))
                        .font(.ticket(.bodyStrong))
                        .foregroundStyle(Theme.brass)
                        .contentTransition(.numericText())
                } else {
                    Text("Tus fijos pasan tu presupuesto por \(whole(fixedTotal - budget)).")
                        .font(.ticket(.footnote)).foregroundStyle(Theme.danger)
                }
            }
            .padding(.vertical, Theme.Space.xxs)
            .accessibilityElement(children: .combine)
        }
    }

    private var walletPage: some View {
        page(title: "Que cada pago se anote solo") {
            WalletChain()
                .onboardingRise(2)
            Text(ShortcutsVersion.isIOS27
                 ? "Atajos, la app de Apple que ya viene en tu iPhone, le avisa a Al día. El atajo ya viene armado: lo agregas una vez y lo enciendes."
                 : "Atajos, la app de Apple que ya viene en tu iPhone, le avisa a Al día. La guía te lleva toque por toque, en unos 5 minutos.")
                .font(.ticket(.callout))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .onboardingRise(3)
            VStack(spacing: Theme.Space.m) {
                // Setting it up goes straight to the guide, as before (the end is for «Después»).
                Button {
                    save(); finish(.guide)
                } label: {
                    PrimaryButtonLabel(ShortcutsVersion.isIOS27 ? "Agregar a Atajos" : "Configurar ahora",
                                       systemImage: "wallet.pass")
                }
                .ticketProminent()
                .accessibilityIdentifier("bienvenida-configurar")
                SecondaryButton("Después", identifier: "bienvenida-despues") { save(); go(to: pages - 1) }
                HintText("¿No pagas con el iPhone? Toca «Después» y anota cada gasto con «+». El atajo queda en «Más › Configurar atajo».")
            }
            .onboardingRise(4)
        }
    }

    /// The end: «Listo», and what each day gets — never «Hoy puedes gastar», which mid-month
    /// would add up the days already gone. Wallet isn't called connected: the shortcut arrives
    /// off, and only a payment proves it.
    private var donePage: some View {
        ScrollView {
            VStack(spacing: Theme.Space.xl) {
                MoneySuccessArt()
                    .padding(.top, Theme.Space.l)
                Text("Listo")
                    .font(.ticket(.pageTitle))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                doneFigure
                if saveFailed {
                    HintText("Al día no pudo guardar tus gastos fijos todavía. Revísalos en «Gastos fijos» del menú «Más».")
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.xxl)
        }
        .onAppear { save() }
    }

    @ViewBuilder private var doneFigure: some View {
        if let pace, let budget {
            if pace.dailyBase > 0 {
                VStack(spacing: Theme.Space.s) {
                    Text("Cada día tienes").ticketCaption(strong: true)
                    MoneyCountUp(value: wholeDecimal(pace.dailyBase), currency: currency)
                        .accessibilityIdentifier("bienvenida-cada-dia")
                    Text(fixedTotal > 0 ? "Presupuesto \(whole(budget)) · fijos \(whole(fixedTotal))" : "Presupuesto \(whole(budget))")
                        .font(.ticket(.detail))
                        .foregroundStyle(Theme.muted)
                }
            } else {
                Text("Tus fijos pasan tu presupuesto por \(whole(fixedTotal - budget)). Ajústalo en «Más › Presupuesto del mes».")
                    .font(.ticket(.callout))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }
        } else {
            Text("Fija tu presupuesto cuando quieras en «Más › Presupuesto del mes» y Al día te dirá cuánto puedes gastar cada día.")
                .font(.ticket(.callout))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
    }

    private func wholeDecimal(_ value: Decimal) -> Decimal {
        var input = value, output = Decimal()
        NSDecimalRound(&output, &input, 0, .down)
        return output
    }

    // MARK: Pieces

    /// Every step's shell under the step bar: the question as the title, then the content, each
    /// block rising in after the one above it.
    private func page<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text(title)
                    .font(.ticket(.pageTitle))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .onboardingRise(1)
                content()
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var pointDivider: some View {
        Divider()
            .overlay(Theme.hairline)
            .padding(.vertical, Theme.Space.xxs)
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
                withAnimation(Theme.Motion.animation(Theme.Motion.quick, reduceMotion: reduceMotion)) {
                    fixed.removeAll { $0.id == item.id }
                }
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
        withAnimation(Theme.Motion.animation(Theme.Motion.settle, reduceMotion: reduceMotion)) {
            fixed.append(FixedDraft(name: draftName.trimmingCharacters(in: .whitespaces),
                                    amount: value, day: draftDay))
        }
        added += 1
        draftName = ""; draftAmount = ""; draftDay = 1
        focused = nil
    }

    /// Whatever was filled in is kept, even when the rest is skipped.
    private func save() {
        guard !saved else { return }
        saved = true
        // A fixed expense typed in but never «Agregar»-ed still counts.
        if draftValue != nil, !draftName.trimmingCharacters(in: .whitespaces).isEmpty { addFixed() }
        storedCurrency = currency
        if let budget {
            storedBudget = BudgetStore.stored(budget)
        }
        // Like «Nuevo gasto fijo»: one whose day already came this month starts now, with its
        // date; one whose day is still to come waits for it (a plan), and is never logged as a
        // charge of the month before.
        var plans: [FixedPlan] = []
        for item in fixed {
            let first = Self.firstCharge(day: item.day)
            let plan = FixedPlan(merchant: item.name, amount: "\(item.amount)", currency: currency,
                                 category: MerchantCatalog.category(for: item.name), rule: nil, firstDate: first,
                                 day: item.day)
            if first <= .now {
                let expense = RecurringExpenses.original(from: plan)
                expense.repeatDay = item.day
                context.insert(expense)
            } else {
                plans.append(plan)
            }
        }
        if !plans.isEmpty { FixedPlan.save(FixedPlan.saved + plans) }
        do {
            try context.save()
        } catch {
            // Left in the context: the next autosave tries again, and the welcome can't hold
            // the person back for it. Nothing is rolled back, so nothing typed is lost.
            saveFailed = true
        }
    }

    /// This month's day (the last one in a shorter month), at 9:00.
    static func firstCharge(day: Int, now: Date = .now, calendar: Calendar = .current) -> Date {
        let length = calendar.range(of: .day, in: .month, for: now)?.count ?? 28
        var parts = calendar.dateComponents([.year, .month], from: now)
        parts.day = min(max(day, 1), length)
        parts.hour = 9
        return calendar.date(from: parts) ?? now
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
