import CentavoCore
import SwiftUI

/// Under the month bar, when this month went past its budget: one line, «Para cerrar el mes
/// · sin gastar más: $366 de más ›». Tapping it brings up `OverspendSheet` with the three ways
/// to spend the days left. Option A of the owner's review (2026-10-29): the figure, its bar,
/// then the plan; nothing unfolds between them.
struct OverspendRow: View {
    let plan: OverspendPlan
    let currency: String
    /// Today, to name the days left («30 y 31 de oct»).
    let now: Date

    @State private var showing = false

    private func whole(_ amount: Decimal) -> String {
        amount.formatted(currencyStyle(currency).precision(.fractionLength(0)))
    }

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    Text("Para cerrar el mes")
                        .font(.ticket(.bodyStrong))
                        .foregroundStyle(Theme.brass)
                    Text(plan.daysAfterToday > 0
                         ? "Sin gastar más: \(whole(plan.stop.closesOver)) de más"
                         : "Hoy cierra con \(whole(plan.stop.closesOver)) de más")
                        .font(.ticket(.detail))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: Theme.Space.s)
                Image(systemName: "chevron.right")
                    .font(.ticket(.detail))
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
            .ticketPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Muestra cómo cerrarías el mes según lo que gastes")
        .accessibilityIdentifier("para-cerrar-el-mes")
        .sheet(isPresented: $showing) {
            OverspendSheet(plan: plan, currency: currency, now: now)
        }
    }
}

/// «Para cerrar el mes»: how the month closes depending on what the days left spend. As tall
/// as what it says, so there is no empty half sheet.
///
/// How each way is worked out (`OverspendPlan`, with the days after today):
/// - Sin gastar más: what is over now, plus the fixed expenses still to come this month.
/// - Lo que te tocaba: (budget − fixed of the month) ÷ days of the month, each day left.
/// - Tu ritmo: what this month spent outside fixed expenses ÷ days gone, each day left.
struct OverspendSheet: View {
    let plan: OverspendPlan
    let currency: String
    let now: Date

    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 420 // ds-allow: altura inicial antes de medir el contenido

    private func whole(_ amount: Decimal) -> String {
        amount.formatted(currencyStyle(currency).precision(.fractionLength(0)))
    }

    /// «30 y 31 de oct», «31 de oct», or nothing on the last day.
    private var daysLeft: String {
        let calendar = Calendar.current
        guard plan.daysAfterToday > 0 else { return "" }
        let days = (1...plan.daysAfterToday).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
        guard let last = days.last else { return "" }
        let month = last.formatted(.dateTime.month(.abbreviated).locale(ExpenseListView.mexico))
        let numbers = days.map { String(calendar.component(.day, from: $0)) }
        let joined = numbers.count > 1
            ? numbers.dropLast().joined(separator: ", ") + " y " + (numbers.last ?? "")
            : numbers[0]
        return "\(joined) de \(month)"
    }

    private struct Path: Identifiable {
        let title: String
        let detail: String
        let closes: Decimal
        let leads: Bool
        var id: String { title }
    }

    private var paths: [Path] {
        var list = [Path(title: "Sin gastar más",
                         detail: plan.fixedToCome > 0 ? "solo llegan tus fijos (\(whole(plan.fixedToCome)))" : "ni un peso más",
                         closes: plan.stop.closesOver, leads: true)]
        if plan.budgetRate.perDay > 0 {
            list.append(Path(title: "\(whole(plan.budgetRate.perDay)) al día", detail: "lo que te tocaba por día",
                             closes: plan.budgetRate.closesOver, leads: false))
        }
        if plan.currentRate.perDay > 0 {
            list.append(Path(title: "\(whole(plan.currentRate.perDay)) al día", detail: "tu ritmo de este mes",
                             closes: plan.currentRate.closesOver, leads: false))
        }
        return list
    }

    private var nextMonth: String {
        let next = Calendar.current.date(byAdding: .month, value: 1, to: now) ?? now
        return next.formatted(.dateTime.month(.wide).locale(ExpenseListView.mexico))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack {
                Text("Para cerrar el mes")
                    .font(.ticket(.footnoteStrong))
                    .tracking(Theme.Tracking.title)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Listo") { dismiss() }
                    .font(.ticket(.footnoteStrong))
                    .frame(minHeight: Theme.Size.tapTarget)
                    .accessibilityIdentifier("hoja-listo")
            }
            Text(plan.daysAfterToday > 0
                 ? "Te pasaste \(whole(plan.over)). Quedan \(plan.daysAfterToday == 1 ? "1 día" : "\(plan.daysAfterToday) días"): \(daysLeft). Así cerrarías según lo que gastes:"
                 : "Te pasaste \(whole(plan.over)). Hoy es el último día del mes.")
                .font(.ticket(.callout))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if plan.daysAfterToday > 0 {
                let widest = paths.map(\.closes).max() ?? 1
                VStack(spacing: Theme.Space.m) {
                    ForEach(paths) { row($0, widest: widest) }
                }
                .padding(Theme.Space.l)
                .ticketPanel()
            }
            Text("El 1 de \(nextMonth) empiezas de cero: lo de más no pasa al mes siguiente.")
                .font(.ticket(.detail))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, Theme.Space.xxl)
        .padding(.bottom, Theme.Space.l)
        .fixedSize(horizontal: false, vertical: true)
        // As tall as what it holds, at any text size: no empty half sheet.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationBackground(Theme.background)
        .presentationCornerRadius(Theme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    /// One way: what it is on the left, how far over it closes on the right, and a bar as
    /// long as that, so the worst one reads at a glance.
    private func row(_ path: Path, widest: Decimal) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
                    Text(path.title)
                        .font(.ticket(path.leads ? .bodyStrong : .body))
                        .foregroundStyle(path.leads ? Theme.brass : Theme.ink)
                    Text(path.detail)
                        .font(.ticket(.detail))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: Theme.Space.xxxs) {
                    Text(whole(path.closes))
                        .font(.ticket(.bodyStrong))
                        .foregroundStyle(path.leads ? Theme.ink : Theme.danger)
                        .monospacedDigit()
                    Text("de más")
                        .font(.ticket(.detail))
                        .foregroundStyle(Theme.muted)
                }
            }
            GeometryReader { geometry in
                Capsule()
                    .fill(Theme.danger.opacity(path.leads ? Theme.Opacity.unselected : Theme.Opacity.visible))
                    .frame(width: geometry.size.width * share(path.closes, of: widest))
            }
            .frame(height: Theme.Size.legendDot)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(path.title), \(path.detail): cierras \(whole(path.closes)) arriba")
    }

    private func share(_ amount: Decimal, of widest: Decimal) -> CGFloat {
        guard widest > 0 else { return 0 }
        return CGFloat(NSDecimalNumber(decimal: amount / widest).doubleValue)
    }
}

#Preview("Te pasaste") {
    let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 29))!
    return OverspendRow(plan: OverspendPlan(pace: BudgetPace(budget: 2_000, spent: 2_366, on: date)!)!,
                        currency: "MXN", now: date)
        .padding(Theme.Space.screen)
        .ticketPreview()
}
