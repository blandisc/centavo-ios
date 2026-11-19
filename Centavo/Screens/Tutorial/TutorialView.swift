import CentavoCore
import SwiftUI

/// The stories of «Cómo funciona» (2026-11-01), in the order the app is learned: the figure,
/// the boleto, what is left, how payments arrive, what doesn't count, where it goes, the backup;
/// and a last one that closes them, like the end of a set of stories (2026-11-03).
enum TutorialStory: Int, CaseIterable, Identifiable {
    case figure, bar, leftover, wallet, uncounted, categories, backup, done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .figure: String(localized: "Cuánto puedes gastar hoy")
        case .bar: String(localized: "Tu mes en un boleto")
        case .leftover: String(localized: "Lo que sobra no se pierde")
        case .wallet: String(localized: "Se anota solo")
        case .uncounted: String(localized: "Lo que no es gasto")
        case .categories: String(localized: "En qué se va")
        case .backup: String(localized: "Tu respaldo")
        case .done: String(localized: "Ya sabes cómo funciona")
        }
    }

    var text: String {
        switch self {
        case .figure: String(localized: "Tu presupuesto, menos tus fijos, entre los días del mes. A eso se suma o resta lo que te sobró o te pasaste antes: esa es la cifra de arriba, y baja con cada pago.")
        case .bar: String(localized: "Cada celda es un día. Se llena con lo que gastas; si un día te pasas, se pinta de rojo. Los días por venir van punteados.")
        case .leftover: String(localized: "Lo que no gastas hoy pasa a mañana. Si prefieres, se reparte entre los días que quedan.")
        case .wallet: CaptureCopy.tutorial
        case .uncounted: String(localized: "Un pago a tu tarjeta o un traspaso: mantenlo presionado y elige «No cuenta». Se queda en la lista, pero no cuenta en tu presupuesto.")
        case .categories: String(localized: "Abajo ves tus categorías. Toca una para ver solo esos gastos.")
        case .backup: String(localized: "Guarda una copia cada noche, cerrada con tu contraseña. Se activa en «··· › Ajustes › Respaldo diario».")
        case .done: String(localized: "Mira tu cifra cada mañana y deja que los pagos se anoten solos. Estas historias siguen en «··· › Cómo funciona».")
        }
    }

    /// Without a budget there is no «Hoy puedes gastar» and the figure on top is the month's
    /// total (DECISIONS): these two stories say what a budget would do instead of
    /// pointing at a figure that isn't there (QA, 2026-11-18). «Pruébalo» opens the budget.
    func text(hasBudget: Bool) -> String {
        switch self {
        case .figure where !hasBudget:
            String(localized: "Con un presupuesto, Al día lo reparte entre los días del mes, menos tus fijos, y arriba te dice cuánto puedes gastar hoy. Sin él, arriba ves lo que llevas en el mes.")
        case .leftover where !hasBudget:
            String(localized: "Con un presupuesto, lo que no gastas hoy pasa a mañana. Si prefieres, se reparte entre los días que quedan.")
        default:
            text
        }
    }

    /// With VoiceOver there is no press-and-hold: «Lo que no es gasto» says the way through the
    /// expense's own sheet, which a double tap opens (QA, 2026-11-18).
    func text(hasBudget: Bool, voiceOver: Bool) -> String {
        if voiceOver, self == .uncounted {
            return String(localized: "Un pago a tu tarjeta o un traspaso: ábrelo, toca «Más detalles» y, en «Tipo», elige «No cuenta». Se queda en la lista, pero no cuenta en tu presupuesto.")
        }
        return text(hasBudget: hasBudget)
    }

    /// Where «Pruébalo» goes, if the story has somewhere to try it.
    var destination: TutorialDestination? {
        switch self {
        case .figure, .leftover: .budget
        case .wallet: .guide
        case .backup: .settings
        case .bar, .uncounted, .categories, .done: nil
        }
    }

    func duration(hasBudget: Bool) -> Double { StoryTiming.duration(for: [title, text(hasBudget: hasBudget)]) }
}

/// What «Pruébalo» opens on «Hoy», once the stories are gone (two covers can't be up at once).
enum TutorialDestination {
    case budget, guide, settings
}

struct TutorialView: View {
    /// «Pruébalo»: where to go after closing.
    let tryIt: (TutorialDestination) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(BudgetStore.key) private var storedBudget = ""

    @State private var index = 0
    /// When the current story started, and how long it has been held since: what has gone by is
    /// worked out from the clock (`elapsed(at:)`), so nothing here changes 20 times a second
    /// (audit 2026-11-02: the whole screen and its drawing were redone on every tick).
    @State private var storyStart = AppClock.now
    @State private var heldBefore: Double = 0
    @State private var heldSince: Date?
    /// Held because the app left the front (locked, another app): the clock doesn't run there.
    @State private var heldByLeaving = false
    /// Reset by the system when a press is cancelled (Control Center, a call), so the story
    /// can't stay held or pulled down.
    @GestureState private var holding = false
    @GestureState(resetTransaction: Transaction(animation: Theme.Motion.Tutorial.change)) private var drag: CGFloat = 0
    @State private var pressStart: Date?
    /// Taps only: the stories that move by themselves don't buzz.
    @State private var taps = 0
    /// The story didn't fit and scrolls: no press there to hold it, so it doesn't move on by
    /// itself while the person scrolls down to read it (QA on the SE, 2026-11-18).
    @State private var scrolls = false

    private var stories: [TutorialStory] { TutorialStory.allCases }
    private var story: TutorialStory { stories[index] }
    private var isFirst: Bool { index == stories.startIndex }
    private var hasBudget: Bool { BudgetStore.amount(from: storedBudget) != nil }
    private var text: String { story.text(hasBudget: hasBudget, voiceOver: voiceOver) }
    private var duration: Double { story.duration(hasBudget: hasBudget) }

    /// It moves on by itself only when the person can read at their pace anyway: never with
    /// VoiceOver, still drawings, an accessibility text size or a story that scrolls.
    private var advancesByItself: Bool {
        !voiceOver && !still && !typeSize.isAccessibilitySize && !scrolls
    }

    private var still: Bool { MotionPolicy.isStill(reduceMotion: reduceMotion) }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            header
            GeometryReader { proxy in
                // What doesn't fit (a big text size, a small phone) scrolls, and a drag there is
                // the scroll's: the buttons move. The ZStack keeps the crossfade in one place.
                ViewThatFits(in: .vertical) {
                    // From the top, never centred: a longer text or a «Pruébalo» made the
                    // story taller, and its title sat on a different line in each one (UX
                    // review, 2026-11-11). The drawing's box is one height, so the title is too.
                    ZStack { storyContent }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .gesture(press(width: proxy.size.width))
                    // Only the variant on screen appears, so this says which one it is.
                    ScrollView { ZStack { storyContent } }
                        .onAppear { scrolls = true }
                        .onDisappear { scrolls = false }
                }
            }
            footer
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.background.ignoresSafeArea())
        .offset(y: max(drag, Theme.Space.none))
        // The spring back after a short pull is a full-screen move: none with «Reducir
        // movimiento» (QA, 2026-11-18). The reset's own transaction can't read the setting.
        .transaction(value: drag) { [isStill = still] in if isStill { $0.animation = nil } }
        // Again when it starts or stops moving by itself (low power, VoiceOver, text size).
        .task(id: RunKey(index: index, moves: advancesByItself)) { await run() }
        .onChange(of: advancesByItself) { restartClock() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, heldSince == nil {
                heldSince = AppClock.now
                heldByLeaving = true
            } else if phase == .active, heldByLeaving {
                heldByLeaving = false
                if !holding, let since = heldSince {
                    heldBefore += AppClock.now.timeIntervalSince(since)
                    heldSince = nil
                }
            }
        }
        .onChange(of: holding) { _, pressed in
            if pressed {
                pressStart = AppClock.now
                heldSince = AppClock.now
            } else if scenePhase != .active {
                // The system cancels a held finger when the app leaves the front (Control
                // Center, a call): keep the clock stopped until it comes back, or the story
                // would move on unseen (QA, 2026-11-18). The `.active` branch above releases it.
                heldByLeaving = true
            } else if let since = heldSince {
                heldBefore += AppClock.now.timeIntervalSince(since)
                heldSince = nil
            }
        }
        .onChange(of: index) {
            if voiceOver { AccessibilityNotification.Announcement("\(story.title). \(text)").post() }
        }
        .sensoryFeedback(.selection, trigger: taps)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.xxs) {
                ForEach(stories) { item in
                    if item.rawValue == index && advancesByItself {
                        // One linear animation to the end, stopped where it is while held (audit
                        // 2026-11-02: a 30 fps clock redrew it the whole story). A new clock is a
                        // new bar.
                        RunningStoryBar(now: StoryTiming.progress(elapsed: elapsed(at: AppClock.now),
                                                                  duration: duration),
                                        duration: duration, paused: heldSince != nil)
                            .id(storyStart)
                    } else {
                        StoryBar(fill: Self.barFill(item.rawValue, current: index, scrolls: scrolls))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Historia \(index + 1) de \(stories.count)")
            HStack {
                Text("Cómo funciona")
                    .font(.ticket(.microStrong))
                    .tracking(Theme.Tracking.action)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("Cerrar", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.ticket(.bodyStrong))
                    .foregroundStyle(Theme.ink)
                    .buttonStyle(.tapTarget)
                    .accessibilityIdentifier("tutorial-cerrar")
            }
        }
    }

    private var storyContent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            PlayOnceClock(until: Theme.Motion.Tutorial.draw) { seconds in
                TutorialArt(story: story, progress: seconds / Theme.Motion.Tutorial.draw)
            }
            .id(story)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.tutorialArt)
            Text(story.title)
                .font(.ticket(.pageTitle))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("tutorial-titulo")
            Text(text)
                .font(.ticket(.body))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let destination = story.destination {
                Button {
                    tryIt(destination)
                    dismiss()
                } label: {
                    LinkActionLabel("Pruébalo", systemImage: "arrow.right", alignment: .leading, fillsWidth: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tutorial-pruebalo")
            }
        }
        .id(index)
        // The old story leaves before the new one comes in: they never overlap (audit 2026-11-02).
        .transition(still ? .identity : .storyChange)
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.m) {
            Button { tap(index - 1) } label: {
                LinkActionLabel("Anterior", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(isFirst)
            .opacity(isFirst ? Theme.Opacity.hidden : Theme.Opacity.visible)
            .accessibilityHidden(isFirst)
            .accessibilityIdentifier("tutorial-anterior")
            Button { index == stories.count - 1 ? dismiss() : tap(index + 1) } label: {
                PrimaryButtonLabel(nextTitle)
            }
            .ticketProminent()
            .accessibilityIdentifier("tutorial-siguiente")
        }
    }

    /// «Siguiente», and «Listo» on the last story.
    private var nextTitle: String {
        if index == stories.count - 1 { return String(localized: "Listo") }
        return String(localized: "Siguiente")
    }

    /// A story's part of the bar when it isn't running: full once gone by, and the current one
    /// full too while it stays still (VoiceOver, still drawings). Empty for one that scrolls:
    /// its first frame had a running bar, and it jumped to full (QA, 2026-11-18).
    static func barFill(_ item: Int, current: Int, scrolls: Bool) -> Double {
        if item < current { return 1 }
        if item == current && !scrolls { return 1 }
        return 0
    }

    // MARK: Moving

    /// How long the current story has been on screen, not counting while it was held.
    private func elapsed(at date: Date) -> Double {
        let holdingNow = heldSince.map { max(date.timeIntervalSince($0), 0) } ?? 0
        return date.timeIntervalSince(storyStart) - heldBefore - holdingNow
    }

    private struct RunKey: Hashable {
        let index: Int
        let moves: Bool
    }

    /// The new story's clock starts now, already held if a finger is down.
    private func restartClock() {
        storyStart = AppClock.now
        heldBefore = 0
        heldSince = holding ? AppClock.now : nil
    }

    /// A tap past the last story closes them, as «Listo» does.
    private func tap(_ target: Int) {
        taps += 1
        if target == stories.count { return dismiss() }
        go(target)
    }

    private func go(_ target: Int) {
        guard stories.indices.contains(target) else { return }
        // The new story's bar starts empty, without animating down from the last one's.
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        withTransaction(reset) { restartClock() }
        withAnimation(still ? nil : Theme.Motion.Tutorial.change) { index = target }
    }

    /// Fills the current story's bar, held while pressed, and moves on when it is full; the last
    /// one waits for «Listo».
    private func run() async {
        guard advancesByItself else { return }
        while !Task.isCancelled {
            let left = duration - elapsed(at: AppClock.now)
            if heldSince == nil && left <= 0 {
                if index < stories.count - 1 { go(index + 1) }
                return
            }
            // Asleep until the story is due; a hold in between pushes it back, and is checked
            // again after it.
            try? await Task.sleep(for: .seconds(heldSince == nil ? left : Theme.Motion.Tutorial.tick))
        }
    }

    /// One gesture for the whole story: a tap moves (the leading part back), pressing holds,
    /// and a drag down closes.
    private func press(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($holding) { _, state, _ in state = true }
            .updating($drag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let held = pressStart.map { AppClock.now.timeIntervalSince($0) } ?? 0
                pressStart = nil
                let moved = hypot(value.translation.width, value.translation.height)
                if value.translation.height > Theme.Size.tutorialCloseDrag {
                    dismiss()
                } else if moved < Theme.Size.tutorialTapSlop && held < Theme.Motion.Tutorial.hold {
                    tap(value.location.x < width * Theme.Size.tutorialBackShare ? index - 1 : index + 1)
                }
            }
    }
}

/// The current story's part of the bar: one linear animation from where it is now to full,
/// frozen in place while `paused` and picked up again after.
private struct RunningStoryBar: View {
    let now: Double
    let duration: Double
    let paused: Bool
    @State private var fill: Double

    init(now: Double, duration: Double, paused: Bool) {
        self.now = now
        self.duration = duration
        self.paused = paused
        _fill = State(initialValue: now)
    }

    var body: some View {
        StoryBar(fill: fill)
            .onAppear { if !paused { play() } }
            .onChange(of: paused) { _, held in
                if held {
                    var stop = Transaction(animation: nil)
                    stop.disablesAnimations = true
                    withTransaction(stop) { fill = now }
                } else {
                    play()
                }
            }
    }

    private func play() {
        guard fill < 1 else { return }
        withAnimation(Theme.Motion.Tutorial.fill(seconds: duration * (1 - fill))) { fill = 1 }
    }
}

/// One story's part of the bar on top: brass up to `fill`.
private struct StoryBar: View {
    let fill: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(Theme.raised)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.brass)
                        .frame(width: proxy.size.width * fill)
                }
        }
        .frame(height: Theme.Size.tutorialProgress)
    }
}
