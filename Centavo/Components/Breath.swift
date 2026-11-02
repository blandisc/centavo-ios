import SwiftUI

/// A mark that breathes a few times when it appears and then rests at full opacity (audit
/// 2026-11-02): today's cell of the boleto, a cursor waiting. Each breath fades down and back
/// up, so the last one always ends where the mark rests: no jump at the end, nothing runs
/// forever. With `MotionPolicy` still it never moves.
private struct Breath: ViewModifier {
    let isOn: Bool
    let times: Int
    /// Seconds for each half of a breath (down, or back up).
    let seconds: Double
    /// How faint the mark gets at the bottom of a breath.
    let low: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(isOn && dim ? low : Theme.Opacity.visible)
            // Once per appearance. While `isOn` is off (another day picked) it shows at full, and
            // the breaths still end undimmed, so turning it back on never finds it faint.
            .task {
                guard isOn, !MotionPolicy.isStill(reduceMotion: reduceMotion) else { return }
                let half = Animation.easeInOut(duration: seconds)
                for _ in 0..<times {
                    withAnimation(half) { dim = true }
                    try? await Task.sleep(for: .seconds(seconds))
                    withAnimation(half) { dim = false }
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled else { return }
                }
            }
    }
}

extension View {
    /// Breathes `times` times when it appears (if `isOn`), then rests at full.
    func breathes(_ isOn: Bool = true, times: Int, seconds: Double, low: Double) -> some View {
        modifier(Breath(isOn: isOn, times: times, seconds: seconds, low: low))
    }
}
