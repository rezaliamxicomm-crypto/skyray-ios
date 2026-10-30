import XCTest
@testable import SkyRayCore

final class AutoScheduleTests: XCTestCase {
    let p = AutoPolicy()
    let lines = ["r1", "r2", "x1", "x2", "w1", "w2"]
    let all: (String) -> Bool = { _ in true }

    func testConnectProbesTheLineInUseFirstThenTheQuickPassTwoAtATime() {
        var s = AutoSchedule()
        XCTAssertNil(s.action(now: 0, warm: true, watched: true, searching: false, current: "r1", due: all))     // not started
        s.start(now: 10, order: lines)
        XCTAssertEqual(s.action(now: 10, warm: false, watched: false, searching: false, current: "r1", due: all), .probeCurrent)   // first pass: in use or not, watched or not
        s.currentProbed(now: 10, policy: p)
        XCTAssertEqual(s.action(now: 10, warm: false, watched: false, searching: false, current: "r1", due: all), .probe(["r2", "x1"]))   // two at a time, the line in use skipped
        XCTAssertFalse(s.probed(now: 10, count: 2, policy: p, draw: 0.5))
        XCTAssertNil(s.action(now: 10.5, warm: false, watched: false, searching: false, current: "r1", due: all))
        XCTAssertEqual(s.action(now: 11, warm: false, watched: false, searching: false, current: "r1", due: all), .probe(["x2", "w1"]))   // a second a step
        XCTAssertFalse(s.probed(now: 11, count: 2, policy: p, draw: 0.5))
        XCTAssertEqual(s.action(now: 12, warm: false, watched: false, searching: false, current: "r1", due: all), .probe(["w2"]))       // r1 is the line in use: the pass ends with w2
        XCTAssertTrue(s.probed(now: 12, count: 1, policy: p, draw: 0.5))                                                                  // a pass: the first pass is over
        XCTAssertEqual(s.phase, .steady); XCTAssertEqual(s.passes, 1); XCTAssertFalse(s.forced)
        XCTAssertNil(s.action(now: 13, warm: false, watched: false, searching: false, current: "r1", due: all))                          // idle now: nothing
        XCTAssertEqual(s.pace(policy: p, draw: 0.5), 30, accuracy: 0.001)                                                                  // 180 s over 6 lines
        XCTAssertNil(s.action(now: 41, warm: true, watched: false, searching: false, current: "r1", due: all))
        XCTAssertEqual(s.action(now: 42, warm: true, watched: false, searching: false, current: "r1", due: all), .probe(["r2"]))        // one at a time from here
    }

    func testASteadyStepNeedsAWarmRadioOrTheScreenAndTheFirstPassNeedsNeither() {
        var s = AutoSchedule(); s.reseed(now: 0, order: lines, policy: p, draw: 0.5)
        XCTAssertNil(s.action(now: 60, warm: false, watched: false, searching: false, current: "r1", due: all))          // cold and unwatched: the phone sleeps
        XCTAssertEqual(s.action(now: 60, warm: false, watched: true, searching: false, current: "r1", due: all), .probeCurrent)   // on screen: the line in use first
        s.currentProbed(now: 60, policy: p)
        XCTAssertEqual(s.action(now: 60, warm: false, watched: true, searching: false, current: "r1", due: all), .probe(["r2"]))  // …then the step
        XCTAssertEqual(s.action(now: 60, warm: true, watched: false, searching: false, current: "r1", due: all), .probe(["r2"]))  // traffic flowing: the step, no current
        var f = AutoSchedule(); f.start(now: 0, order: lines)
        XCTAssertEqual(f.action(now: 0, warm: false, watched: false, searching: false, current: "r1", due: all), .probeCurrent)   // the first pass asks nobody
    }

    func testTheLineInUseIsProbedEveryThirtySecondsOnlyWhileWatched() {
        var s = AutoSchedule()
        s.reseed(now: 0, order: lines, policy: p, draw: 0.5)
        XCTAssertNil(s.action(now: 29, warm: true, watched: true, searching: false, current: "r1", due: all))
        XCTAssertEqual(s.action(now: 30, warm: true, watched: true, searching: false, current: "r1", due: all), .probeCurrent)
        XCTAssertEqual(s.action(now: 30, warm: true, watched: false, searching: false, current: "r1", due: all), .probe(["r2"]))        // not watched: the trickle only (its step is due too)
        s.currentProbed(now: 30, policy: p)
        XCTAssertEqual(s.action(now: 30, warm: true, watched: true, searching: false, current: "r1", due: all), .probe(["r2"]))         // both due: the current came first, the step follows
    }

    func testTheJitterKeepsEachStepWithinTenPercentOfThePace() {
        var s = AutoSchedule(); s.reseed(now: 0, order: lines, policy: p, draw: 0.5)
        XCTAssertEqual(s.pace(policy: p, draw: 0), 27, accuracy: 0.001)
        XCTAssertEqual(s.pace(policy: p, draw: 1), 33, accuracy: 0.001)
        XCTAssertEqual(AutoSchedule().pace(policy: p, draw: 0.5), 180, accuracy: 0.001)                                                 // no lines yet: the whole interval
    }

    func testLinesWaitingTheirRetryAreSkippedAndASpentStepMovesOn() {
        var s = AutoSchedule(); s.reseed(now: 0, order: ["a", "b", "c"], policy: p, draw: 0.5)
        let due: (String) -> Bool = { $0 != "b" }
        XCTAssertEqual(s.next(count: 1, current: "a", due: due), ["c"])
        XCTAssertEqual(s.next(count: 2, current: nil, due: due), ["a", "c"])
        XCTAssertEqual(s.next(count: 1, current: "a", due: { $0 == "a" }), [])
        s.nothingDue(now: 60, policy: p, draw: 0.5)
        XCTAssertEqual(s.nextProbeAt!, 120, accuracy: 0.001)
    }

    func testIdleStopsTheTrickleAndTrafficReturningResumesItWithTheLineInUse() {
        var s = AutoSchedule(); s.reseed(now: 0, order: lines, policy: p, draw: 0.5)
        XCTAssertNil(s.action(now: 600, warm: false, watched: false, searching: false, current: "r1", due: all))
        s.wake(now: 600)
        XCTAssertEqual(s.action(now: 600, warm: true, watched: false, searching: false, current: "r1", due: all), .probeCurrent)        // forced: even unwatched
        var fresh = AutoSchedule(); fresh.wake(now: 5)
        XCTAssertNil(fresh.action(now: 5, warm: true, watched: true, searching: false, current: "r1", due: all))                        // before Connect: nothing to wake
    }

    func testANetworkChangeRestartsAQuickPassInFifteenSecondsInUseOrNotDebounced() {
        var s = AutoSchedule(); s.reseed(now: 0, order: lines, policy: p, draw: 0.5)
        s.networkChanged(now: 100)
        XCTAssertNil(s.action(now: 114, warm: false, watched: false, searching: false, current: "r1", due: all))
        XCTAssertEqual(s.action(now: 115, warm: false, watched: false, searching: false, current: "r1", due: all), .probeCurrent)
        s.currentProbed(now: 115, policy: p)
        XCTAssertEqual(s.action(now: 115, warm: false, watched: false, searching: false, current: "r1", due: all), .probe(["r2", "x1"]))   // the quick pass, two at a time
        s.networkChanged(now: 130)                                                                                                        // within a minute: the same event
        XCTAssertEqual(s.lastNetworkAt, 100)
        XCTAssertEqual(s.phase, .first)
    }

    func testSearchingIsTheFastTrickleOverEveryLineRetriesIgnored() {
        var s = AutoSchedule(); s.reseed(now: 0, order: ["a", "b", "c"], policy: p, draw: 0.5)
        s.searchingBegan(now: 50)
        XCTAssertEqual(s.action(now: 50, warm: false, watched: false, searching: true, current: "a", due: { _ in false }), .probe(["a", "b"]))   // every line, the line in use too, two at a time
        s.searchStep(now: 50, count: 2)
        XCTAssertNil(s.action(now: 50.5, warm: false, watched: false, searching: true, current: "a", due: all))
        XCTAssertEqual(s.action(now: 51, warm: false, watched: false, searching: true, current: "a", due: all), .probe(["c", "a"]))
    }

    func testTheFallbackLastsOnlyWhileTheTargetAnswersNobody() {
        XCTAssertFalse(AutoSchedule.nextFallback(current: false, targetAnswered: true, fallbackAnswered: true))
        XCTAssertFalse(AutoSchedule.nextFallback(current: false, targetAnswered: false, fallbackAnswered: false))   // a blip: nobody answers → stay
        XCTAssertTrue(AutoSchedule.nextFallback(current: false, targetAnswered: false, fallbackAnswered: true))
        XCTAssertFalse(AutoSchedule.nextFallback(current: true, targetAnswered: true, fallbackAnswered: false))     // the scout answers: back
        XCTAssertTrue(AutoSchedule.nextFallback(current: true, targetAnswered: false, fallbackAnswered: true))
    }
}
