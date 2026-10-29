import CentavoCore
import SwiftUI

/// Under «Te pasaste» this month: the days left are still worth deciding, so the ticket lays
/// out three ways to spend them and where each one closes the month — nothing more, the
/// budget's pace, or the pace so far — and offers to change the budget.
///
/// The first line is the one to aim for and reads in brass; the others are context. The last
/// day of the month there is nothing left to choose, so only the closing line shows.
///
/// It can be closed: then only one quiet line stays, to open it again. Closed is remembered
/// for the rest of that month (a new month that goes over shows it again).
struct OverspendPanel: View {
    let plan: OverspendPlan
    let currency: String
    /// The month it is about, «2026-10»: closing it lasts until the month changes.
    let month: String
    let onAdjust: () -> Void

    @AppStorage("planCerradoMes") private var closedMonth = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isClosed: Bool { closedMonth == month }

    private func setClosed(_ closed: Bool) {
        withAnimation(Theme.Motion.animation(Theme.Motion.toggle, reduceMotion: reduceMotion)) {
            closedMonth = closed ? month : ""
        }
    }

    private func whole(_ amount: Decimal) -> String {
        amount.formatted(currencyStyle(currency).precision(.fractionLength(0)))
    }

    private var daysText: String {
        plan.daysAfterToday == 1 ? "1 día" : "\(plan.daysAfterToday) días"
    }

    var body: some View {
        if isClosed { reopen } else { panel }
    }

    /// The minimal view: one line that opens the plan again.
    private var reopen: some View {
        Button { setClosed(false) } label: {
            HStack(spacing: Theme.Space.xs) {
                Text("Ver cómo cerrar el mes")
                Image(systemName: "chevron.down").accessibilityHidden(true)
            }
            .font(.ticket(.detail))
            .foregroundStyle(Theme.muted)
            .frame(minHeight: Theme.Size.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("abrir-plan")
        .transition(.opacity)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.daysAfterToday > 0 ? "Para cerrar el mes · \(daysText.lowercased()) más"
                                             : "Hoy cierra el mes")
                    .ticketCaption()
                Spacer(minLength: Theme.Space.s)
                Button("Cerrar", systemImage: "xmark") { setClosed(true) }
                    .labelStyle(.iconOnly)
                    .font(.ticket(.detail))
                    .foregroundStyle(Theme.faint)
                    .frame(minWidth: Theme.Size.tapTarget, minHeight: Theme.Size.tapTarget)
                    .contentShape(Rectangle())
                    .padding(.vertical, -Theme.Space.ml)
                    .accessibilityIdentifier("cerrar-plan")
            }
            if plan.daysAfterToday > 0 {
                VStack(spacing: Theme.Space.sm) {
                    path("Sin gastar más", detail: plan.fixedToCome > 0 ? "solo los fijos que faltan" : nil,
                         closes: plan.stop.closesOver, leads: true)
                    Divider().overlay(Theme.hairline)
                    // With fixed expenses eating the whole budget there was nothing a day:
                    // the same as stopping, so it is not said twice.
                    if plan.budgetRate.perDay > 0 {
                        path("\(whole(plan.budgetRate.perDay)) al día", detail: "lo que tocaba por día",
                             closes: plan.budgetRate.closesOver)
                    }
                    if plan.currentRate.perDay > 0 {
                    path("\(whole(plan.currentRate.perDay)) al día", detail: "tu ritmo de este mes",
                         closes: plan.currentRate.closesOver)
                    }
                }
            } else {
                path("Cierras", detail: nil, closes: plan.stop.closesOver, leads: true)
            }
            Button(action: onAdjust) {
                Label("Ajustar presupuesto", systemImage: "slider.horizontal.3")
                    .font(.ticket(.footnoteStrong))
                    .tracking(Theme.Tracking.action)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.brass)
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ajustar-presupuesto")
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ticketPanel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("para-cerrar-el-mes")
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// One way to spend the rest: what it is on the left, where the month closes on the right.
    private func path(_ title: String, detail: String?, closes: Decimal, leads: Bool = false) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                label(title, detail: detail, leads: leads)
                Spacer(minLength: Theme.Space.s)
                closing(closes, leads: leads)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                label(title, detail: detail, leads: leads)
                closing(closes, leads: leads)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func label(_ title: String, detail: String?, leads: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
            Text(title)
                .font(.ticket(leads ? .bodyStrong : .body))
                .foregroundStyle(leads ? Theme.brass : Theme.ink)
            if let detail {
                Text(detail)
                    .font(.ticket(.detail))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func closing(_ amount: Decimal, leads: Bool) -> some View {
        (Text("cierras ").foregroundStyle(Theme.muted)
            + Text(whole(amount)).foregroundStyle(leads ? Theme.ink : Theme.danger)
            + Text(" arriba").foregroundStyle(Theme.muted))
            .font(.ticket(.callout))
            .monospacedDigit()
    }
}

#Preview("Te pasaste") {
    let calendar = Calendar.current
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29))!
    return OverspendPanel(plan: OverspendPlan(pace: BudgetPace(budget: 2_000, spent: 2_366, on: date)!)!,
                          currency: "MXN", month: "2026-10", onAdjust: {})
        .padding(Theme.Space.screen)
        .ticketPreview()
}
