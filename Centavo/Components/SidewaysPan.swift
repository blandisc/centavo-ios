import SwiftUI
import UIKit

/// A pan that begins only when the finger moves more sideways than up or down; anything else
/// is left to the scroll view. UIKit's, not a SwiftUI `DragGesture`: inside the screen's vertical
/// scroll a drag gesture was cancelled as soon as the thumb went a little diagonal.
///
/// - `ratio`: how much more sideways than vertical the finger must go to begin.
/// - `alongside`: also runs with the other gestures under it (a carousel's own scroll, a tile's
///   tap), instead of taking the touch from them.
struct SidewaysPan: UIGestureRecognizerRepresentable {
    var ratio: CGFloat = Theme.Size.sidewaysRatio
    var alongside = false
    var changed: (CGFloat) -> Void = { _ in }
    let ended: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(ratio: ratio, alongside: alongside)
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dx = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed: changed(dx)
        case .ended, .cancelled, .failed: ended(dx, recognizer.velocity(in: recognizer.view).x)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let ratio: CGFloat
        let alongside: Bool

        init(ratio: CGFloat, alongside: Bool) {
            self.ratio = ratio
            self.alongside = alongside
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * ratio
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            alongside
        }
    }
}
