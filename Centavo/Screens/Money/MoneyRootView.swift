import LocalAuthentication
import SwiftData
import SwiftUI

/// The «Mi dinero» tab: locked behind Face ID every time it's opened (2026-10-31), and
/// locked again when the tab or the app is left. While the app is in the switcher the tab is
/// covered, so no figure shows in the snapshot.
struct MoneyRootView: View {
    @Environment(\.scenePhase) private var phase
    @State private var unlocked = MoneyLock.skips
    @State private var visible = false
    @State private var asking = false

    var body: some View {
        Group {
            switch MoneyStore.opened {
            case .success(let container):
                if unlocked {
                    MoneyHomeView().modelContainer(container)
                } else {
                    MoneyLockedView(asking: asking, unlock: { Task { await unlock() } })
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
            Task { await unlock() }
        }
        .onDisappear {
            visible = false
            lock()
        }
        .onChange(of: phase) { _, now in
            if now == .background { lock() }
            if now == .active && visible { Task { await unlock() } }
        }
    }

    private func lock() {
        guard !MoneyLock.skips else { return }
        unlocked = false
    }

    private func unlock() async {
        guard !unlocked, !asking else { return }
        asking = true
        defer { asking = false }
        unlocked = await MoneyLock.authenticate()
    }
}

enum MoneyLock {
    static var skips: Bool {
        #if DEBUG
        DemoData.skipsLock
        #else
        false
        #endif
    }

    /// Face ID, or the phone's passcode when Face ID fails. A phone with no passcode at all has
    /// nothing to check against: it opens, as the phone itself does.
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
