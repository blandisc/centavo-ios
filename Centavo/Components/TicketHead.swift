import SwiftUI

/// The ticket's head over a perforation, the same on «Hoy» and on «Mi dinero»: at one end the
/// day («JUE 29 DE OCT») and at the other the folio, like the number printed on a ticket
/// («N.º 042», «CORTE N.º 003»), its digits in brass. With an accessibility text size the two
/// stack and wrap instead of being cut («VIE 2… N.º 0…» said nothing).
struct TicketHead: View {
    let title: String
    /// What goes before the digits: «N.º», «Corte N.º».
    var folio = "N.º"
    /// Zero prints no folio.
    let number: Int
    /// What VoiceOver says for the folio: «12 pagos este mes».
    let spoken: String
    var titleIdentifier: String?
    var folioIdentifier: String?

    @Environment(\.dynamicTypeSize) private var typeSize

    /// «jue 29 de oct», as every ticket head writes a day (uppercased by the head itself).
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "es_MX")))
            .replacingOccurrences(of: ".", with: "")
    }

    var body: some View {
        AdaptiveStack(alignment: .firstTextBaseline) {
            Text(title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(titleIdentifier ?? "")
            if !typeSize.isAccessibilitySize { Spacer(minLength: Theme.Space.s) }
            if number > 0 {
                Text("\(folio) \(Text(String(format: "%03d", number)).foregroundStyle(Theme.brass))")
                    .monospacedDigit()
                    .accessibilityLabel(spoken)
                    .accessibilityIdentifier(folioIdentifier ?? "")
            }
        }
        .font(.ticket(.microStrong))
        .tracking(Theme.Tracking.label)
        .textCase(.uppercase)
        .foregroundStyle(Theme.ink)
        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        .padding(.bottom, Theme.Space.s)
        .overlay(alignment: .bottom) { Perforation() }
    }
}

#Preview("Cabecera del ticket") {
    VStack(spacing: Theme.Space.xl) {
        TicketHead(title: TicketHead.day(.now), number: 42, spoken: "42 pagos este mes")
        TicketHead(title: TicketHead.day(.now), folio: "Corte N.º", number: 3, spoken: "3 cortes")
        TicketHead(title: "sep 2026", number: 0, spoken: "")
    }
    .padding(Theme.Space.screen)
    .ticketPreview()
}
