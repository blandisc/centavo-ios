import CentavoCore
import SwiftUI

/// Under «Te pasaste» this month: the days left are still worth deciding, so the ticket lays
/// out three ways to spend them and where each one closes the month — nothing more, the
/// budget's pace, or the pace so far — and offers to change the budget.
///
/// The first line is the one to aim for and reads in brass; the others are context. The last
/// day of the month there is nothing left to choose, so only the closing line shows.
///
/// It folds to its title and one line (the way to aim for), and unfolds in place. Folded is
/// remembered for the rest of that month (a new month that goes over shows it open again).
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
        withAnimation(Theme.Motion.animation(Theme.Motion.fold, reduceMotion: reduceMotion)) {
            closedMonth = closed ? month : ""
        }
    }

    private func whole(_ amount: Decimal) -> String {
        amount.formatted(currencyStyle(currency).precision(.fractionLength(0)))
    }

    private var daysText: String {
        plan.daysAfterToday == 1 ? "1 día" : "\(plan.daysAfterToday) días"
    }

    private var title: String {
        plan.daysAfterToday > 0 ? "Para cerrar el mes · \(daysText) más" : "Hoy cierra el mes"
    }

    /// One panel that folds and unfolds in place. The title and the first way (stop spending)
    /// never move: folding only hides what is under them, so nothing swaps or blinks, and the
    /// panel's height eases with the rest of the screen.
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Button { setClosed(!isClosed) } label: {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(title).ticketCaption()
                    Spacer(minLength: Theme.Space.s)
                    Image(systemName: "chevron.down")
                        .font(.ticket(.detail))
                        .foregroundStyle(Theme.faint)
                        .rotationEffect(.degrees(isClosed ? 0 : 180))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Theme.Size.compactRow)
                .contentShape(Rectangle())
            }
            // No dimming on touch: the title is the panel's own, not a button that flashes.
            .buttonStyle(SteadyButtonStyle())
            .accessibilityValue(isClosed ? "Cerrado" : "Abierto")
            .accessibilityHint(isClosed ? "Muestra las otras formas de cerrar el mes" : "Deja solo la primera")
            .accessibilityIdentifier("plegar-plan")

            leadPath

            if !isClosed {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    otherPaths
                    adjustButton
                }
                .transition(.unfold)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ticketPanel()
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("para-cerrar-el-mes")
    }

    /// The way to aim for: stop spending (or, the last day, how it closes).
    private var leadPath: some View {
        path(plan.daysAfterToday > 0 ? "Sin gastar más" : "Cierras",
             // Why it is more than «de más» today: the fixed expenses still arrive.
             detail: plan.daysAfterToday > 0 && plan.fixedToCome > 0
                 ? "+ \(whole(plan.fixedToCome)) de fijos que faltan" : nil,
             closes: plan.stop.closesOver, leads: true)
    }

    @ViewBuilder private var otherPaths: some View {
        if plan.daysAfterToday > 0 {
            VStack(spacing: Theme.Space.sm) {
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
        }
    }

    private var adjustButton: some View {
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

    /// One way to spend the rest: what it is on the left, how far over the month closes on the
    /// right («$866 / de más»), the same shape on every line.
    private func path(_ title: String, detail: String?, closes: Decimal, leads: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
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
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: Theme.Space.xxxs) {
                Text(whole(closes))
                    .font(.ticket(.bodyStrong))
                    .foregroundStyle(leads ? Theme.ink : Theme.danger)
                    .monospacedDigit()
                Text("de más")
                    .font(.ticket(.detail))
                    .foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)\(detail.map { ", \($0)" } ?? ""): cierras \(whole(closes)) arriba")
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

/// A button that does not dim when touched: for a title that opens its own panel.
private struct SteadyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

