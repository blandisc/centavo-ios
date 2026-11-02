import SwiftUI

/// Where a step flow is (2026-11-01): one part per step, brass up to the current one, its name
/// beside «Paso N de M». The current part carries a light that crosses it once when the step
/// opens, then stays still. Shared by the welcome and «Mi dinero»'s first time.
struct StepBar: View {
    let step: Int
    let of: Int
    let label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheen: CGFloat = -Theme.Size.moneySheenShare

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.xxs) {
                ForEach(1...of, id: \.self) { part in
                    Capsule()
                        .fill(part <= step ? Theme.brass : Theme.raised)
                        .frame(height: Theme.Size.moneyStepBar)
                        .overlay {
                            if part == step && !MotionPolicy.isStill(reduceMotion: reduceMotion) {
                                GeometryReader { proxy in
                                    LinearGradient(colors: [.clear, Theme.ink.opacity(Theme.Opacity.paceBehind), .clear],
                                                   startPoint: .leading, endPoint: .trailing)
                                        .frame(width: proxy.size.width * Theme.Size.moneySheenShare)
                                        .offset(x: proxy.size.width * sheen)
                                }
                            }
                        }
                        .clipShape(Capsule())
                }
            }
            HStack {
                Text("Paso \(Text("\(step) de \(of)").foregroundStyle(Theme.ink))")
                Spacer(minLength: Theme.Space.s)
                Text(label)
            }
            .font(.ticket(.microStrong))
            .tracking(Theme.Tracking.action)
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paso \(step) de \(of), \(label)")
        .onAppear(perform: cross)
        .onChange(of: step) { cross() }
    }

    /// Back to the start with no animation (it would run backwards over the bar), then across
    /// once, in the next update so the two changes don't merge into one.
    private func cross() {
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        withTransaction(reset) { sheen = -Theme.Size.moneySheenShare }
        guard !MotionPolicy.isStill(reduceMotion: reduceMotion) else { return }
        Task { @MainActor in
            withAnimation(Theme.Motion.Money.sheen) { sheen = 1 }
        }
    }
}

/// When the drawings and loops of the app stand still (2026-11-01): «Reducir movimiento», Low
/// Power Mode, and the UI tests (which wait for the app to be idle, and a loop never is).
/// A view that reads it in `body` redraws when Low Power Mode turns on or off (`LowPowerWatch`).
@MainActor
enum MotionPolicy {
    static func isStill(reduceMotion: Bool) -> Bool {
        reduceMotion || LowPowerWatch.shared.isOn || testsWantStill
    }

    nonisolated static var testsWantStill: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-centavo-sin-animaciones") || arguments.contains("-centavo-dibujos-quietos")
        #else
        false
        #endif
    }
}

/// Low Power Mode, watched live (audit 2026-11-02): reading `ProcessInfo` once left a loop
/// running after the person turned it on. Observable, so `MotionPolicy` readers redraw.
@MainActor @Observable
final class LowPowerWatch {
    static let shared = LowPowerWatch()

    private(set) var isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}
