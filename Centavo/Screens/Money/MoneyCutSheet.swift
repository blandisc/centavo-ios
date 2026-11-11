import CentavoCore
import SwiftData
import SwiftUI

/// The month's cut (2026-10-31, decision 1 A): one sheet with every account. Each line waits
/// for a balance typed or «Sin cambio»; nothing is taken as an answer without being looked at,
/// and «Guardar» says how many are left. The yield is only a hint. Leaving keeps the draft.
struct MoneyCutSheet: View {
    @Bindable var draft: MoneyCut

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(MoneyStore.activeIncomes) private var incomes: [MoneyIncome]

    @State private var typed: [UUID: String] = [:]
    @State private var movements: [UUID: String] = [:]
    @State private var rateTexts: [String: String] = [:]
    @State private var ratesReviewed: Set<String> = []
    /// Each foreign rate the draft started with: the last cut's, or one typed since in «Nueva
    /// cuenta» (`MoneyStore.pendingRates`), offered as is.
    @State private var startRates: [String: Decimal] = [:]
    @State private var confirmingDiscard = false
    @State private var addingIncome = false
    @State private var problem: String?
    /// The month already has a cut made on this date: «¿Reemplazar…?» before anything goes.
    @State private var replacing: Date?
    @FocusState private var focus: UUID?
    /// The movement and the exchange rate being typed: «N sin revisar» can take the cursor there.
    @FocusState private var movementFocus: UUID?
    @FocusState private var rateFocus: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The cut this one starts from: the same month's (being redone) or the one before. Never a
    /// later month's, when the cut is for the month that just ended.
    private var previous: MoneyCut? { MoneyStore.cut(before: draft.month, in: context) }

    private var entries: [MoneyEntry] {
        (draft.entries ?? []).filter { $0.account != nil }
            .sorted { ($0.account?.order ?? 0, $0.account?.createdAt ?? AppClock.now) < ($1.account?.order ?? 0, $1.account?.createdAt ?? AppClock.now) }
    }

    /// The entries in the order the sheet shows them, section by section.
    private var shown: [MoneyEntry] {
        rows(of: [.account, .investment]) + rows(of: [.receivable]) + rows(of: [.debt])
    }

    private func rows(of kinds: [MoneyKind]) -> [MoneyEntry] {
        entries.filter { kinds.contains($0.account?.kind ?? .account) }
    }

    private var foreign: [String] {
        MoneyMath.foreignCurrencies(in: draft.lines, main: draft.mainCurrency)
    }

    /// A movement typed that doesn't read: it would be dropped without a word.
    private var unreadableMovements: Int {
        entries.compactMap(\.account).filter { MoneyTyping.signedReading(movements[$0.id] ?? "") == .unreadable }.count
    }

    private var pending: Int {
        entries.filter { !$0.reviewed }.count + foreign.filter { !ratesReviewed.contains($0) }.count + unreadableMovements
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                // No income yet (none imported): the cut asks for it (2026-11-01). Optional.
                if incomes.isEmpty {
                    Section {
                        Button { addingIncome = true } label: {
                            LinkActionLabel("Agregar lo que te entra", systemImage: "plus", alignment: .leading)
                        }
                        .accessibilityIdentifier("corte-agregar-ingreso")
                    } header: {
                        Text("¿Cuánto te entra al mes?").ticketCaption()
                    } footer: {
                        HintText("Tu sueldo o lo que cobras cada mes, ya sin impuestos. Es opcional y no suma a tu patrimonio.")
                    }
                    .listRowBackground(Theme.surface)
                }
                if !foreign.isEmpty {
                    Section {
                        ForEach(foreign, id: \.self) { code in rateRow(code) }
                    } header: {
                        Text("Tipo de cambio de hoy").ticketCaption()
                    }
                    .listRowBackground(Theme.surface)
                }
                section("¿Cuánto hay hoy?", kinds: [.account, .investment])
                section("¿Cuánto te deben hoy?", kinds: [.receivable])
                section("¿Cuánto debes hoy?", kinds: [.debt])
                Section {
                    DestructiveRowButton("Descartar corte", identifier: "corte-descartar") { confirmingDiscard = true }
                } footer: {
                    HintText("Corte de \(MoneyHead.fullMonthName(draft.month)). Si sales sin guardar, te espera como lo dejaste.")
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            // Short, or iOS pushes it off center beside «Cerrar» (≤ ~18 characters).
            .ticketBarTitle("Corte del mes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }.font(.ticket(.footnoteStrong))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if pending == 0 {
                        Button("Guardar", action: save)
                            .font(.ticket(.footnoteStrong))
                            .accessibilityIdentifier("corte-guardar")
                    } else {
                        // Not a dead «Guardar»: it takes you to what is left (owner, 2026-11-11).
                        Button { goToPending(proxy) } label: {
                            HStack(spacing: Theme.Space.xxs) {
                                Text("\(pending) sin revisar")
                                Image(systemName: "arrow.down").accessibilityHidden(true)
                            }
                            .font(.ticket(.footnoteStrong))
                            .frame(minHeight: Theme.Size.tapTarget)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("\(pending) sin revisar. Ir al siguiente")
                        .accessibilityIdentifier("corte-pendientes")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if let id = focus, let entry = entries.first(where: { $0.account?.id == id }) {
                        Button("Sin cambio") { keep(entry) }.font(.ticket(.footnoteStrong))
                    }
                    Spacer()
                    Button("Siguiente") { focus = nextPending(after: focus) }.font(.ticket(.footnoteStrong))
                }
            }
            // The one way to ask before something goes away (owner, 2026-11-11).
            .confirmsRemoval(isPresented: $confirmingDiscard, question: {
                TicketQuestion(title: "¿Descartar el corte?", name: "Corte de \(MoneyHead.fullMonthName(draft.month))",
                               note: "Se borra lo que escribiste en este corte. Tus cortes pasados no cambian.",
                               verb: "Descartar")
            }) {
                // A failure is said, and the sheet stays (second audit, 2026-11-02).
                do {
                    try MoneyStore.discard(draft, in: context)
                    dismiss()
                } catch {
                    context.rollback()
                    problem = "No se descartó el corte"
                }
            }
            .alert("¿Reemplazar el corte de \(MoneyHead.fullMonthName(draft.month))?",
                   isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } })) {
                Button("Cancelar", role: .cancel) {}
                Button("Reemplazar", role: .destructive) { save(replacing: true) }
            } message: {
                Text("Ese mes ya tiene un corte, hecho el \(replacing?.formatted(.dateTime.day().month(.wide).locale(MoneyHead.mexico)) ?? ""). Si lo reemplazas, cuenta este y el otro se quita.")
            }
            .alert(problem ?? "", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: { Text("Intenta otra vez.") }
            .sheet(isPresented: $addingIncome) { MoneyIncomeSheet(income: nil, mainCurrency: draft.mainCurrency).moneyPrivacyCover() }
            .onAppear(perform: load)
            .onChange(of: ratesReviewed) { _, now in draft.reviewedRates = MoneyWords.encodeCodes(now) }
            .onMoneyCovered { confirmingDiscard = false; problem = nil; replacing = nil }
            }
        }
    }

    // MARK: Rows

    private func rateRow(_ code: String) -> some View {
        // A rate typed since the last cut (in «Nueva cuenta») is offered first.
        let last = previous?.rateTable[code]
        let typedSince = startRates[code].flatMap { $0 != last ? $0 : nil }
        let before = typedSince ?? last
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                Text("1 \(code)").font(.ticket(.bodyMedium))
                Text(before.map { "\(typedSince != nil ? "el que escribiste" : "el corte pasado"): \(formatMoney($0, isoCode: draft.mainCurrency, label: draft.mainCurrency))" } ?? "primera vez")
                    .font(.ticket(.hint)).foregroundStyle(ratesReviewed.contains(code) ? Theme.good : Theme.muted)
            }
            Spacer()
            TextField("Tipo de cambio", text: Binding(
                get: { rateTexts[code] ?? "" },
                set: { text in
                    rateTexts[code] = text
                    // A rate, never thousands: «18.125» is eighteen and a bit.
                    guard let value = MoneyMath.decimal(text), value > 0 else { ratesReviewed.remove(code); return }
                    var table = draft.rateTable
                    table[code] = value
                    draft.rateTable = table
                    ratesReviewed.insert(code)
                }),
                prompt: Text(before.map { BackupNumber.text($0) } ?? "0.00").foregroundStyle(Theme.faint))
                .font(.ticket(.field))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($rateFocus, equals: code)
                .accessibilityIdentifier("corte-cambio-\(code)")
            if let before, !ratesReviewed.contains(code) {
                Button(typedSince != nil ? "Usar ese" : "Sin cambio") {
                    var table = draft.rateTable
                    table[code] = before
                    draft.rateTable = table
                    ratesReviewed.insert(code)
                }
                .font(.ticket(.label))
                .foregroundStyle(Theme.brass)
                .buttonStyle(.tapTarget)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, kinds: [MoneyKind]) -> some View {
        let group = rows(of: kinds)
        if !group.isEmpty {
            Section {
                ForEach(group) { entry in row(entry) }
            } header: {
                Text(title).ticketCaption()
            }
            .listRowBackground(Theme.surface)
        }
    }

    private func row(_ entry: MoneyEntry) -> some View {
        let account = entry.account!
        let before = previous?.shownEntry(for: account)?.balance
        let separator = Locale.current.decimalSeparator ?? "."
        // Thousands while typing (2026-11-11). The model is given what the field will show, in
        // the same step: the text is only rewritten afterwards (`groupsMoney`), and until then
        // «1,2345» would not read.
        let balanceText = Binding(
            get: { typed[account.id] ?? "" },
            set: { text in
                let shown = MoneyTyping.typed(text, was: typed[account.id] ?? "", decimalSeparator: separator)
                typed[account.id] = text
                switch MoneyTyping.reading(shown) {
                case .value(let value):
                    entry.balance = value
                    entry.reviewed = true
                case .empty, .unreadable:
                    // What doesn't read waits, marked: never the last amount that read.
                    entry.reviewed = false
                }
            })
        let movementText = Binding(
            get: { movements[account.id] ?? "" },
            set: { text in
                let shown = MoneyTyping.typed(text, was: movements[account.id] ?? "", decimalSeparator: separator)
                movements[account.id] = text
                if case .value(let value) = MoneyTyping.signedReading(shown) {
                    entry.movement = value
                } else {
                    entry.movement = nil
                }
            })
        let state = hint(for: entry, account: account, before: before)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    Text(account.name)
                        .font(.ticket(.bodyMedium))
                        .tracking(Theme.Tracking.name)
                        .textCase(.uppercase)
                    Text(state.shown)
                        .font(.ticket(.hint))
                        .foregroundStyle(MoneyTyping.reading(typed[account.id] ?? "") == .unreadable ? Theme.danger
                                         : entry.reviewed ? Theme.good : Theme.muted)
                        // «✓ escrito» is read as «Escrito», without the mark.
                        .accessibilityLabel(state.spoken)
                }
                Spacer(minLength: Theme.Space.s)
                TextField(account.name, text: balanceText,
                    prompt: Text(before.map { formatMoney($0, isoCode: account.currency, label: account.currency, main: draft.mainCurrency) } ?? "0.00")
                        .foregroundStyle(Theme.faint))
                    .font(.ticket(.field))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focus, equals: account.id)
                    .groupsMoney(balanceText)
                    .accessibilityIdentifier("corte-saldo-\(account.name)")
            }
            if account.kind == .investment {
                TextField("¿Metiste o sacaste?", text: movementText,
                    prompt: Text("¿Metiste o sacaste? (−300 si sacaste)").foregroundStyle(Theme.faint))
                    .font(.ticket(.detail))
                    .keyboardType(.numbersAndPunctuation)
                    .focused($movementFocus, equals: account.id)
                    .groupsMoney(movementText)
                if MoneyTyping.signedReading(movements[account.id] ?? "") == .unreadable {
                    Text("No se lee: escribe solo el número, como −300.")
                        .font(.ticket(.hint)).foregroundStyle(Theme.danger)
                }
            }
            if !entry.reviewed, before != nil {
                Button("Sin cambio") { keep(entry) }
                    .font(.ticket(.label))
                    .foregroundStyle(Theme.brass)
                    .buttonStyle(.tapTarget)
                    .accessibilityIdentifier("corte-sin-cambio-\(account.name)")
            }
        }
    }

    /// The line under an account's name, as it is shown and as VoiceOver says it: a looked-at
    /// line shows «✓ escrito» and is read «Escrito» (2026-11-11).
    private func hint(for entry: MoneyEntry, account: MoneyAccount, before: Decimal?) -> (shown: String, spoken: String) {
        if entry.reviewed, MoneyTyping.reading(typed[account.id] ?? "") != .unreadable {
            let word = switch typed[account.id] {
            case .some(""): "sin cambio"
            case .some: "escrito"
            case .none: "revisado"
            }
            return ("✓ \(word)", word.prefix(1).uppercased() + String(word.dropFirst()))
        }
        let text = waitingHint(for: entry, account: account, before: before)
        return (text, text)
    }

    private func waitingHint(for entry: MoneyEntry, account: MoneyAccount, before: Decimal?) -> String {
        if MoneyTyping.reading(typed[account.id] ?? "") == .unreadable {
            return "no se lee: escribe solo el número, como 12500.50"
        }
        guard let before else { return "nueva" }
        var text = "antes \(formatMoney(before, isoCode: account.currency, label: account.currency, main: draft.mainCurrency))"
        if let rate = account.yearlyRate, let since = previous?.date {
            let days = Calendar.current.dateComponents([.day], from: since, to: AppClock.now).day ?? 0
            let yield = MoneyMath.expectedYield(previous: before, yearlyRate: rate, days: days)
            if yield > 0 { text += " · rendiría ~\(formatMoney(yield, isoCode: account.currency, label: account.currency, main: draft.mainCurrency))" }
        }
        return text
    }

    // MARK: Actions

    /// Reopening a draft: what was written comes back in its fields (second audit,
    /// 2026-11-02: the balances already looked at and the movements were saved but the fields
    /// opened empty), and the rates already looked at stay looked at, with their value shown.
    private func load() {
        let reviewed = MoneyWords.decodeCodes(draft.reviewedRates).intersection(foreign)
        ratesReviewed.formUnion(reviewed)
        for code in foreign where rateTexts[code] == nil {
            rateTexts[code] = reviewed.contains(code) ? draft.rateTable[code].map { BackupNumber.text($0) } ?? "" : ""
            if !reviewed.contains(code), let start = draft.rateTable[code] { startRates[code] = start }
        }
        for entry in entries {
            guard let account = entry.account else { continue }
            // As the fields write them (thousands with commas): they read back to the same amount.
            if typed[account.id] == nil, entry.reviewed { typed[account.id] = MoneyTyping.groupedText(entry.balance) }
            if movements[account.id] == nil, entry.movement != nil { movements[account.id] = MoneyTyping.groupedText(entry.movement) }
        }
    }

    /// «Sin cambio»: the last balance, looked at. With a rate it means no yield, on purpose.
    private func keep(_ entry: MoneyEntry) {
        guard let account = entry.account else { return }
        entry.balance = previous?.shownEntry(for: account)?.balance ?? entry.balance
        entry.reviewed = true
        typed[account.id] = ""
        focus = nextPending(after: account.id)
    }

    /// The next line still waiting, in the order of the sheet, going round.
    private func nextPending(after id: UUID?) -> UUID? {
        let ids = shown.compactMap(\.account?.id)
        let start = id.flatMap { ids.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        let pendingIDs = Set(entries.filter { !$0.reviewed }.compactMap(\.account?.id))
        return (ids[start...] + ids[..<start]).first { pendingIDs.contains($0) && $0 != id }
    }

    /// «N sin revisar»: the list moves to the first thing left, from the top of the sheet (an
    /// exchange rate, then a balance, then a movement that doesn't read), and the cursor goes
    /// there. With the cursor already on a balance, to the next one waiting.
    private func goToPending(_ proxy: ScrollViewProxy) {
        if let code = foreign.first(where: { !ratesReviewed.contains($0) }) {
            reveal(code, with: proxy) { rateFocus = code }
        } else if let id = nextPending(after: focus) ?? focus,
                  let entry = shown.first(where: { $0.account?.id == id }), !entry.reviewed {
            reveal(entry.id, with: proxy) { focus = id }
        } else if let entry = shown.first(where: { entry in
            entry.account.map { MoneyTyping.signedReading(movements[$0.id] ?? "") == .unreadable } ?? false
        }), let id = entry.account?.id {
            reveal(entry.id, with: proxy) { movementFocus = id }
        }
    }

    /// A row off screen has no field yet to take the cursor: the list gets there first.
    private func reveal<ID: Hashable>(_ row: ID, with proxy: ScrollViewProxy, then takeCursor: @escaping @MainActor () -> Void) {
        withAnimation(Theme.Motion.animation(Theme.Motion.page, reduceMotion: reduceMotion)) {
            proxy.scrollTo(row, anchor: .center)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Theme.Motion.Money.pendingReveal))
            takeCursor()
        }
    }

    private func save() { save(replacing: false) }

    private func save(replacing: Bool) {
        do {
            try MoneyStore.finish(draft, replacing: replacing, in: context)
            draft.reviewedRates = ""
            try? context.save()
            dismiss()
        } catch MoneyStore.CutProblem.monthHasCut(let date) {
            self.replacing = date
        } catch {
            problem = "No se guardó el corte"
        }
    }
}
