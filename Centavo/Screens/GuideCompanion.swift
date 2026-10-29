import AVFoundation
import AVKit
import CryptoKit
import os
import SwiftUI

/// The floating guide: the setup guide's pictures in a Picture in Picture window that stays
/// over Atajos while the person builds the automation, so nobody has to switch apps to read
/// the next tap.
///
/// The pictures (the real Atajos screenshot with its brass ring and the line saying what to
/// tap) are drawn into a short video on the phone the first time, kept in the caches, and
/// played by the system's player: the same path any video app's floating window takes. A
/// sample buffer layer was tried first and the owner's iPhone never let it float (it stayed
/// «not possible», 2026-10-29). Drawn from the guide itself, it weighs nothing in the app
/// and follows the iOS version the guide follows.
///
/// The window's ⏪ / ⏩ buttons go to the previous or next picture, whatever interval the
/// system skips by. A picture with something to tap stops at its end and waits for ▶︎ (or ⏩):
/// at 8 seconds a picture, people were still tapping when it moved on (user research,
/// 2026-10-29). A result («Así debe verse») moves on by itself. Coming back to Al día lands
/// the guide on the step the window was showing.
@MainActor @Observable
final class GuideCompanion: NSObject {
    /// One picture of the floating guide.
    struct Page: Equatable {
        /// The guide's step it belongs to (0-based) and that step's title.
        let step: Int
        let stepTitle: String
        /// The step's brass symbol, drawn big when the picture has no screenshot.
        var symbol = "checkmark.circle"
        let caption: String
        /// A guide screenshot from the asset catalog, if the picture has one, and the part of
        /// it worth showing (`GuideFrame.focus`).
        var photo: String?
        var focus: CGRect?
        /// «Así debe verse»: a result, not something to tap.
        var isResult = false
    }

    /// Picture in Picture runs on this device.
    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    private(set) var pages: [Page] = []
    private(set) var index = 0
    /// The window is floating right now.
    private(set) var isFloating = false
    /// The current picture, shown under the player so the thumbnail is never black.
    private(set) var poster: UIImage?
    /// The step the window shows, for the guide to follow it.
    var step: Int { pages.indices.contains(index) ? pages[index].step : 0 }

    let player = AVPlayer()
    /// What `CompanionLayerView` puts on screen: the window floats from it.
    let layer = AVPlayerLayer()
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var possibleWatch: NSKeyValueObservation?
    @ObservationIgnored private var timeWatch: Any?
    /// Stops the player at the end of every picture with something to tap.
    @ObservationIgnored private var holdWatch: Any?
    /// Where the player was a moment ago, to tell a ⏩ / ⏪ jump from playing along.
    @ObservationIgnored private var lastTime: Double = 0
    @ObservationIgnored private var snapping = false
    /// What to open once the window floats (Atajos).
    @ObservationIgnored private var openWhenFloating: URL?
    @ObservationIgnored private var building: Task<Void, Never>?

    private var pageSeconds: Double { Theme.Motion.companionPage }

    override init() {
        super.init()
        layer.player = player
        layer.videoGravity = .resizeAspect
        player.isMuted = true
        player.actionAtItemEnd = .pause
        timeWatch = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                   queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.follow(time.seconds) }
        }
    }

    func load(_ pages: [Page]) {
        guard pages != self.pages else { return }
        self.pages = pages
        index = min(index, max(pages.count - 1, 0))
        updatePoster()
        dumpFramesIfAsked()
        building?.cancel()
        building = Task { await buildVideo() }
    }

    // MARK: Floating

    /// Floats the window on the first picture of `step`, then opens `url` (Atajos) under it;
    /// with no `url` it only floats (a preview from the thumbnail). Atajos always opens: if the
    /// window can't start, or the system never answers, it opens anyway.
    func float(from step: Int, thenOpen url: URL?) {
        if let first = pages.firstIndex(where: { $0.step == step }) { go(to: first) }
        activateAudio()
        prepareController()
        openWhenFloating = url
        CompanionDiary.write("Tocar: soportado=\(Self.isSupported) posible=\(controller?.isPictureInPicturePossible ?? false) video=\(player.currentItem?.status.rawValue ?? -1) ventana=\(layer.superlayer != nil)")
        Task { [weak self] in
            guard let self else { return }
            // The video may still be drawing the first time, and possible turns true a
            // moment after the player is ready.
            for _ in 0..<30 where !(self.controller?.isPictureInPicturePossible ?? false) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if let controller = self.controller, controller.isPictureInPicturePossible {
                CompanionDiary.write("Arrancando")
                // Playing from the first moment: the window opens already moving on by itself,
                // nobody has to find its ▶︎ (owner, 2026-10-29).
                self.player.play()
                controller.startPictureInPicture()
            } else {
                CompanionDiary.write("Nunca fue posible; se abre Atajos sin ventana")
            }
            guard url != nil else { return }
            try? await Task.sleep(for: .seconds(Theme.Motion.companionFallback))
            guard let url = self.openWhenFloating else { return }
            CompanionDiary.write("Sin respuesta a tiempo; se abre Atajos")
            self.openWhenFloating = nil
            await UIApplication.shared.open(url)
        }
    }

    func stop() {
        controller?.stopPictureInPicture()
        player.pause()
    }

    /// Picture in Picture needs a playback session: set before the controller exists.
    private func activateAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback,
                                                            options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            CompanionDiary.write("Sesión de audio: \(error.localizedDescription)")
        }
    }

    /// Prepares the controller once the layer is on screen, so starting is instant.
    func prepareController() {
        guard controller == nil, Self.isSupported, layer.superlayer != nil else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback,
                                                         options: [.mixWithOthers])
        guard let controller = AVPictureInPictureController(playerLayer: layer) else {
            CompanionDiary.write("No se pudo crear el controlador")
            return
        }
        controller.delegate = self
        controller.requiresLinearPlayback = false
        // Leaving for Atajos while the guide plays also floats it.
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller
        possibleWatch = controller.observe(\.isPictureInPicturePossible, options: [.new]) { _, change in
            let possible = change.newValue ?? false
            Task { @MainActor in CompanionDiary.write("Posible: \(possible)") }
        }
        CompanionDiary.write("Controlador listo")
    }

    // MARK: Moving

    private func go(to page: Int) {
        guard pages.indices.contains(page) else { return }
        index = page
        updatePoster()
        snapping = true
        let time = CMTime(seconds: Double(page) * pageSeconds + Theme.Motion.companionSettle,
                          preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.lastTime = time.seconds
                self?.snapping = false
            }
        }
    }

    /// Follows the player: playing along moves page by page, and a jump of the window's ⏩ / ⏪
    /// (10 or 15 seconds, the system decides) lands on the next or previous picture instead.
    private func follow(_ seconds: Double) {
        guard !snapping, seconds.isFinite, !pages.isEmpty else { return }
        let jump = seconds - lastTime
        lastTime = seconds
        if abs(jump) > Theme.Motion.companionJump {
            go(to: min(max(index + (jump > 0 ? 1 : -1), 0), pages.count - 1))
            return
        }
        let page = min(max(Int(seconds / pageSeconds), 0), pages.count - 1)
        if page != index {
            index = page
            updatePoster()
        }
    }

    private func updatePoster() {
        guard pages.indices.contains(index) else { return }
        let renderer = ImageRenderer(content: CompanionCard(pages: pages, position: index))
        renderer.proposedSize = ProposedViewSize(Theme.Size.companionCard)
        renderer.scale = Theme.Size.companionScale
        poster = renderer.uiImage
    }

    /// Debug only: `-centavo-guia-cuadros` saves every picture as a PNG in
    /// Library/Caches/guia-cuadros/, to look at the video's pictures without playing it.
    private func dumpFramesIfAsked() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-centavo-guia-cuadros"),
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }
        let folder = caches.appending(path: "guia-cuadros")
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (position, page) in pages.enumerated() {
            let renderer = ImageRenderer(content: CompanionCard(pages: pages, position: position))
            renderer.proposedSize = ProposedViewSize(Theme.Size.companionCard)
            renderer.scale = Theme.Size.companionScale
            guard let data = renderer.uiImage?.pngData() else { continue }
            try? data.write(to: folder.appending(path: String(format: "cuadro-%02d.png", position + 1)))
        }
        CompanionDiary.write("Cuadros guardados: \(pages.count)")
        #endif
    }

    // MARK: The video

    /// Draws every picture and writes them as one video in the caches, once per guide.
    private func buildVideo() async {
        let key = pages.map { "\($0.step)|\($0.caption)|\($0.photo ?? "")|\($0.focus.map { "\($0)" } ?? "")" }
            .joined(separator: "#")
        // A name that stays the same from one launch to the next (`hashValue` changes), so the
        // video is drawn once per guide; older ones are removed.
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let name = "guia-flotante-\(digest)-v5.mp4"
        guard let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let url = folder.appending(path: name)
        let old = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in old where file.hasPrefix("guia-flotante-") && file.hasSuffix(".mp4") && file != name {
            try? FileManager.default.removeItem(at: folder.appending(path: file))
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            var images: [CGImage] = []
            for (position, page) in pages.enumerated() {
                let renderer = ImageRenderer(content: CompanionCard(pages: pages, position: position))
                renderer.proposedSize = ProposedViewSize(Theme.Size.companionCard)
                renderer.scale = Theme.Size.companionScale
                guard let image = renderer.cgImage else {
                    CompanionDiary.write("No se pudo dibujar la imagen \(position)")
                    return
                }
                images.append(image)
                await Task.yield()
            }
            do {
                try await Self.writeVideo(images, seconds: pageSeconds, to: url)
                CompanionDiary.write("Video listo: \(images.count) imágenes")
            } catch {
                CompanionDiary.write("No se pudo escribir el video: \(error.localizedDescription)")
                return
            }
        }
        guard !Task.isCancelled else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        watchHolds()
        go(to: index)
    }

    /// Just before each action picture fades into the next, the player stops; ▶︎ goes on from
    /// there, past the stop. Skips (⏩ / ⏪, `go(to:)`) seek over it without stopping.
    private func watchHolds() {
        if let holdWatch { player.removeTimeObserver(holdWatch) }
        let times = pages.indices.filter { !pages[$0].isResult && $0 < pages.count - 1 }.map { position in
            NSValue(time: CMTime(seconds: Double(position + 1) * pageSeconds - Theme.Motion.companionFade
                                 - Theme.Motion.companionHold, preferredTimescale: 600))
        }
        guard !times.isEmpty else { holdWatch = nil; return }
        holdWatch = player.addBoundaryTimeObserver(forTimes: times, queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.player.rate > 0 else { return }
                self.player.pause()
            }
        }
    }

    /// One still frame per picture, each held `seconds` and fading into the next over its last
    /// `Theme.Motion.companionFade` seconds, H.264, no sound. Every picture starts clean on a
    /// multiple of `seconds`, where `follow` and `go(to:)` expect it.
    nonisolated private static func writeVideo(_ images: [CGImage], seconds: Double, to url: URL) async throws {
        guard let first = images.first else { return }
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: first.width,
            AVVideoHeightKey: first.height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: first.width,
            kCVPixelBufferHeightKey as String: first.height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        func append(_ pixels: CVPixelBuffer, at time: Double) async throws {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            adaptor.append(pixels, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
        }
        // A frame at the start of each picture and one just before the next: players hold
        // a still frame until the next one, and the last needs its end. Between the two, the
        // fade into the next picture.
        let fade = Theme.Motion.companionFade
        let steps = Theme.Motion.companionFadeSteps
        for (position, image) in images.enumerated() {
            guard let pixels = pixelBuffer(from: image) else { continue }
            let end = Double(position + 1) * seconds
            try await append(pixels, at: Double(position) * seconds)
            try await append(pixels, at: end - Theme.Motion.companionSettle)
            guard images.indices.contains(position + 1) else { continue }
            for step in 1...steps {
                let amount = Double(step) / Double(steps + 1)
                guard let blend = pixelBuffer(from: image, fadingInto: images[position + 1], by: amount)
                else { continue }
                try await append(blend, at: end - fade + fade * Double(step - 1) / Double(steps))
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: Double(images.count) * seconds, preferredTimescale: 600))
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    nonisolated private static func pixelBuffer(from image: CGImage, fadingInto next: CGImage? = nil,
                                                by amount: Double = 0) -> CVPixelBuffer? {
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true,
                          kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                          kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        var created: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height,
                            kCVPixelFormatType_32BGRA, attributes, &created)
        guard let buffer = created else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: rect)
        if let next {
            // Eased, so the fade starts and ends softly.
            let eased = amount * amount * (3 - 2 * amount)
            context.setAlpha(eased)
            context.draw(next, in: rect)
        }
        return buffer
    }

    private func endSession() {
        player.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Picture in Picture

// The window calls these on the main thread.
extension GuideCompanion: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            CompanionDiary.write("Flotando")
            isFloating = true
            if let url = openWhenFloating { UIApplication.shared.open(url) }
            openWhenFloating = nil
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: any Error) {
        let message = (error as NSError).description
        MainActor.assumeIsolated {
            CompanionDiary.write("No arrancó: \(message)")
            if let url = openWhenFloating { UIApplication.shared.open(url) }
            openWhenFloating = nil
            endSession()
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isFloating = false
            endSession()
        }
    }

    /// Coming back from the window: the guide is already following `step`, nothing to restore.
    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

/// What happened each time the floating guide was asked for, in a small file of the app's
/// own (Library/Caches/guia-flotante.log, the last 200 lines) and in the system log: Picture in
/// Picture fails without a word on some iPhones, and this is how to know why.
enum CompanionDiary {
    private static let logger = Logger(subsystem: "com.blandisc.centavo", category: "guia-flotante")

    static func write(_ line: String) {
        logger.notice("\(line, privacy: .public)")
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "guia-flotante.log") else { return }
        let stamp = Date.now.formatted(.iso8601)
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines = (old.split(separator: "\n").map(String.init) + ["\(stamp) \(line)"]).suffix(200)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Views

/// Holds the companion's player on screen: Picture in Picture only starts from a layer that is
/// in a window. The guide keeps it behind its dock, covered, so no thumbnail shows (owner,
/// 2026-10-29); the current picture sits under the player so the window never opens black.
struct CompanionLayerView: View {
    let companion: GuideCompanion

    var body: some View {
        ZStack {
            Theme.background
            if let poster = companion.poster {
                Image(uiImage: poster).resizable().scaledToFit()
            }
            PlayerLayerHost(companion: companion)
        }
    }
}

private struct PlayerLayerHost: UIViewRepresentable {
    let companion: GuideCompanion

    func makeUIView(context: Context) -> LayerHost {
        let view = LayerHost()
        view.hostCompanion = companion
        view.isUserInteractionEnabled = false
        view.layer.addSublayer(companion.layer)
        return view
    }

    func updateUIView(_ view: LayerHost, context: Context) {}

    final class LayerHost: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.forEach { $0.frame = bounds }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { hostCompanion?.prepareController() }
        }

        /// Set by the representable; read once the view is in a window.
        weak var hostCompanion: GuideCompanion?
    }
}

/// One picture of the floating guide, drawn big: it is read in a window a third of the screen
/// wide. On top, a bar with one segment per guide step (it fills as the pictures play, like
/// a story) and the step it is on; then the instruction, as big as it fits; then a stage that
/// holds the Atajos screenshot, or the step's symbol when the picture has none. A result
/// («Así debe verse») gets a brass tag and a brass edge on its stage. Nothing is ever cut:
/// a long instruction steps down a size and the screenshot shrinks to make room.
struct CompanionCard: View {
    let pages: [GuideCompanion.Page]
    let position: Int

    private var page: GuideCompanion.Page { pages[position] }
    private var stepCount: Int { (pages.map(\.step).max() ?? 0) + 1 }
    /// Pages of the current step, and how far into them this one is (1-based).
    private var stepPages: [Int] { pages.indices.filter { pages[$0].step == page.step } }
    private var stepProgress: Double {
        let done = (stepPages.firstIndex(of: position) ?? 0) + 1
        return Double(done) / Double(max(stepPages.count, 1))
    }
    private var isLast: Bool { position == pages.count - 1 }

    /// The instruction without «Así debe verse:», which the tag above it already says.
    private var instruction: String {
        let prefix = "Así debe verse:"
        guard page.isResult, page.caption.hasPrefix(prefix) else { return page.caption }
        let rest = page.caption.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                progress
                header
            }
            HeightCap(cap: Theme.Size.companionTextBudget) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    if page.isResult {
                        Label("Así debe verse", systemImage: "checkmark.circle.fill")
                            .font(Theme.Companion.tag)
                            .tracking(Theme.Tracking.tag)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.brass)
                    }
                    instructionText
                }
            }
            .layoutPriority(1)
            stage
            // The window waits on these (`watchHolds`): say how to go on.
            if !page.isResult && !isLast {
                Text("Al terminar, toca \(Image(systemName: "play.fill"))")
                    .font(Theme.Companion.tag)
                    .foregroundStyle(Theme.brass)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: Theme.Size.companionCard.width, height: Theme.Size.companionCard.height,
               alignment: .topLeading)
        .background(Theme.background)
        .environment(\.dynamicTypeSize, .large)
    }

    /// One segment per step: the ones done in brass, the current one filling with its pictures.
    private var progress: some View {
        HStack(spacing: Theme.Space.xxs) {
            ForEach(0..<stepCount, id: \.self) { step in
                Capsule()
                    .fill(Theme.raised)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Theme.brass)
                                .frame(width: proxy.size.width * fill(of: step))
                        }
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: Theme.Size.companionProgress)
    }

    private func fill(of step: Int) -> Double {
        if step < page.step { return 1 }
        return step == page.step ? stepProgress : 0
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxxs) {
            Text("Paso \(page.step + 1) de \(stepCount)")
                .font(Theme.Companion.stepNumber)
                .tracking(Theme.Tracking.label)
                .textCase(.uppercase)
                .foregroundStyle(Theme.brass)
            Text(page.stepTitle)
                .font(Theme.Companion.stepTitle)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The biggest size of the instruction that fits its budget.
    private var instructionText: some View {
        ViewThatFits(in: .vertical) {
            ForEach(Theme.Companion.instruction.indices, id: \.self) { size in
                Text(instruction)
                    .font(Theme.Companion.instruction[size])
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The part of the screenshot worth showing, as big as the stage allows, with its frame
    /// hugging it (no empty band of stage around it); or, when the picture has none, the
    /// step's emblem ringed in brass, as the screenshots ring what to tap. Either way it sits
    /// centred in the room the text leaves.
    private var stage: some View {
        Group {
            if let photo = page.photo, let image = Self.crop(photo, to: page.focus) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .strokeBorder(page.isResult ? Theme.brass : Theme.hairline,
                                          lineWidth: page.isResult ? Theme.Stroke.strong : Theme.Stroke.hairline)
                    }
            } else {
                Image(systemName: isLast ? "arrow.uturn.backward" : page.symbol)
                    .font(Theme.Symbol.companionStage)
                    .foregroundStyle(Theme.brass)
                    .frame(width: Theme.Size.companionEmblem, height: Theme.Size.companionEmblem)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .strokeBorder(Theme.brass, lineWidth: Theme.Stroke.strong)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `focus` of the named screenshot, in its own pixels; the whole one when there is none.
    private static func crop(_ name: String, to focus: CGRect?) -> CGImage? {
        guard let image = UIImage(named: name)?.cgImage else { return nil }
        guard let focus else { return image }
        let size = CGSize(width: image.width, height: image.height)
        let rect = CGRect(x: focus.minX * size.width, y: focus.minY * size.height,
                          width: focus.width * size.width, height: focus.height * size.height)
            .integral.intersection(CGRect(origin: .zero, size: size))
        return image.cropping(to: rect) ?? image
    }
}

/// Offers its content at most `cap` of height and takes the content's own size: unlike
/// `.frame(maxHeight:)`, which grows to the cap, a short instruction stays short.
private struct HeightCap: Layout {
    let cap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(capped(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: capped(ProposedViewSize(bounds.size)))
    }

    private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width, height: min(proposal.height ?? cap, cap))
    }
}

#Preview("Guía flotante") {
    CompanionCard(pages: [.init(step: 0, stepTitle: "Crea un atajo nuevo", caption: "Abre Atajos."),
                          .init(step: 1, stepTitle: "Que se active con una notificación", symbol: "bell.badge.fill",
                                caption: "Toca «Notificación», en la sección Apps.",
                                photo: "guia27-03-notificacion")],
                  position: 1)
        .ticketPreview()
}
