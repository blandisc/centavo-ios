import CentavoCore
import SwiftUI

/// How often a fixed expense comes back: every N weeks, every quincena (15th and last day) or
/// every N months. The day is the first charge's own.
struct RepeatRulePicker: View {
    @Binding var rule: RepeatRule

    private var kind: Binding<RepeatRule.Kind> {
        Binding(get: { rule.kind }, set: { rule = RepeatRule(kind: $0, count: 1) })
    }

    private var count: Binding<Int> {
        Binding(get: { rule.count }, set: { rule = RepeatRule(kind: rule.kind, count: $0) })
    }

    private var countText: String {
        switch (rule.kind, rule.count) {
        case (.weeks, 1): "Cada semana"
        case (.weeks, let n): "Cada \(n) semanas"
        case (.months, 1): "Cada mes"
        case (.months, let n): "Cada \(n) meses"
        case (.semimonthly, _): "Cada quincena"
        }
    }

    var body: some View {
        Picker("Frecuencia", selection: kind) {
            Text("Semana").tag(RepeatRule.Kind.weeks)
            Text("Quincena").tag(RepeatRule.Kind.semimonthly)
            Text("Mes").tag(RepeatRule.Kind.months)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("frecuencia")
        if rule.kind != .semimonthly {
            Stepper(value: count, in: 1...12) {
                SectionLabel(countText)
            }
            .accessibilityIdentifier("cada-cuanto")
        }
    }
}

/// The sentences that say how a fixed expense works, the same in every sheet.
enum FixedWording {
    /// «Cada lunes: se anota solo ese día, y lo que falta del mes se aparta de «Hoy puedes gastar».»
    static func howItRepeats(_ rule: RepeatRule, from date: Date) -> String {
        let when = rule.describe(anchor: date)
        return when.prefix(1).uppercased() + when.dropFirst()
            + ": se anota solo ese día, y lo que falta del mes se aparta de «Hoy puedes gastar»."
    }
}
