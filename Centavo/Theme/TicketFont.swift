import CoreText
import SwiftUI
import UIKit

/// IBM Plex Mono (SIL OFL, bundled in Resources/Fonts), the receipt typewriter.
///
/// Every size is tied to a text style, so Dynamic Type still scales it. If the font
/// is missing, the system monospaced face stands in and nothing else changes.
enum TicketFont {
    /// Called once at launch. The files are registered by hand so the Info.plist stays generated.
    static func register() {
        let urls = ["IBMPlexMono-Regular", "IBMPlexMono-Medium", "IBMPlexMono-SemiBold"]
            .compactMap { Bundle.main.url(forResource: $0, withExtension: "ttf") }
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    private static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .semibold, .bold, .heavy, .black: "IBMPlexMono-SemiBold"
        case .medium: "IBMPlexMono-Medium"
        default: "IBMPlexMono-Regular"
        }
    }

    /// The faces that loaded, looked up once: `.ticket()` runs for every text on every redraw.
    /// Read after `register()` (the first text is drawn after launch), so it sees the fonts.
    private static let available: Set<String> = Set(
        ["IBMPlexMono-Regular", "IBMPlexMono-Medium", "IBMPlexMono-SemiBold"]
            .filter { UIFont(name: $0, size: UIFont.systemFontSize) != nil }
    )

    static func font(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) -> Font {
        let name = postScriptName(for: weight)
        guard available.contains(name) else {
            return .system(style, design: .monospaced, weight: weight)
        }
        return .custom(name, size: size, relativeTo: style)
    }
}

/// Every text role of the app: one name, one size, one weight, one Dynamic Type style.
/// Screens write `.font(.ticket(.body))`, never a size. Sizes are points at the default
/// text size; each grows with the person's setting through its `textStyle`.
/// Letter spacing goes with the role through `Theme.Tracking` (see docs/DESIGN_SYSTEM.md).
enum TicketStyle: CaseIterable {
    /// 54 medium. The one figure the main screen is about («Hoy puedes gastar»). Tracking `.hero`.
    case hero
    /// 44 medium. An amount being typed (`AmountInputField`). Tracking `.amount`.
    case amountInput
    /// 40 medium. An amount typed inside a card, where 44 leaves no room.
    case amountInputCompact
    /// 32 semibold. A figure that heads a sheet (the amount in «¿Borrar este gasto?»).
    case display
    /// 28 semibold. A page title outside a navigation bar (onboarding).
    case pageTitle
    /// 22 medium. A message's title (the store error).
    case heading
    /// 22 regular. A figure inside a card (the budget page). Tracking `.figure`.
    case figure
    /// 20 semibold. A step's title in the guide.
    case subheading
    /// 17 regular. Text being typed in a field. Tracking `.detail`.
    case field
    /// 17 medium. A row's figure next to its name.
    case headline
    /// 15 regular. Body text and plain rows.
    case body
    /// 15 medium. A row's name (a merchant, a fixed expense).
    case bodyMedium
    /// 15 semibold. A strong line: an empty state's title, a destructive button.
    case bodyStrong
    /// 14 regular. A paragraph that explains (empty states, errors).
    case callout
    /// 14 semibold. A capsule button's title («Guardar»).
    case button
    /// 13 regular. Secondary lines, toolbar buttons, previews of a value.
    case footnote
    /// 13 semibold. Bar titles and uppercase actions (`PrimaryButtonLabel`). Tracking `.action`.
    case footnoteStrong
    /// 12 regular. Notes under a field, details, summaries.
    case detail
    /// 12 semibold. Section labels and compact buttons (`SectionLabel`). Tracking `.label`.
    case label
    /// 12 regular (11 before 2026-10-29: nothing that carries information goes under 12). Captions (`ticketCaption()`). Tracking `.caption`.
    case caption
    /// 12 semibold. A caption that heads the hero figure.
    case captionStrong
    /// 12 regular. Hints (`HintText`) and row details. Tracking `.detail`.
    case hint
    /// 12 regular (10 before 2026-10-29). Chart axes, weekday letters, a day's total.
    case micro
    /// 12 semibold (10 before 2026-10-29). A day's name in the list.
    case microStrong

    var size: CGFloat {
        switch self {
        case .hero: 54
        case .amountInput: 44
        case .amountInputCompact: 40
        case .display: 32
        case .pageTitle: 28
        case .heading, .figure: 22
        case .subheading: 20
        case .field, .headline: 17
        case .body, .bodyMedium, .bodyStrong: 15
        case .callout, .button: 14
        case .footnote, .footnoteStrong: 13
        case .detail, .label: 12
        case .caption, .captionStrong, .hint: 12
        case .micro, .microStrong: 12
        }
    }

    var weight: Font.Weight {
        switch self {
        case .hero, .amountInput, .amountInputCompact, .heading, .headline, .bodyMedium: .medium
        case .display, .pageTitle, .subheading, .bodyStrong, .button, .footnoteStrong, .label,
             .captionStrong, .microStrong: .semibold
        default: .regular
        }
    }

    /// The Dynamic Type style it grows with.
    var textStyle: Font.TextStyle {
        switch self {
        case .hero, .amountInput, .amountInputCompact, .display: .largeTitle
        case .pageTitle: .title
        case .heading, .figure: .title2
        case .subheading: .title3
        case .headline: .headline
        case .field, .body, .bodyMedium, .bodyStrong, .button: .body
        case .callout: .callout
        case .footnote, .footnoteStrong, .detail, .label: .footnote
        case .caption, .captionStrong: .caption
        case .hint, .micro, .microStrong: .caption2
        }
    }
}

extension Font {
    /// The ticket typeface in one of its roles: `.font(.ticket(.body))`.
    static func ticket(_ style: TicketStyle) -> Font {
        TicketFont.font(size: style.size, weight: style.weight, relativeTo: style.textStyle)
    }

    /// The ticket typeface at `size` points. Only inside `Centavo/Theme/` and for drawings
    /// measured against something else (the guide's pictures of Shortcuts, a chart's labels
    /// sized by `@ScaledMetric`): screens use `ticket(_: TicketStyle)`. The lint enforces it.
    static func ticket(_ size: CGFloat, weight: Font.Weight = .regular,
                       relativeTo style: Font.TextStyle = .body) -> Font {
        TicketFont.font(size: size, weight: weight, relativeTo: style)
    }
}

extension View {
    /// Small, spaced, uppercase label: "TOTAL MXN AL 12/10".
    /// `strong`: the hero's caption over the big figure («HOY PUEDES GASTAR», «TOTAL MXN»).
    func ticketCaption(strong: Bool = false) -> some View {
        self.font(.ticket(strong ? .captionStrong : .caption))
            .tracking(Theme.Tracking.caption)
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)
    }

    /// The small key over a figure inside a ticket («LLEVAS», «NOTA», «POR VENIR»): one step
    /// quieter than a section's caption, so the figure under it leads.
    func ticketKey(_ color: Color = Theme.muted) -> some View {
        self.font(.ticket(.micro))
            .tracking(Theme.Tracking.label)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
