import Testing
@testable import CentavoCore

@Suite struct MoneyTextTests {
    @Test func splitsOffTheCents() {
        #expect(MoneyText.splitCents("$1,093.50", decimalSeparator: ".")
                == .init(head: "$1,093", cents: ".50", tail: ""))
    }

    @Test func keepsWhatFollowsTheCents() {
        #expect(MoneyText.splitCents("1.093,50 €", decimalSeparator: ",")
                == .init(head: "1.093", cents: ",50", tail: " €"))
    }

    @Test func leavesAnAmountWithoutCentsWhole() {
        #expect(MoneyText.splitCents("$1,093", decimalSeparator: ".")
                == .init(head: "$1,093", cents: "", tail: ""))
        // A grouping dot followed by three digits is not a decimal part.
        #expect(MoneyText.splitCents("1.093", decimalSeparator: ".")
                == .init(head: "1.093", cents: "", tail: ""))
        #expect(MoneyText.splitCents("", decimalSeparator: ".")
                == .init(head: "", cents: "", tail: ""))
    }
}
