import Foundation

/// «En qué se va» as a mosaic: one block per category, as big as what was spent there.
public enum ShareMosaic {
    public struct Tile: Equatable, Sendable {
        public let x: Double, y: Double, width: Double, height: Double
    }

    /// Squarified treemap (Bruls et al.): blocks as close to square as the shares allow,
    /// biggest first, filling `width` × `height` exactly.
    ///
    /// Every block is at least `minSide` on each side when the space allows it: a tiny block
    /// can't be tapped (44 pt) or read. Small shares are drawn a little bigger than they are
    /// for that; the figure written on them stays the real one.
    public static func layout(_ shares: [Double], width: Double, height: Double,
                              minSide: Double = 44) -> [Tile] {
        guard !shares.isEmpty, width > 0, height > 0 else { return [] }
        let raw = shares.map { max($0, 0) }
        let total = raw.reduce(0, +)
        guard total > 0 else { return [] }
        // A floor of area per block, raised until every block clears `minSide` (or every
        // block is the same size, the most the space can do).
        let even = 1 / Double(raw.count)
        var floor = min(minSide * minSide / (width * height), even)
        while true {
            let tiles = squarify(raw.map { max($0 / total, floor) }, width: width, height: height)
            if floor >= even || tiles.allSatisfy({ $0.width >= minSide && $0.height >= minSide }) {
                return tiles
            }
            floor = min(floor * 1.2, even)
        }
    }

    private static func squarify(_ values: [Double], width: Double, height: Double) -> [Tile] {
        var tiles = [Tile?](repeating: nil, count: values.count)
        var rest = Array(values.indices)
        var box = (x: 0.0, y: 0.0, w: width, h: height)
        var remaining = values.reduce(0, +)
        while !rest.isEmpty {
            let side = min(box.w, box.h)
            let scale = box.w * box.h / remaining
            func worst(_ row: [Int]) -> Double {
                let areas = row.map { values[$0] * scale }
                let sum = areas.reduce(0, +)
                return max(side * side * areas.max()! / (sum * sum), sum * sum / (side * side * areas.min()!))
            }
            var row = [rest[0]]
            while row.count < rest.count, worst(row + [rest[row.count]]) <= worst(row) {
                row.append(rest[row.count])
            }
            let rowValue = row.reduce(0) { $0 + values[$1] }
            let fraction = rowValue / remaining
            var offset = 0.0
            if box.w >= box.h {
                let columnWidth = box.w * fraction
                for index in row {
                    let h = box.h * values[index] / rowValue
                    tiles[index] = Tile(x: box.x, y: box.y + offset, width: columnWidth, height: h)
                    offset += h
                }
                box = (box.x + columnWidth, box.y, box.w - columnWidth, box.h)
            } else {
                let rowHeight = box.h * fraction
                for index in row {
                    let w = box.w * values[index] / rowValue
                    tiles[index] = Tile(x: box.x + offset, y: box.y, width: w, height: rowHeight)
                    offset += w
                }
                box = (box.x, box.y + rowHeight, box.w, box.h - rowHeight)
            }
            remaining -= rowValue
            rest.removeFirst(row.count)
        }
        return tiles.compactMap { $0 }
    }
}
