import CentavoCore
import SwiftUI
import WidgetKit

@main
struct CentavoWidgets: WidgetBundle {
    init() { TicketFont.register() }

    var body: some Widget {
        HoyWidget()
        EnQueSeVaWidget()
        HoyBloqueoWidget()
    }
}

/// «Hoy puedes gastar» y la barra del mes: pequeño (propuesta A) y mediano (propuesta A, con «+»).
struct HoyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Hoy", provider: DayProvider()) { entry in
            HoyView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("Hoy puedes gastar")
        .description("Cuánto puedes gastar hoy, cómo vas y la barra del mes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// «Hoy puedes gastar» con «En qué se va» al lado (mediano, propuesta B).
struct EnQueSeVaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EnQueSeVa", provider: DayProvider()) { entry in
            WhereItGoesView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("Hoy y en qué se va")
        .description("Cuánto puedes gastar hoy y tus tres categorías más grandes.")
        .supportedFamilies([.systemMedium])
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
