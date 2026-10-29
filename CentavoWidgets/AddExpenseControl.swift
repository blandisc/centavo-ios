import AppIntents
import SwiftUI
import WidgetKit

/// «Anotar gasto» in the Control Center, on the lock screen (instead of the flashlight or the
/// camera) and on the Action button: one tap opens Al día on the expense sheet
/// (`OpenAddExpenseIntent`, the same as the small widget's «+»).
struct AddExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.blandisc.centavo.anotar") {
            ControlWidgetButton(action: OpenAddExpenseIntent()) {
                Label("Anotar gasto", systemImage: "plus.circle")
            }
        }
        .displayName("Anotar gasto")
        .description("Abre Al día para anotar un gasto a mano.")
    }
}
