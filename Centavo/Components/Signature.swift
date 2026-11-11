import SwiftUI

/// The signature in a navigation bar (2026-10-29): lowercase, bigger than a sheet's title, with
/// a brass full stop. «al día.» on «Hoy», «mi dinero.» on its tab.
///
/// The bar doesn't grow with the type, so the signature stops growing where the bar's own
/// buttons do: with accessibility sizes it was cut to «al d…».
struct Signature: View {
    let words: String
    let spoken: String

    init(_ words: String, spoken: String) {
        self.words = words
        self.spoken = spoken
    }

    var body: some View {
        Text("\(words)\(Text(".").foregroundStyle(Theme.brass))")
            .font(.ticket(.subheading))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(Theme.MinimumScale.text)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityLabel(spoken)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(spacing: Theme.Space.xl) {
        Signature("al día", spoken: "Al día")
        Signature("mi dinero", spoken: "Mi dinero")
    }
    .ticketPreview()
}
