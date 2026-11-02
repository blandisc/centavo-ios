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

    private func cross() {
        sheen = -Theme.Size.moneySheenShare
        guard !MotionPolicy.isStill(reduceMotion: reduceMotion) else { return }
        withAnimation(Theme.Motion.Money.sheen) { sheen = 1 }
    }
}

/// When the drawings and loops of the app stand still (2026-11-01): «Reducir movimiento», Low
/// Power Mode, and the UI tests (which wait for the app to be idle, and a loop never is).
enum MotionPolicy {
    static func isStill(reduceMotion: Bool) -> Bool {
        reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled || testsWantStill
    }

    static var testsWantStill: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-centavo-sin-animaciones") || arguments.contains("-centavo-dibujos-quietos")
        #else
        false
        #endif
    }
}
