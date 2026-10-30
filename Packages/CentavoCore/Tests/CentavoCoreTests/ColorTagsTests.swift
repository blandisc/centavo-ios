import Foundation
import Testing
@testable import CentavoCore

@Suite struct ColorTagsTests {
    @Test func aChosenColorWinsAndIgnoresCaseAndAccents() {
        var tags = ColorTags()
        tags.set(4, for: "Café")
        #expect(tags.index(for: "cafe ") == 4)
        #expect(tags.index(for: "Café", fallback: 6) == 4)
    }

    @Test func withoutAChoiceTheFallbackThenTheNameDecide() {
        let tags = ColorTags()
        #expect(tags.index(for: "Comida", fallback: 1) == 1)
        // The same name, the same color, every time.
        #expect(tags.index(for: "Gimnasio") == tags.index(for: "gimnasio"))
        #expect((0..<ColorTags.count).contains(tags.index(for: "Gimnasio")))
    }

    @Test func forgettingGoesBackToTheUsualColor() {
        var tags = ColorTags()
        tags.set(3, for: "Comida")
        tags.set(nil, for: "Comida")
        #expect(tags.index(for: "Comida", fallback: 1) == 1)
    }

    @Test func aRenameKeepsTheColor() {
        var tags = ColorTags()
        tags.set(5, for: "BBVA")
        tags.rename("BBVA", to: "BBVA Azul")
        #expect(tags.index(for: "BBVA Azul") == 5)
        #expect(tags.chosen["bbva"] == nil)
    }

    @Test func aNewOneTakesTheLeastUsedColor() {
        var tags = ColorTags()
        let names = (0..<7).map { "Tarjeta \($0)" }
        for (index, name) in names.enumerated() { tags.set(index, for: name) }
        #expect(tags.nextFree(among: names) == 7)
        tags.set(7, for: "Otra")
        // All eight used once: the first one again.
        #expect(tags.nextFree(among: names + ["Otra"]) == 0)
    }

    @Test func itSurvivesBeingStoredAndUnreadableTextIsNoChoices() {
        var tags = ColorTags()
        tags.set(2, for: "Nu")
        #expect(ColorTags(stored: tags.stored) == tags)
        #expect(ColorTags(stored: "no es json").chosen.isEmpty)
    }

    @Test func aSliceRemembersItsColorAndOldSnapshotsStillRead() throws {
        let slices = WidgetSnapshot.slices([CategoryTotal(category: "Comida", amount: 10)],
                                           color: { $0 == "Comida" ? 1 : nil })
        #expect(slices.first?.color == 1)
        let old = #"{"name":"Comida","amount":10,"isRest":false}"#
        let decoded = try JSONDecoder().decode(WidgetSnapshot.Slice.self, from: Data(old.utf8))
        #expect(decoded.color == nil)
    }
}

@Suite struct WidgetSnapshotDaysTests {
    @Test func theDaysCarryOverInTheMonthAndEmptyInTheNext() {
        let calendar = Calendar(identifier: .gregorian)
        let taken = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 12))!
        let snapshot = WidgetSnapshot(budget: 3_100, isoCode: "MXN", label: "$", takenAt: taken, spent: 300,
                                      days: [100, 0, 200])
        let later = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        #expect(snapshot.month(at: later, calendar: calendar).days == [100, 0, 200])
        let next = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!
        #expect(snapshot.month(at: next, calendar: calendar).days == [])
        // A snapshot from before the days existed still reads, with none.
        let old = #"{"label":"$","takenAt":0,"spent":0,"spentToday":0,"fixedSpent":0,"fixedToday":0,"reserved":0,"slices":[]}"#
        #expect(WidgetSnapshot.decode(Data(old.utf8))?.days == nil)
    }
}
