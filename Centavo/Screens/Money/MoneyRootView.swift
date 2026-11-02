import CentavoCore
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
            lock.visible = true
            if explained { ask() }
        }
        .onDisappear {
            visible = false
            lock.visible = false
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
///
/// Leaving the tab while Face ID is still asking used to open it anyway when the answer came
/// (2026-11-02 audit). Now every lock starts a new generation and cancels the prompt; an answer
/// only opens if it belongs to the current generation and the tab is still on screen.
@MainActor @Observable
final class MoneyLockState {
    static let shared = MoneyLockState()
    private(set) var unlocked = MoneyLock.skips
    private(set) var asking = false
    /// The tab is on screen (set by `MoneyRootView`).
    var visible = false
    private var gate = UnlockGate()
    @ObservationIgnored private var prompt: LAContext?

    func lock() {
        guard !MoneyLock.skips else { return }
        gate.lock()
        prompt?.invalidate()
        prompt = nil
        asking = false
        unlocked = false
    }

    func ask() {
        guard !unlocked, !asking, visible else { return }
        asking = true
        let started = gate.generation
        let context = LAContext()
        prompt = context
        Task {
            let granted = await MoneyLock.authenticate(context: context)
            // Locked again while the prompt was up (or the tab left): this answer is stale.
            guard started == gate.generation else { return }
            prompt = nil
            asking = false
            unlocked = gate.opens(granted: granted, started: started, stillVisible: visible)
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
    static func authenticate(context: LAContext) async -> Bool {
        await OwnerCheck.confirm(reason: "Para abrir «Mi dinero».", context: context)
    }
}

/// Before iOS asks «¿Permitir que Al día use Face ID?»: why, in one breath. It names what
/// this iPhone uses (Face ID, Touch ID or its passcode) and says so when it has no passcode,
/// because then «Mi dinero» opens without asking (2026-11-02 audit).
struct MoneyFaceIDIntro: View {
    let start: () -> Void
    @State private var method = OwnerCheck.method

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if method == .faceID {
                    MoneyFaceIDArt().frame(maxWidth: .infinity)
                } else {
                    Image(systemName: method.symbol)
                        .font(Theme.Symbol.large)
                        .foregroundStyle(Theme.brass)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                Text(method.title)
                    .font(.ticket(.heading))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(method.points, id: \.self) { point($0) }
                }
                Button(action: start) { PrimaryButtonLabel(method.button, systemImage: method.symbol) }
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
    @State private var method = OwnerCheck.method

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.xl) {
                Spacer()
                VStack(spacing: Theme.Space.m) {
                    Image(systemName: method.symbol)
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
                Button(action: unlock) { PrimaryButtonLabel("Desbloquear", systemImage: method.symbol) }
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
            Text("Tus gastos de «Hoy» están bien. Cierra Al día por completo y vuelve a abrirla. Si sigue igual, restaurar un respaldo en Más › Ajustes › Respaldo diario lo arregla: «Mi dinero» que no abre se guarda aparte en este iPhone, sin borrarse. Restaurar también regresa tus gastos al día de ese respaldo.")
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
/// switcher, a Face ID prompt): sheets sit above the tab's lock. While covered, what's under it
/// can't be read by VoiceOver nor touched, and the keyboard goes away (2026-11-02 audit).
private struct MoneyPrivacyCover: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @State private var lock = MoneyLockState.shared

    private var covered: Bool { !MoneyLock.skips && (phase != .active || !lock.unlocked) }

    func body(content: Content) -> some View {
        content
            .disabled(covered)
            .accessibilityHidden(covered)
            .overlay {
                // Covered while the app isn't in front, and until Face ID opens it again after.
                if covered {
                    MoneyLockedView(asking: lock.asking, unlock: { lock.ask() })
                }
            }
    }
}

/// Runs `action` the moment «Mi dinero» gets covered (the app leaves the front, or the lock
/// closes): each screen uses it to close its own pending alerts and dialogs, which iOS draws
/// above everything, cover included. The keyboard is put away too.
private struct MoneyCoverReset: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @State private var lock = MoneyLockState.shared
    let action: () -> Void

    private var covered: Bool { !MoneyLock.skips && (phase != .active || !lock.unlocked) }

    func body(content: Content) -> some View {
        content.onChange(of: covered) { _, now in
            guard now else { return }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            action()
        }
    }
}

extension View {
    func moneyPrivacyCover() -> some View { modifier(MoneyPrivacyCover()) }

    /// Closes this screen's alerts and dialogs when «Mi dinero» gets covered.
    func onMoneyCovered(_ action: @escaping () -> Void) -> some View { modifier(MoneyCoverReset(action: action)) }
}
