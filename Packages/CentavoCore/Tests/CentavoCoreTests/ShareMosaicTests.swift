import Foundation
import Testing
@testable import CentavoCore

@Suite struct ShareMosaicTests {
    private let october = [1004.5, 540, 449.5, 310, 62]

    @Test func fillsTheSpaceExactly() {
        let tiles = ShareMosaic.layout(october, width: 354, height: 150)
        #expect(tiles.count == 5)
        let area = tiles.reduce(0) { $0 + $1.width * $1.height }
        #expect(abs(area - 354 * 150) < 0.5)
        for tile in tiles {
            #expect(tile.x >= -0.001 && tile.y >= -0.001)
            #expect(tile.x + tile.width <= 354.001 && tile.y + tile.height <= 150.001)
        }
    }

    @Test func biggerSharesGetBiggerBlocks() {
        let areas = ShareMosaic.layout(october, width: 354, height: 150).map { $0.width * $0.height }
        #expect(areas == areas.sorted(by: >))
    }

    /// Café is 3 % of the month: drawn to scale it would be a sliver nobody can tap.
    @Test func everyBlockCanBeTapped() {
        for tile in ShareMosaic.layout(october, width: 354, height: 150) {
            #expect(tile.width >= 44 && tile.height >= 44, "\(tile)")
        }
    }

    @Test func nothingToShowIsNoBlocks() {
        #expect(ShareMosaic.layout([], width: 300, height: 100).isEmpty)
        #expect(ShareMosaic.layout([0, 0], width: 300, height: 100).isEmpty)
        #expect(ShareMosaic.layout([1], width: 0, height: 100).isEmpty)
    }

    @Test func aBlockShowsWhatFits() {
        let fit = { (w: Double, h: Double, name: String) in
            ShareMosaic.fit(width: w, height: h, name: name, lineHeight: 14, charWidth: 7.2)
        }
        #expect(fit(170, 150, "Ropa") == .full)
        #expect(fit(240, 40, "Servicios") == .line)
        #expect(fit(48, 140, "Salidas") == .vertical)
        #expect(fit(46, 46, "Suscripciones") == .icon)
    }
}
