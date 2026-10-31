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

    @State private var typed: [UUID: String] = [:]
    @State private var movements: [UUID: String] = [:]
    @State private var rateTexts: [String: String] = [:]
    @State private var ratesReviewed: Set<String> = []
    @State private var confirmingDiscard = false
    @State private var problem: String?
    @FocusState private var focus: UUID?

    private var previous: MoneyCut? {
        var descriptor = MoneyCut.finished
        descriptor.sortBy = [SortDescriptor(\.month, order: .reverse)]
        return (try? context.fetch(descriptor))?.first { $0.id != draft.id }
    }

    private var entries: [MoneyEntry] {
        (draft.entries ?? []).filter { $0.account != nil }
            .sorted { ($0.account?.order ?? 0, $0.account?.createdAt ?? .now) < ($1.account?.order ?? 0, $1.account?.createdAt ?? .now) }
    }

    private var foreign: [String] {
        MoneyMath.foreignCurrencies(in: draft.lines, main: draft.mainCurrency)
    }

    private var pending: Int {
        entries.filter { !$0.reviewed }.count + foreign.filter { !ratesReviewed.contains($0) }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                if !foreign.isEmpty {
                    Section {
                        ForEach(foreign, id: \.self) { code in rateRow(code) }
                    } header: {
                        Text("Tipo de cambio de hoy").ticketCaption()
                    }
                    .listRowBackground(Theme.surface)
                }
                section("¿Cuánto hay hoy?", kinds: [.account, .investment])
                section("Por cobrar", kinds: [.receivable])
                section("¿Cuánto debes hoy?", kinds: [.debt])
                Section {
                    DestructiveRowButton("Descartar corte", identifier: "corte-descartar") { confirmingDiscard = true }
                } footer: {
                    HintText("Si sales sin guardar, el corte te espera como lo dejaste.")
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Corte de \(MoneyHead.monthName(draft.month))")
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
                    try? MoneyStore.discard(draft, in: context)
                    dismiss()
                }
            } message: { Text("Se borra lo que escribiste en este corte. Tus cortes pasados no cambian.") }
            .alert("No se pudo", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: { Text(problem ?? "") }
            .onAppear(perform: load)
        }
    }

    // MARK: Rows

    private func rateRow(_ code: String) -> some View {
        let before = previous?.rateTable[code]
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                Text("1 \(code)").font(.ticket(.bodyMedium))
                Text(before.map { "el corte pasado: \(formatMoney($0, isoCode: draft.mainCurrency, label: draft.mainCurrency))" } ?? "primera vez")
                    .font(.ticket(.hint)).foregroundStyle(ratesReviewed.contains(code) ? Theme.good : Theme.muted)
            }
            Spacer()
            TextField("Tipo de cambio", text: Binding(
                get: { rateTexts[code] ?? "" },
                set: { text in
                    rateTexts[code] = text
                    guard let value = AmountParser.parse(text)?.value, value > 0 else { ratesReviewed.remove(code); return }
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
                Button("Sin cambio") {
                    var table = draft.rateTable
                    table[code] = before
                    draft.rateTable = table
                    ratesReviewed.insert(code)
                }
                .font(.ticket(.label))
                .foregroundStyle(Theme.brass)
                .buttonStyle(.borderless)
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
        let before = previous?.entry(for: account)?.balance
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    Text(account.name)
                        .font(.ticket(.bodyMedium))
                        .tracking(Theme.Tracking.name)
                        .textCase(.uppercase)
                    Text(hint(for: entry, account: account, before: before))
                        .font(.ticket(.hint))
                        .foregroundStyle(entry.reviewed ? Theme.good : Theme.muted)
                }
                Spacer(minLength: Theme.Space.s)
                TextField(account.name, text: Binding(
                    get: { typed[account.id] ?? "" },
                    set: { text in
                        typed[account.id] = text
                        if let value = AmountParser.parse(text)?.value {
                            entry.balance = value
                            entry.reviewed = true
                        } else if text.isEmpty {
                            entry.reviewed = false
                        }
                    }),
                    prompt: Text(before.map { formatMoney($0, isoCode: account.currency, label: account.currency) } ?? "0.00")
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
                        let negative = text.hasPrefix("-") || text.hasPrefix("−")
                        let value = AmountParser.parse(String(text.drop(while: { $0 == "-" || $0 == "−" })))?.value
                        entry.movement = value.map { negative ? -$0 : $0 }
                    }),
                    prompt: Text("¿Metiste o sacaste? (−300 si sacaste)").foregroundStyle(Theme.faint))
                    .font(.ticket(.detail))
                    .keyboardType(.numbersAndPunctuation)
            }
            if !entry.reviewed, before != nil {
                Button("Sin cambio") { keep(entry) }
                    .font(.ticket(.label))
                    .foregroundStyle(Theme.brass)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("corte-sin-cambio-\(account.name)")
            }
        }
    }

    private func hint(for entry: MoneyEntry, account: MoneyAccount, before: Decimal?) -> String {
        if entry.reviewed {
            switch typed[account.id] {
            case .some(""): return "✓ sin cambio"
            case .some: return "✓ escrito"
            case .none: return "✓ revisado"
            }
        }
        guard let before else { return "nueva" }
        var text = "antes \(formatMoney(before, isoCode: account.currency, label: account.currency))"
        if let rate = account.yearlyRate, let since = previous?.date {
            let days = Calendar.current.dateComponents([.day], from: since, to: .now).day ?? 0
            let yield = MoneyMath.expectedYield(previous: before, yearlyRate: rate, days: days)
            if yield > 0 { text += " · rendiría ~\(formatMoney(yield, isoCode: account.currency, label: account.currency))" }
        }
        return text
    }

    // MARK: Actions

    private func load() {
        for code in foreign where rateTexts[code] == nil { rateTexts[code] = "" }
    }

    /// «Sin cambio»: the last balance, looked at. With a rate it means no yield, on purpose.
    private func keep(_ entry: MoneyEntry) {
        guard let account = entry.account else { return }
        entry.balance = previous?.entry(for: account)?.balance ?? entry.balance
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

    private func save() {
        do {
            try MoneyStore.finish(draft, in: context)
            dismiss()
        } catch {
            problem = "No se guardó el corte. Intenta otra vez."
        }
    }
}
