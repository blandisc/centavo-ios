import Foundation
import Testing
@testable import CentavoCore

@Suite struct CaptureProofTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    // MARK: «Ya funciona»

    @Test func aPaymentAfterOpeningTheGuideProvesIt() {
        let proof = CaptureProof(sessionStart: minutesAgo(10), arrivedHere: minutesAgo(2), lastKnown: minutesAgo(2), now: now)
        #expect(proof == .working(arrived: minutesAgo(2)))
    }

    @Test func aPaymentFromBeforeOpeningTheGuideDoesNot() {
        // Yesterday's payment: under three days old, and still no proof of today's setup.
        let yesterday = minutesAgo(24 * 60)
        let proof = CaptureProof(sessionStart: minutesAgo(10), arrivedHere: yesterday, lastKnown: yesterday, now: now)
        #expect(proof == .waiting(last: yesterday))
    }

    @Test func aPaymentThatCameInARestoredBackupDoesNot() {
        // The expenses have a capture from a minute ago, but nothing arrived on this iPhone.
        let proof = CaptureProof(sessionStart: minutesAgo(10), arrivedHere: nil, lastKnown: minutesAgo(1), now: now)
        #expect(proof == .waiting(last: minutesAgo(1)))
    }

    @Test func withNoPaymentEverItWaitsForTheFirst() {
        #expect(CaptureProof(sessionStart: minutesAgo(10), arrivedHere: nil, lastKnown: nil, now: now) == .waiting(last: nil))
    }

    @Test func withoutASessionOrWithAnOldOneNothingIsProof() {
        #expect(CaptureProof(sessionStart: nil, arrivedHere: minutesAgo(2), lastKnown: nil, now: now)
                == .waiting(last: minutesAgo(2)))
        let old = minutesAgo(25 * 60)
        #expect(CaptureProof(sessionStart: old, arrivedHere: minutesAgo(2), lastKnown: nil, now: now)
                == .waiting(last: minutesAgo(2)))
    }

    @Test func aClockSetBackProvesNothing() {
        let ahead = now.addingTimeInterval(600)
        #expect(CaptureProof(sessionStart: ahead, arrivedHere: ahead.addingTimeInterval(60), lastKnown: nil, now: now)
                == .waiting(last: nil))
        #expect(CaptureProof(sessionStart: minutesAgo(10), arrivedHere: ahead, lastKnown: minutesAgo(30), now: now)
                == .waiting(last: minutesAgo(30)))
    }

    @Test func theNewestKnownPaymentIsTheOneSaid() {
        #expect(CaptureProof(sessionStart: minutesAgo(10), arrivedHere: minutesAgo(600), lastKnown: minutesAgo(90), now: now)
                == .waiting(last: minutesAgo(90)))
    }

    // MARK: When a setup starts

    @Test func theFirstTimeStartsNow() {
        #expect(CaptureProof.sessionStart(previous: nil, arrivedHere: nil, now: now) == now)
    }

    @Test func comingBackFromShortcutsCarriesOn() {
        // Opened, went to Atajos, paid, came back and opened the guide again: that payment counts.
        let start = CaptureProof.sessionStart(previous: minutesAgo(40), arrivedHere: minutesAgo(3), now: now)
        #expect(start == minutesAgo(40))
        #expect(CaptureProof(sessionStart: start, arrivedHere: minutesAgo(3), lastKnown: nil, now: now)
                == .working(arrived: minutesAgo(3)))
    }

    @Test func comingBackHoursAfterAProofStartsOver() {
        // It worked five hours ago; whoever opens the guide now came to check again.
        let start = CaptureProof.sessionStart(previous: minutesAgo(6 * 60), arrivedHere: minutesAgo(5 * 60), now: now)
        #expect(start == now)
        #expect(CaptureProof(sessionStart: start, arrivedHere: minutesAgo(5 * 60), lastKnown: nil, now: now)
                == .waiting(last: minutesAgo(5 * 60)))
    }

    @Test func aDayLaterStartsOver() {
        #expect(CaptureProof.sessionStart(previous: minutesAgo(24 * 60), arrivedHere: nil, now: now) == now)
        #expect(CaptureProof.sessionStart(previous: now.addingTimeInterval(60), arrivedHere: nil, now: now) == now)
    }

    @Test func anOlderPaymentDoesNotRestartAnOpenSetup() {
        #expect(CaptureProof.sessionStart(previous: minutesAgo(30), arrivedHere: minutesAgo(3 * 24 * 60), now: now)
                == minutesAgo(30))
    }
}
