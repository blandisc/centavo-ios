import LocalAuthentication
import SwiftData
import SwiftUI

/// The «Mi dinero» tab: locked behind Face ID every time it's opened (2026-10-31), and
/// locked again when the tab or the app is left. While the app is in the switcher the tab is
/// covered, so no figure shows in the snapshot.
///
/// Face ID is asked for once per opening, never in a loop: its own sheet makes the app inactive
/// and active again, so «came back to the app» only counts after a real trip to the background.
/// A cancel leaves the tab locked with its button. The very first time, a screen says why
/// before iOS asks for permission (2026-10-31).
struct MoneyRootView: View {
    @Environment(\.scenePhase) private var phase
    @AppStorage(MoneyLock.explainedKey) private var explained = false
    @State private var lock = MoneyLockState.shared
    @State private var visible = false
    @State private var wentToBackground = false
    @State private var opened = MoneyLock.skips

    private var unlocked: Bool { lock.unlocked }
    private var asking: Bool { lock.asking }

    var body: some View {
        Group {
            switch MoneyStore.opened {
            case .success(let container):
                ZStack {
                    // Once opened, «Mi dinero» stays mounted under the lock: leaving to check the
                    // bank (as the rows suggest) and coming back keeps a half-written row.
                    if opened {
                        MoneyHomeView().modelContainer(container)
                            .accessibilityHidden(!unlocked)
                            .allowsHitTesting(unlocked)
                    }
                    if !unlocked {
                        if explained {
                            MoneyLockedView(asking: asking, unlock: ask)
                        } else {
                            MoneyFaceIDIntro { explained = true; ask() }
                        }
                    }
                }
                .onChange(of: lock.unlocked) { _, now in if now { opened = true } }
            case .failure:
                MoneyStoreErrorView()
            }
        }
        .overlay {
            if unlocked && phase != .active && !MoneyLock.skips { MoneyLockedView(asking: false, unlock: {}) }
        }
        .onAppear {
            visible = true
            if explained { ask() }
        }
        .onDisappear {
            visible = false
            relock()
        }
        .onChange(of: phase) { _, now in
            switch now {
            case .background:
                wentToBackground = true
                relock()
            case .active where wentToBackground:
                wentToBackground = false
                if visible && explained { ask() }
            default:
                break
            }
        }
    }

    private func relock() { lock.lock() }

    private func ask() { lock.ask() }
}

/// The one lock of «Mi dinero», shared by the tab and its sheets: a sheet sits above the tab,
/// so it needs the same «locked» to cover itself and the same Face ID to open.
@MainActor @Observable
final class MoneyLockState {
    static let shared = MoneyLockState()
    private(set) var unlocked = MoneyLock.skips
    private(set) var asking = false

    func lock() {
        guard !MoneyLock.skips else { return }
        unlocked = false
    }

    func ask() {
        guard !unlocked, !asking else { return }
        asking = true
        Task {
            unlocked = await MoneyLock.authenticate()
            asking = false
        }
    }
}

enum MoneyLock {
    /// Set once the person has read why Face ID is asked for.
    static let explainedKey = "dinero.faceIDExplicado"

    static var skips: Bool {
        #if DEBUG
        DemoData.skipsLock
        #else
        false
        #endif
    }

    /// Face ID, or the phone's passcode when Face ID fails or isn't allowed. A phone with no
    /// passcode at all has nothing to check against: it opens, as the phone itself does.
    @MainActor
    static func authenticate() async -> Bool {
        let context = LAContext()
        var problem: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else {
            return problem?.code == LAError.passcodeNotSet.rawValue
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: "Para abrir «Mi dinero».")) ?? false
    }
}

/// Before iOS asks «¿Permitir que Al día use Face ID?»: why, in one breath.
struct MoneyFaceIDIntro: View {
    let start: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                MoneyFaceIDArt().frame(maxWidth: .infinity)
                Text("«Mi dinero» se abre solo con tu cara")
                    .font(.ticket(.heading))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    point("Aquí van tus saldos y lo que debes: si le prestas tu iPhone a alguien en «Hoy», no puede pasar a verlos.")
                    point("Te lo pide cada vez que abres esta pestaña. Si Face ID falla, usas el código de tu iPhone.")
                    point("Al tocar «Activar», iOS te pregunta si Al día puede usar Face ID. Tu cara nunca sale del iPhone.")
                }
                Button(action: start) { PrimaryButtonLabel("Activar Face ID", systemImage: "faceid") }
                    .ticketProminent()
                    .accessibilityIdentifier("dinero-activar-faceid")
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.xxl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.background.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .principal) { MoneySignature() } }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text("·").foregroundStyle(Theme.brass)
            Text(text)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.ticket(.callout))
    }
}

/// The blank ticket while locked: no figures, one way in.
struct MoneyLockedView: View {
    let asking: Bool
    let unlock: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.xl) {
                Spacer()
                VStack(spacing: Theme.Space.m) {
                    Image(systemName: "faceid")
                        .font(Theme.Symbol.large)
                        .foregroundStyle(Theme.brass)
                    Text("$ ••• •••")
                        .font(.ticket(.display))
                        .foregroundStyle(Theme.raised)
                        .accessibilityHidden(true)
                    Text("Tus cuentas están protegidas.")
                        .font(.ticket(.callout))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.xxl)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.ticket)
                        .strokeBorder(Theme.outline, style: StrokeStyle(lineWidth: Theme.Stroke.hairline, dash: Theme.Dash.ticket))
                }
                Button(action: unlock) { PrimaryButtonLabel("Desbloquear", systemImage: "faceid") }
                    .ticketProminent()
                    .disabled(asking)
                    .accessibilityIdentifier("dinero-desbloquear")
                Spacer()
            }
            .padding(.horizontal, Theme.Space.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) { MoneySignature() }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// «mi dinero.», the tab's signature, like «al día.» on «Hoy».
struct MoneySignature: View {
    var body: some View {
        Text("mi dinero\(Text(".").foregroundStyle(Theme.brass))")
            .font(.ticket(.subheading))
            .foregroundStyle(Theme.ink)
            .accessibilityLabel("Mi dinero")
            .accessibilityAddTraits(.isHeader)
    }
}

struct MoneyStoreErrorView: View {
    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Text("«Mi dinero» no pudo abrir")
                .font(.ticket(.heading))
                .foregroundStyle(Theme.ink)
            Text("Tus gastos de «Hoy» no se tocaron. Restaura tu último respaldo desde Ajustes.")
                .font(.ticket(.callout))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Space.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}

/// Covers a «Mi dinero» sheet with the blank ticket whenever the app isn't in front (the app
/// switcher, a Face ID prompt): sheets sit above the tab's lock.
private struct MoneyPrivacyCover: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @State private var lock = MoneyLockState.shared

    func body(content: Content) -> some View {
        content.overlay {
            // Covered while the app isn't in front, and until Face ID opens it again after.
            if !MoneyLock.skips && (phase != .active || !lock.unlocked) {
                MoneyLockedView(asking: lock.asking, unlock: { lock.ask() })
            }
        }
    }
}

extension View {
    func moneyPrivacyCover() -> some View { modifier(MoneyPrivacyCover()) }
}
