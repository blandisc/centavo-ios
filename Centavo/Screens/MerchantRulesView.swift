import CentavoCore
import SwiftData
import SwiftUI

/// «Lo que recuerdo»: what arrives as each text and how it is written down (owner's request,
/// 2026-11-11: «todo lo que me llega así lo reclasifico así»). The rules make themselves when
/// an expense is corrected; here they are seen, changed and forgotten.
struct MerchantRulesView: View {
    @AppStorage(UserCatalog.merchantRenamesKey) private var storedRenames = ""
    @AppStorage(UserCatalog.categoryRulesKey) private var storedRules = ""
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @AppStorage(UserCatalog.categoryColorsKey) private var storedCategoryColors = ""
    @AppStorage(UserCatalog.sourceColorsKey) private var storedSourceColors = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editing: MerchantRule?
    /// A rule about to be forgotten, waiting for «Olvidar».
    @State private var forgetting: MerchantRule?

    private var rules: [MerchantRule] {
        MerchantRules.list(renames: MerchantRenames(stored: storedRenames),
                           categories: CategoryRules(stored: storedRules))
    }

    private var colors: CatalogColors {
        CatalogColors(categories: storedCategoryColors, sources: storedSourceColors)
    }

    var body: some View {
        let rules = rules
        return List {
            if rules.isEmpty {
                Section {
                    empty
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(rules) { rule in
                        Button { editing = rule } label: { row(rule) }
                            .buttonStyle(.plain)
                            // No role: a destructive swipe would take the row out before the question.
                            .swipeActions(edge: .trailing) {
                                Button("Olvidar", systemImage: "trash") { forgetting = rule }
                                    .tint(Theme.danger)
                            }
                            .accessibilityIdentifier("recuerdo-\(rule.sent)")
                    }
                } header: {
                    Text("Lo que llega como…").ticketCaption()
                } footer: {
                    HintText("Al día recuerda cómo llamas y dónde pones cada comercio. Se anotan solas cuando corriges un gasto o le eliges categoría, también en los que escribes a mano y en los fijos. Toca una para cambiarla; desliza para olvidarla.")
                }
                .listRowBackground(Theme.surface)
            }
        }
        .ticketForm()
        .navigationBarTitleDisplayMode(.inline)
        .ticketBarTitle("Lo que recuerdo")
        .sheet(item: $editing) { MerchantRuleSheet(rule: $0) }
        .confirmsRemoval(of: $forgetting, question: { $0.forgetQuestion }) { UserCatalog.removeRule($0) }
    }

    /// The blank ticket: how the first one is made.
    private var empty: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Todavía no recuerdo nada")
                .font(.ticket(.bodyStrong))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Cámbiale el nombre o la categoría a un pago que llegó de Wallet, o elige la categoría de cualquier gasto, y guarda. Desde entonces, lo que vuelva a llegar igual se anota así, y aparece aquí.")
                .font(.ticket(.callout))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.xlx)
        .ticketOutline(.emphasis)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recuerdo-vacio")
    }

    private func row(_ rule: MerchantRule) -> some View {
        ExpenseRowLayout(name: rule.arrivesAs,
                         tile: CategoryIconTile(icon: rule.category.map { CategoryStyle.icon(for: $0, custom: UserCatalog.decode(storedCategories)) } ?? "tag",
                                                color: rule.category.map(colors.category))) {
            ExpenseMetaText(rule.summary)
        } amount: {
            // Stacked with the largest text, where an arrow on a line of its own says nothing.
            if !typeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(Theme.Symbol.regular)
                    .imageScale(.small)
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lo que llega como \(rule.arrivesAs) \(rule.summary.lowercasedFirst)")
        .accessibilityHint("Abre para cambiarlo u olvidarlo")
    }
}

extension MerchantRule {
    /// The quiet line under the text it arrives as: «Se anota como Tacos Pepe · Comida».
    var summary: String {
        let filed = category ?? (goesUncategorized ? "sin categoría" : nil)
        if let name {
            return (["Se anota como \(name)"] + [filed].compactMap { $0 }).joined(separator: " · ")
        }
        if let category { return "Va a \(category)" }
        return "Se queda sin categoría"
    }

    /// What «Olvidar» asks first.
    var forgetQuestion: TicketQuestion {
        TicketQuestion(title: "¿Olvidar este comercio?", name: arrivesAs, detail: summary,
                       note: "Los gastos ya anotados no cambian. Lo próximo que llegue así se anota como lo mande Wallet.",
                       verb: "Olvidar")
    }
}

private extension String {
    /// «Se anota como…» in the middle of a sentence.
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

/// One rule, to change or forget: the name it is written down with and its category, and
/// whether the expenses already saved should follow.
struct MerchantRuleSheet: View {
    let rule: MerchantRule

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(UserCatalog.categoriesKey) private var storedCategories = ""
    @AppStorage(UserCatalog.categoryColorsKey) private var storedCategoryColors = ""
    @AppStorage(UserCatalog.sourceColorsKey) private var storedSourceColors = ""
    @State private var name = ""
    @State private var filing = Filing.automatic
    /// The categories to pick from, read once when the sheet opens.
    @State private var offered: [String] = []
    /// The expenses already saved from this merchant, read once.
    @State private var saved: [Expense] = []
    @State private var texts: [String] = []
    /// «Cambiar también los otros»: off until someone turns it on.
    @State private var changesSaved = false
    @State private var askingDiscard = false
    @State private var confirmingForget = false
    @State private var saveFailed = false

    /// Where it is filed: the app decides, nowhere on purpose, or in a category.
    enum Filing: Hashable {
        case automatic, uncategorized, category(String)

        init(_ rule: MerchantRule) {
            self = rule.category.map(Filing.category) ?? (rule.goesUncategorized ? .uncategorized : .automatic)
        }

        var choice: CategoryRules.Choice? {
            switch self {
            case .automatic: nil
            case .uncategorized: .uncategorized
            case .category(let name): .category(name)
            }
        }

        var title: String {
            switch self {
            case .automatic: "Automática"
            case .uncategorized: "Sin categoría"
            case .category(let name): name
            }
        }

        var category: String? {
            if case .category(let name) = self { return name }
            return nil
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The name it will be saved with from now on, or `nil` for the one it arrives with.
    private var givenName: String? {
        trimmedName.isEmpty || MerchantKey.normalized(trimmedName) == rule.sent ? nil : trimmedName
    }
    private var colors: CatalogColors {
        CatalogColors(categories: storedCategoryColors, sources: storedSourceColors)
    }
    private var hasChanges: Bool {
        givenName != rule.name || filing != Filing(rule) || changesSaved
    }
    /// Nothing left to remember: saving it forgets the rule.
    private var remembersNothing: Bool { givenName == nil && filing == .automatic }

    private var backfill: MerchantBackfill {
        MerchantBackfill(texts: texts, name: givenName, category: filing.category, replacing: rule.category)
    }

    private var summary: String {
        if remembersNothing { return "Sin nombre ni categoría: se olvida" }
        return [givenName ?? rule.arrivesAs, filing == .automatic ? nil : filing.title]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// A category that is hidden or was deleted is never filled in on its own (2026-10-23).
    private var isNotFilledIn: Bool {
        guard let category = filing.category else { return false }
        return UserCatalog.notAutoAssigned.contains { UserCatalog.same($0, category) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(rule.arrivesAs)
                        .font(.ticket(.body))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
                        .accessibilityIdentifier("recuerdo-llega-como")
                } header: {
                    Text("Lo que llega como").ticketCaption()
                } footer: {
                    HintText("Mayúsculas, acentos y espacios no cuentan. Otra sucursal u otro número es otro comercio.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    TicketTextField("Nombre", text: $name, prompt: rule.arrivesAs, identifier: "recuerdo-nombre")
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                } header: {
                    Text("Se anota como").ticketCaption()
                } footer: {
                    HintText("Vacío, se anota con el nombre que llega.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    filingMenu
                } header: {
                    Text("En la categoría").ticketCaption()
                } footer: {
                    if isNotFilledIn {
                        NoteText("«\(filing.title)» está oculta o borrada y no se pone sola. Muéstrala en «Pagos y categorías» o elige otra.")
                    } else {
                        HintText("«Automática»: Al día la elige por lo último que usaste ahí.")
                    }
                }
                .listRowBackground(Theme.surface)

                savedSection

                Section {
                    DestructiveRowButton("Olvidar", identifier: "recuerdo-olvidar") { confirmingForget = true }
                } footer: {
                    HintText("Los gastos ya anotados no cambian.")
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .scrollDismissesKeyboard(.immediately)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Comercio recordado")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        if hasChanges { askingDiscard = true } else { dismiss() }
                    }
                    .font(.ticket(.footnote))
                    .accessibilityIdentifier("hoja-cancelar")
                }
            }
            .saveBar(summary, enabled: hasChanges, identifier: "recuerdo-guardar", action: save)
            .alert("No se guardó", isPresented: $saveFailed) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text("Al día no pudo cambiar tus gastos; nada cambió. Intenta otra vez.")
            }
            .confirmsRemoval(isPresented: $confirmingForget, question: { rule.forgetQuestion }) {
                UserCatalog.removeRule(rule)
                dismiss()
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: load)
        .confirmsDiscard(hasChanges: hasChanges, isAsking: $askingDiscard) { dismiss() }
    }

    /// The category as a menu on the whole row, with its icon and color.
    private var filingMenu: some View {
        Menu {
            Picker("Categoría", selection: $filing) {
                Text(Filing.automatic.title).tag(Filing.automatic)
                ForEach(offered, id: \.self) { Text($0).tag(Filing.category($0)) }
                Text(Filing.uncategorized.title).tag(Filing.uncategorized)
            }
        } label: {
            HStack(spacing: Theme.Space.m) {
                CategoryIconTile(icon: filing.category.map { CategoryStyle.icon(for: $0, custom: UserCatalog.decode(storedCategories)) } ?? "tag",
                                 color: filing.category.map(colors.category), background: Theme.raised)
                Text(filing.title)
                    .font(.ticket(.body))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Space.s)
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Categoría")
        .accessibilityValue(filing.title)
        .accessibilityIdentifier("recuerdo-categoria")
    }

    /// «Cambiar también los otros 6 gastos»: only while saved expenses would change.
    @ViewBuilder private var savedSection: some View {
        let count = backfill.pending(in: saved).count
        if count > 0 {
            Section {
                Toggle(isOn: $changesSaved) {
                    SectionLabel(MerchantBackfill.offer(count))
                }
                .tint(Theme.brass)
                .accessibilityIdentifier("cambiar-los-otros")
            } footer: {
                HintText("Los gastos ya anotados de este comercio quedan con este nombre y esta categoría. El que tenga otra categoría puesta por ti la conserva.")
            }
            .listRowBackground(Theme.surface)
        }
    }

    private func load() {
        name = rule.name ?? ""
        filing = Filing(rule)
        // Whole rows, once: the ones from this merchant may be written to on «Guardar».
        let history = (try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        offered = CategoryStyle.offered(known: CategoryMemory.known(in: history.map(\.categorized)),
                                        custom: UserCatalog.decode(storedCategories),
                                        current: rule.category ?? "", hidden: UserCatalog.hiddenNames)
        // The text it arrives as, and the name those payments were saved with since.
        texts = MerchantRules.texts(for: rule.name ?? rule.sent, renames: UserCatalog.merchantRenames)
        if !texts.contains(rule.sent) { texts.append(rule.sent) }
        let wanted = Set(texts)
        saved = history.filter { !$0.isFixed && wanted.contains(MerchantKey.normalized($0.merchant)) }
    }

    /// The expenses first, in one save: if they can't be saved, nothing else changes and the
    /// sheet stays open with what was chosen.
    private func save() {
        let pending = changesSaved ? backfill.pending(in: saved) : []
        if !pending.isEmpty {
            for item in pending { MerchantBackfill.apply(item.change, to: item.expense) }
            do {
                try context.save()
            } catch {
                context.rollback()
                saveFailed = true
                return
            }
        }
        UserCatalog.changeRule(rule, name: trimmedName, choice: filing.choice)
        dismiss()
    }
}

#Preview("Lo que recuerdo") {
    NavigationStack { MerchantRulesView() }.ticketPreview()
}
