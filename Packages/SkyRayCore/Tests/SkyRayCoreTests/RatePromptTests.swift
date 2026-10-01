import XCTest
@testable import SkyRayCore

final class RatePromptTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)   // the first working connection
    private func days(_ n: Double) -> Date { t0.addingTimeInterval(n * 86_400) }

    func testTheFirstAskNeedsFiveConnectionsAndThreeDays() {
        XCTAssertFalse(RatePrompt(connects: 4, firstAt: t0).due(now: days(10)))
        XCTAssertFalse(RatePrompt(connects: 5, firstAt: t0).due(now: days(3).addingTimeInterval(-1)))
        XCTAssertTrue(RatePrompt(connects: 5, firstAt: t0).due(now: days(3)))
        XCTAssertTrue(RatePrompt(connects: 40, firstAt: t0).due(now: days(30)))
    }
    func testABusyFirstDayDoesNotAsk() {
        XCTAssertFalse(RatePrompt(connects: 25, firstAt: t0).due(now: days(1)))
    }
    func testAfterNotNowTheNextAskNeedsTenMoreConnectionsAndTwoWeeks() {
        var asked = RatePrompt(connects: 5, firstAt: t0, asks: 1, lastAskAt: days(3), lastAskConnects: 5)
        asked.connects = 14
        XCTAssertFalse(asked.due(now: days(60)))
        asked.connects = 15
        XCTAssertFalse(asked.due(now: days(17).addingTimeInterval(-1)))
        XCTAssertTrue(asked.due(now: days(17)))
    }
    func testThreeAsksAtMost() {
        var s = RatePrompt(connects: 500, firstAt: t0, asks: 3, lastAskAt: days(40), lastAskConnects: 30)
        XCTAssertFalse(s.due(now: days(400)))
        s.asks = 2
        XCTAssertTrue(s.due(now: days(400)))
    }
    func testNeverAgainOnceTheCustomerWentToTheStore() {
        XCTAssertFalse(RatePrompt(connects: 50, firstAt: t0, done: true).due(now: days(30)))
    }
    func testNothingCountedYetOrAClockSetBackJustWaits() {
        XCTAssertFalse(RatePrompt().due(now: t0))
        XCTAssertFalse(RatePrompt(connects: 9, firstAt: t0).due(now: days(-5)))
    }
    func testCountingAndAsking() {
        var s = RatePrompt()
        for _ in 1...4 {
            let early = s.connected(now: t0)
            XCTAssertFalse(early)
        }
        XCTAssertEqual(s.firstAt, t0)
        let fifth = s.connected(now: days(3))             // the 5th, three days on
        XCTAssertTrue(fifth)
        s.asked(now: days(3))
        XCTAssertEqual(s.asks, 1)
        let sixth = s.connected(now: days(3))
        XCTAssertFalse(sixth)
        s.done = true
        let before = s.connects
        let later = s.connected(now: days(90))
        XCTAssertFalse(later)
        XCTAssertEqual(s.connects, before)                // nothing left to count for
    }
    func testItSurvivesTheStoreFile() throws {
        var s = RatePrompt(connects: 7, firstAt: t0)
        s.asked(now: days(4))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        XCTAssertEqual(try decoder.decode(RatePrompt.self, from: encoder.encode(s)), s)
        XCTAssertEqual(try decoder.decode(RatePrompt.self, from: encoder.encode(RatePrompt())), RatePrompt())
    }
}
