import SwiftUI

/// The ticket's head over a perforation, the same on «Hoy» and on «Mi dinero»: at one end the
/// day («JUE 29 DE OCT») and at the other the folio, like the number printed on a ticket
/// («N.º 042», «CORTE N.º 003»), its digits in brass. With an accessibility text size the two
/// stay on one line while they fit and otherwise go on two tidy lines, day over folio, instead
/// of being cut («VIE 2… N.º 0…» said nothing) or broken into three.
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

    /// The most the head grows (2026-11-18): past it, on an iPhone SE, «VIE 20 DE NOV» broke
    /// into two lines with the folio on a third. At this size the day always fits on one line,
    /// and the folio goes on its own line under it when both don't fit side by side.
    static let largestType = DynamicTypeSize.accessibility2

    private var titleText: some View {
        Text(title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(titleIdentifier ?? "")
    }

    @ViewBuilder private var folioText: some View {
        if number > 0 {
            Text("\(folio) \(Text(String(format: "%03d", number)).foregroundStyle(Theme.brass))")
                .monospacedDigit()
                .accessibilityLabel(spoken)
                .accessibilityIdentifier(folioIdentifier ?? "")
        }
    }

    /// Day at one end, folio at the other, on one line.
    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            titleText
            Spacer(minLength: Theme.Space.s)
            folioText
        }
        .lineLimit(1)
    }

    /// The day over the folio, each on its own line; they wrap only if even that can't fit.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            titleText
            folioText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var layout: some View {
        if typeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                row
                stacked
            }
            .dynamicTypeSize(...Self.largestType)
        } else {
            row
        }
    }

    var body: some View {
        layout
            .font(.ticket(.microStrong))
            .tracking(Theme.Tracking.label)
            .textCase(.uppercase)
            .foregroundStyle(Theme.ink)
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
