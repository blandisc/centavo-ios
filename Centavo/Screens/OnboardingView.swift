import CentavoCore
import SwiftData
import SwiftUI

/// The first time Al día opens empty: what it does, the currency, the budget, the fixed
/// expenses and the Wallet automation, one short page each. Every page can be skipped.
struct OnboardingView: View {
    /// Called when it is done; `openGuide` asks for the Wallet guide right after.
    let finish: (_ openGuide: Bool) -> Void

    @Environment(\.modelContext) private var context
    @AppStorage(BudgetStore.key) private var storedBudget = ""
    @AppStorage(CurrencyPreference.key) private var storedCurrency = ""
    @State private var page = 0
    @State private var currency = CurrencyPreference.current
    @State private var budgetText = ""
    @State private var fixed: [FixedDraft] = []
    @State private var draftName = ""
    @State private var draftAmount = ""
    @State private var draftDay = 1
    @FocusState private var focused: Field?

    private enum Field { case budget, name, amount }
    private let pages = 5

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                welcome.tag(0)
                currencyPage.tag(1)
                budgetPage.tag(2)
                fixedPage.tag(3)
                walletPage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Bienvenida")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if page < pages - 1 {
                        Button("Omitir") { save(); finish(false) }
                            .font(.ticket(13, relativeTo: .footnote))
                            .accessibilityIdentifier("bienvenida-omitir")
                    }
                }
                // The number pad has no return key and covers the bottom bar.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Siguiente") {
                        focused = nil
                        if page < pages - 1 { withAnimation { page += 1 } }
                    }
                    .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                    .accessibilityIdentifier("teclado-siguiente")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Anterior", systemImage: "chevron.left") { withAnimation { page -= 1 } }
                        .disabled(page == 0)
                    Spacer()
                    Text("\(page + 1) de \(pages)")
                        .font(.ticket(13, relativeTo: .footnote))
                        .tracking(2)
                        .textCase(.uppercase)
                        .fixedSize()
                    Spacer()
                    Button("Siguiente", systemImage: "chevron.right") {
                        focused = nil
                        withAnimation { page += 1 }
                    }
                    .disabled(page == pages - 1)
                    .accessibilityIdentifier("bienvenida-siguiente")
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Pages

    private var welcome: some View {
        pageLayout(title: "Al día", lead: "Te dice cuánto puedes gastar hoy, sin que tengas que anotar nada.") {
            VStack(alignment: .leading, spacing: 14) {
                point("wallet.pass", "Cada compra con Wallet se anota sola: en línea o acercando el teléfono.")
                point("calendar", "Reparte tu presupuesto entre los días que quedan del mes.")
                point("lock", "Todo se queda en tu iPhone. Sin cuenta ni servidor.")
            }
        }
    }

    private var currencyPage: some View {
        pageLayout(title: "Tu moneda", lead: "En la que sumas el mes. Lo demás se muestra aparte.") {
            VStack(spacing: 8) {
                ForEach(CurrencyPreference.offered, id: \.self) { code in
                    Button {
                        currency = code
                    } label: {
                        HStack {
                            Text(CurrencyPreference.name(code)).foregroundStyle(Theme.ink)
                            Spacer()
                            if currency == code {
                                Image(systemName: "checkmark").foregroundStyle(Theme.brass)
                            }
                        }
                        .font(.ticket(15, relativeTo: .body))
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            if currency == code {
                                RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.brass, lineWidth: 1.5)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("moneda-\(code)")
                    .accessibilityAddTraits(currency == code ? .isSelected : [])
                }
            }
        }
    }

    private var budgetPage: some View {
        pageLayout(title: "Tu presupuesto", lead: "¿Cuánto quieres gastar al mes? Con esto te dice cuánto puedes gastar hoy.") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Presupuesto", text: $budgetText, prompt: Text("8000").foregroundStyle(Theme.faint))
                    .font(.ticket(40, weight: .medium, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.ink)
                    .keyboardType(.decimalPad)
                    .focused($focused, equals: .budget)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("bienvenida-presupuesto")
                if let value = AmountParser.parse(budgetText)?.value, value > 0 {
                    Text(BudgetStore.dailyPreview(value, currency: currency))
                        .font(.ticket(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.brass)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: budgetText)
                } else {
                    hint("Puedes dejarlo vacío y fijarlo después en «Más».")
                }
            }
        }
    }

    private var fixedPage: some View {
        pageLayout(title: "Gastos fijos", lead: "Renta, suscripciones, la luz: se anotan solos cada mes.") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(fixed) { item in
                    HStack {
                        Text(item.name).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(item.amount.formatted(.number.precision(.fractionLength(0...2)))) · día \(item.day)")
                            .foregroundStyle(Theme.muted)
                    }
                    .font(.ticket(13, relativeTo: .footnote))
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(spacing: 8) {
                    TextField("Qué es", text: $draftName, prompt: Text("Renta, Netflix…").foregroundStyle(Theme.faint))
                        .textInputAutocapitalization(.words)
                        .focused($focused, equals: .name)
                        .accessibilityIdentifier("bienvenida-fijo-nombre")
                    Divider().overlay(Theme.hairline)
                    TextField("Cuánto", text: $draftAmount, prompt: Text("Monto").foregroundStyle(Theme.faint))
                        .keyboardType(.decimalPad)
                        .focused($focused, equals: .amount)
                        .accessibilityIdentifier("bienvenida-fijo-monto")
                    Divider().overlay(Theme.hairline)
                    Stepper("El día \(draftDay) de cada mes", value: $draftDay, in: 1...31)
                        .foregroundStyle(Theme.ink)
                }
                .font(.ticket(15, relativeTo: .body))
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                Button("Agregar", systemImage: "plus", action: addFixed)
                    .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                    .disabled(draftValue == nil || draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("bienvenida-fijo-agregar")
                hint("También puedes marcar cualquier gasto como fijo después.")
            }
        }
    }

    private var walletPage: some View {
        pageLayout(title: "Conecta Wallet", lead: "Una automatización de Atajos le avisa a Al día de cada compra. Se hace una vez y toma unos minutos.") {
            VStack(spacing: 12) {
                Button {
                    save(); finish(true)
                } label: {
                    Label("Configurar ahora", systemImage: "wallet.pass")
                        .font(.ticket(13, weight: .semibold, relativeTo: .footnote))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.onBrass)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brass)
                .accessibilityIdentifier("bienvenida-configurar")
                Button("Después") { save(); finish(false) }
                    .font(.ticket(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("bienvenida-despues")
            }
        }
    }

    // MARK: Pieces

    private func pageLayout<Content: View>(title: String, lead: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.ticket(28, weight: .semibold, relativeTo: .title))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(lead)
                    .font(.ticket(15, relativeTo: .body))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.brass).frame(width: 22)
            Text(text).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
        .font(.ticket(14, relativeTo: .body))
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.ticket(12, relativeTo: .footnote)).foregroundStyle(Theme.faint)
    }

    // MARK: Saving

    private var draftValue: Decimal? {
        guard let value = AmountParser.parse(draftAmount)?.value, value > 0 else { return nil }
        return value
    }

    private func addFixed() {
        guard let value = draftValue else { return }
        fixed.append(FixedDraft(name: draftName.trimmingCharacters(in: .whitespaces),
                                amount: value, day: draftDay))
        draftName = ""; draftAmount = ""; draftDay = 1
        focused = .name
    }

    /// Whatever was filled in is kept, even when the rest is skipped.
    private func save() {
        storedCurrency = currency
        if let value = AmountParser.parse(budgetText)?.value, value > 0 {
            storedBudget = BudgetStore.stored(value)
        }
        for item in fixed {
            let date = RecurringSchedule.firstDate(day: item.day, now: .now)
            let expense = Expense(amount: item.amount, currencyMarker: currency, merchant: item.name,
                                  date: date, category: MerchantCatalog.category(for: item.name))
            expense.repeatsMonthly = true
            expense.repeatsThrough = date
            context.insert(expense)
        }
        try? context.save()
    }
}

private struct FixedDraft: Identifiable {
    let id = UUID()
    let name: String
    let amount: Decimal
    let day: Int
}
