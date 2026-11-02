import SwiftUI

// The drawings of «Mi dinero»'s first time (2026-11-01), in the app's own language: hairlines,
// the ticket's dashes, the boleto's cells and one brass. Each is a Canvas driven by a clock,
// drawn in a small design space (the numbers in `Geo`) and scaled to fit. They loop slowly a few
// times, then rest, and never bounce; with «Reducir movimiento» each one stands still at its most telling moment.

/// Where a loop is, 0…1, from the clock; `rest` when motion is reduced. It turns `loops` times
/// and stops on `rest` (audit 2026-11-02: nothing runs forever), so the last turn ends where the
/// still drawing stands, with no jump.
struct MoneyLoopClock<Content: View>: View {
    let cycle: Double
    let rest: Double
    var loops = Theme.Motion.Money.loops
    @ViewBuilder let content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var done = false

    private var still: Bool { MotionPolicy.isStill(reduceMotion: reduceMotion) }
    /// Seconds until the last turn reaches `rest`.
    private var runs: Double { (Double(max(loops, 1) - 1) + rest) * cycle }

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Motion.Money.frameInterval, paused: still || done)) { context in
            content(phase(at: context.date))
        }
        // Shown still, it stays on its last frame for good: turning low power off later never
        // jumps into the middle of a turn. Gone still while turning (low power on, then off),
        // the same: once at rest it stays at rest (second audit, 2026-11-02).
        .onAppear { if start == nil { if still { done = true } else { start = AppClock.now } } }
        .onChange(of: still) { _, now in if now { done = true } }
        .task(id: start) {
            guard let start else { return }
            let left = runs - AppClock.now.timeIntervalSince(start)
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            guard !Task.isCancelled else { return }
            done = true
        }
    }

    private func phase(at date: Date) -> Double {
        guard !still, !done, let start else { return rest }
        let elapsed = date.timeIntervalSince(start)
        guard elapsed < runs else { return rest }
        return elapsed.truncatingRemainder(dividingBy: cycle) / cycle
    }
}

/// Smooth in and out, no overshoot.
func moneyEase(_ x: Double) -> Double {
    let t = min(max(x, 0), 1)
    return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

/// How far along `t` is between `from` and `to`, eased.
func moneySpan(_ t: Double, _ from: Double, _ to: Double) -> Double { moneyEase((t - from) / (to - from)) }

/// Rises over `inFrom…inTo`, holds, and falls over `outFrom…outTo`.
func moneyRise(_ t: Double, _ inFrom: Double, _ inTo: Double, _ outFrom: Double, _ outTo: Double) -> Double {
    moneySpan(t, inFrom, inTo) * (1 - moneySpan(t, outFrom, outTo))
}

/// The design space of a drawing, scaled into the space it was given and centered.
func artFit(_ context: inout GraphicsContext, _ size: CGSize, design: CGSize) {
    let scale = min(size.width / design.width, size.height / design.height)
    context.translateBy(x: (size.width - design.width * scale) / 2, y: (size.height - design.height * scale) / 2)
    context.scaleBy(x: scale, y: scale)
}

enum ArtGeo {
    static let hair: CGFloat = 1.3
    static let line: CGFloat = 1.6
    static let bold: CGFloat = 3
    static let cellCorner: CGFloat = 1.5
    static let dash: [CGFloat] = [3, 3]
    static let ring: [CGFloat] = [5, 6]
    static let soft: Double = 0.18
    static let glow: Double = 0.14
    static let label: CGFloat = 7
}

func artStroke(_ color: Color, _ lw: CGFloat = ArtGeo.hair, dash: [CGFloat] = []) -> StrokeStyle {
    StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round, dash: dash)
}

func artCell(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
    Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: ArtGeo.cellCorner)
}


// MARK: - The welcome: your net worth, month by month

/// The welcome's boleto: a cell per month, each a little taller, filling left to right at `t`.
struct MoneyGrowthBars: View {
    /// Example heights, oldest first: a year that grows.
    static let months: [Double] = [0.38, 0.41, 0.40, 0.46, 0.50, 0.49, 0.55, 0.60, 0.63, 0.69, 0.76, 0.88]
    let t: Double

    var body: some View {
        Canvas { context, size in
            let count = Self.months.count
            let gap = Theme.Size.moneyHeroCellGap
            let w = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            for (i, height) in Self.months.enumerated() {
                let x = CGFloat(i) * (w + gap)
                let fill = moneyRise(t, 0.06 + Double(i) * 0.017, 0.34 + Double(i) * 0.017, 0.80, 0.96)
                let h = size.height * height * fill
                context.fill(artCell(x, size.height - h, w, h), with: .color(Theme.brass))
                context.stroke(artCell(x, 0, w, size.height), with: .color(i == count - 1 ? Theme.ink : Theme.hairline),
                               style: artStroke(Theme.hairline))
            }
        }
    }
}

// MARK: - The kinds

/// What each kind of line is, drawn small on its card.
enum MoneyArtKind: String, CaseIterable {
    case account, investment, card, loan, other, lent, coming
    /// «¿Lo tienes en Excel?»: a sheet whose rows fly into the ticket.
    case excel

    /// Where each drawing rests, whole and clean (second audit, 2026-11-02): every part drawn,
    /// nothing mid-flight. One `rest` for all left a ring frozen halfway in `coming`, the third
    /// cell almost empty in `excel` and the chip at 60 % in `card`.
    var rest: Double {
        switch self {
        case .account, .investment, .loan, .other: 0.6
        case .card: 0.25        // the chip's glow at its fullest
        case .lent: 0.9         // the coin back home, at full
        case .excel: 0.75       // the three cells filled, nothing flying
        case .coming: 0.8       // the days passed, the coin landed, the ping gone
        }
    }
}

struct MoneyKindArt: View {
    let kind: MoneyArtKind

    var body: some View {
        MoneyLoopClock(cycle: Theme.Motion.Money.kindCycle, rest: kind.rest) { t in
            Canvas { context, size in
                var context = context
                switch kind {
                case .account: account(&context, size, t)
                case .investment: investment(&context, size, t)
                case .card: card(&context, size, t)
                case .loan: loan(&context, size, t)
                case .other: other(&context, size, t)
                case .lent: lent(&context, size, t)
                case .coming: coming(&context, size, t)
                case .excel: excel(&context, size, t)
                }
            }
        }
        .frame(height: Theme.Size.moneyKindArt)
        .accessibilityHidden(true)
    }

    /// The boleto fills: money that is yours today.
    private func account(_ c: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        artFit(&c, size, design: CGSize(width: 120, height: 62))
        c.stroke(Path(roundedRect: CGRect(x: 18, y: 8, width: 84, height: 46), cornerRadius: 4),
                 with: .color(Theme.outline), style: artStroke(Theme.outline, dash: ArtGeo.dash))
        let empty: [CGFloat] = [10, 4, 14, 0, 8]
        for i in 0..<5 {
            let x = 26 + CGFloat(i) * 14
            c.stroke(artCell(x, 18, 10, 28), with: .color(Theme.outline), style: artStroke(Theme.outline))
            let full = 28 - empty[i]
            let h = full * moneyRise(t, 0.08 + Double(i) * 0.04, 0.35 + Double(i) * 0.04, 0.82, 0.96)
            c.fill(artCell(x, 46 - h, 10, h), with: .color(Theme.brass))
        }
    }

    /// A fine line goes up and down.
    private func investment(_ c: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        artFit(&c, size, design: CGSize(width: 120, height: 62))
        for y: CGFloat in [50, 30] {
            var guide = Path(); guide.move(to: CGPoint(x: 14, y: y)); guide.addLine(to: CGPoint(x: 106, y: y))
            c.stroke(guide, with: .color(Theme.outline.opacity(y == 50 ? 1 : 0.5)), style: artStroke(Theme.outline, dash: ArtGeo.dash))
        }
        let points: [CGPoint] = [.init(x: 14, y: 46), .init(x: 30, y: 38), .init(x: 44, y: 42), .init(x: 60, y: 24),
                                 .init(x: 74, y: 30), .init(x: 90, y: 14), .init(x: 106, y: 18)]
        var line = Path(); line.addLines(points)
        let drawn = moneySpan(t, 0, 0.45)
        let fade = 1 - moneySpan(t, 0.85, 1)
        c.stroke(line.trimmedPath(from: 0, to: drawn), with: .color(Theme.brass.opacity(fade)), style: artStroke(Theme.brass, ArtGeo.line))
        let dot = moneyRise(t, 0.45, 0.5, 0.85, 1)
        c.fill(Path(ellipseIn: CGRect(x: 102.8, y: 14.8, width: 6.4, height: 6.4)), with: .color(Theme.brass.opacity(dot)))
    }

    /// A hairline card, its brass chip glowing slowly.
    private func card(_ c: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        artFit(&c, size, design: CGSize(width: 80, height: 62))
        c.stroke(Path(roundedRect: CGRect(x: 10, y: 12, width: 60, height: 38), cornerRadius: 5),
                 with: .color(Theme.outline), style: artStroke(Theme.outline))
        let glow = 0.75 + 0.25 * sin(t * 2 * .pi)
        c.fill(Path(roundedRect: CGRect(x: 17, y: 21, width: 11, height: 8), cornerRadius: 1.5), with: .color(Theme.brass.opacity(glow)))
        var stripe = Path(); stripe.move(to: CGPoint(x: 17, y: 41)); stripe.addLine(to: CGPoint(x: 63, y: 41))
        c.stroke(stripe, with: .color(Theme.outline), style: artStroke(Theme.outline, dash: ArtGeo.dash))
    }

    /// Payments, crossed off one by one.
    private func loan(_ c: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        artFit(&c, size, design: CGSize(width: 80, height: 62))
        for i in 0..<5 {
            let x = 10 + CGFloat(i) * 12.5
            c.stroke(artCell(x, 16, 9, 30), with: .color(Theme.outline), style: artStroke(Theme.outline))
            guard i < 3 else { continue }
            var cross = Path(); cross.move(to: CGPoint(x: x - 1, y: 48)); cross.addLine(to: CGPoint(x: x + 10, y: 14))
            let drawn = moneyRise(t, 0.10 + Double(i) * 0.08, 0.30 + Double(i) * 0.08, 0.86, 1)
            c.stroke(cross.trimmedPath(from: 0, to: drawn), with: .color(Theme.brass), style: artStroke(Theme.brass))
        }
    }

    /// A receipt prints.
    private func other(_ c: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        artFit(&c, size, design: CGSize(width: 80, height: 62))
        var slot = Path(); slot.move(to: CGPoint(x: 20, y: 8)); slot.addLine(to: CGPoint(x: 60, y: 8))
        c.stroke(slot, with: .color(Theme.outline), style: artStroke(Theme.outline))
        let shown = moneyRise(t, 0, 0.45, 0.85, 1)
        var paper = c
        paper.clip(to: Path(CGRect(x: 0, y: 8, width: 80, height: 54)))
        paper.translateBy(x: 0, y: -28 * (1 - moneySpan(t, 0, 0.45)))
        paper.opacity = shown
        var receipt = Path()
        receipt.move(to: CGPoint(x: 24, y: 8)); receipt.addLine(to: CGPoint(x: 24, y: 48))
        for i in 0..<8 { receipt.addLine(to: CGPoint(x: 28 + CGFloat(i) * 4, y: i.isMultiple(of: 2) ? 52 : 48)) }
        receipt.addLine(to: CGPoint(x: 56, y: 48)); receipt.addLine(to: CGPoint(x: 56, y: 8))
        paper.stroke(receipt, with: .color(Theme.outline), style: artStroke(Theme.outline))
        for (y, end) in [(18.0, 51.0), (26, 51), (34, 44)] as [(CGFloat, CGFloat)] {
            var row = Path(); row.move(to: CGPoint(x: 29, y: y)); row.addLine(to: CGPoint(x: end, y: y))
            paper.stroke(row, with: .color(Theme.outline), style: artStroke(Theme.outline, dash: ArtGeo.dash))
        }
        paper.fill(Path(roundedRect: CGRect(x: 45, y: 38, width: 7, height: 3), cornerRadius: 1), with: .color(Theme.brass))
    }

    /// From you to Ana, and the dashed way back.
    private func lent(_ c: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        artFit(&c, size, design: CGSize(width: 120, height: 62))
        for x: CGFloat in [22, 98] {
            c.stroke(Path(ellipseIn: CGRect(x: x - 9, y: 19, width: 18, height: 18)), with: .color(Theme.outline), style: artStroke(Theme.outline))
        }
        var back = Path(); back.move(to: CGPoint(x: 88, y: 40)); back.addQuadCurve(to: CGPoint(x: 32, y: 40), control: CGPoint(x: 60, y: 56))
        let phase = CGFloat(t * 4).truncatingRemainder(dividingBy: 1) * -6
        c.stroke(back, with: .color(Theme.brass), style: StrokeStyle(lineWidth: ArtGeo.hair, lineCap: .round, dash: ArtGeo.dash, dashPhase: phase))
        // Out to Ana, a pause, and home.
        let out = moneySpan(t, 0.08, 0.38), home = moneySpan(t, 0.56, 0.86)
        let x = 22 + 76 * out - 76 * home
        let dim = t > 0.38 && t < 0.56 ? 0.35 : 1
        c.fill(Path(ellipseIn: CGRect(x: x - 5, y: 23, width: 10, height: 10)), with: .color(Theme.brass.opacity(dim)))
    }

    /// A hairline spreadsheet: a brass row walks down it, its rows fly into the dashed ticket
    /// and fill its cells.
    private func excel(_ c: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        artFit(&c, size, design: CGSize(width: 110, height: 58))
        let sheet = CGRect(x: 6, y: 8, width: 44, height: 40)
        c.stroke(Path(roundedRect: sheet, cornerRadius: 3), with: .color(Theme.outline), style: artStroke(Theme.outline))
        for y: CGFloat in [18, 28, 38] {
            var row = Path(); row.move(to: CGPoint(x: 6, y: y)); row.addLine(to: CGPoint(x: 50, y: y))
            c.stroke(row, with: .color(Theme.outline), style: artStroke(Theme.outline))
        }
        for x: CGFloat in [20, 35] {
            var column = Path(); column.move(to: CGPoint(x: x, y: 8)); column.addLine(to: CGPoint(x: x, y: 48))
            c.stroke(column, with: .color(Theme.outline), style: artStroke(Theme.outline))
        }
        // The highlight walks the three rows.
        let walk = moneySpan(t, 0.08, 0.50)
        let shown = moneyRise(t, 0.04, 0.10, 0.52, 0.60)
        c.fill(Path(CGRect(x: 6.6, y: 18.6 + 20 * walk, width: 42.8, height: 8.8)),
               with: .color(Theme.brass.opacity(ArtGeo.soft * 1.2 * shown)))
        // Each row's figure flies right into the ticket, and its cell fills.
        c.stroke(Path(roundedRect: CGRect(x: 62, y: 8, width: 42, height: 40), cornerRadius: 3),
                 with: .color(Theme.outline), style: artStroke(Theme.outline, dash: ArtGeo.dash))
        let heights: [CGFloat] = [18, 22, 14]
        for i in 0..<3 {
            let start = 0.14 + Double(i) * 0.12
            let fly = moneySpan(t, start, start + 0.22)
            let visible = t > start && fly < 1
            if visible {
                let x = 40 + 30 * CGFloat(fly) + CGFloat(i) * 11 * CGFloat(fly)
                c.fill(Path(roundedRect: CGRect(x: x, y: 21 + CGFloat(i) * 8 * CGFloat(1 - fly), width: 8, height: 4), cornerRadius: 1),
                       with: .color(Theme.brass))
            }
            let cellX = 68 + CGFloat(i) * 11
            c.stroke(artCell(cellX, 16, 8, 26), with: .color(Theme.outline), style: artStroke(Theme.outline))
            let filled = moneyRise(t, start + 0.20, start + 0.30, 0.86, 0.98)
            let h = heights[i] * filled
            c.fill(artCell(cellX, 42 - h, 8, h), with: .color(Theme.brass))
        }
    }

    /// «Hoy» stays put; the days pass; a coin lands on the day it arrives, which stays marked.
    private func coming(_ c: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        artFit(&c, size, design: CGSize(width: 120, height: 62))
        c.stroke(artCell(10, 24, 10, 16), with: .color(Theme.ink), style: artStroke(Theme.ink))
        for i in 1...5 {
            let x = 10 + CGFloat(i) * 14
            let passed = moneyRise(t, Double(i - 1) * 0.06 + 0.04, Double(i - 1) * 0.06 + 0.10, 0.90, 1)
            c.fill(artCell(x, 24, 10, 16), with: .color(Theme.brassMid.opacity(ArtGeo.soft * passed)))
            c.stroke(artCell(x, 24, 10, 16), with: .color(passed > 0.5 ? Theme.brassMid : Theme.outline), style: artStroke(Theme.outline))
        }
        let landed = moneyRise(t, 0.54, 0.56, 0.92, 1)
        let day = artCell(94, 24, 10, 16)
        c.stroke(day, with: .color(landed > 0.5 ? Theme.brass : Theme.outline), style: artStroke(Theme.brass))
        // Dotted, as if marked with a pencil.
        let dots = moneyRise(t, 0.54, 0.64, 0.92, 1)
        if dots > 0 {
            for row in 0..<5 { for col in 0..<3 {
                let dot = CGRect(x: 96 + CGFloat(col) * 3, y: 26 + CGFloat(row) * 3, width: 1.4, height: 1.4)
                c.fill(Path(ellipseIn: dot), with: .color(Theme.brass.opacity(dots)))
            } }
        }
        // The coin falls, with weight, and is gone where it lands.
        let fall = min(max((t - 0.42) / 0.12, 0), 1)
        if t > 0.42 && t < 0.58 {
            let y = 20 - 22 * (1 - fall * fall)
            c.fill(Path(ellipseIn: CGRect(x: 95.4, y: y - 3.6, width: 7.2, height: 7.2)), with: .color(Theme.brass))
        }
        // The ping.
        let ping = moneySpan(t, 0.54, 0.72)
        if t > 0.54 && t < 0.72 {
            let r = 4.8 + 10.4 * ping
            c.stroke(Path(ellipseIn: CGRect(x: 99 - r, y: 32 - r, width: r * 2, height: r * 2)),
                     with: .color(Theme.brass.opacity(0.9 * (1 - ping))), style: artStroke(Theme.brass))
        }
    }
}

// MARK: - Face ID

/// The Face ID mark drawn with hairlines: the face traces itself, a line of light passes, and the
/// face turns into a check while the corners go brass.
struct MoneyFaceIDArt: View {
    var body: some View {
        // At rest: the check drawn, the corners brass, the pulse gone (0.75 left a faint ring).
        MoneyLoopClock(cycle: Theme.Motion.Money.faceCycle, rest: 0.88) { t in
            Canvas { context, size in
                var c = context
                artFit(&c, size, design: CGSize(width: 150, height: 150))
                let brass = moneySpan(t, 0.52, 0.60) * (1 - moneySpan(t, 0.92, 1))
                let corner = brass > 0.5 ? Theme.brass : Theme.outline
                let corners: [[CGPoint]] = [
                    [.init(x: 30, y: 52), .init(x: 30, y: 30), .init(x: 52, y: 30)],
                    [.init(x: 98, y: 30), .init(x: 120, y: 30), .init(x: 120, y: 52)],
                    [.init(x: 30, y: 98), .init(x: 30, y: 120), .init(x: 52, y: 120)],
                    [.init(x: 98, y: 120), .init(x: 120, y: 120), .init(x: 120, y: 98)],
                ]
                for points in corners {
                    var path = Path(); path.move(to: points[0])
                    path.addArc(tangent1End: points[1], tangent2End: points[2], radius: 10)
                    path.addLine(to: points[2])
                    c.stroke(path, with: .color(corner), style: artStroke(corner, ArtGeo.bold))
                }
                var features: [Path] = []
                var eye1 = Path(); eye1.move(to: .init(x: 58, y: 60)); eye1.addLine(to: .init(x: 58, y: 68)); features.append(eye1)
                var eye2 = Path(); eye2.move(to: .init(x: 92, y: 60)); eye2.addLine(to: .init(x: 92, y: 68)); features.append(eye2)
                var nose = Path(); nose.move(to: .init(x: 76, y: 60)); nose.addLine(to: .init(x: 76, y: 84)); nose.addLine(to: .init(x: 70, y: 84)); features.append(nose)
                var smile = Path(); smile.move(to: .init(x: 60, y: 94)); smile.addQuadCurve(to: .init(x: 90, y: 94), control: .init(x: 75, y: 104)); features.append(smile)
                let gone = 1 - moneySpan(t, 0.52, 0.60)
                for (i, path) in features.enumerated() {
                    let drawn = moneySpan(t, 0.08 + Double(i) * 0.03, 0.28 + Double(i) * 0.03)
                    c.stroke(path.trimmedPath(from: 0, to: drawn), with: .color(Theme.ink.opacity(gone)), style: artStroke(Theme.ink, ArtGeo.bold))
                }
                if t > 0.22 && t < 0.54 {
                    let y = 27 + 96 * moneySpan(t, 0.24, 0.50)
                    var scan = Path(); scan.move(to: .init(x: 34, y: y)); scan.addLine(to: .init(x: 116, y: y))
                    c.stroke(scan, with: .linearGradient(Gradient(colors: [Theme.brass.opacity(0), Theme.brass, Theme.brass.opacity(0)]),
                                                         startPoint: .init(x: 34, y: y), endPoint: .init(x: 116, y: y)),
                             style: artStroke(Theme.brass, ArtGeo.line))
                }
                var check = Path(); check.move(to: .init(x: 58, y: 76)); check.addLine(to: .init(x: 70, y: 88)); check.addLine(to: .init(x: 93, y: 62))
                let checked = moneySpan(t, 0.58, 0.70) * (1 - moneySpan(t, 0.92, 1))
                c.stroke(check.trimmedPath(from: 0, to: checked), with: .color(Theme.brass), style: artStroke(Theme.brass, ArtGeo.bold + 1))
                let pulse = moneySpan(t, 0.60, 0.86)
                if t > 0.60 && t < 0.86 {
                    let r = 63 + 19 * pulse
                    c.stroke(Path(ellipseIn: CGRect(x: 75 - r, y: 75 - r, width: r * 2, height: r * 2)),
                             with: .color(Theme.brass.opacity(0.6 * (1 - pulse))), style: artStroke(Theme.brass))
                }
            }
        }
        .frame(width: Theme.Size.moneyFaceArt, height: Theme.Size.moneyFaceArt)
        .accessibilityHidden(true)
    }
}

// MARK: - Success

/// The dashed ring turns a little and closes in brass, like a ticket completed; a faint glow,
/// the check in one stroke, and eight short rays that show and go. Plays once and stays.
struct MoneySuccessArt: View {
    @State private var start = AppClock.now
    @State private var played = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Motion.Money.frameInterval,
                                paused: MotionPolicy.isStill(reduceMotion: reduceMotion) || played)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let t = MotionPolicy.isStill(reduceMotion: reduceMotion) || played ? 1 : min(elapsed / Theme.Motion.Money.success, 1)
            Canvas { context, size in
                var c = context
                artFit(&c, size, design: CGSize(width: 132, height: 132))
                let center = CGPoint(x: 66, y: 66)
                let glow = moneyRise(t, 0.30, 0.45, 0.6, 0.9)
                c.fill(Path(ellipseIn: CGRect(x: 12, y: 12, width: 108, height: 108)), with: .color(Theme.brass.opacity(ArtGeo.glow * glow)))
                var dashed = c
                dashed.translateBy(x: center.x, y: center.y)
                dashed.rotate(by: .degrees(40 * moneySpan(t, 0, 0.4)))
                dashed.translateBy(x: -center.x, y: -center.y)
                dashed.stroke(Path(ellipseIn: CGRect(x: 14, y: 14, width: 104, height: 104)), with: .color(Theme.outline),
                              style: artStroke(Theme.outline, ArtGeo.line, dash: ArtGeo.ring))
                var ring = Path()
                ring.addArc(center: center, radius: 52, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
                c.stroke(ring.trimmedPath(from: 0, to: moneySpan(t, 0.06, 0.45)), with: .color(Theme.brass), style: artStroke(Theme.brass, ArtGeo.line + 1))
                var tick = Path(); tick.move(to: .init(x: 44, y: 68)); tick.addLine(to: .init(x: 59, y: 83)); tick.addLine(to: .init(x: 90, y: 50))
                c.stroke(tick.trimmedPath(from: 0, to: moneySpan(t, 0.40, 0.65)), with: .color(Theme.brass), style: artStroke(Theme.brass, ArtGeo.bold + 2))
                let rays = moneySpan(t, 0.62, 0.9)
                if t > 0.62 && t < 0.92 {
                    for i in 0..<8 {
                        let angle = Double(i) * .pi / 4
                        let inner = 62 + 6 * rays, outer = inner + 7 * (1 - rays)
                        var ray = Path()
                        ray.move(to: .init(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
                        ray.addLine(to: .init(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
                        c.stroke(ray, with: .color(Theme.brass.opacity(1 - rays)), style: artStroke(Theme.brass, ArtGeo.line))
                    }
                }
            }
        }
        .frame(width: Theme.Size.moneySuccessArt, height: Theme.Size.moneySuccessArt)
        .onAppear { start = AppClock.now }
        .task {
            try? await Task.sleep(for: .seconds(Theme.Motion.Money.success))
            played = true
        }
        .accessibilityLabel("Listo")
    }
}

// MARK: - The empty «Hoy» (2026-11-01)

/// A clock that plays once from when the view appears: `seconds` since, then still at `until`.
/// Still from the start (at `until`) with reduced motion, Low Power Mode or in the UI tests.
struct PlayOnceClock<Content: View>: View {
    let until: Double
    @ViewBuilder let content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = AppClock.now
    @State private var played = false

    private var still: Bool { MotionPolicy.isStill(reduceMotion: reduceMotion) || played }

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Motion.Money.frameInterval, paused: still)) { context in
            content(still ? until : min(context.date.timeIntervalSince(start), until))
        }
        .onAppear { start = AppClock.now }
        // Gone still halfway (low power on), it stays at its end: turning it off again never
        // jumps back into the middle (second audit, 2026-11-02).
        .onChange(of: MotionPolicy.isStill(reduceMotion: reduceMotion)) { _, now in if now { played = true } }
        .task {
            try? await Task.sleep(for: .seconds(until))
            played = true
        }
    }
}

/// The two first steps of an empty «Hoy», drawn: `progress` 0…1 plays them; 1 is their resting
/// look (and what reduced motion shows).
struct EmptyStepArt: View {
    enum Kind { case budget, wallet }
    let kind: Kind
    let progress: Double

    var body: some View {
        Canvas { context, size in
            var c = context
            artFit(&c, size, design: CGSize(width: 120, height: 52))
            switch kind {
            case .budget: budget(&c)
            case .wallet: wallet(&c)
            }
        }
        .accessibilityHidden(true)
    }

    /// The boleto's cells fill, then a dashed line splits them evenly: a budget per day.
    private func budget(_ c: inout GraphicsContext) {
        for i in 0..<7 {
            let x = 14 + CGFloat(i) * 13
            c.stroke(artCell(x, 10, 9, 32), with: .color(Theme.outline), style: artStroke(Theme.outline))
            let fill = moneySpan(progress, 0.05 + Double(i) * 0.06, 0.45 + Double(i) * 0.06)
            let h = 20 * fill
            c.fill(artCell(x, 42 - h, 9, h), with: .color(Theme.brass))
        }
        var line = Path(); line.move(to: CGPoint(x: 10, y: 22)); line.addLine(to: CGPoint(x: 110, y: 22))
        c.stroke(line.trimmedPath(from: 0, to: moneySpan(progress, 0.7, 1)), with: .color(Theme.brass),
                 style: artStroke(Theme.brass, dash: ArtGeo.dash))
    }

    /// The phone pays (two rings that go), a line of light runs, the payment prints on the ticket.
    private func wallet(_ c: inout GraphicsContext) {
        c.stroke(Path(roundedRect: CGRect(x: 14, y: 10, width: 20, height: 32), cornerRadius: 4),
                 with: .color(Theme.outline), style: artStroke(Theme.outline))
        for (i, delay) in [0.0, 0.12].enumerated() {
            let ring = moneySpan(progress, delay, delay + 0.4)
            if ring > 0 && ring < 1 {
                let r = 6 + CGFloat(i) * 5 + 8 * CGFloat(ring)
                c.stroke(Path(ellipseIn: CGRect(x: 24 - r, y: 26 - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.brass.opacity(1 - ring)), style: artStroke(Theme.brass))
            }
        }
        var link = Path(); link.move(to: CGPoint(x: 38, y: 26)); link.addLine(to: CGPoint(x: 76, y: 26))
        c.stroke(link, with: .color(Theme.outline), style: artStroke(Theme.outline, dash: ArtGeo.dash))
        c.stroke(link.trimmedPath(from: 0, to: moneySpan(progress, 0.35, 0.7)), with: .color(Theme.brass),
                 style: artStroke(Theme.brass, ArtGeo.line))
        c.stroke(Path(roundedRect: CGRect(x: 80, y: 10, width: 28, height: 32), cornerRadius: 3),
                 with: .color(Theme.outline), style: artStroke(Theme.outline, dash: ArtGeo.dash))
        let printed = moneySpan(progress, 0.7, 1)
        var row = c
        row.opacity = printed
        row.translateBy(x: 0, y: -4 * (1 - printed))
        row.fill(Path(roundedRect: CGRect(x: 85, y: 20, width: 18, height: 4), cornerRadius: 1.5), with: .color(Theme.brass))
        row.fill(Path(roundedRect: CGRect(x: 85, y: 28, width: 12, height: 3), cornerRadius: 1.5), with: .color(Theme.outline))
    }
}
