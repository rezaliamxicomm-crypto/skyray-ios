import XCTest
@testable import SkyRayCore

final class LineHealthTests: XCTestCase {
    let p = AutoPolicy()

    func testAFailedLineWaitsLongerEachTimeUpToTheCap() {
        var h = LineHealth()
        XCTAssertTrue(h.due("a", now: 0))                                        // never seen: due
        h.failed("a", now: 1000, policy: p)
        XCTAssertFalse(h.due("a", now: 1000 + 899)); XCTAssertTrue(h.due("a", now: 1000 + 900))       // 15 min
        h.failed("a", now: 1900, policy: p)
        XCTAssertFalse(h.due("a", now: 1900 + 1799)); XCTAssertTrue(h.due("a", now: 1900 + 1800))     // 30 min
        h.failed("a", now: 3700, policy: p); h.failed("a", now: 7300, policy: p); h.failed("a", now: 14500, policy: p)
        XCTAssertTrue(h.due("a", now: 14500 + 7200)); XCTAssertFalse(h.due("a", now: 14500 + 7199))   // capped at 2 h
        XCTAssertTrue(h.isDead("a"))
        h.ok("a", ms: 180, now: 30000)
        XCTAssertFalse(h.isDead("a")); XCTAssertTrue(h.due("a", now: 30001)); XCTAssertEqual(h.lastMs("a"), 180)
        h.failed("a", now: 40000, policy: p)
        XCTAssertTrue(h.due("a", now: 40000 + 900))                             // the backoff starts over after a good probe
    }

    func testTheOrderIsKnownGoodByTimeThenUnseenThenDead() {
        var h = LineHealth()
        h.ok("r2", ms: 190, now: 1); h.ok("r1", ms: 210, now: 1); h.failed("x1", now: 1, policy: p); h.ok("w1", ms: 190, now: 1)
        XCTAssertEqual(h.bestFirst(["r1", "r2", "x1", "x2", "w1"]), ["r2", "w1", "r1", "x2", "x1"])   // equals keep the subscription's order
        XCTAssertEqual(h.bestKnown(["r1", "r2", "x1", "x2", "w1"]), "r2")
        XCTAssertEqual(h.bestKnown(["r1", "r2", "x1", "x2", "w1"], except: "r2"), "w1")
        XCTAssertNil(LineHealth().bestKnown(["a", "b"]))                          // nothing known yet
    }

    func testForgivenessAfterANetworkChange() {
        var h = LineHealth()
        h.failed("x1", now: 1, policy: p); h.failed("x1", now: 2, policy: p)
        XCTAssertFalse(h.due("x1", now: 100))
        h.forgive()
        XCTAssertTrue(h.due("x1", now: 100)); XCTAssertFalse(h.isDead("x1"))
    }

    func testNothingAnswersWhenEveryLineFailedOrWaitsItsRetry() {
        var h = LineHealth()
        h.failed("x1", now: 1, policy: p); h.failed("x2", now: 1, policy: p)                      // in backoff: not probed this session
        let results: [String: Int64] = ["r1": -1, "r2": -1]                                      // probed and failed
        XCTAssertTrue(h.allOut(["r1", "r2", "x1", "x2"], current: "r1", result: { results[$0] ?? 0 }))
        XCTAssertFalse(h.allOut(["r1", "r2", "x1", "x2", "w1"], current: "r1", result: { results[$0] ?? 0 }))   // w1 never probed, not held failed: not out
        XCTAssertFalse(h.allOut(["r1", "r2", "x1"], current: "r1", result: { ["r1": 200, "r2": -1][$0] ?? 0 }))  // the line in use answers
        XCTAssertFalse(LineHealth().allOut([], current: "r1", result: { _ in -1 }))
    }

    func testItSurvivesTheStore() throws {
        var h = LineHealth(); h.ok("a", ms: 100, now: 5); h.failed("b", now: 6, policy: p)
        let back = try JSONDecoder().decode(LineHealth.self, from: JSONEncoder().encode(h))
        XCTAssertEqual(back, h)
    }
}
