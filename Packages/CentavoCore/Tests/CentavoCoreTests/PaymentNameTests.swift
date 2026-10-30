import Testing
@testable import CentavoCore

@Suite struct PaymentNameTests {
    @Test func walletsLongNamesGetShort() {
        #expect(PaymentName.short("American Express México") == "Amex")
        #expect(PaymentName.short("AMERICAN EXPRESS MEXICO") == "Amex")
        #expect(PaymentName.short("American Express Platinum") == "Amex Platinum")
        #expect(PaymentName.short("BBVA México") == "BBVA")
    }

    @Test func namesSomeoneChoseStayAsTheyAre() {
        #expect(PaymentName.short("Nu") == "Nu")
        #expect(PaymentName.short("Efectivo") == "Efectivo")
        // A name that is only the country is not emptied.
        #expect(PaymentName.short("México") == "México")
    }
}
