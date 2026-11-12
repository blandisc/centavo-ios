import CentavoCore
import SwiftData
import SwiftUI

/// «Mi dinero», unlocked: the net worth of the latest cut and every account under it
/// (2026-10-31). The cut sheet updates the balances; «+» adds an account.
struct MoneyHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(MoneyStore.activeAccounts) private var accounts: [MoneyAccount]
    @Query(MoneyCut.finished) private var cuts: [MoneyCut]
    @Query(filter: #Predicate<MoneyAccount> { $0.archived }, sort: \MoneyAccount.name) private var archived: [MoneyAccount]
    @Query(MoneyStore.activeIncomes) private var incomes: [MoneyIncome]
    @AppStorage(CurrencyPreference.key) private var storedCurrency = ""
    /// Where «Primera cuenta» is: 0 not started, 1…4 a step, 5 done (`MoneyStep`).
    @AppStorage(MoneyHomeView.stepKey) private var step = 0
    static let stepKey = "dinero.recorrido"

    @State private var adding = false
    @State private var editing: MoneyAccount?
    @State private var cutting: MoneyCut?
    @State private var choosingMonth = false
    @State private var addingIncome = false
    @State private var editingIncome: MoneyIncome?
    @State private var problem: String?

    private var main: String { CurrencyPreference.resolve(storedCurrency) }
    private var latest: MoneyCut? { cuts.last }
    private var previous: MoneyCut? { cuts.count > 1 ? cuts[cuts.count - 2] : nil }
    /// The opening balances: where «Mi dinero» starts, not a cut the person made (2026-11-11).
    private var start: MoneyCut? { MoneyStore.start(among: cuts) }

    var body: some View {
        if MoneyStep(rawValue: step) != nil {
            MoneyOnboardingView(step: $step, mainCurrency: main)
        } else {
            home
        }
    }

    private var home: some View {
        NavigationStack {
            Group {
                // Only with nothing at all: with every account archived, «Archivadas» and the
                // incomes stay reachable (second audit, 2026-11-02).
                if accounts.isEmpty && archived.isEmpty { empty } else { filled }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { MoneySignature() }
                if !accounts.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        // By its name, not a symbol to guess (owner, 2026-11-11): the first
                        // time ends with «toca Hacer corte». Short, so the signature stays centered.
                        Button("Corte") { startCut() }
                            .font(.ticket(.footnoteStrong))
                            .accessibilityLabel("Hacer corte")
                            .accessibilityIdentifier("dinero-hacer-corte")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Agregar cuenta", systemImage: "plus") { adding = true }
                        .accessibilityIdentifier("dinero-agregar")
                }
            }
            // A sheet sits above the tab's Face ID lock: it's covered while the app isn't in front
            // and until Face ID opens it again, keeping what was being written.
            .sheet(isPresented: $adding) {
                MoneyAccountSheet(account: nil, mainCurrency: latest?.mainCurrency ?? main).moneyPrivacyCover()
            }
            .sheet(item: $editing) { MoneyAccountSheet(account: $0, mainCurrency: latest?.mainCurrency ?? main).moneyPrivacyCover() }
            .sheet(item: $cutting) { MoneyCutSheet(draft: $0).moneyPrivacyCover() }
            .confirmationDialog("¿De qué mes es el corte?", isPresented: $choosingMonth, titleVisibility: .visible) {
                ForEach(MoneyStore.suggestedMonths(latest: latest?.month), id: \.self) { month in
                    Button("Corte de \(MoneyHead.fullMonthName(month))") { startCut(for: month) }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Si ese mes ya tiene corte, Al día pregunta antes de reemplazarlo.")
            }
            .sheet(isPresented: $addingIncome) {
                MoneyIncomeSheet(income: nil, mainCurrency: latest?.mainCurrency ?? main).moneyPrivacyCover()
            }
            .sheet(item: $editingIncome) {
                MoneyIncomeSheet(income: $0, mainCurrency: latest?.mainCurrency ?? main).moneyPrivacyCover()
            }

            .alert(problem ?? "", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: { Text("Intenta de nuevo.") }
            .onMoneyCovered { problem = nil; choosingMonth = false }
        }
    }

    // MARK: Empty

    /// The welcome (2026-11-01): the same dashed ticket as before, with a boleto over it that
    /// shows a net worth growing month by month. «Agregar tu primera cuenta» starts the steps.
    private var empty: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                MoneyGrowthHero(currency: main)
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Patrimonio").ticketCaption()
                    Text("Todo tu dinero en un número")
                        .font(.ticket(.heading))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Agrega tus cuentas, lo que debes y lo que te deben. Cada mes haces un corte y ves si ahorraste lo que debías.")
                        .font(.ticket(.callout))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.ticket)
                        .strokeBorder(Theme.outline, style: StrokeStyle(lineWidth: Theme.Stroke.hairline, dash: Theme.Dash.ticket))
                }
                Button { step = MoneyStep.have.rawValue } label: {
                    PrimaryButtonLabel("Agregar tu primera cuenta", systemImage: "plus")
                }
                .ticketProminent()
                .accessibilityIdentifier("dinero-primera-cuenta")
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.xxl)
        }
    }

    // MARK: Filled

    /// The same page as «Hoy» (owner, 2026-11-11): a scroll with the screen's margin, the head
    /// as far under the bar, one separation between blocks and perforations between lines, so
    /// nothing jumps when the tab changes. It was a `List`, with its own margins and solid lines.
    private var filled: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                hero
                group("Cuentas", kinds: [.account, .investment])
                group("Te deben", kinds: [.receivable])
                group("Debes", kinds: [.debt])
                incomeSection
                if !archived.isEmpty { archivedSection }
            }
            .padding(.horizontal, Theme.Space.screen)
            // As «Hoy»'s list starts under its bar.
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
        }
    }

    private var hero: some View {
        let worth = latest?.worthToday(accounts) ?? NetWorth()
        let currency = latest?.mainCurrency ?? main
        return VStack(alignment: .leading, spacing: Theme.Space.none) {
            // A section's distance from the figure, as the head of «Hoy».
            MoneyHead(date: AppClock.now, cutNumber: MoneyStore.cutsMade(among: cuts))
                .padding(.bottom, Theme.Space.xxl)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Patrimonio").ticketCaption(strong: true)
                heroFigure(worth, currency: currency)
                heroLine(worth: worth, currency: currency)
                if !worth.missingRates.isEmpty {
                    WarningText("Falta el tipo de cambio de \(worth.missingRates.sorted().joined(separator: ", ")): esas cuentas no se suman. Hazlo en el corte.")
                }
            }
            if let month = cutDue { cutRow(month) }
        }
    }

    /// Whole pesos, like «Hoy puedes gastar»: the rows below keep the cents.
    private func heroFigure(_ worth: NetWorth, currency: String) -> some View {
        Text(worth.total.formatted(currencyStyle(currency).precision(.fractionLength(0))))
            .font(.ticket(.hero))
            .tracking(Theme.Tracking.hero)
            .foregroundStyle(Theme.brass)
            // The same optical fit as the figure of «Hoy»: the «$» carries its own air on the
            // left, and the figure sits as close to its caption.
            .padding(.leading, Theme.Space.outset)
            .padding(.vertical, Theme.Space.heroTrim)
            .lineLimit(1)
            .minimumScaleFactor(Theme.MinimumScale.figure)
            .accessibilityIdentifier("dinero-patrimonio")
    }

    /// The month whose cut is due, if one is (owner, 2026-11-11): the first of the months «Hacer
    /// corte» offers that has no cut made by hand. Not the month «Mi dinero» was started in
    /// while it lasts: its balances were just written.
    private var cutDue: String? {
        guard !accounts.isEmpty else { return nil }
        let this = MoneyMath.monthKey(of: AppClock.now)
        let made = Set(cuts.filter { $0.id != start?.id }.map(\.month))
        return MoneyStore.suggestedMonths(latest: latest?.month).first { month in
            !made.contains(month) && !(month == this && start?.month == this)
        }
    }

    /// «Hacer corte de noviembre», in brass under the net worth, only while it is due.
    private func cutRow(_ month: String) -> some View {
        Button { startCut(suggesting: month) } label: {
            HStack(spacing: Theme.Space.s) {
                LinkActionLabel("Hacer corte de \(MoneyHead.fullMonthName(month))", systemImage: "plus", alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.ticket(.footnote))
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Perforation() }
        .padding(.top, Theme.Space.l)
        .accessibilityIdentifier("dinero-corte-del-mes")
    }

    private func heroLine(worth: NetWorth, currency: String) -> some View {
        var parts: [Text] = []
        if let previous {
            // The same accounts on both sides: archiving one isn't a loss, a new one isn't saved.
            let delta = latest.map { $0.change(since: previous) } ?? 0
            // Against the opening balances it's «desde el inicio»: that month has no cut to name.
            let since = previous.id == start?.id ? "el inicio" : MoneyHead.monthName(previous.month)
            parts.append(Text("\(delta >= 0 ? "+" : "−")\(formatMoney(delta.magnitude, isoCode: currency, label: currency))")
                .foregroundStyle(delta >= 0 ? Theme.good : Theme.danger) + Text(" desde \(since)"))
        }
        if worth.receivable > 0 {
            parts.append(Text(formatMoney(worth.receivable, isoCode: currency, label: currency)).foregroundStyle(Theme.ink)
                         + Text(" te deben"))
        }
        let line = parts.enumerated().reduce(Text("")) { sum, item in
            item.offset == 0 ? item.element : sum + Text(" · ").foregroundStyle(Theme.brass) + item.element
        }
        return line
            .font(.ticket(.detail))
            .foregroundStyle(Theme.muted)
    }

    @ViewBuilder
    private func group(_ title: String, kinds: [MoneyKind]) -> some View {
        let rows = accounts.filter { kinds.contains($0.kind) }
        if !rows.isEmpty, let latest {
            VStack(alignment: .leading, spacing: Theme.Space.none) {
                MoneySectionHead(title: title,
                                 total: formatMoney(sum(rows, in: latest), isoCode: latest.mainCurrency, label: latest.mainCurrency))
                ForEach(rows) { account in
                    Button { editing = account } label: {
                        MoneyAccountRow(account: account, cut: latest, previous: previous).moneyLine()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// What comes in each month (2026-11-02 audit): seen, edited and removed here. It's apart
    /// from the net worth, so its total isn't added to anything above.
    private var incomeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.none) {
            MoneySectionHead(title: "Te entra al mes", total: nil)
            ForEach(incomes) { income in
                Button { editingIncome = income } label: { MoneyIncomeRow(income: income).moneyLine() }
                    .buttonStyle(.plain)
            }
            Button { addingIncome = true } label: {
                LinkActionLabel(incomes.isEmpty ? "Agregar lo que te entra" : "Agregar otro ingreso",
                                systemImage: "plus", alignment: .leading)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { Perforation() }
            .accessibilityIdentifier("dinero-agregar-ingreso")
        }
    }

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.none) {
            MoneySectionHead(title: "Archivadas", total: nil)
            ForEach(archived) { account in archivedRow(account) }
            HintText("No suman en tu patrimonio ni salen en el corte. Al regresarla, el próximo corte te pide su saldo.")
                .padding(.top, Theme.Space.s)
        }
    }

    private func archivedRow(_ account: MoneyAccount) -> some View {
        AdaptiveStack(spacing: Theme.Space.m, stackedSpacing: Theme.Space.none) {
            Text(account.name)
                .font(.ticket(.bodyMedium))
                .tracking(Theme.Tracking.name)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Regresar") { unarchive(account) }
                .font(.ticket(.label))
                .foregroundStyle(Theme.brass)
                .buttonStyle(.tapTarget)
                .accessibilityIdentifier("dinero-regresar-\(account.name)")
        }
        .frame(minHeight: Theme.Size.tapTarget)
        .overlay(alignment: .top) { Perforation() }
    }

    private func sum(_ rows: [MoneyAccount], in cut: MoneyCut) -> Decimal {
        let lines = rows.compactMap { account in
            cut.shownEntry(for: account).map { MoneyLine(kind: .account, currency: account.currency, balance: $0.balance) }
        }
        return NetWorth(lines: lines, main: cut.mainCurrency, rates: cut.rateTable).owned
    }

    private func unarchive(_ account: MoneyAccount) {
        account.archived = false
        do { try context.save() } catch {
            context.rollback()
            problem = "No se pudo regresar la cuenta"
        }
    }

    /// A cut left half-done opens as it was, whatever its month. Otherwise the cut asks which
    /// month it's for: in the first days, the one that just ended comes first.
    private func startCut() {
        do {
            if let draft = try MoneyStore.openDraft(in: context) {
                cutting = draft
            } else {
                choosingMonth = true
            }
        } catch {
            problem = "No se pudo empezar el corte"
        }
    }

    /// The row under the net worth names a month: a cut left half-done still comes first.
    private func startCut(suggesting month: String) {
        do {
            if let draft = try MoneyStore.openDraft(in: context) {
                cutting = draft
            } else {
                startCut(for: month)
            }
        } catch {
            problem = "No se pudo empezar el corte"
        }
    }

    private func startCut(for month: String) {
        do {
            cutting = try MoneyStore.draft(for: month, in: context, mainCurrency: latest?.mainCurrency ?? main)
        } catch {
            problem = "No se pudo empezar el corte"
        }
    }
}

/// One account: the name in capitals, a quieter line under it, the balance on the right.
struct MoneyAccountRow: View {
    let account: MoneyAccount
    let cut: MoneyCut
    let previous: MoneyCut?

    @Environment(\.dynamicTypeSize) private var typeSize

    private var balance: Decimal? { cut.shownEntry(for: account)?.balance }

    private var detail: String {
        var bits: [String] = account.institution.map { [$0] } ?? []
        if let rate = account.yearlyRate { bits.append("\(rate.formatted(.number.precision(.fractionLength(0...2))))% anual") }
        if account.currency != cut.mainCurrency, let balance {
            bits.append(formatMoney(balance, isoCode: account.currency, label: account.currency, main: cut.mainCurrency))
        }
        switch MoneySubtype.of(account) {
        case .account: break
        case .investment: bits.append("varía")
        case let other: bits.append(other.short)
        }
        if balance == nil { bits.append("en tu próximo corte") }
        return bits.joined(separator: " · ")
    }

    private var shown: String {
        guard let balance else { return "—" }
        // Without a rate it isn't zero: it's money that can't be added up yet.
        guard let rate = account.currency == cut.mainCurrency ? 1 : cut.rateTable[account.currency] else {
            return "sin tipo de cambio"
        }
        let value = MoneyMath.cents(balance * rate)
        let text = formatMoney(value, isoCode: cut.mainCurrency, label: cut.mainCurrency)
        return account.kind == .debt ? "−" + text : text
    }

    var body: some View {
        // With large text the balance goes under the name, whole (audit 2026-11-02).
        AdaptiveStack(spacing: Theme.Space.m, stackedSpacing: Theme.Space.xxs, alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                Text(account.name)
                    .font(.ticket(.bodyMedium))
                    .tracking(Theme.Tracking.name)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.ticket(.hint))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(shown)
                .font(.ticket(.headline))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// One income: its name, where it comes from, and how much each month in its currency.
struct MoneyIncomeRow: View {
    let income: MoneyIncome
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // With large text the amount goes under the name, whole, as an account's.
        AdaptiveStack(spacing: Theme.Space.m, stackedSpacing: Theme.Space.xxs, alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                Text(income.name)
                    .font(.ticket(.bodyMedium))
                    .tracking(Theme.Tracking.name)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                Text([income.institution, "al mes"].compactMap { $0 }.joined(separator: " · "))
                    .font(.ticket(.hint))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatMoney(income.amount, isoCode: income.currency, label: income.currency))
                .font(.ticket(.headline))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// A block's caption on «Mi dinero», and its total at the other end: «CUENTAS   $440,300.00».
struct MoneySectionHead: View {
    let title: String
    let total: String?

    var body: some View {
        AdaptiveStack(alignment: .firstTextBaseline) {
            Text(title)
                .ticketCaption()
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let total {
                Text(total)
                    .font(.ticket(.detail))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            }
        }
        .padding(.bottom, Theme.Space.s)
    }
}

extension View {
    /// A line of «Mi dinero»'s ticket, as an expense's on «Hoy» (`ExpenseRowLayout`): the same
    /// air, at least a two-line row tall, growing with its text, under a perforation.
    func moneyLine() -> some View {
        padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.tallRow, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { Perforation() }
    }
}

/// «SÁB 31 DE OCT · CORTE N.º 003», the same ticket head as «Hoy».
struct MoneyHead: View {
    let date: Date
    let cutNumber: Int

    static let mexico = Locale(identifier: "es_MX")

    /// «sep» for «2026-09».
    static func monthName(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
        else { return key }
        return date.formatted(.dateTime.month(.abbreviated).locale(mexico)).replacingOccurrences(of: ".", with: "")
    }

    /// «septiembre» for «2026-09».
    static func fullMonthName(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
        else { return key }
        return date.formatted(.dateTime.month(.wide).locale(mexico))
    }

    var body: some View {
        // The very head of «Hoy» (`TicketHead`), with the cuts made as its folio.
        TicketHead(title: TicketHead.day(date), folio: "Corte N.º", number: cutNumber,
                   spoken: cutNumber == 1 ? "1 corte" : "\(cutNumber) cortes")
    }
}
