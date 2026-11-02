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
    /// It waits for this (the view it lives in has come in), then `after` seconds more.
    let begins: Bool
    let after: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    @State private var breathed = false

    private var still: Bool { MotionPolicy.isStill(reduceMotion: reduceMotion) }

    func body(content: Content) -> some View {
        content
            .opacity(isOn && dim ? low : Theme.Opacity.visible)
            // Once per appearance. While `isOn` is off (another day picked) it shows at full, and
            // the breaths still end undimmed, so turning it back on never finds it faint.
            .task(id: begins) {
                guard begins, !breathed, isOn, !still else { return }
                breathed = true
                if after > 0 { try? await Task.sleep(for: .seconds(after)) }
                let half = Animation.easeInOut(duration: seconds)
                for _ in 0..<times {
                    // Low Power Mode (or reduced motion) turned on midway: straight to rest.
                    guard !Task.isCancelled, !still else { break }
                    withAnimation(half) { dim = true }
                    try? await Task.sleep(for: .seconds(seconds))
                    withAnimation(still ? nil : half) { dim = false }
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(for: .seconds(seconds))
                }
                if dim { withAnimation(nil) { dim = false } }
            }
            .onChange(of: still) { _, isStill in
                if isStill, dim { withAnimation(nil) { dim = false } }
            }
    }
}

extension View {
    /// Breathes `times` times when it appears (if `isOn`), then rests at full. With `begins`,
    /// only once that turns true, and `after` seconds later: not while it is still coming in.
    func breathes(_ isOn: Bool = true, times: Int, seconds: Double, low: Double,
                  begins: Bool = true, after: Double = 0) -> some View {
        modifier(Breath(isOn: isOn, times: times, seconds: seconds, low: low, begins: begins, after: after))
    }
}
