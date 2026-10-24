import AppIntents
import WidgetKit

/// What the medium «Hoy puedes gastar» widget shows, chosen in «Editar widget».
enum HoyMediumLayout: String, AppEnum {
    case pace
    case whereItGoes

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mostrar"
    static let caseDisplayRepresentations: [HoyMediumLayout: DisplayRepresentation] = [
        .pace: "Ritmo del presupuesto",
        .whereItGoes: "En qué se va",
    ]
}

/// «Editar widget» of «Hoy puedes gastar»: only the medium one has something to choose.
struct HoyConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Hoy puedes gastar"
    static let description = IntentDescription("Elige qué muestra el widget mediano.")

    @Parameter(title: "Mostrar", default: .pace)
    var show: HoyMediumLayout

    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemMedium) {
            Summary { \.$show }
        } otherwise: {
            Summary()
        }
    }
}
