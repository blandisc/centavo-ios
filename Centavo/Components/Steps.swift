import SwiftUI

/// The brass symbol on a raised, hairline-edged tile that heads each step page: the step's
/// best one-word picture. Decorative: VoiceOver reads the title that follows, not the symbol,
/// and with an accessibility text size it is left out so the page stays within reach.
///
///     StepEmblem(systemImage: "wallet.pass")
struct StepEmblem: View {
    let systemImage: String

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tile = Theme.Size.stepEmblem

    var body: some View {
        if typeSize.isAccessibilitySize {
            EmptyView()
        } else {
            Image(systemName: systemImage)
                .font(Theme.Symbol.large)
                .foregroundStyle(Theme.brass)
                .frame(width: tile, height: tile)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.hairline)
                }
                .accessibilityHidden(true)
        }
    }
}

/// The bottom-bar progress of a step flow: one pill per step, the current one longer, like
/// the carousel's dots. The «Paso X de N» caption above the title carries the progress for
/// VoiceOver, so hide the dots with `.accessibilityHidden(true)` when you place it.
///
///     StepDots(current: 2, of: 5)
struct StepDots: View {
    let current: Int
    let of: Int

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            ForEach(0..<of, id: \.self) { index in
                Capsule()
                    .fill(current == index ? Theme.ink : Theme.dimmed)
                    .frame(width: current == index ? Theme.Size.pageDotCurrent : Theme.Size.pageDot,
                           height: Theme.Size.pageDot)
            }
        }
    }
}

#Preview("Paso de una guía") {
    VStack(alignment: .leading, spacing: Theme.Space.xl) {
        StepEmblem(systemImage: "wallet.pass")
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Paso 3 de 8").ticketCaption()
            Text("Conecta el importe")
                .font(.ticket(.pageTitle))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
        }
        StepDots(current: 2, of: 8)
    }
    .padding(Theme.Space.screen)
    .ticketPreview()
}