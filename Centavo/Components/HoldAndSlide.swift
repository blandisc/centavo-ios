import SwiftUI
import UIKit

/// Hold a moment, then slide (2026-11-02): UIKit's long press, not SwiftUI's. SwiftUI's long
/// press followed by a drag took every touch that started on it, so a swipe up from the month's
/// code never scrolled the screen. This one lets the scroll and the carousel have the touch until
/// it holds; once it holds, the slide is its own.
///
/// - `began`, `moved`: where the finger is, in the SwiftUI view's own space.
/// - `ended`: where it let go, or `nil` when the touch was cancelled.
struct HoldAndSlide: UIGestureRecognizerRepresentable {
    var hold: Double
    var slop: CGFloat
    var began: (CGPoint) -> Void
    var moved: (CGPoint) -> Void
    var ended: (CGPoint?) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = hold
        press.allowableMovement = slop
        press.delegate = context.coordinator
        return press
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.minimumPressDuration = hold
        recognizer.allowableMovement = slop
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        // In the SwiftUI view's own space: the recognizer's view may be a larger host.
        let location = context.converter.localLocation
        switch recognizer.state {
        case .began: began(location)
        case .changed: moved(location)
        case .ended: ended(location)
        case .cancelled, .failed: ended(nil)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Until it holds, everything else may have the touch too (the scroll, the carousel, a
        /// tap); once it holds, the slide reads days and nothing else moves.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            recognizer.state == .possible
        }
    }
}
