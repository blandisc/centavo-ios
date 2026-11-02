import CentavoCore
import SwiftUI

/// The stories of «Cómo funciona» (2026-11-01), in the order the app is learned: the figure,
/// the bar, what is left, how payments arrive, what doesn't count, where it goes, the backup.
enum TutorialStory: Int, CaseIterable, Identifiable {
    case figure, bar, leftover, wallet, uncounted, categories, backup

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .figure: "Cuánto puedes gastar hoy"
        case .bar: "Tu mes en una barra"
        case .leftover: "Lo que sobra no se pierde"
        case .wallet: "Se anota solo"
        case .uncounted: "Lo que no es gasto"
        case .categories: "En qué se va"
        case .backup: "Tu respaldo"
        }
    }

    var text: String {
        switch self {
        case .figure: "Tu presupuesto, menos tus fijos, entre los días del mes: eso te toca cada día. Es la cifra de arriba y baja con cada pago."
        case .bar: "El latón es lo que llevas; la raya, lo que podrías llevar a estas alturas del mes. Si el latón la pasa, vas arriba del ritmo."
        case .leftover: "Lo que no gastas hoy pasa a mañana. Si prefieres, se reparte entre los días que quedan."
        case .wallet: "Cada pago con Apple Pay llega por Atajos y se anota. El efectivo, con «+»."
        case .uncounted: "Un pago a tu tarjeta o un traspaso: ábrelo, toca «Más detalles» y en «Tipo» elige «No cuenta». Se queda en la lista, pero no cuenta en tu presupuesto."
        case .categories: "Abajo ves tus categorías. Toca una para ver solo esos pagos."
        case .backup: "Elige una contraseña y una carpeta en Ajustes, y Al día guarda ahí una copia diaria cerrada con ella. Así no pierdes nada al cambiar de iPhone."
        }
    }

    /// Where «Pruébalo» goes, if the story has somewhere to try it.
    var destination: TutorialDestination? {
        switch self {
        case .figure, .leftover: .budget
        case .wallet: .guide
        case .backup: .settings
        case .bar, .uncounted, .categories: nil
        }
    }

    var duration: Double { StoryTiming.duration(for: [title, text]) }
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

    @State private var index = 0
    @State private var elapsed: Double = 0
    /// Reset by the system when a press is cancelled (Control Center, a call), so the story
    /// can't stay held or pulled down.
    @GestureState private var holding = false
    @GestureState(resetTransaction: Transaction(animation: Theme.Motion.Tutorial.change)) private var drag: CGFloat = 0
    @State private var pressStart: Date?
    /// Taps only: the stories that move by themselves don't buzz.
    @State private var taps = 0

    private var stories: [TutorialStory] { TutorialStory.allCases }
    private var story: TutorialStory { stories[index] }
    private var isFirst: Bool { index == stories.startIndex }

    /// It moves on by itself only when the person can read at their pace anyway: never with
    /// VoiceOver, still drawings or an accessibility text size.
    private var advancesByItself: Bool {
        !voiceOver && !still && !typeSize.isAccessibilitySize
    }

    private var still: Bool { MotionPolicy.isStill(reduceMotion: reduceMotion) }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            header
            GeometryReader { proxy in
                // What doesn't fit (a big text size, a small phone) scrolls, and a drag there is
                // the scroll's: the buttons move. The ZStack keeps the crossfade in one place.
                ViewThatFits(in: .vertical) {
                    ZStack { storyContent }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .gesture(press(width: proxy.size.width))
                    ScrollView { ZStack { storyContent } }
                }
            }
            footer
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.background.ignoresSafeArea())
        .offset(y: max(drag, Theme.Space.none))
        .task(id: index) { await run() }
        .onChange(of: holding) { _, pressed in if pressed { pressStart = .now } }
        .onChange(of: index) {
            if voiceOver { AccessibilityNotification.Announcement("\(story.title). \(story.text)").post() }
        }
        .sensoryFeedback(.selection, trigger: taps)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.xxs) {
                ForEach(stories) { item in
                    GeometryReader { proxy in
                        Capsule().fill(Theme.raised)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.brass)
                                    .frame(width: proxy.size.width * fill(of: item))
                            }
                    }
                    .frame(height: Theme.Size.tutorialProgress)
                    .animation(still ? nil : .linear(duration: Theme.Motion.Tutorial.tick), value: elapsed)
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
                    .frame(minWidth: Theme.Size.tapTarget, minHeight: Theme.Size.tapTarget)
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
            Text(story.text)
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
        .transition(.opacity)
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
                PrimaryButtonLabel(index == stories.count - 1 ? "Listo" : "Siguiente")
            }
            .ticketProminent()
            .accessibilityIdentifier("tutorial-siguiente")
        }
    }

    // MARK: Moving

    /// The bar of each story: full behind, empty ahead, filling for the current one.
    private func fill(of item: TutorialStory) -> CGFloat {
        if item.rawValue < index { return 1 }
        if item.rawValue > index { return 0 }
        return advancesByItself ? StoryTiming.progress(elapsed: elapsed, duration: story.duration) : 1
    }

    private func tap(_ target: Int) {
        taps += 1
        go(target)
    }

    private func go(_ target: Int) {
        guard stories.indices.contains(target) else { return }
        // The new story's bar starts empty, without animating down from the last one's.
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        withTransaction(reset) { elapsed = 0 }
        withAnimation(still ? nil : Theme.Motion.Tutorial.change) { index = target }
    }

    /// Fills the current story's bar, held while pressed, and moves on when it is full; the last
    /// one waits for «Listo».
    private func run() async {
        elapsed = 0
        guard advancesByItself else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Theme.Motion.Tutorial.tick))
            if !holding { elapsed += Theme.Motion.Tutorial.tick }
            if elapsed >= story.duration {
                if index < stories.count - 1 { go(index + 1) }
                return
            }
        }
    }

    /// One gesture for the whole story: a tap moves (the leading part back), pressing holds,
    /// and a drag down closes.
    private func press(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($holding) { _, state, _ in state = true }
            .updating($drag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let held = pressStart.map { Date.now.timeIntervalSince($0) } ?? 0
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
