import Foundation

/// An amount as it is being typed, with its thousands put in for you: "8000" shows as
/// "8,000" and "1234567.5" as "1,234,567.5". `AmountParser` reads the result back as is.
public enum AmountTyping {
    /// - Parameter decimalSeparator: the one the keyboard types. A region that writes "8,5"
    ///   gives a "," key on the decimal pad; it is read as the decimal point.
    public static func grouped(_ text: String, decimalSeparator: String = ".") -> String {
        var integer = ""
        var fraction: String?
        for character in text {
            if character.isNumber, character.isASCII {
                if fraction != nil {
                    if fraction!.count < 2 { fraction!.append(character) }
                } else {
                    integer.append(character)
                }
            } else if character == "." || String(character) == decimalSeparator {
                if fraction == nil { fraction = "" }
            }
        }
        // "007" is 7; a lone "0" before the point stays.
        while integer.count > 1, integer.first == "0" { integer.removeFirst() }
        if integer.isEmpty, fraction != nil { integer = "0" }
        var groups: [String] = []
        var rest = Substring(integer)
        while rest.count > 3 {
            groups.insert(String(rest.suffix(3)), at: 0)
            rest = rest.dropLast(3)
        }
        if !rest.isEmpty { groups.insert(String(rest), at: 0) }
        let head = groups.joined(separator: ",")
        guard let fraction else { return head }
        return head + "." + fraction
    }
}
