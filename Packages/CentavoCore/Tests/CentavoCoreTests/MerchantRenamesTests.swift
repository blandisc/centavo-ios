import Testing
@testable import CentavoCore

@Suite struct MerchantRenamesTests {
    @Test func aRenamedMerchantComesBackWithItsNewName() {
        var renames = MerchantRenames()
        renames.rename("OXXO SUC 1234", to: "Oxxo de la esquina")
        #expect(renames.name(for: "OXXO SUC 1234") == "Oxxo de la esquina")
        // Wallet is not consistent about case, accents or spaces.
        #expect(renames.name(for: "oxxo  suc 1234 ") == "Oxxo de la esquina")
        // Another branch is another place.
        #expect(renames.name(for: "OXXO SUC 5678") == nil)
    }

    @Test func renamingTwiceLandsOnTheLastName() {
        var renames = MerchantRenames()
        renames.rename("STARBUCKS 22", to: "Café")
        renames.rename("Café", to: "Starbucks Reforma")
        #expect(renames.name(for: "STARBUCKS 22") == "Starbucks Reforma")
    }

    @Test func renamingBackForgetsIt() {
        var renames = MerchantRenames()
        renames.rename("UBER *TRIP", to: "Uber")
        renames.rename("Uber", to: "UBER *TRIP")
        #expect(renames.name(for: "UBER *TRIP") == nil)
    }

    @Test func noMerchantIsNeverRenamed() {
        var renames = MerchantRenames()
        renames.rename("Sin comercio", to: "Tienda")
        renames.rename("Tienda", to: "  ")
        #expect(renames.entries.isEmpty)
    }

    @Test func survivesBeingStored() {
        var renames = MerchantRenames()
        renames.rename("AMZN MKTP MX", to: "Amazon")
        #expect(MerchantRenames(stored: renames.stored) == renames)
        #expect(MerchantRenames(stored: "basura").entries.isEmpty)
    }
}
