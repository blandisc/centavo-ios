import CentavoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// «¿Lo tienes en Excel?» (2026-11-01): the person's own AI turns their spreadsheet into lines
/// for «Mi dinero». Al día gives the instructions, takes back what the AI wrote (pasted, or a
/// file) and shows it for review before anything is saved: every row can be fixed, removed or
/// added, each foreign currency gets its exchange rate, and what didn't read says why.
///
/// It's a screen pushed inside the steps, not a sheet: going to the AI and coming back keeps it
/// under «Mi dinero»'s Face ID lock, figures included.
struct MoneyImportView: View {
    let mainCurrency: String
    let finished: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // No @Query here: a pushed screen querying what the screen behind it queries kept SwiftUI
    // redrawing it without end. What it needs is read once, when an answer is loaded.
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var copied = false
    @State private var choosingFile = false
    @State private var rows: [MoneyImportRow] = []
    @State private var notes: [String] = []
    @State private var rateTexts: [String: String] = [:]
    @State private var rateChoices: [String: [Decimal]] = [:]
    @State private var open: UUID?
    @State private var problem: String?
    /// The pasteboard's count right after pasting: if nothing else was copied since, what was
    /// pasted (the person's finances) is cleared from it on saving.
    @State private var pastedAt: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if rows.isEmpty { instructions } else { review }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { if !rows.isEmpty { saveBar } }
        .navigationBarTitleDisplayMode(.inline)
        .ticketBarTitle("Desde tu Excel")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Ocultar teclado") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(.ticket(.footnoteStrong))
            }
        }
        .fileImporter(isPresented: $choosingFile,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .utf8PlainText]) { result in
            guard case .success(let url) = result else { return }
            guard let text = Self.read(url) else { problem = "No pude abrir ese archivo."; return }
            load(text)
        }
        .alert("No se pudo", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text(problem ?? "") }
        .onDisappear { if pastedAt != nil { forgetPasted() } }
    }

    // MARK: Before: the instructions

    @ViewBuilder private var instructions: some View {
        Text("Tu Excel, con tu IA")
            .font(.ticket(.pageTitle))
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
        Text("Tu Excel lo lee la IA que tú elijas, con sus reglas; Al día no lo recibe. Si quieres, usa un chat temporal.")
            .font(.ticket(.callout))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
        step(1, "Copia las instrucciones", "Ya traen tu moneda y el formato de Al día.")
        Button(action: copy) {
            PrimaryButtonLabel(copied ? "Copiadas" : "Copiar instrucciones", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .ticketProminent()
        .accessibilityIdentifier("importar-copiar")
        step(2, "Pégalas en tu IA con tu Excel", "ChatGPT, Claude, Gemini o la que uses. Adjunta tu archivo.")
        step(3, "Trae lo que te devuelva", "Copia su respuesta y pégala, o súbela si te dio un archivo.")
        // The system's Paste button sizes itself (UIKit underneath): left at its own size, alone on
        // its line. Beside a button that stretches, the two kept re-laying out without end.
        PasteButton(payloadType: String.self) { texts in
            guard let text = texts.first else { return }
            Task { @MainActor in
                pastedAt = UIPasteboard.general.changeCount
                load(text)
            }
        }
        .tint(Theme.brass)
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .accessibilityIdentifier("importar-pegar")
        Button { choosingFile = true } label: {
            Label("O sube el archivo que te dio", systemImage: "doc.badge.plus")
                .font(.ticket(.label))
                .tracking(Theme.Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(Theme.brass)
                .frame(minHeight: Theme.Size.tapTarget)
        }
        .accessibilityIdentifier("importar-archivo")
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-centavo-importar-ejemplo") {
            Button("Usar ejemplo") { load(MoneyDemo.importSample) }
                .font(.ticket(.label))
                .foregroundStyle(Theme.brass)
                .accessibilityIdentifier("importar-ejemplo")
        }
        #endif
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text("\(number)")
                .font(.ticket(.label))
                .foregroundStyle(Theme.brass)
                .frame(width: Theme.Size.rowTile, height: Theme.Size.rowTile)
                .background(Theme.brass.opacity(Theme.Opacity.moneyCurrency), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
            VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                Text(title).font(.ticket(.bodyStrong)).foregroundStyle(Theme.ink)
                Text(detail).font(.ticket(.detail)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: After: the review

    private var ready: [MoneyImportRow] { rows.filter { $0.include && $0.isReady(main: mainCurrency) } }
    private var waiting: [MoneyImportRow] { rows.filter { $0.include && !$0.isReady(main: mainCurrency) } }
    private var currencies: [String] {
        Array(Set(ready.map(\.draft.currency))).filter { $0 != mainCurrency }.sorted()
    }
    private var missingRates: [String] { currencies.filter { rate(for: $0) == nil } }
    private func rate(for code: String) -> Decimal? {
        MoneyMath.decimal(rateTexts[code] ?? "").flatMap { $0 > 0 ? $0 : nil }
    }

    @ViewBuilder private var review: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Revisa antes de guardar")
                .font(.ticket(.pageTitle))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("\(ready.count == 1 ? "1 lista" : "\(ready.count) listas") · \(waiting.count) por revisar")
                .font(.ticket(.detail))
                .foregroundStyle(waiting.isEmpty ? Theme.muted : Theme.brass)
                .accessibilityIdentifier("importar-resumen")
            Text("Toca un renglón para corregirlo. Nada se guarda hasta que lo confirmes.")
                .font(.ticket(.detail))
                .foregroundStyle(Theme.muted)
        }
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Notas de tu IA").ticketCaption()
                ForEach(notes, id: \.self) { Text($0).font(.ticket(.detail)).foregroundStyle(Theme.ink) }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        if !currencies.isEmpty { rates }
        ForEach(MoneyImportRow.Place.allCases, id: \.self) { place in
            group(place.title, rows: rows.filter { $0.placed == place })
        }
        Button(action: addRow) {
            Label("Agregar otra", systemImage: "plus")
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
        .accessibilityIdentifier("importar-agregar")
        Button("Pegar otra respuesta") {
            withAnimation(motion) { rows = []; notes = []; rateTexts = [:]; rateChoices = [:] }
        }
            .font(.ticket(.label))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
    }

    private var rates: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Tipos de cambio de hoy").ticketCaption()
            ForEach(currencies, id: \.self) { code in
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack {
                        Text("1 \(MoneyCurrency.symbol(code)) =").font(.ticket(.bodyMedium)).foregroundStyle(Theme.ink)
                        Spacer()
                        TextField("Tipo de cambio", text: Binding(get: { rateTexts[code] ?? "" }, set: { rateTexts[code] = $0 }),
                                  prompt: Text("\(MoneyCurrency.symbol(mainCurrency))0.00").foregroundStyle(Theme.faint))
                            .font(.ticket(.field))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(rate(for: code) == nil ? Theme.brass : Theme.ink)
                            .accessibilityIdentifier("importar-cambio-\(code)")
                    }
                    if let choices = rateChoices[code], choices.count > 1 {
                        Text("Tu Excel trae \(choices.count) distintos. ¿Cuál usamos?")
                            .font(.ticket(.detail)).foregroundStyle(Theme.brass)
                        HStack(spacing: Theme.Space.xs) {
                            ForEach(choices, id: \.self) { value in
                                TicketChip(BackupNumber.text(value), selected: rateTexts[code] == BackupNumber.text(value)) {
                                    rateTexts[code] = BackupNumber.text(value)
                                }
                            }
                        }
                    } else if rate(for: code) == nil {
                        Text("Escríbelo: tu Excel no lo traía.").font(.ticket(.detail)).foregroundStyle(Theme.brass)
                    }
                }
                .padding(Theme.Space.m)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, rows group: [MoneyImportRow]) -> some View {
        if !group.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(title).ticketCaption()
                ForEach(group) { row in line(row.id) }
            }
        }
    }

    private func binding(_ id: UUID) -> Binding<MoneyImportRow> {
        Binding(get: { rows.first { $0.id == id } ?? MoneyImportRow(draft: MoneyRowDraft()) },
                set: { new in if let at = rows.firstIndex(where: { $0.id == id }) { rows[at] = new } })
    }

    private func line(_ id: UUID) -> some View {
        let row = binding(id)
        let isOpen = open == id
        let needs = row.wrappedValue.placed == .review
        return VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            MoneyRow(title: row.wrappedValue.draft.trimmedName.isEmpty ? "Sin nombre" : row.wrappedValue.draft.trimmedName,
                     subtitle: row.wrappedValue.subtitle(main: mainCurrency),
                     swatch: needs ? Theme.brass : Theme.categories[Int(UInt(bitPattern: id.hashValue) % UInt(Theme.categories.count))],
                     figure: row.wrappedValue.figure(main: mainCurrency), isOpen: isOpen,
                     toggle: { withAnimation(motion) { open = isOpen ? nil : id } }) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Picker("Qué es", selection: row.draft.subtype) {
                        ForEach(MoneyImportRow.kinds, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.brass)
                    .font(.ticket(.body))
                    MoneyRowEditor(draft: row.draft, mainCurrency: mainCurrency, isNew: true, asksExchange: false,
                                   done: { confirm(id) }, remove: { removeRow(id) }, removeTitle: "Quitar")
                }
            }
            if let original = row.wrappedValue.duplicateOf {
                Toggle(isOn: Binding(get: { row.wrappedValue.include },
                                     set: { row.wrappedValue.include = $0; place(id) })) {
                    Text("¿Ya la tienes como «\(original)»? Agrégala de todos modos")
                        .font(.ticket(.detail)).foregroundStyle(Theme.muted)
                }
                .tint(Theme.brass)
                .padding(.horizontal, Theme.Space.m)
            }
        }
    }

    // MARK: The bar

    private var saveBar: some View {
        VStack(spacing: Theme.Space.xxs) {
            Button(action: save) {
                PrimaryButtonLabel(ready.isEmpty ? "Nada listo para agregar" : "Agregar \(ready.count)")
            }
            .ticketProminent()
            .disabled(ready.isEmpty || !missingRates.isEmpty)
            .accessibilityIdentifier("importar-guardar")
            if !missingRates.isEmpty {
                Text("Falta el tipo de cambio de \(missingRates.joined(separator: ", ")).")
                    .font(.ticket(.detail)).foregroundStyle(Theme.brass)
            } else if !waiting.isEmpty {
                Text("\(waiting.count) por revisar se quedan fuera; puedes completarlas antes o después.")
                    .font(.ticket(.detail)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.background.opacity(Theme.Opacity.paceAhead))
    }

    // MARK: Actions

    private var motion: Animation? { Theme.Motion.animation(Theme.Motion.Money.row, reduceMotion: reduceMotion) }

    private func copy() {
        UIPasteboard.general.string = MoneyImport.instructions(main: mainCurrency)
        withAnimation(motion) { copied = true }
    }

    private func load(_ text: String) {
        let result = MoneyImport.parse(text, main: mainCurrency)
        if let refusal = result.refusal { problem = refusal; return }
        withAnimation(motion) {
            notes = result.notes
            let accounts = (try? context.fetch(MoneyStore.activeAccounts)) ?? []
            let incomes = (try? context.fetch(MoneyStore.activeIncomes)) ?? []
            rows = result.lines.map { line in
                var row = MoneyImportRow(line: line, main: mainCurrency, existing: accounts, incomes: incomes)
                row.place(main: mainCurrency)
                return row
            }
            rateChoices = result.rates
            // What the file says, or else the rate already in «Mi dinero».
            let known = MoneyStore.latestCut(in: context)?.rateTable ?? [:]
            for code in Set(result.lines.map(\.currency)) where code != mainCurrency {
                rateTexts[code] = (result.rates[code]?.first ?? known[code]).map { BackupNumber.text($0) } ?? ""
            }
            open = nil
        }
    }

    /// «Listo»: looked at, and placed again in the group it belongs to now.
    private func confirm(_ id: UUID) {
        guard let at = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[at].reviewed = true
        withAnimation(motion) {
            rows[at].place(main: mainCurrency)
            open = nil
        }
    }

    private func place(_ id: UUID) {
        guard let at = rows.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(motion) { rows[at].place(main: mainCurrency) }
    }

    private func removeRow(_ id: UUID) {
        withAnimation(motion) {
            rows.removeAll { $0.id == id }
            open = nil
        }
    }

    private func addRow() {
        var row = MoneyImportRow(draft: MoneyRowDraft(subtype: .account, currency: mainCurrency))
        row.reviewed = true
        row.placed = .review
        withAnimation(motion) {
            rows.insert(row, at: 0)
            open = row.id
        }
    }

    private func save() {
        let lines = ready.compactMap { $0.toSave }
        var rates: [String: Decimal] = [:]
        for code in currencies { rates[code] = rate(for: code) }
        do {
            try MoneyStore.addAll(lines, rates: rates, in: context, mainCurrency: mainCurrency)
            // The finances pasted shouldn't stay on the clipboard (nor reach the Mac's).
            forgetPasted()
            finished()
        } catch {
            problem = "No se guardó nada. Intenta otra vez."
        }
    }

    /// The finances pasted shouldn't stay on the clipboard, saved or not, if nothing else was copied since.
    private func forgetPasted() {
        if let pastedAt, UIPasteboard.general.changeCount == pastedAt { UIPasteboard.general.items = [] }
        pastedAt = nil
    }

    /// A file the AI gave, in whatever encoding Excel or the AI saved it.
    static func read(_ url: URL) -> String? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        // UTF-16 only with its mark: tried blindly, a Windows file of even length reads as noise.
        let marked = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        let encodings: [String.Encoding] = marked ? [.utf16] : [.utf8, .windowsCP1252, .isoLatin1]
        return encodings.lazy.compactMap { String(data: data, encoding: $0) }.first
    }
}

/// One row of the review: what the AI wrote, as an editable draft.
struct MoneyImportRow: Identifiable {
    static let kinds: [MoneySubtype] = [.account, .investment, .card, .loan, .other, .lent, .coming, .income]

    /// Where a row sits in the review. Set on loading and on «Listo», never while typing, so a
    /// row being edited doesn't jump to another group under the finger.
    enum Place: CaseIterable {
        case review, have, owe, owed, income, already

        var title: String {
            switch self {
            case .review: "Por revisar"
            case .have: "Tienes"
            case .owe: "Debes"
            case .owed: "Te deben"
            case .income: "Ingresos al mes"
            case .already: "Ya las tienes"
            }
        }
    }

    let id = UUID()
    var draft: MoneyRowDraft
    var placed: Place = .review
    var problems: [String] = []
    var warnings: [String] = []
    /// Opened and confirmed with «Listo»: its problems were looked at.
    var reviewed = false
    var include = true
    /// The name of a line already in «Mi dinero» that looks like this one.
    var duplicateOf: String?

    init(draft: MoneyRowDraft) { self.draft = draft }

    mutating func place(main: String) {
        if !include { placed = .already; return }
        guard isReady(main: main) else { placed = .review; return }
        switch draft.subtype {
        case .account, .investment: placed = .have
        case .card, .loan, .other: placed = .owe
        case .lent, .coming: placed = .owed
        case .income: placed = .income
        }
    }

    init(line: MoneyImport.Line, main: String, existing: [MoneyAccount], incomes: [MoneyIncome] = []) {
        var draft = MoneyRowDraft(subtype: line.kind.flatMap { MoneySubtype(rawValue: $0.rawValue) } ?? .account,
                                  currency: line.currency)
        draft.name = line.name
        draft.institution = line.institution
        draft.amount = line.amount.map { BackupNumber.text($0) } ?? ""
        draft.rate = line.yearlyRate.map { BackupNumber.text($0) } ?? ""
        self.draft = draft
        problems = line.problems
        warnings = line.warnings
        let name = Self.fold(line.name), institution = Self.fold(line.institution)
        if draft.subtype == .income {
            // An income is only ever the same as an income.
            if let twin = incomes.first(where: { Self.fold($0.name) == name }) {
                duplicateOf = twin.name
                include = false
            }
            return
        }
        if let twin = existing.first(where: { account in
            guard MoneySubtype.of(account).kind == draft.subtype.kind else { return false }
            let theirs = Self.fold(account.name), theirInstitution = Self.fold(account.institution ?? "")
            return theirs == name || (!institution.isEmpty && (theirs == institution || theirInstitution == institution && theirs == name))
        }) {
            duplicateOf = twin.name
            include = false
        }
    }

    func isReady(main: String) -> Bool {
        guard (problems.isEmpty || reviewed), !draft.trimmedName.isEmpty, draft.balance != nil else { return false }
        return draft.rate.isEmpty || draft.yearlyRate != nil
    }

    func figure(main: String) -> String? {
        guard let balance = draft.balance else { return nil }
        let text = formatMoney(balance, isoCode: draft.currency, label: draft.currency, main: main)
        return draft.subtype.kind == .debt ? "−" + text : text
    }

    func subtitle(main: String) -> String {
        if !reviewed, let first = problems.first { return first }
        var bits = [draft.trimmedInstitution, draft.subtype.short].compactMap { $0 }
        if let rate = draft.yearlyRate { bits.append("\(BackupNumber.text(rate))%") }
        if let warning = warnings.first, !reviewed { bits.append(warning) }
        return bits.joined(separator: " · ")
    }

    var toSave: MoneyLineToSave? {
        guard var amount = draft.balance else { return nil }
        // The same rule as reading the file: a debt, money owed or an income is written positive,
        // even when the row was an overdrawn account before its type was changed. Only an
        // account (or an investment) can be below zero.
        if amount < 0, draft.subtype.kind == .debt || draft.subtype.kind == .receivable || draft.subtype == .income {
            amount = -amount
        }
        return MoneyLineToSave(subtype: draft.subtype, name: draft.trimmedName, institution: draft.trimmedInstitution,
                               currency: draft.currency, amount: amount,
                               yearlyRate: draft.subtype.takesRate ? draft.yearlyRate : nil)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
            .filter { !$0.isWhitespace }
    }
}
