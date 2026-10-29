import AVFoundation
import AVKit
import os
import SwiftUI

/// The floating guide: the setup guide's pictures in a Picture in Picture window that stays
/// over Atajos while the person builds the automation, so nobody has to switch apps to read
/// the next tap.
///
/// It is not a recorded video. Each picture of the guide (the real Atajos screenshot with its
/// brass ring and the line saying what to tap) is drawn into a frame and shown on a sample
/// buffer layer, the kind of layer Picture in Picture can float. So it always matches the
/// guide in the app, weighs nothing extra and follows the iOS version the guide follows.
///
/// The window's ⏪ / ⏩ buttons go to the previous or next picture; ▶︎ moves on by itself every
/// `Theme.Motion.companionPage` seconds. Coming back to Al día from the window opens the guide
/// on the step the window was showing.
@MainActor @Observable
final class GuideCompanion: NSObject {
    /// One picture of the floating guide.
    struct Page: Equatable {
        /// The guide's step it belongs to (0-based) and that step's title.
        let step: Int
        let stepTitle: String
        let caption: String
        /// A guide screenshot from the asset catalog, if the picture has one.
        var photo: String?
        /// «Así debe verse»: a result, not something to tap.
        var isResult = false
    }

    /// Picture in Picture runs on this device (every iPhone with iOS 18 does; the check
    /// keeps the button away where it would not).
    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    private(set) var pages: [Page] = []
    private(set) var index = 0
    /// The window is floating right now.
    private(set) var isFloating = false
    private(set) var isPlaying = false
    /// The step the window shows, for the guide to follow it.
    var step: Int { pages.indices.contains(index) ? pages[index].step : 0 }

    /// What the layer shows; `CompanionLayerView` puts it on screen so the window can start.
    let layer = AVSampleBufferDisplayLayer()
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var timebase: CMTimebase?
    @ObservationIgnored private var autoAdvance: Task<Void, Never>?
    /// What to open once the window floats (Atajos).
    @ObservationIgnored private var openWhenFloating: URL?

    func load(_ pages: [Page]) {
        guard pages != self.pages else { return }
        self.pages = pages
        index = min(index, max(pages.count - 1, 0))
        show()
    }

    /// Floats the window on the first picture of `step`, then opens `url` (Atajos) under it;
    /// with no `url` it only floats (a preview from the thumbnail). Atajos always opens: if the
    /// window can't start, or the system never answers, it opens anyway (on the owner's iPhone
    /// a start went unanswered and nothing opened, 2026-10-29).
    func float(from step: Int, thenOpen url: URL?) {
        if let first = pages.firstIndex(where: { $0.step == step }) { index = first }
        show()
        activateAudio()
        prepareController()
        openWhenFloating = url
        CompanionDiary.write("Tocar: soportado=\(Self.isSupported) posible=\(controller?.isPictureInPicturePossible ?? false) capa=\(layer.sampleBufferRenderer.status.rawValue) error=\(layer.sampleBufferRenderer.error?.localizedDescription ?? "-") ventana=\(layer.superlayer != nil)")
        Task { [weak self] in
            guard let self else { return }
            // Possible can turn true a moment after the layer gets its first picture.
            for _ in 0..<10 where !(self.controller?.isPictureInPicturePossible ?? false) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if let controller = self.controller, controller.isPictureInPicturePossible {
                CompanionDiary.write("Arrancando")
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

    /// Picture in Picture needs a playback session, set before the controller exists: made
    /// after, the controller can stay «not possible».
    private func activateAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback,
                                                            options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            CompanionDiary.write("Sesión de audio: \(error.localizedDescription)")
        }
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    /// Prepares the controller as soon as the layer is on screen, so starting is instant.
    func prepareController() {
        guard controller == nil, Self.isSupported else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback,
                                                         options: [.mixWithOthers])
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer,
                                                                playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.requiresLinearPlayback = false
        self.controller = controller
        CompanionDiary.write("Controlador listo")
    }

    // MARK: Moving

    func move(by offset: Int) {
        let target = min(max(index + offset, 0), pages.count - 1)
        guard target != index else { return }
        index = target
        show()
    }

    private func setPlaying(_ playing: Bool) {
        isPlaying = playing
        autoAdvance?.cancel()
        if playing {
            autoAdvance = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Theme.Motion.companionPage))
                    guard let self, !Task.isCancelled else { return }
                    if self.index >= self.pages.count - 1 { self.setPlaying(false); return }
                    self.move(by: 1)
                }
            }
        }
        syncTimebase()
        controller?.invalidatePlaybackState()
    }

    // MARK: Drawing

    /// Draws the current picture and puts it on the layer.
    private func show() {
        guard pages.indices.contains(index) else { return }
        guard let buffer = Self.sampleBuffer(for: pages[index], position: index, of: pages.count,
                                             at: time(of: index)) else {
            CompanionDiary.write("No se pudo dibujar la imagen \(index)")
            return
        }
        syncTimebase()
        layer.sampleBufferRenderer.flush()
        layer.sampleBufferRenderer.enqueue(buffer)
        controller?.invalidatePlaybackState()
    }

    private func time(of page: Int) -> CMTime {
        CMTime(seconds: Double(page) * Theme.Motion.companionPage, preferredTimescale: 600)
    }

    /// The window's progress bar follows the picture: each one is a slice of the «video».
    private func syncTimebase() {
        if timebase == nil {
            var created: CMTimebase?
            CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
                                            sourceClock: CMClockGetHostTimeClock(),
                                            timebaseOut: &created)
            timebase = created
            layer.controlTimebase = created
        }
        guard let timebase else { return }
        CMTimebaseSetTime(timebase, time: time(of: index))
        CMTimebaseSetRate(timebase, rate: isPlaying ? 1 : 0)
    }

    private static func sampleBuffer(for page: Page, position: Int, of count: Int,
                                     at time: CMTime) -> CMSampleBuffer? {
        let renderer = ImageRenderer(content: CompanionCard(page: page, position: position, count: count))
        renderer.proposedSize = ProposedViewSize(Theme.Size.companionCard)
        renderer.scale = Theme.Size.companionScale
        guard let image = renderer.cgImage, let pixels = pixelBuffer(from: image) else { return nil }
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels,
                                                     formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var buffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels,
                                                 formatDescription: format, sampleTiming: &timing,
                                                 sampleBufferOut: &buffer)
        guard let buffer else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return buffer
    }

    private static func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
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
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    private func endSession() {
        setPlaying(false)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Picture in Picture

// The window calls these on the main thread.
extension GuideCompanion: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                setPlaying playing: Bool) {
        MainActor.assumeIsolated { setPlaying(playing) }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ controller: AVPictureInPictureController) -> CMTimeRange {
        MainActor.assumeIsolated {
            CMTimeRange(start: .zero, duration: time(of: max(pages.count, 1))) // ds-allow: at least one picture long, not a layout value
        }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ controller: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { !isPlaying }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    /// ⏪ and ⏩: one picture back or forward, whatever interval the window says.
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        let back = skipInterval.seconds < 0
        MainActor.assumeIsolated { move(by: back ? -1 : 1) }
        completionHandler()
    }
}

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

/// Holds the companion's layer on screen: Picture in Picture only starts from a layer that is
/// in a window. Shown as the thumbnail of the floating guide on each guide step.
struct CompanionLayerView: UIViewRepresentable {
    let companion: GuideCompanion

    func makeUIView(context: Context) -> LayerHost {
        let view = LayerHost()
        companion.layer.videoGravity = .resizeAspect
        view.layer.addSublayer(companion.layer)
        companion.prepareController()
        return view
    }

    func updateUIView(_ view: LayerHost, context: Context) {}

    final class LayerHost: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.forEach { $0.frame = bounds }
        }
    }
}

/// One picture of the floating guide, drawn big: it is read in a window a third of the screen
/// wide. The step and the line saying what to do on top, the Atajos screenshot under it.
struct CompanionCard: View {
    let page: GuideCompanion.Page
    let position: Int
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text(page.stepTitle).ticketCaption().lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                Text("\(position + 1)/\(count)")
                    .font(.ticket(.captionStrong))
                    .foregroundStyle(Theme.brass)
                    .monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                if page.isResult {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.brass)
                }
                Text(page.caption)
                    .font(.ticket(.subheading))
                    .foregroundStyle(page.isResult ? Theme.muted : Theme.ink)
                    .lineLimit(5)
                    .minimumScaleFactor(Theme.MinimumScale.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let photo = page.photo {
                Image(photo)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: Theme.Space.none)
            }
            Label(position + 1 < count ? "⏩ siguiente toque" : "Vuelve a Al día", systemImage: "hand.tap")
                .font(.ticket(.caption))
                .foregroundStyle(Theme.faint)
        }
        .padding(Theme.Space.l)
        .frame(width: Theme.Size.companionCard.width, height: Theme.Size.companionCard.height,
               alignment: .topLeading)
        .background(Theme.background)
        .environment(\.dynamicTypeSize, .large)
    }
}

#Preview("Guía flotante") {
    CompanionCard(page: .init(step: 1, stepTitle: "Que se active con una notificación",
                              caption: "Toca «Notificación», en la sección Apps.",
                              photo: "guia27-03-notificacion"),
                  position: 2, count: 18)
        .ticketPreview()
}
