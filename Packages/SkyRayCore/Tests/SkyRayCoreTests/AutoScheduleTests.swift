import XCTest
@testable import SkyRayCore

final class AutoScheduleTests: XCTestCase {
    let p = AutoPolicy()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testTheNextRoundComesOneIntervalAfterTheLastEndedWhateverTheMeasurementTook() {
        var s = AutoSchedule()
        XCTAssertNil(s.action(now: at(1000), inUse: true, searching: false))                 // nothing before the first race ended
        s.roundDone(now: t0, results: ["a": 200, "b": 250, "c": 300], policy: p, draw: 0.5, searching: false)   // 180 s
        XCTAssertNil(s.action(now: at(179), inUse: true, searching: false))
        XCTAssertEqual(s.action(now: at(180), inUse: true, searching: false), .round)
        // the bug of 2.0.0–2.0.2: at that moment every line is measured, not skipped for having been probed "too recently"
        XCTAssertEqual(s.linesForRound(now: at(180), lines: ["a", "b", "c"], searching: false), ["a", "b", "c"])
        XCTAssertNil(s.action(now: at(180), inUse: false, searching: false))                 // idle: no round
    }

    func testAFailedLineWaitsItsRetryAndIsRetriedOncePerWindow() {
        var s = AutoSchedule()
        s.roundDone(now: t0, results: ["a": -1, "b": 200], policy: p, draw: 0.5, searching: false)
        XCTAssertEqual(s.linesForRound(now: at(180), lines: ["a", "b"], searching: false), ["b"])
        XCTAssertEqual(s.linesForRound(now: at(899), lines: ["a", "b"], searching: false), ["b"])
        XCTAssertEqual(s.linesForRound(now: at(900), lines: ["a", "b"], searching: false), ["a", "b"])
        s.roundDone(now: at(900), results: ["a": -1, "b": 210], policy: p, draw: 0.5, searching: false)   // still dead: another 900 s
        XCTAssertEqual(s.linesForRound(now: at(1080), lines: ["a", "b"], searching: false), ["b"])
        XCTAssertEqual(s.linesForRound(now: at(1800), lines: ["a", "b"], searching: false), ["a", "b"])
        s.roundDone(now: at(1800), results: ["a": 190], policy: p, draw: 0.5, searching: false)          // back: free again
        XCTAssertEqual(s.linesForRound(now: at(1980), lines: ["a", "b"], searching: false), ["a", "b"])
        XCTAssertEqual(s.linesForRound(now: at(1), lines: ["a", "b"], searching: true), ["a", "b"])       // Searching measures every line
    }

    func testTheSettlingRoundComesOnceAfterTheConnectRaceAndNotAfterAManualTest() {
        var s = AutoSchedule()
        s.raceDone(now: t0, results: ["a": 393, "b": 400], policy: p, draw: 0.5, searching: false, settle: true)
        XCTAssertNil(s.action(now: at(9), inUse: false, searching: false))
        XCTAssertEqual(s.action(now: at(10), inUse: false, searching: false), .settle)       // in use or not
        s.settleTaken()
        s.roundDone(now: at(12), results: ["a": 203, "b": 390], policy: p, draw: 0.5, searching: false)
        XCTAssertNil(s.action(now: at(13), inUse: true, searching: false))
        XCTAssertEqual(s.action(now: at(192), inUse: true, searching: false), .round)          // 180 s after the settle ended
        var m = AutoSchedule()
        m.raceDone(now: t0, results: ["a": 200], policy: p, draw: 0.5, searching: false, settle: false)
        XCTAssertNil(m.action(now: at(10), inUse: true, searching: false))
        var off = AutoSchedule()
        off.raceDone(now: t0, results: ["a": 200], policy: AutoPolicy.parse("settle=0"), draw: 0.5, searching: false, settle: true)
        XCTAssertNil(off.action(now: at(10), inUse: true, searching: false))
    }

    func testSearchingRunsEverySearchSecInUseOrNot() {
        var s = AutoSchedule()
        s.roundDone(now: t0, results: ["a": -1], policy: p, draw: 0.5, searching: true)
        XCTAssertNil(s.action(now: at(59), inUse: false, searching: true))
        XCTAssertEqual(s.action(now: at(60), inUse: false, searching: true), .round)
    }

    func testTheJitterKeepsTheRoundWithinTenPercent() {
        var lo = AutoSchedule(), hi = AutoSchedule()
        lo.roundDone(now: t0, results: [:], policy: p, draw: 0, searching: false)
        hi.roundDone(now: t0, results: [:], policy: p, draw: 1, searching: false)
        XCTAssertEqual(lo.action(now: at(162), inUse: true, searching: false), .round)
        XCTAssertNil(lo.action(now: at(161), inUse: true, searching: false))
        XCTAssertEqual(hi.action(now: at(198), inUse: true, searching: false), .round)
        XCTAssertNil(hi.action(now: at(197), inUse: true, searching: false))
    }

    func testTheFallbackLastsOneRoundAndComesBackWhenTheTargetAnswers() {
        XCTAssertFalse(AutoSchedule.nextFallback(current: false, fullSet: true, targetAnswered: true, fallbackAnswered: true))
        XCTAssertFalse(AutoSchedule.nextFallback(current: false, fullSet: false, targetAnswered: false, fallbackAnswered: true))
        XCTAssertFalse(AutoSchedule.nextFallback(current: false, fullSet: true, targetAnswered: false, fallbackAnswered: false))   // a blip: nothing answers → stay on the target
        XCTAssertTrue(AutoSchedule.nextFallback(current: false, fullSet: true, targetAnswered: false, fallbackAnswered: true))
        XCTAssertFalse(AutoSchedule.nextFallback(current: true, fullSet: true, targetAnswered: true, fallbackAnswered: false))     // the scout answers: back
        XCTAssertTrue(AutoSchedule.nextFallback(current: true, fullSet: true, targetAnswered: false, fallbackAnswered: true))
    }

    func testANetworkChangeIsOneRoundFifteenSecondsLaterInUseOrNotAndDebounced() {
        var s = AutoSchedule()
        s.roundDone(now: t0, results: ["a": -1, "b": 200], policy: p, draw: 0.5, searching: false)
        s.networkChanged(now: at(30))
        XCTAssertNil(s.action(now: at(44), inUse: false, searching: false))
        XCTAssertEqual(s.action(now: at(45), inUse: false, searching: false), .round)           // idle or not
        XCTAssertEqual(s.linesForRound(now: at(45), lines: ["a", "b"], searching: false), ["a", "b"])   // failures void
        s.networkChanged(now: at(50))                                                           // a second event within a minute: ignored
        XCTAssertEqual(s.nextRoundAt, at(45))
        s.roundDone(now: at(46), results: ["a": 210, "b": 200], policy: p, draw: 0.5, searching: false)
        XCTAssertFalse(s.forced)
        XCTAssertNil(s.action(now: at(226), inUse: false, searching: false))                    // back to needing traffic
        s.networkChanged(now: at(120))                                                          // a minute later: a new event
        XCTAssertEqual(s.nextRoundAt, at(135))
    }

    func testTrafficReturningAfterIdleBringsARoundAtOnce() {
        var s = AutoSchedule()
        s.roundDone(now: t0, results: ["a": 200], policy: p, draw: 0.5, searching: false)
        XCTAssertNil(s.action(now: at(500), inUse: false, searching: false))                    // idle: the 180 s passed, nothing ran
        s.wake(now: at(500))
        XCTAssertEqual(s.action(now: at(500), inUse: true, searching: false), .round)
        var fresh = AutoSchedule()
        fresh.wake(now: t0)                                                                     // before the first race: nothing to wake
        XCTAssertNil(fresh.action(now: t0, inUse: true, searching: false))
    }
}
