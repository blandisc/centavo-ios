/// Keeps the last thing worked out and the inputs it came from, and works it out again only
/// when those inputs change. The main screen redraws for many reasons (a row swiped open, a
/// sheet, the width); its totals only change with the expenses or the month.
public struct Memo<Key: Equatable, Value> {
    private var last: (key: Key, value: Value)?

    public init() {}

    /// The value for `key`: the kept one if `key` is the same as last time, else `make()`'s.
    public mutating func value(for key: Key, make: () -> Value) -> Value {
        if let last, last.key == key { return last.value }
        let value = make()
        last = (key, value)
        return value
    }

    /// Forgets what it kept, so the next call works it out again.
    public mutating func reset() { last = nil }
}
