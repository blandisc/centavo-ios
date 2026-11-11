import CentavoCore
import SwiftData
import SwiftUI

/// «Primera cuenta» (2026-11-01): four steps in the order a person thinks of their money —
/// what you have, what you owe, what you're owed, and the result. Each step offers only its
/// own kinds, drawn small with what they are and examples. The lines are rows that open in
/// place: you see them all and fill the one you open. Every line is saved the moment its row
/// says «Listo», so leaving to check the bank loses nothing; the step is remembered too.
struct MoneyOnboardingView: View {
    @Binding var step: Int
    let mainCurrency: String

    @Environment(\.modelContext) private var context
    @Query(MoneyStore.activeAccounts) private var accounts: [MoneyAccount]
    @Query(MoneyCut.finished) private var cuts: [MoneyCut]
    @Query(MoneyStore.activeIncomes) private var incomes: [MoneyIncome]
    @AppStorage(BudgetStore.key) private var storedBudget = ""
    @State private var importing = false

    @State private var chosen: MoneySubtype = .account
    /// The row that is open: a saved account's id, or `draftID` for a new one.
    @State private var open: UUID?
    @State private var draft = MoneyRowDraft()
    @State private var problem: String?
    /// While typing, the step's button steps aside instead of riding over the fields.
    @State private var typing = false
    @State private var confirmingLeave = false
    /// A saved row whose «Quitar» was tapped: it's asked before (2026-11-02 audit).
    @State private var removing: MoneyAccount?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let draftID = UUID()

    private var page: MoneyStep { MoneyStep(rawValue: step) ?? .have }
    private var rows: [MoneyAccount] { accounts.filter { page.subtypes.contains(MoneySubtype.of($0)) } }
    /// Without archived accounts, like «Mi dinero» (second audit, 2026-11-02).
    private var worth: NetWorth { cuts.last?.worthToday(accounts) ?? NetWorth() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    MoneyStepBar(step: page)
                    if page == .done { finish } else { stepContent }
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { if !typing { actions } }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in typing = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in typing = false }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { MoneySignature() }
                if page != .done {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Anterior", systemImage: "chevron.left", action: back)
                            .accessibilityIdentifier("recorrido-anterior")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Ocultar teclado") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.ticket(.footnoteStrong))
                }
            }
            .alert("No se guardó la cuenta", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: { Text(problem ?? "") }
            .navigationDestination(isPresented: $importing) {
                MoneyImportView(mainCurrency: mainCurrency) { importing = false }
            }
            .alert("Tienes un renglón sin terminar", isPresented: $confirmingLeave) {
                Button("Seguir llenando", role: .cancel) {}
                Button("Continuar sin guardarlo", role: .destructive) { go(to: page.following) }
            } message: {
                Text("Si continúas, ese renglón no se guarda.")
            }
            .alert("¿Quitar \(removing?.name ?? "")?",
                   isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("Cancelar", role: .cancel) { removing = nil }
                Button("Quitar", role: .destructive) {
                    if let removing { remove(removing) }
                    removing = nil
                }
            } message: {
                Text(removing.map(MoneyStore.hasHistory) ?? false
                     ? "Tiene cortes pasados: se archiva y esos cortes la conservan."
                     : "Se borra con su saldo.")
            }
            .onMoneyCovered { confirmingLeave = false; removing = nil; problem = nil }
            .onAppear(perform: arrive)
        }
    }

    // MARK: A step

    @ViewBuilder private var stepContent: some View {
        Text(page.title)
            .font(.ticket(.pageTitle))
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        kinds
        if page == .have { excelButton }
        if let note = page.note {
            Text(note).font(.ticket(.detail)).foregroundStyle(Theme.muted)
        }
        if !rows.isEmpty || open == Self.draftID {
            HStack(alignment: .firstTextBaseline) {
                Text(page == .have ? "Llevas" : "Tu patrimonio").ticketCaption()
                Spacer()
                Text(money(page == .have ? worth.owned : worth.total, mainCurrency))
                    .font(.ticket(.figure))
                    .foregroundStyle(Theme.brass)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.animation(Theme.Motion.Money.total, reduceMotion: reduceMotion),
                               value: page == .have ? worth.owned : worth.total)
            }
        }
        if !worth.missingRates.isEmpty {
            Text("Falta el tipo de cambio de \(worth.missingRates.sorted().joined(separator: ", ")): esas cuentas no se suman todavía.")
                .font(.ticket(.detail))
                .foregroundStyle(Theme.brass)
        }
        VStack(spacing: Theme.Space.s) {
            ForEach(rows) { account in
                MoneyRow(title: account.name, subtitle: subtitle(for: account), swatch: swatch(for: account),
                         figure: figure(for: account), isOpen: open == account.id,
                         toggle: { toggle(account) }) {
                    MoneyRowEditor(draft: $draft, mainCurrency: mainCurrency, isNew: false,
                                   done: { save(account) }, remove: { removing = account })
                }
            }
            if open == Self.draftID {
                MoneyRow(title: draft.name.isEmpty ? "Nueva · \(draft.subtype.name.lowercased())" : draft.name,
                         subtitle: draft.subtype.short, swatch: Theme.brass, figure: nil, isOpen: true,
                         toggle: { withAnimation(Theme.Motion.animation(Theme.Motion.Money.row, reduceMotion: reduceMotion)) { open = nil } }) {
                    MoneyRowEditor(draft: $draft, mainCurrency: mainCurrency, isNew: true,
                                   done: { save(nil) }, remove: { withAnimation(Theme.Motion.animation(Theme.Motion.Money.row, reduceMotion: reduceMotion)) { open = nil } })
                }
            }
            Button { startNew(chosen) } label: {
                Text("＋ Agregar \(rows.isEmpty ? chosen.name.lowercased() : "otra")")
                    .font(.ticket(.label))
                    .tracking(Theme.Tracking.label)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.brass)
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .strokeBorder(Theme.outline, style: StrokeStyle(lineWidth: Theme.Stroke.hairline, dash: Theme.Dash.ticket))
                    }
            }
            .accessibilityIdentifier("recorrido-agregar")
        }
    }

    /// «¿Lo tienes en Excel?»: a secondary way in, full width under the two main kinds.
    private var excelButton: some View {
        Button { importing = true } label: {
            HStack(spacing: Theme.Space.m) {
                if !typeSize.isAccessibilitySize {
                    MoneyKindArt(kind: .excel)
                        .frame(width: Theme.Size.moneyExcelArt)
                }
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    Text("¿Lo tienes en Excel?").font(.ticket(.bodyStrong)).foregroundStyle(Theme.brass)
                    Text("Pásalo con tu IA y cárgalo todo de una vez.").font(.ticket(.hint)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.xxs)
                Image(systemName: "chevron.right").font(.ticket(.footnote)).foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Space.sm)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.outline, style: StrokeStyle(lineWidth: Theme.Stroke.hairline, dash: Theme.Dash.ticket))
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recorrido-excel")
    }

    private var kinds: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Theme.Space.m))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.m))
        return layout {
            ForEach(page.subtypes, id: \.self) { subtype in
                MoneyKindCard(subtype: subtype, isChosen: chosen == subtype,
                              compact: page.subtypes.count > 2 && !typeSize.isAccessibilitySize) {
                    chosen = subtype
                    startNew(subtype)
                }
            }
        }
    }

    // MARK: The end

    @ViewBuilder private var finish: some View {
        MoneySuccessArt().frame(maxWidth: .infinity)
        Text("Tu patrimonio")
            .font(.ticket(.pageTitle))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
        VStack(spacing: Theme.Space.s) {
            receiptLine("Tienes", worth.owned)
            receiptLine("Te deben", worth.receivable)
            receiptLine("Debes", -worth.debts)
            Perforation()
            HStack(alignment: .firstTextBaseline) {
                Text("Patrimonio").font(.ticket(.bodyMedium))
                Spacer()
                MoneyCountUp(value: worth.total, currency: mainCurrency)
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.ticket))
        if !incomes.isEmpty { incomeLine }
        Text("Al terminar el mes, toca «Hacer corte» en «Mi dinero» y verás cuánto ahorraste.")
            .font(.ticket(.callout))
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// What comes in each month, and — with a budget in «Hoy» and everything in the main
    /// currency — what that leaves to save. Asked for in the first cut when it wasn't imported.
    private var incomeLine: some View {
        let sameCurrency = incomes.allSatisfy { $0.currency == mainCurrency }
        let total = incomes.reduce(Decimal(0)) { $0 + $1.amount }
        let budget = BudgetStore.amount(from: storedBudget)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text("Te entra al mes").font(.ticket(.body))
                Spacer()
                Text(sameCurrency ? money(total, mainCurrency) : incomes.count == 1 ? "1 ingreso" : "\(incomes.count) ingresos").font(.ticket(.bodyMedium)).monospacedDigit()
            }
            .foregroundStyle(Theme.ink)
            if sameCurrency, let budget, budget > 0 {
                let left = total - budget
                Text(left > 0 ? "Con tu presupuesto de \(money(budget, mainCurrency)), debes ahorrar \(Text(money(left, mainCurrency)).foregroundStyle(Theme.brass)) al mes."
                     : left == 0 ? "Tu presupuesto de \(money(budget, mainCurrency)) es todo lo que te entra: no queda para ahorrar."
                     : "Tu presupuesto de \(money(budget, mainCurrency)) es mayor que lo que te entra.")
                    .font(.ticket(.callout))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.ticket))
        .accessibilityElement(children: .combine)
    }

    private func receiptLine(_ title: String, _ value: Decimal) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(money(value, mainCurrency)).monospacedDigit()
        }
        .font(.ticket(.body))
        .foregroundStyle(Theme.ink)
    }

    // MARK: Bottom

    private var actions: some View {
        VStack(spacing: Theme.Space.s) {
            Button(action: next) { PrimaryButtonLabel(page.next) }
                .ticketProminent()
                .disabled(page == .have && rows.isEmpty)
                .accessibilityIdentifier("recorrido-siguiente")
            if let skip = page.skip, rows.isEmpty {
                Button(skip, action: next)
                    .font(.ticket(.label))
                    .tracking(Theme.Tracking.label)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.brass)
                    .buttonStyle(.tapTarget)
                    .accessibilityIdentifier("recorrido-saltar")
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.background.opacity(Theme.Opacity.paceAhead))
    }

    // MARK: Actions

    private func arrive() {
        if step < MoneyStep.have.rawValue { step = MoneyStep.have.rawValue }
        chosen = page.subtypes.first ?? .account
        if page == .have && rows.isEmpty && open == nil { startNew(.account) }
    }

    private func go(to target: MoneyStep) {
        withAnimation(Theme.Motion.animation(Theme.Motion.page, reduceMotion: reduceMotion)) {
            open = nil
            step = target.rawValue
            chosen = target.subtypes.first ?? .account
        }
    }

    private func next() {
        if page == .done { step = MoneyStep.finished; return }
        if open == Self.draftID {
            // A row that couldn't be saved stays open where it is, with what was written.
            if draft.isComplete(mainCurrency: mainCurrency) { guard save(nil) else { return } }
            else if draft.hasContent { confirmingLeave = true; return }
        }
        go(to: page.following)
    }

    /// Back a step; from the first, back to the welcome (nothing written is lost).
    private func back() {
        if page == .have {
            open = nil
            step = 0
        } else {
            go(to: page.previous)
        }
    }

    /// A new row of `subtype`; a row already half-written keeps what it has and only changes kind.
    private func startNew(_ subtype: MoneySubtype) {
        withAnimation(Theme.Motion.animation(Theme.Motion.Money.row, reduceMotion: reduceMotion)) {
            if open == Self.draftID && draft.hasContent {
                draft.subtype = subtype
            } else {
                draft = MoneyRowDraft(subtype: subtype, currency: mainCurrency)
            }
            open = Self.draftID
        }
    }

    private func toggle(_ account: MoneyAccount) {
        withAnimation(Theme.Motion.animation(Theme.Motion.Money.row, reduceMotion: reduceMotion)) {
            if open == account.id { open = nil; return }
            draft = MoneyRowDraft(account: account, balance: cuts.last?.shownEntry(for: account)?.balance,
                                  rate: cuts.last?.rateTable[account.currency])
            open = account.id
        }
    }

    @discardableResult
    private func save(_ account: MoneyAccount?) -> Bool {
        guard let balance = draft.balance, draft.isComplete(mainCurrency: mainCurrency) else { return false }
        do {
            if let account {
                account.name = draft.trimmedName
                account.institution = draft.trimmedInstitution
                account.yearlyRate = draft.subtype.takesRate ? draft.yearlyRate : nil
                try MoneyStore.update(account, balance: balance, rate: draft.exchange, in: context)
            } else {
                let new = MoneyAccount(name: draft.trimmedName, kind: draft.subtype.kind, currency: draft.currency,
                                       yearlyRate: draft.subtype.takesRate ? draft.yearlyRate : nil)
                new.subtype = draft.subtype.rawValue
                new.institution = draft.trimmedInstitution
                try MoneyStore.add(new, balance: balance, rate: draft.exchange, in: context, mainCurrency: mainCurrency)
            }
            withAnimation(Theme.Motion.animation(Theme.Motion.Money.row, reduceMotion: reduceMotion)) { open = nil }
            return true
        } catch {
            problem = "Intenta otra vez."
            return false
        }
    }

    private func remove(_ account: MoneyAccount) {
        do {
            try MoneyStore.remove(account, in: context)
            withAnimation(Theme.Motion.animation(Theme.Motion.Money.row, reduceMotion: reduceMotion)) { open = nil }
        } catch {
            problem = "No se pudo quitar. Intenta otra vez."
        }
    }

    // MARK: Words

    private func subtitle(for account: MoneyAccount) -> String {
        var bits = [account.institution, MoneySubtype.of(account).short].compactMap { $0 }
        if let rate = account.yearlyRate { bits.append("\(rate.formatted(.number.precision(.fractionLength(0...2))))% anual") }
        if account.currency != mainCurrency { bits.append(MoneyCurrency.symbol(account.currency)) }
        return bits.joined(separator: " · ")
    }

    private func figure(for account: MoneyAccount) -> String? {
        guard let balance = cuts.last?.shownEntry(for: account)?.balance else { return nil }
        let text = formatMoney(balance, isoCode: account.currency, label: account.currency, main: mainCurrency)
        return account.kind == .debt ? "−" + text : text
    }

    private func swatch(for account: MoneyAccount) -> Color {
        Theme.categories[account.order % Theme.categories.count]
    }
}

/// Whole units, like the figures at the top of «Hoy».
func money(_ value: Decimal, _ currency: String) -> String {
    value.formatted(currencyStyle(currency).precision(.fractionLength(0)))
}

// MARK: - Steps

enum MoneyStep: Int {
    case have = 1, owe, owed, done
    /// Past the last step: «Mi dinero» shows itself.
    static let finished = 5

    var subtypes: [MoneySubtype] {
        switch self {
        case .have: [.account, .investment]
        case .owe: [.card, .loan, .other]
        case .owed: [.lent, .coming]
        case .done: []
        }
    }

    var label: String {
        switch self {
        case .have: "Lo que tienes"
        case .owe: "Lo que debes"
        case .owed: "Lo que te deben · opcional"
        case .done: "Listo"
        }
    }

    var title: String {
        switch self {
        case .have: "¿Dónde tienes tu dinero?"
        case .owe: "¿Qué debes hoy?"
        case .owed: "¿Te deben o te va a caer algo?"
        case .done: "Tu patrimonio"
        }
    }

    var note: String? {
        switch self {
        case .have: "Lo que debes y lo que te deben van en los pasos 2 y 3."
        case .owed: "Suma a tu patrimonio marcado «por caer», para que no lo confundas con lo que ya está en tu cuenta."
        default: nil
        }
    }

    var next: String {
        switch self {
        case .have: "Ya están todas · Paso 2"
        case .owe: "Continuar · Paso 3"
        case .owed: "Continuar · Paso 4"
        case .done: "Ver mi dinero"
        }
    }

    var skip: String? {
        switch self {
        case .owe: "No debo nada"
        case .owed: "Nada por ahora"
        default: nil
        }
    }

    var following: MoneyStep { MoneyStep(rawValue: rawValue + 1) ?? .done }
    var previous: MoneyStep { MoneyStep(rawValue: rawValue - 1) ?? .have }
}

/// Four parts; the current one carries a slow sheen. «Paso N de 4» and its name under it.
struct MoneyStepBar: View {
    let step: MoneyStep

    var body: some View { StepBar(step: step.rawValue, of: 4, label: step.label) }
}

// MARK: - A kind's card

struct MoneyKindCard: View {
    let subtype: MoneySubtype
    let isChosen: Bool
    let compact: Bool
    let choose: () -> Void

    private var art: MoneyArtKind {
        switch subtype {
        case .account: .account
        case .investment: .investment
        case .card: .card
        case .loan: .loan
        case .other: .other
        case .lent: .lent
        case .coming: .coming
        case .income: .account
        }
    }

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                VStack(spacing: Theme.Space.xxxs) {
                    MoneyKindArt(kind: art)
                    if let legend = subtype.legend {
                        HStack {
                            Text(legend.left)
                            Spacer(minLength: Theme.Space.xxs)
                            Text(legend.right).foregroundStyle(Theme.brass)
                        }
                        .font(.ticket(.micro))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.Space.xs)
                        .padding(.bottom, Theme.Space.xxs)
                    }
                }
                .background(Theme.ink.opacity(Theme.Opacity.moneyArtWash), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                Text(subtype.name).font(.ticket(.bodyStrong)).foregroundStyle(Theme.ink)
                Text(subtype.meaning(compact: compact)).font(.ticket(.hint)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !compact, let example = subtype.example {
                    Text(example).font(.ticket(.hint)).foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(isChosen ? Theme.brass.opacity(Theme.Opacity.moneyChosen) : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(isChosen ? Theme.brass : Theme.hairline, lineWidth: Theme.Stroke.hairline)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(subtype.name): \(subtype.meaning(compact: false))")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityHint("Agrega una nueva")
        .accessibilityIdentifier("tipo-\(subtype.rawValue)")
    }
}

extension MoneySubtype {
    func meaning(compact: Bool) -> String {
        switch self {
        case .account: "Dinero tuyo hoy, que puedes usar."
        case .investment: "Sube y baja. En cada corte dices cuánto vale."
        case .card: compact ? "Lo de hoy, no el límite." : "Lo que debes hoy, no el límite."
        case .loan: "Lo que falta pagar."
        case .other: compact ? "A familia, pendientes." : "Lo que no es tarjeta ni préstamo."
        case .lent: "Prestaste dinero y te lo van a regresar."
        case .coming: "Ya lo ganaste, pero llega en una fecha que viene."
        case .income: "Lo que te entra cada mes."
        }
    }

    var example: String? {
        switch self {
        case .account: "Banco, Nu, ahorro, efectivo"
        case .investment: "Fondo, acciones, cripto"
        case .lent: "Le prestaste $8,000 a Ana"
        case .coming: "Bono de diciembre, aguinaldo, un reembolso"
        default: nil
        }
    }

    /// The words under a drawing that needs them, left and right: who lent to whom, when it lands.
    var legend: (left: String, right: String)? {
        switch self {
        case .lent: ("tú → ana", "regresa")
        case .coming: ("hoy", "te llega")
        default: nil
        }
    }

    /// Accounts and debts can carry a yearly rate (a yield, or the interest charged).
    var takesRate: Bool { self == .account || self == .investment || self == .card || self == .loan }

    var amountQuestion: String {
        switch self {
        case .account: "¿Cuánto hay hoy?"
        case .investment: "¿Cuánto vale hoy?"
        case .card, .loan, .other: "¿Cuánto debes hoy?"
        case .lent: "¿Cuánto te deben?"
        case .coming: "¿Cuánto te va a llegar?"
        case .income: "¿Cuánto te entra al mes?"
        }
    }

    var amountHint: String {
        switch self {
        case .account: "Ábrela en la app de tu banco y copia el saldo de hoy."
        case .investment: "El valor de hoy en la app donde inviertes."
        case .card: "En tu app del banco: «saldo actual». Lo que debes hoy, no el pago mínimo."
        case .loan: "Lo que te falta por pagar, no la mensualidad."
        case .other: "Cuánto le debes hoy."
        case .lent: "Lo que todavía no te regresan."
        case .coming: "Lo que te van a pagar."
        case .income: "Lo que te llega cada mes, ya sin impuestos."
        }
    }

    var namePrompt: String {
        switch self {
        case .account: "Nu cajita, BBVA nómina…"
        case .investment: "Fondo GBM, acciones…"
        case .card: "Amex, Nu, BBVA…"
        case .loan: "Auto, casa, personal…"
        case .other: "Mamá, renta pendiente…"
        case .lent: "Préstamo a Ana…"
        case .coming: "Bono anual, aguinaldo…"
        case .income: "Sueldo, renta que cobras…"
        }
    }
}

// MARK: - Rows that open in place

struct MoneyRow<Editor: View>: View {
    let title: String
    let subtitle: String
    let swatch: Color
    let figure: String?
    let isOpen: Bool
    let toggle: () -> Void
    @ViewBuilder let editor: () -> Editor

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.none) {
            Button(action: toggle) {
                HStack(spacing: Theme.Space.sm) {
                    RoundedRectangle(cornerRadius: Theme.Radius.bar)
                        .fill(swatch)
                        .frame(width: Theme.Size.moneySwatch, height: Theme.Size.moneySwatch)
                    VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                        Text(title)
                            .font(.ticket(.bodyMedium))
                            .tracking(Theme.Tracking.name)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                        Text(subtitle).font(.ticket(.hint)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: Theme.Space.s)
                    if let figure {
                        Text(figure).font(.ticket(.headline)).foregroundStyle(Theme.ink).monospacedDigit()
                    }
                    Image(systemName: "chevron.right")
                        .font(.ticket(.footnote))
                        .foregroundStyle(Theme.faint)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Theme.Space.m)
                .frame(minHeight: Theme.Size.tallRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Cierra los detalles" : "Abre los detalles")
            if isOpen {
                editor()
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.bottom, Theme.Space.m)
                    // The app's one fold (`Theme.Motion.fold`, 2026-10-29): it shows once there
                    // is room and goes before the room closes.
                    .transition(.unfold)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(isOpen ? Theme.brassMid : .clear, lineWidth: Theme.Stroke.hairline)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

/// What a row holds while it's being written.
struct MoneyRowDraft {
    var subtype: MoneySubtype = .account
    var name = ""
    var institution = ""
    var currency = "MXN"
    var amount = ""
    var rate = ""
    var exchangeText = ""

    init() {}

    init(subtype: MoneySubtype, currency: String) {
        self.subtype = subtype
        self.currency = currency
    }

    init(account: MoneyAccount, balance: Decimal?, rate exchange: Decimal?) {
        subtype = MoneySubtype.of(account)
        name = account.name
        institution = account.institution ?? ""
        currency = account.currency
        amount = balance.map { BackupNumber.text($0) } ?? ""
        rate = account.yearlyRate.map { BackupNumber.text($0) } ?? ""
        exchangeText = exchange.map { BackupNumber.text($0) } ?? ""
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedInstitution: String? {
        let text = institution.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
    var balance: Decimal? { MoneyAmount.read(amount) }
    var yearlyRate: Decimal? { rate.isEmpty ? nil : MoneyMath.decimal(rate) }
    var exchange: Decimal? { MoneyMath.decimal(exchangeText) }
    /// Something written that would be lost.
    var hasContent: Bool { !trimmedName.isEmpty || !amount.isEmpty }

    func isComplete(mainCurrency: String) -> Bool {
        guard !trimmedName.isEmpty, balance != nil else { return false }
        if !rate.isEmpty && yearlyRate == nil { return false }
        return currency == mainCurrency || (exchange ?? 0) > 0
    }
}

struct MoneyRowEditor: View {
    @Binding var draft: MoneyRowDraft
    let mainCurrency: String
    let isNew: Bool
    /// The import asks one exchange rate per currency, above the rows, not one per row.
    var asksExchange = true
    let done: () -> Void
    let remove: () -> Void
    /// What the left button says; «Cancelar» for a new row, «Quitar» for a saved one.
    var removeTitle: String?

    /// Complete for its «Listo»: without the per-row exchange rate when it's asked elsewhere.
    private var complete: Bool { draft.isComplete(mainCurrency: asksExchange ? mainCurrency : draft.currency) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            field("Nombre", hint: "Como le dices.") {
                TextField("Nombre", text: $draft.name, prompt: Text(draft.subtype.namePrompt).foregroundStyle(Theme.faint))
                    .accessibilityIdentifier("fila-nombre")
            }
            field("Institución · opcional", hint: "El banco, la tarjeta o el lugar: Nu, BBVA, Amex.") {
                TextField("Institución", text: $draft.institution, prompt: Text("Nu, BBVA, Amex…").foregroundStyle(Theme.faint))
                    .accessibilityIdentifier("fila-institucion")
            }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Moneda").ticketCaption()
                if isNew {
                    MoneyCurrencyCarousel(selection: $draft.currency)
                } else {
                    Text(MoneyCurrency.symbol(draft.currency) + " · " + MoneyCurrency.name(draft.currency))
                        .font(.ticket(.body)).foregroundStyle(Theme.muted)
                }
            }
            field(draft.subtype.amountQuestion, hint: draft.subtype.amountHint) {
                TextField(draft.subtype.amountQuestion, text: $draft.amount,
                          prompt: Text(MoneyCurrency.symbol(draft.currency) + "0").foregroundStyle(Theme.faint))
                    .keyboardType(.decimalPad)
                    .groupsThousands($draft.amount)
                    .accessibilityIdentifier("fila-monto")
            }
            if asksExchange && draft.currency != mainCurrency {
                field("1 \(MoneyCurrency.symbol(draft.currency)) = \(MoneyCurrency.symbol(mainCurrency))",
                      hint: "El tipo de cambio de hoy. Lo actualizas en cada corte.") {
                    TextField("Tipo de cambio", text: $draft.exchangeText, prompt: Text("0.00").foregroundStyle(Theme.faint))
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("fila-cambio")
                }
            }
            if draft.subtype.takesRate {
                field(draft.subtype.kind == .debt ? "¿Te cobra interés? · opcional" : "¿Te da rendimiento? · opcional",
                      hint: draft.subtype.kind == .debt ? "Al año, en %. Solo para orientarte en el corte."
                                                        : "Al año, en %. Con ella, cada corte te dice cuánto debió rendir.") {
                    TextField("Tasa", text: $draft.rate, prompt: Text("Ej. 10.5").foregroundStyle(Theme.faint))
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("fila-tasa")
                }
            }
            HStack {
                Button(removeTitle ?? (isNew ? "Cancelar" : "Quitar"), role: isNew && removeTitle == nil ? .cancel : .destructive,
                       action: remove)
                    .font(.ticket(.label))
                    .tracking(Theme.Tracking.label)
                    .textCase(.uppercase)
                    .foregroundStyle(isNew && removeTitle == nil ? Theme.muted : Theme.danger)
                    .buttonStyle(.tapTarget)
                Spacer()
                Button("Listo", action: done)
                    .font(.ticket(.label))
                    .tracking(Theme.Tracking.label)
                    .textCase(.uppercase)
                    .foregroundStyle(complete ? Theme.brass : Theme.faint)
                    .disabled(!complete)
                    .buttonStyle(.tapTarget)
                    .accessibilityIdentifier("fila-listo")
            }
            .frame(minHeight: Theme.Size.tapTarget)
        }
    }

    private func field<Input: View>(_ title: String, hint: String, @ViewBuilder input: () -> Input) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title).ticketCaption()
            input()
                .font(.ticket(.field))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Theme.Space.sm)
                .frame(minHeight: Theme.Size.tapTarget)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            Text(hint).font(.ticket(.hint)).foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Currency by its symbol

enum MoneyCurrency {
    /// In the order people here reach for them.
    static let offered = ["MXN", "USD", "EUR", "GBP", "CAD", "JPY", "CHF"]

    static func symbol(_ code: String) -> String {
        switch code {
        case "MXN": "$"
        case "USD": "US$"
        case "EUR": "€"
        case "GBP": "£"
        case "CAD": "CA$"
        case "JPY": "¥"
        default: code
        }
    }

    static func name(_ code: String) -> String {
        switch code {
        case "MXN": "pesos"
        case "USD": "dólares"
        case "EUR": "euros"
        case "GBP": "libras"
        case "CAD": "dól. can."
        case "JPY": "yenes"
        case "CHF": "francos"
        default: code
        }
    }
}

/// The currencies as tiles with their symbol, sliding sideways; the edge fades to say there's more.
struct MoneyCurrencyCarousel: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.xs) {
                ForEach(MoneyCurrency.offered, id: \.self) { code in
                    Button { selection = code } label: {
                        VStack(spacing: Theme.Space.xxxs) {
                            Text(MoneyCurrency.symbol(code))
                                .font(.ticket(.bodyStrong))
                                .foregroundStyle(selection == code ? Theme.brass : Theme.ink)
                            Text(MoneyCurrency.name(code))
                                .font(.ticket(.micro))
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, Theme.Space.xs)
                        .frame(minWidth: Theme.Size.moneyCurrencyTile, minHeight: Theme.Size.tallRow)
                        .background(selection == code ? Theme.brass.opacity(Theme.Opacity.moneyCurrency) : .clear,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.control)
                                .strokeBorder(selection == code ? Theme.brass : Theme.outline, lineWidth: Theme.Stroke.hairline)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MoneyCurrency.name(code))
                    .accessibilityAddTraits(selection == code ? .isSelected : [])
                    .accessibilityIdentifier("moneda-\(code)")
                }
            }
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8),
                                     .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
    }
}

/// The final figure counting up once, from zero.
struct MoneyCountUp: View {
    let value: Decimal
    let currency: String
    @State private var shown: Decimal = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(money(shown, currency))
            .font(.ticket(.display))
            .foregroundStyle(Theme.brass)
            .monospacedDigit()
            .contentTransition(.numericText(value: NSDecimalNumber(decimal: shown).doubleValue))
            .onAppear {
                if MotionPolicy.isStill(reduceMotion: reduceMotion) { shown = value; return }
                withAnimation(Theme.Motion.countUp.delay(Theme.Motion.Money.countUpDelay)) { shown = value }
            }
            .accessibilityLabel(money(value, currency))
    }
}
