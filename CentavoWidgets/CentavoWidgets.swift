import CentavoCore
import SwiftUI
import WidgetKit

@main
struct CentavoWidgets: WidgetBundle {
    init() { TicketFont.register() }

    var body: some Widget {
        HoyWidget()
        HoyBloqueoWidget()
    }
}

/// «Hoy puedes gastar»: pequeño (propuesta A) y mediano, que en «Editar widget» muestra el ritmo
/// del presupuesto (propuesta A, con «+») o en qué se va (propuesta B). Mismo `kind` que antes,
/// así los widgets ya puestos se quedan.
struct HoyWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Hoy", intent: HoyConfiguration.self, provider: HoyProvider()) { entry in
            Group {
                if entry.show == .whereItGoes {
                    HoyAdaptiveView(entry: entry)
                } else {
                    HoyView(entry: entry)
                }
            }
            .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("Hoy puedes gastar")
        .description("Cuánto puedes gastar hoy. El mediano muestra la barra del mes o en qué se va: mantenlo presionado › Editar widget.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// «En qué se va» only fits the medium; the small one stays the same.
private struct HoyAdaptiveView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemMedium { WhereItGoesView(entry: entry) } else { HoyView(entry: entry) }
    }
}

/// Pantalla bloqueada: el anillo de hoy, el rectangular de la propuesta A y la línea de la fecha.
struct HoyBloqueoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoyBloqueo", provider: DayProvider()) { entry in
            LockView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Hoy puedes gastar")
        .description("Lo que llevas hoy contra lo que puedes gastar hoy.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
