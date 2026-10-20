import CentavoCore
import SwiftData
import SwiftUI

/// «Más › Gastos fijos»: what comes back on its own (rent on the 1st, the cleaning every
/// Monday, Netflix on the 15th), when it comes next, and what this month still has coming,
/// which «Hoy puedes gastar» already sets apart.
struct FixedExpensesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Expense> { $0.repeatsMonthly == true }) private var originals: [Expense]
    @Query(filter: #Predicate<Expense> { $0.isRepeat == true }) private var copies: [Expense]
    @AppStorage(FixedPlan.key) private var storedPlans = ""
    @AppStorage(CurrencyPreference.key) private var storedCurrency = ""
    @State private var adding = false
    @State private var editing: Expense?

    private var primary: String { CurrencyPreference.resolve(storedCurrency) }
    private var items: [FixedItem] { FixedOutlook.items(originals: originals, plans: FixedPlan.decode(storedPlans)) }

    private func money(_ amount: Decimal, _ currency: String) -> String {
        let iso = CurrencyResolver.isoCode(for: currency, primary: primary)
        return formatMoney(amount, isoCode: iso, label: currency)
    }

    /// What already arrived this month, in the main currency.
    private var arrived: Decimal {
        (originals + copies)
            .filter { MonthNavigator.isSameMonth($0.date, as: .now) && $0.date <= .now }
            .filter { CurrencyResolver.isoCode(for: $0.currencyMarker, primary: primary) == primary }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var coming: Decimal {
        FixedOutlook.reserved(originals: originals, plans: FixedPlan.decode(storedPlans), primary: primary)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        summaryFigure("Ya llegaron", money(arrived, primary))
                        Spacer()
                        summaryFigure("Faltan", money(coming, primary), brass: true)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("fijos-resumen")
                } header: {
                    Text("Este mes").ticketCaption()
                } footer: {
                    hint("Lo que falta ya se aparta de «Hoy puedes gastar», y cada uno se anota solo el día que llega.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    ForEach(items) { item in
                        Button { editing = item.original } label: { row(item) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                if let original = item.original {
                                    Button("Dejar de repetir", systemImage: "stop.circle", role: .destructive) {
                                        stop(original)
                                    }
                                } else if let plan = item.plan {
                                    Button("Borrar", systemImage: "trash", role: .destructive) { remove(plan) }
                                }
                            }
                    }
                    Button { adding = true } label: {
                        Label("Agregar gasto fijo", systemImage: "plus")
                            .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                            .foregroundStyle(Theme.brass)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("agregar-fijo")
                } header: {
                    Text("Tus gastos fijos").ticketCaption()
                } footer: {
                    hint(items.isEmpty
                         ? "La renta, la limpieza de cada lunes, Netflix: anótalos una vez y se anotan solos el día que llegan."
                         : "Toca uno para cambiarlo. Desliza a la izquierda para que deje de repetirse; lo ya anotado se queda.")
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Gastos fijos")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                        .accessibilityIdentifier("hoja-listo")
                }
            }
            .sheet(isPresented: $adding) { FixedPlanSheet() }
            .sheet(item: $editing) { ExpenseEditorView(expense: $0) }
            .onAppear { try? RecurringExpenses.logDue(in: context) }
        }
    }

    private func row(_ item: FixedItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.ticket(15, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(money(item.amount, item.currency))
                    .font(.ticket(15, relativeTo: .body))
                    .foregroundStyle(Theme.ink)
                    .fixedSize()
            }
            Text(item.ruleText)
                .font(.ticket(11, relativeTo: .caption2))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
            if let next = item.next {
                Text((item.original == nil ? "Empieza: " : "Próximo: ")
                     + next.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.ticket(11, relativeTo: .caption2))
                    .foregroundStyle(item.coming.isEmpty ? Theme.muted : Theme.brass)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func summaryFigure(_ label: String, _ amount: String, brass: Bool = false) -> some View {
        VStack(alignment: brass ? .trailing : .leading, spacing: 2) {
            Text(label)
                .font(.ticket(10, relativeTo: .caption2))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
            Text(amount)
                .font(.ticket(17, weight: .medium, relativeTo: .headline))
                .foregroundStyle(brass ? Theme.brass : Theme.ink)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.ticket(12, relativeTo: .footnote)).foregroundStyle(Theme.muted)
    }

    /// What is already logged stays; only what is to come stops.
    private func stop(_ original: Expense) {
        original.repeatsMonthly = nil
        original.repeatsThrough = nil
        original.repeatDay = nil
        original.repeatRule = nil
    }

    private func remove(_ plan: FixedPlan) {
        FixedPlan.save(FixedPlan.decode(storedPlans).filter { $0.id != plan.id })
    }
}

/// «Agregar gasto fijo»: how much, what it is, how often and when it first comes. A first
/// charge that already came is logged now (with its date), and the ones after it that also
/// came; one still to come waits for its day.
struct FixedPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var history: [Expense]
    @State private var amountText = ""
    @State private var merchant = ""
    @State private var rule = RepeatRule.monthly
    @State private var firstDay = Date.now
    @FocusState private var amountFocused: Bool

    private var amount: Decimal? {
        guard let value = AmountParser.parse(amountText)?.value, value > 0 else { return nil }
        return value
    }

    private var name: String { merchant.trimmingCharacters(in: .whitespaces) }

    /// The first charge's moment: 9:00 of the day picked, like the welcome's fixed expenses.
    private var firstDate: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: firstDay) ?? firstDay
    }

    private var latest: Date { Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Monto", text: $amountText, prompt: Text("0.00").foregroundStyle(Theme.faint))
                        .font(.ticket(44, weight: .medium, relativeTo: .largeTitle))
                        .tracking(-1.5)
                        .foregroundStyle(Theme.ink)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .groupsThousands($amountText)
                        .accessibilityIdentifier("fijo-monto")
                } header: {
                    Text("Monto (\(CurrencyPreference.current))").ticketCaption()
                }
                .listRowBackground(Theme.surface)

                Section {
                    TextField("Qué es", text: $merchant,
                              prompt: Text("Renta, limpieza, Netflix…").foregroundStyle(Theme.faint))
                        .font(.ticket(17, relativeTo: .body))
                        .foregroundStyle(Theme.ink)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("fijo-nombre")
                } header: {
                    Text("Qué es").ticketCaption()
                }
                .listRowBackground(Theme.surface)

                Section {
                    RepeatRulePicker(rule: $rule)
                    DatePicker(selection: $firstDay, in: ...latest, displayedComponents: .date) {
                        Text("Primer cobro")
                            .font(.ticket(12, relativeTo: .footnote))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    .accessibilityIdentifier("fijo-primer-cobro")
                } header: {
                    Text("Cada cuándo").ticketCaption()
                } footer: {
                    hint(FixedWording.howItRepeats(rule, from: firstDate) + " "
                         + (firstDate > .now
                            ? "Hasta su primer cobro no se anota nada."
                            : "El primer cobro ya llegó: se anota con su fecha, y los que hayan llegado después."))
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .scrollDismissesKeyboard(.immediately)
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Nuevo gasto fijo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(.ticket(13, relativeTo: .footnote))
                        .accessibilityIdentifier("hoja-cancelar")
                }
            }
            .saveBar(amount == nil ? "Falta el monto" : name.isEmpty ? "Falta qué es"
                        : "\(name) · " + FixedWording.howItRepeats(rule, from: firstDate).components(separatedBy: ":").first!,
                     enabled: amount != nil && !name.isEmpty, action: save)
            .onAppear { amountFocused = true }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.ticket(11, relativeTo: .caption2))
            .tracking(0.6)
            .foregroundStyle(Theme.faint)
    }

    private func save() {
        guard let amount else { return }
        let plan = FixedPlan(
            merchant: String(name.prefix(ExpenseRecorder.maxMerchantLength)),
            amount: "\(amount)",
            currency: CurrencyPreference.current,
            category: MerchantCatalog.suggestion(for: name, history: history.map(\.categorized)),
            rule: rule.stored,
            firstDate: firstDate
        )
        if plan.firstDate <= .now {
            context.insert(RecurringExpenses.original(from: plan))
            try? RecurringExpenses.logDue(in: context)
        } else {
            FixedPlan.save(FixedPlan.saved + [plan])
        }
        dismiss()
    }
}
