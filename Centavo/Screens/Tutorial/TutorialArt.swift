import SwiftUI

// The drawings of «Cómo funciona» (2026-11-01), in «Mi dinero»'s language (`MoneyArt`): hairlines,
// the ticket's dashes, the boleto's cells and one brass. Each plays once from `progress` 0 to 1
// and stays at 1, its resting look (what reduced motion shows). Design space 200 × 120.

struct TutorialArt: View {
    let story: TutorialStory
    let progress: Double

    private static let design = CGSize(width: 200, height: 120)

    var body: some View {
        Canvas { context, size in
            var c = context
            artFit(&c, size, design: Self.design)
            switch story {
            case .figure: figure(&c)
            case .bar: bar(&c)
            case .leftover: leftover(&c)
            case .wallet: wallet(&c)
            case .uncounted: uncounted(&c)
            case .categories: categories(&c)
            case .backup: backup(&c)
            }
        }
        .accessibilityHidden(true)
    }

    private func label(_ c: inout GraphicsContext, _ text: String, at point: CGPoint, size: CGFloat = 22,
                       color: Color = Theme.ink, opacity: Double = 1) {
        var layer = c
        layer.opacity = opacity
        layer.draw(Text(text).font(.custom("IBMPlexMono-SemiBold", fixedSize: size)).foregroundStyle(color),
                   at: point)
    }

    /// The figure: a payment drops in and «$355» becomes «$266»; today's cell fills.
    private func figure(_ c: inout GraphicsContext) {
        let pay = artCell(60, 8, 80, 18)
        let drop = moneySpan(progress, 0, 0.35)
        var notice = c
        notice.opacity = drop * (1 - moneySpan(progress, 0.45, 0.6))
        notice.translateBy(x: 0, y: -10 * (1 - drop))
        notice.stroke(pay, with: .color(Theme.outline), style: artStroke(Theme.outline))
        notice.fill(Path(roundedRect: CGRect(x: 66, y: 15, width: 30, height: 4), cornerRadius: 1.5), with: .color(Theme.ink))
        notice.fill(Path(roundedRect: CGRect(x: 118, y: 15, width: 16, height: 4), cornerRadius: 1.5), with: .color(Theme.brass))
        let swap = moneySpan(progress, 0.45, 0.7)
        label(&c, "$355", at: CGPoint(x: 100, y: 58 - 8 * swap), size: 30, opacity: 1 - swap)
        label(&c, "$266", at: CGPoint(x: 100, y: 66 - 8 * swap), size: 30, opacity: swap)
        for i in 0..<12 {
            let x = 22 + CGFloat(i) * 13.5
            c.stroke(artCell(x, 90, 9, 20), with: .color(Theme.outline), style: artStroke(Theme.outline, dash: ArtGeo.dash))
        }
        let today = moneySpan(progress, 0.6, 1)
        c.fill(artCell(22, 110 - 20 * today, 9, 20 * today), with: .color(Theme.brass))
    }

    /// The month bar: brass is what went, the white rule is an even month so far.
    private func bar(_ c: inout GraphicsContext) {
        let track = CGRect(x: 14, y: 46, width: 172, height: 26)
        c.stroke(Path(roundedRect: track, cornerRadius: ArtGeo.cellCorner), with: .color(Theme.outline),
                 style: artStroke(Theme.outline))
        let went = 172 * 0.42 * moneySpan(progress, 0.05, 0.55)
        c.fill(Path(roundedRect: CGRect(x: 14, y: 46, width: went, height: 26), cornerRadius: ArtGeo.cellCorner),
               with: .color(Theme.brass))
        let rule = moneySpan(progress, 0.5, 0.8)
        var line = Path()
        line.move(to: CGPoint(x: 14 + 172 * 0.5, y: 38)); line.addLine(to: CGPoint(x: 14 + 172 * 0.5, y: 80))
        c.stroke(line.trimmedPath(from: 0, to: rule), with: .color(Theme.ink), style: artStroke(Theme.ink, ArtGeo.line))
        label(&c, "Llevas", at: CGPoint(x: 40, y: 96), size: 10, color: Theme.brass, opacity: moneySpan(progress, 0.3, 0.6))
        label(&c, "Podrías", at: CGPoint(x: 100, y: 28), size: 10, color: Theme.muted, opacity: rule)
    }

    /// What a day leaves over: the unspent part of today's cell slides into tomorrow's.
    private func leftover(_ c: inout GraphicsContext) {
        let height: CGFloat = 70, top: CGFloat = 24, width: CGFloat = 46
        for x in [44, 110] as [CGFloat] {
            c.stroke(artCell(x, top, width, height), with: .color(Theme.outline), style: artStroke(Theme.outline))
        }
        let spent = 0.6 * moneySpan(progress, 0, 0.3)
        c.fill(artCell(44, top + height * (1 - spent), width, height * spent), with: .color(Theme.brass))
        // The unspent top of today's cell travels to the bottom of tomorrow's, and lands there.
        let move = moneySpan(progress, 0.35, 0.8)
        let piece = artCell(44 + 66 * move, top + height * 0.6 * move, width, height * 0.4)
        var chunk = c
        chunk.opacity = moneySpan(progress, 0.3, 0.4)
        chunk.stroke(piece, with: .color(Theme.brass), style: artStroke(Theme.brass, ArtGeo.line, dash: ArtGeo.dash))
        chunk.fill(piece, with: .color(Theme.brass.opacity(0.35 * moneySpan(progress, 0.8, 1))))
        label(&c, "Hoy", at: CGPoint(x: 67, y: 108), size: 10, color: Theme.muted)
        label(&c, "Mañana", at: CGPoint(x: 133, y: 108), size: 10, color: Theme.muted)
        label(&c, "+", at: CGPoint(x: 133, y: 14), size: 14, color: Theme.brass, opacity: moneySpan(progress, 0.8, 1))
    }

    /// The phone pays, Atajos carries it, the ticket prints it; and a «+» for cash.
    private func wallet(_ c: inout GraphicsContext) {
        c.stroke(Path(roundedRect: CGRect(x: 18, y: 30, width: 34, height: 58), cornerRadius: 6),
                 with: .color(Theme.outline), style: artStroke(Theme.outline))
        for (i, delay) in [0.0, 0.12].enumerated() {
            let ring = moneySpan(progress, delay, delay + 0.4)
            if ring > 0 && ring < 1 {
                let r = 10 + CGFloat(i) * 8 + 14 * CGFloat(ring)
                c.stroke(Path(ellipseIn: CGRect(x: 35 - r, y: 59 - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.brass.opacity(1 - ring)), style: artStroke(Theme.brass))
            }
        }
        var link = Path(); link.move(to: CGPoint(x: 58, y: 59)); link.addLine(to: CGPoint(x: 128, y: 59))
        c.stroke(link, with: .color(Theme.outline), style: artStroke(Theme.outline, dash: ArtGeo.dash))
        c.stroke(link.trimmedPath(from: 0, to: moneySpan(progress, 0.3, 0.6)), with: .color(Theme.brass),
                 style: artStroke(Theme.brass, ArtGeo.line))
        c.stroke(Path(roundedRect: CGRect(x: 134, y: 26, width: 48, height: 66), cornerRadius: 3),
                 with: .color(Theme.outline), style: artStroke(Theme.outline, dash: ArtGeo.dash))
        for (i, from) in [0.55, 0.75].enumerated() {
            let printed = moneySpan(progress, from, from + 0.2)
            var row = c
            row.opacity = printed
            row.translateBy(x: 0, y: -4 * (1 - printed))
            let y = 38 + CGFloat(i) * 16
            row.fill(Path(roundedRect: CGRect(x: 141, y: y, width: 22, height: 4), cornerRadius: 1.5),
                     with: .color(i == 0 ? Theme.brass : Theme.ink))
            row.fill(Path(roundedRect: CGRect(x: 167, y: y, width: 9, height: 4), cornerRadius: 1.5), with: .color(Theme.outline))
        }
        label(&c, "+", at: CGPoint(x: 158, y: 80), size: 16, color: Theme.brass, opacity: moneySpan(progress, 0.8, 1))
    }

    /// Three rows; the middle one (a card payment) is crossed out of the total, which stays put.
    private func uncounted(_ c: inout GraphicsContext) {
        for i in 0..<3 {
            let y = 12 + CGFloat(i) * 30
            let off = i == 1 ? moneySpan(progress, 0.3, 0.7) : 0
            var row = c
            row.opacity = 1 - 0.55 * off
            row.fill(Path(roundedRect: CGRect(x: 30, y: y, width: i == 1 ? 70 : 52, height: 5), cornerRadius: 2),
                     with: .color(Theme.ink))
            row.fill(Path(roundedRect: CGRect(x: 140, y: y, width: 30, height: 5), cornerRadius: 2),
                     with: .color(i == 1 ? Theme.muted : Theme.brass))
            if i == 1 {
                var strike = Path()
                strike.move(to: CGPoint(x: 134, y: y + 2.5)); strike.addLine(to: CGPoint(x: 176, y: y + 2.5))
                c.stroke(strike.trimmedPath(from: 0, to: off), with: .color(Theme.ink), style: artStroke(Theme.ink, ArtGeo.line))
            }
        }
        var rule = Path(); rule.move(to: CGPoint(x: 24, y: 88)); rule.addLine(to: CGPoint(x: 176, y: 88))
        c.stroke(rule, with: .color(Theme.outline), style: artStroke(Theme.outline, dash: ArtGeo.dash))
        label(&c, "Total", at: CGPoint(x: 50, y: 104), size: 12, color: Theme.muted)
        label(&c, "$2,140", at: CGPoint(x: 150, y: 104), size: 14, color: Theme.ink)
        label(&c, "No cuenta", at: CGPoint(x: 155, y: 54), size: 9, color: Theme.brass, opacity: moneySpan(progress, 0.65, 0.9))
    }

    /// Where it goes: three categories, each bar growing to its share.
    private func categories(_ c: inout GraphicsContext) {
        let shares: [CGFloat] = [0.9, 0.55, 0.3]
        for (i, share) in shares.enumerated() {
            let y = 22 + CGFloat(i) * 30
            c.stroke(artCell(70, y, 110, 16), with: .color(Theme.outline), style: artStroke(Theme.outline, dash: ArtGeo.dash))
            let grown = moneySpan(progress, Double(i) * 0.15, 0.5 + Double(i) * 0.15)
            c.fill(artCell(70, y, 110 * share * grown, 16), with: .color(i == 0 ? Theme.brass : Theme.brass.opacity(0.55)))
            c.fill(Path(roundedRect: CGRect(x: 20, y: y + 6, width: 40 - CGFloat(i) * 8, height: 5), cornerRadius: 2),
                   with: .color(Theme.ink))
        }
    }

    /// The backup: a page folds into a sealed envelope, a padlock closes on it.
    private func backup(_ c: inout GraphicsContext) {
        let rise = moneySpan(progress, 0, 0.4)
        var page = c
        page.translateBy(x: 0, y: 20 * (1 - rise))
        page.opacity = rise
        page.stroke(Path(roundedRect: CGRect(x: 72, y: 14, width: 56, height: 72), cornerRadius: 3),
                    with: .color(Theme.outline), style: artStroke(Theme.outline))
        for i in 0..<4 {
            page.fill(Path(roundedRect: CGRect(x: 80, y: 26 + CGFloat(i) * 12, width: i == 0 ? 30 : 40, height: 4), cornerRadius: 1.5),
                      with: .color(i == 0 ? Theme.brass : Theme.outline))
        }
        let lock = moneySpan(progress, 0.45, 0.8)
        let body = CGRect(x: 86, y: 72, width: 28, height: 22)
        var padlock = c
        padlock.opacity = lock
        padlock.fill(Path(roundedRect: body, cornerRadius: 3), with: .color(Theme.brass))
        var shackle = Path()
        let drop = 6 * (1 - moneySpan(progress, 0.7, 0.9))
        shackle.move(to: CGPoint(x: 92, y: 72 - drop))
        shackle.addLine(to: CGPoint(x: 92, y: 66 - drop))
        shackle.addArc(center: CGPoint(x: 100, y: 66 - drop), radius: 8, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        shackle.addLine(to: CGPoint(x: 108, y: 72 - drop))
        padlock.stroke(shackle, with: .color(Theme.brass), style: artStroke(Theme.brass, ArtGeo.bold))
        label(&c, "Cada día", at: CGPoint(x: 100, y: 110), size: 10, color: Theme.muted, opacity: moneySpan(progress, 0.85, 1))
    }
}
