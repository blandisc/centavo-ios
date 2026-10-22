import SwiftUI
import UIKit

/// Swipe a row left to show «Borrar», as in a system list; swipe it all the way to ask right
/// away. The main screen is not a `List` (a list can't ease a row's height, and the carousel's
/// height has to ease: see docs/DECISIONS.md), so this is the list's swipe, done by hand.
private struct SwipeToDelete: ViewModifier {
    let id: AnyHashable
    /// The one row that is open on the screen; opening another, or scrolling, closes it.
    @Binding var openRow: AnyHashable?
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 0
    @ScaledMetric(relativeTo: .footnote) private var buttonWidth: CGFloat = 84
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOpen: Bool { openRow == id }
    private var settle: Animation? { reduceMotion ? nil : .smooth(duration: 0.3) }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            // While open, a tap on the row closes it instead of opening the expense.
            .overlay {
                if isOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .offset(x: offset)
                        .onTapGesture { close() }
                        .accessibilityHidden(true)
                }
            }
            .background(alignment: .trailing) {
                // Only there while the row is pulled: hidden ones on every row read as many
                // «Borrar» buttons to VoiceOver and to the tests.
                if offset < 0 {
                    Button(role: .destructive) {
                        close()
                        onDelete()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Borrar")
                                .font(.ticket(11, weight: .semibold, relativeTo: .caption))
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .frame(width: -offset)
                    .background(Theme.danger)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("deslizar-borrar")
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // UIKit's pan, not a SwiftUI DragGesture: a drag gesture on every row competed with
            // the scroll and made a fast scroll stick (owner's iPhone). This one only starts
            // when the finger goes sideways, so scrolling up and down never meets it.
            .gesture(SidewaysPan(changed: changed, ended: ended))
            .onChange(of: openRow) { _, row in
                if row != id, offset != 0 { withAnimation(settle) { offset = 0 } }
            }
            .accessibilityAction(named: "Borrar", onDelete)
    }

    private func changed(_ dx: CGFloat) {
        if openRow != id { openRow = id }
        let start = isOpen && offset <= -buttonWidth / 2 ? -buttonWidth : 0
        let x = start + dx
        // Rightward past closed, it resists instead of moving away.
        offset = x > 0 ? x * 0.15 : x
    }

    private func ended(_ dx: CGFloat, _ velocity: CGFloat) {
        // Where a flick would carry the row, a fifth of a second on.
        let reach = -(offset + velocity * 0.2)
        if width > 0, -offset > width * 0.55 || reach > width * 0.8 {
            // All the way: the row slides off and the confirmation comes up.
            withAnimation(settle) { offset = -width }
            onDelete()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                close()
            }
        } else if reach > buttonWidth / 2 {
            withAnimation(settle) { offset = -buttonWidth }
            openRow = id
        } else {
            close()
        }
    }

    private func close() {
        withAnimation(settle) { offset = 0 }
        if openRow == id { openRow = nil }
    }
}

extension View {
    /// Swipe left to delete (see `SwipeToDelete`); `onDelete` asks before deleting.
    func swipeToDelete(id: AnyHashable, openRow: Binding<AnyHashable?>,
                       onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(id: id, openRow: openRow, onDelete: onDelete))
    }
}

/// A pan that begins only when the finger moves more sideways than up or down; anything else
/// is left to the scroll view.
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    let ended: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dx = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed: changed(dx)
        case .ended, .cancelled, .failed: ended(dx, recognizer.velocity(in: recognizer.view).x)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.3
        }
    }
}
