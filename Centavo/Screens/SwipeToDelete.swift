import SwiftUI

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
    /// Whether the drag going on is sideways (a swipe) or up and down (the list scrolling).
    @State private var sideways: Bool?
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
            .simultaneousGesture(swipe)
            .onChange(of: openRow) { _, row in
                if row != id, offset != 0 { withAnimation(settle) { offset = 0 } }
            }
            .accessibilityAction(named: "Borrar", onDelete)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if sideways == nil {
                    sideways = abs(value.translation.width) > abs(value.translation.height) * 1.3
                }
                guard sideways == true else { return }
                if openRow != id { openRow = id }
                let start = isOpen && offset <= -buttonWidth / 2 ? -buttonWidth : 0
                let x = start + value.translation.width
                // Rightward past closed, it resists instead of moving away.
                offset = x > 0 ? x * 0.15 : x
            }
            .onEnded { value in
                defer { sideways = nil }
                guard sideways == true else { return }
                let reach = -(offset + value.predictedEndTranslation.width - value.translation.width)
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
