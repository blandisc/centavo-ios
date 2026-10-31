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
    @State private var unlocked = MoneyLock.skips
    @State private var visible = false
    @State private var asking = false
    @State private var wentToBackground = false

    var body: some View {
        Group {
            switch MoneyStore.opened {
            case .success(let container):
                if unlocked {
                    MoneyHomeView().modelContainer(container)
                } else if !explained {
                    MoneyFaceIDIntro { explained = true; ask() }
                } else {
                    MoneyLockedView(asking: asking, unlock: ask)
                }
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
            lock()
        }
        .onChange(of: phase) { _, now in
            switch now {
            case .background:
                wentToBackground = true
                lock()
            case .active where wentToBackground:
                wentToBackground = false
                if visible && explained { ask() }
            default:
                break
            }
        }
    }

    private func lock() {
        guard !MoneyLock.skips else { return }
        unlocked = false
    }

    private func ask() {
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
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Spacer()
                Image(systemName: "faceid")
                    .font(Theme.Symbol.large)
                    .foregroundStyle(Theme.brass)
                Text("«Mi dinero» se abre solo con tu cara")
                    .font(.ticket(.heading))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    point("Aquí van tus saldos y lo que debes: si le prestas tu iPhone a alguien en «Hoy», no puede pasar a verlos.")
                    point("Te lo pide cada vez que abres esta pestaña. Si Face ID falla, usas el código de tu iPhone.")
                    point("Al tocar «Activar», iOS te pregunta si Al día puede usar Face ID. Tu cara nunca sale del iPhone.")
                }
                Spacer()
                Button(action: start) { PrimaryButtonLabel("Activar Face ID", systemImage: "faceid") }
                    .ticketProminent()
                    .accessibilityIdentifier("dinero-activar-faceid")
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, Theme.Space.xxl)
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
