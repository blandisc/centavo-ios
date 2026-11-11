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

    /// The cut this one starts from: the same month's (being redone) or the one before. Never a
    /// later month's, when the cut is for the month that just ended.
    private var previous: MoneyCut? { MoneyStore.cut(before: draft.month, in: context) }

    private var entries: [MoneyEntry] {
        (draft.entries ?? []).filter { $0.account != nil }
            .sorted { ($0.account?.order ?? 0, $0.account?.createdAt ?? AppClock.now) < ($1.account?.order ?? 0, $1.account?.createdAt ?? AppClock.now) }
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
                    Button(pending == 0 ? "Guardar" : "\(pending) sin revisar", action: save)
                        .font(.ticket(.footnoteStrong))
                        .disabled(pending > 0)
                        .accessibilityIdentifier("corte-guardar")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if let id = focus, let entry = entries.first(where: { $0.account?.id == id }) {
                        Button("Sin cambio") { keep(entry) }.font(.ticket(.footnoteStrong))
                    }
                    Spacer()
                    Button("Siguiente") { focus = nextPending(after: focus) }.font(.ticket(.footnoteStrong))
                }
            }
            .alert("¿Descartar el corte?", isPresented: $confirmingDiscard) {
                Button("Cancelar", role: .cancel) {}
                Button("Descartar", role: .destructive) {
                    // A failure is said, and the sheet stays (second audit, 2026-11-02).
                    do {
                        try MoneyStore.discard(draft, in: context)
                        dismiss()
                    } catch {
                        context.rollback()
                        problem = "No se descartó el corte"
                    }
                }
            } message: { Text("Se borra lo que escribiste en este corte. Tus cortes pasados no cambian.") }
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
        let rows = entries.filter { kinds.contains($0.account?.kind ?? .account) }
        if !rows.isEmpty {
            Section {
                ForEach(rows) { entry in row(entry) }
            } header: {
                Text(title).ticketCaption()
            }
            .listRowBackground(Theme.surface)
        }
    }

    private func row(_ entry: MoneyEntry) -> some View {
        let account = entry.account!
        let before = previous?.shownEntry(for: account)?.balance
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    Text(account.name)
                        .font(.ticket(.bodyMedium))
                        .tracking(Theme.Tracking.name)
                        .textCase(.uppercase)
                    Text(hint(for: entry, account: account, before: before))
                        .font(.ticket(.hint))
                        .foregroundStyle(MoneyTyping.reading(typed[account.id] ?? "") == .unreadable ? Theme.danger
                                         : entry.reviewed ? Theme.good : Theme.muted)
                }
                Spacer(minLength: Theme.Space.s)
                TextField(account.name, text: Binding(
                    get: { typed[account.id] ?? "" },
                    set: { text in
                        typed[account.id] = text
                        switch MoneyTyping.reading(text) {
                        case .value(let value):
                            entry.balance = value
                            entry.reviewed = true
                        case .empty, .unreadable:
                            // What doesn't read waits, marked: never the last amount that read.
                            entry.reviewed = false
                        }
                    }),
                    prompt: Text(before.map { formatMoney($0, isoCode: account.currency, label: account.currency, main: draft.mainCurrency) } ?? "0.00")
                        .foregroundStyle(Theme.faint))
                    .font(.ticket(.field))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focus, equals: account.id)
                    .accessibilityIdentifier("corte-saldo-\(account.name)")
            }
            if account.kind == .investment {
                TextField("¿Metiste o sacaste?", text: Binding(
                    get: { movements[account.id] ?? "" },
                    set: { text in
                        movements[account.id] = text
                        if case .value(let value) = MoneyTyping.signedReading(text) {
                            entry.movement = value
                        } else {
                            entry.movement = nil
                        }
                    }),
                    prompt: Text("¿Metiste o sacaste? (−300 si sacaste)").foregroundStyle(Theme.faint))
                    .font(.ticket(.detail))
                    .keyboardType(.numbersAndPunctuation)
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

    private func hint(for entry: MoneyEntry, account: MoneyAccount, before: Decimal?) -> String {
        if MoneyTyping.reading(typed[account.id] ?? "") == .unreadable {
            return "no se lee: escribe solo el número, como 12500.50"
        }
        if entry.reviewed {
            switch typed[account.id] {
            case .some(""): return "✓ sin cambio"
            case .some: return "✓ escrito"
            case .none: return "✓ revisado"
            }
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
            if typed[account.id] == nil, entry.reviewed { typed[account.id] = MoneyTyping.text(entry.balance) }
            if movements[account.id] == nil, entry.movement != nil { movements[account.id] = MoneyTyping.signedText(entry.movement) }
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

    private func nextPending(after id: UUID?) -> UUID? {
        let ids = entries.compactMap(\.account?.id)
        let start = id.flatMap { ids.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        let pendingIDs = Set(entries.filter { !$0.reviewed }.compactMap(\.account?.id))
        return (ids[start...] + ids[..<start]).first { pendingIDs.contains($0) && $0 != id }
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
