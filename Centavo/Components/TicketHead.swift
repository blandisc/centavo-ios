import SwiftUI

/// The ticket's head over a perforation, the same on «Hoy» and on «Mi dinero»: at one end the
/// day («JUE 29 DE OCT») and at the other the folio, like the number printed on a ticket
/// («N.º 042», «CORTE N.º 003»), its digits in brass. With an accessibility text size the two
/// stack and wrap instead of being cut («VIE 2… N.º 0…» said nothing).
struct TicketHead: View {
    let title: String
    /// What goes before the digits: «N.º», «Corte N.º».
    var folio: String
    /// Zero prints no folio.
    let number: Int
    /// What VoiceOver says for the folio: «12 pagos este mes».
    let spoken: String
    var titleIdentifier: String?
    var folioIdentifier: String?

    @Environment(\.dynamicTypeSize) private var typeSize

    /// `title` is a day or a month made at run time (`day(_:)`); `spoken`, a literal, is looked up
    /// in the catalog. With no `folio`, «N.º» in the person's language.
    init(title: String, folio: String? = nil, number: Int, spoken: LocalizedStringResource,
         titleIdentifier: String? = nil, folioIdentifier: String? = nil) {
        self.init(title: title, folio: folio, number: number, spoken: String(localized: spoken),
                  titleIdentifier: titleIdentifier, folioIdentifier: folioIdentifier)
    }

    /// What VoiceOver says for the folio, made at run time.
    @_disfavoredOverload
    init<S: StringProtocol>(title: String, folio: String? = nil, number: Int, spoken: S,
                            titleIdentifier: String? = nil, folioIdentifier: String? = nil) {
        self.title = title
        self.folio = folio ?? String(localized: "N.º", comment: "Before a ticket's number, like «N.º 042»")
        self.number = number
        self.spoken = String(spoken)
        self.titleIdentifier = titleIdentifier
        self.folioIdentifier = folioIdentifier
    }

    /// «jue 29 de oct», as every ticket head writes a day (uppercased by the head itself), in
    /// the person's language («thu, oct 29» in English).
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale.current))
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
