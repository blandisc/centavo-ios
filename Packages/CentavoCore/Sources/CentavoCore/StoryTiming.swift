import Foundation

/// How long a story of «Cómo funciona» stays before moving on (2026-11-01): long enough to read
/// it — four seconds plus a quarter second per word, at most ten.
public enum StoryTiming {
    public static let base: Double = 4
    public static let perWord: Double = 0.25
    public static let longest: Double = 10

    public static func words(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    public static func duration(for texts: [String]) -> Double {
        min(longest, base + perWord * Double(texts.map(words(in:)).reduce(0, +)))
    }

    /// Where a story is, 0…1, after `elapsed` seconds of `duration`.
    public static func progress(elapsed: Double, duration: Double) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(elapsed / duration, 0), 1)
    }
}
