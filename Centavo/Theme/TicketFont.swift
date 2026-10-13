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

    static func font(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) -> Font {
        let name = postScriptName(for: weight)
        guard UIFont(name: name, size: size) != nil else {
            return .system(style, design: .monospaced, weight: weight)
        }
        return .custom(name, size: size, relativeTo: style)
    }
}

extension Font {
    /// The ticket typeface at `size` points on the default Dynamic Type setting.
    static func ticket(_ size: CGFloat, weight: Font.Weight = .regular,
                       relativeTo style: Font.TextStyle = .body) -> Font {
        TicketFont.font(size: size, weight: weight, relativeTo: style)
    }
}

extension View {
    /// Small, spaced, uppercase label: "TOTAL MXN AL 12/10".
    func ticketCaption() -> some View {
        self.font(.ticket(11, relativeTo: .caption))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)
    }
}
