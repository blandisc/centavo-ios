import CentavoCore
import SwiftUI
import WidgetKit

/// The lock screen. iOS paints it in one tone, so there is no brass and no red: going past
/// is said with words and a «−», and the ring and the bar say the rest with their shape.
struct LockView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    private var state: DayState { DayState(entry) }
    private var money: Money { Money(entry.snapshot) }
    private var ink: Ink { Ink(mode: .vibrant) }

    /// «$190», or «−$430» once past it.
    private var signed: String {
        (state.isBad ? "−" : "") + money.whole(state.figure)
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: rectangular
        }
    }

    // MARK: Circular

    /// What today spent against what today could spend: the ring fills as the day spends.
    private var todayUsed: Double {
        guard let pace = state.pace else { return 0 }
        if pace.isOverToday || pace.isOverBudget { return 1 }
        guard pace.todayShare > 0 else { return 1 }
        return min(max(NSDecimalNumber(decimal: pace.variableToday / pace.todayShare).doubleValue, 0), 1)
    }

    private var circular: some View {
        Gauge(value: todayUsed) {
            Text("Hoy")
        } currentValueLabel: {
            VStack(spacing: Theme.Space.none) {
                Text(state.pace == nil ? money.whole(state.figure) : signed)
                    .font(.widget(.ringFigure))
                    .lineLimit(1)
                    .minimumScaleFactor(Theme.MinimumScale.ringFigure)
                    .widgetAccentable()
                Text(state.pace == nil ? "mes" : "hoy")
                    .font(.widget(.captionTiny))
                    .textCase(.uppercase)
                    .tracking(Theme.Tracking.compactLabel)
                    .opacity(Theme.Opacity.widgetSecondary)
            }
            .padding(.horizontal, Theme.Space.xxxs)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetURL(state.pace == nil ? .setBudget : nil)
        .accessibilityLabel(spoken)
    }

    // MARK: Rectangular

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: Theme.Space.widgetHair) {
            Caption(text: state.caption, color: ink.lockCaption, style: .captionSmall)
            Text(state.pace == nil ? money.whole(state.figure) : signed)
                .font(.widget(.lockFigure))
                .tracking(Theme.Tracking.figure)
                .lineLimit(1)
                .minimumScaleFactor(Theme.MinimumScale.lockFigure)
                .widgetAccentable()
            if let pace = state.pace {
                MonthStrip(pace: pace, ink: ink, height: Theme.Size.widgetStripThin)
            } else if case .noBudget(_, let today) = state {
                Caption(text: "Sin presupuesto · hoy \(money.whole(today))", color: ink.lockCaption, style: .captionTiny)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(state.pace == nil ? .setBudget : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: Inline

    private var inline: some View {
        Group {
            switch state {
            case .noBudget(let spent, _): Text("Al día · llevas \(money.whole(spent))")
            case .overBudget: Text("Al día · te pasaste \(money.whole(state.figure))")
            case .overToday, .normal: Text("Al día \(signed) hoy")
            }
        }
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        switch state {
        case .noBudget(let spent, let today): "Llevas \(money.whole(spent)) este mes, hoy \(money.whole(today))"
        case .overBudget: "Te pasaste del presupuesto por \(money.whole(state.figure))"
        case .overToday: "Hoy te pasaste por \(money.whole(state.figure))"
        case .normal: "Hoy puedes gastar \(money.whole(state.figure))"
        }
    }
}
