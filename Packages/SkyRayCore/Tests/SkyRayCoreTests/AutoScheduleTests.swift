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
        XCTAssertFalse(s.probed(now: 10, ids: ["r2", "x1"], policy: p, draw: 0.5))
        XCTAssertNil(s.action(now: 10.5, warm: false, watched: false, searching: false, current: "r1", due: all))
        XCTAssertEqual(s.action(now: 11, warm: false, watched: false, searching: false, current: "r1", due: all), .probe(["x2", "w1"]))   // a second a step
        XCTAssertFalse(s.probed(now: 11, ids: ["x2", "w1"], policy: p, draw: 0.5))
        XCTAssertEqual(s.action(now: 12, warm: false, watched: false, searching: false, current: "r1", due: all), .probe(["w2"]))       // r1 is the line in use: the pass ends with w2
        XCTAssertTrue(s.probed(now: 12, ids: ["w2"], policy: p, draw: 0.5))                                                                  // a pass: the first pass is over
        XCTAssertEqual(s.phase, .steady); XCTAssertEqual(s.passes, 1); XCTAssertFalse(s.forced)
        XCTAssertNil(s.action(now: 13, warm: false, watched: false, searching: false, current: "r1", due: all))                          // idle now: nothing
        XCTAssertEqual(s.pace(policy: p, draw: 0.5), 30, accuracy: 0.001)                                                                  // 180 s over 6 lines
        XCTAssertNil(s.action(now: 41, warm: true, watched: false, searching: false, current: "r1", due: all))
        XCTAssertEqual(s.action(now: 42, warm: true, watched: false, searching: false, current: "r1", due: all), .probe(["r1"]))        // one at a time from here, the line in use among them
        _ = s.probed(now: 42, ids: ["r1"], policy: p, draw: 0.5)
        XCTAssertEqual(s.action(now: 72, warm: true, watched: false, searching: false, current: "r1", due: all), .probe(["r2"]))
        // the pace spreads the round over the lines that can be probed, not over lines waiting their retry
        _ = s.probed(now: 72, ids: ["r2"], policy: p, draw: 0.5, active: 2)
        XCTAssertEqual(s.nextProbeAt!, 72 + 90, accuracy: 0.001)                                                                 // 180 s over 2 live lines
    }

    func testASteadyStepNeedsAWarmRadioOrTheScreenAndTheFirstPassNeedsNeither() {
        var s = AutoSchedule(); s.reseed(now: 0, order: lines, policy: p, draw: 0.5)
        XCTAssertNil(s.action(now: 60, warm: false, watched: false, searching: false, current: "r1", due: all))          // cold and unwatched: the phone sleeps
        XCTAssertEqual(s.action(now: 60, warm: false, watched: true, searching: false, current: "r1", due: all), .probeCurrent)   // on screen: the line in use first
        s.currentProbed(now: 60, policy: p)
        XCTAssertEqual(s.action(now: 60, warm: false, watched: true, searching: false, current: "r1", due: all), .probe(["r1"]))  // …then the step (steady: the line in use is in the rotation)
        XCTAssertEqual(s.action(now: 60, warm: true, watched: false, searching: false, current: "r1", due: all), .probe(["r1"]))  // traffic flowing: the step, no extra current probe
        var f = AutoSchedule(); f.start(now: 0, order: lines)
        XCTAssertEqual(f.action(now: 0, warm: false, watched: false, searching: false, current: "r1", due: all), .probeCurrent)   // the first pass asks nobody
    }

    func testTheLineInUseIsProbedEveryThirtySecondsOnlyWhileWatched() {
        var s = AutoSchedule()
        s.reseed(now: 0, order: lines, policy: p, draw: 0.5)
        XCTAssertNil(s.action(now: 29, warm: true, watched: true, searching: false, current: "r1", due: all))
        XCTAssertEqual(s.action(now: 30, warm: true, watched: true, searching: false, current: "r1", due: all), .probeCurrent)
        XCTAssertEqual(s.action(now: 30, warm: true, watched: false, searching: false, current: "r1", due: all), .probe(["r1"]))        // not watched: the trickle only (its step is due too)
        s.currentProbed(now: 30, policy: p)
        XCTAssertEqual(s.action(now: 30, warm: true, watched: true, searching: false, current: "r1", due: all), .probe(["r1"]))         // both due: the current came first, the step follows
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
        XCTAssertEqual(s.cursor, 0); XCTAssertEqual(s.passes, 1)                                                     // the rest held nothing: the pass ended
        // a skipped line on the way counts as consumed: the step after [r2, x1] (r1 skipped) is [x2, w1], never x1 again
        var r = AutoSchedule(); r.start(now: 0, order: ["r1", "r2", "x1", "x2", "w1", "w2"])
        XCTAssertEqual(r.next(count: 2, current: "r1", due: all), ["r2", "x1"]); _ = r.probed(now: 0, ids: ["r2", "x1"], policy: p, draw: 0.5)
        XCTAssertEqual(r.cursor, 3); XCTAssertEqual(r.next(count: 2, current: "r1", due: all), ["x2", "w1"])
        _ = r.probed(now: 1, ids: ["x2", "w1"], policy: p, draw: 0.5); XCTAssertEqual(r.next(count: 2, current: "r1", due: all), ["w2"])   // a step never straddles a pass
    }

    func testIdleStopsTheTrickleAndTrafficReturningResumesItWithTheLineInUse() {
        var s = AutoSchedule(); s.reseed(now: 0, order: lines, policy: p, draw: 0.5)
        XCTAssertNil(s.action(now: 600, warm: false, watched: false, searching: false, current: "r1", due: all))
        s.wake(now: 600)
        XCTAssertEqual(s.action(now: 600, warm: false, watched: false, searching: false, current: "r1", due: all), .probeCurrent)       // one probe of the line in use, watched or not
        s.currentProbed(now: 600, policy: p)
        XCTAssertNil(s.action(now: 601, warm: false, watched: false, searching: false, current: "r1", due: all))                       // then the trickle waits for the radio or the screen: no forced pass
        XCTAssertFalse(s.forced)
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
        s.searchStep(now: 50, count: 2, policy: p)
        XCTAssertNil(s.action(now: 79, warm: false, watched: false, searching: true, current: "a", due: all))                         // paced: 3 lines, two a step → a step every 30 s, each line once a minute
        XCTAssertEqual(s.action(now: 80, warm: false, watched: false, searching: true, current: "a", due: all), .probe(["c"]))        // to the end of the rotation…
        s.searchStep(now: 80, count: 1, policy: p, slow: true)                                                                         // the box says the network blocks every line: three times slower
        XCTAssertNil(s.action(now: 169, warm: false, watched: false, searching: true, current: "a", due: all))
        XCTAssertEqual(s.action(now: 170, warm: false, watched: false, searching: true, current: "a", due: all), .probe(["a", "b"]))  // …then round again
        s.searchStep(now: 170, count: 2, policy: p)
        XCTAssertNil(s.action(now: 700, warm: false, watched: false, searching: true, current: "a", due: all))                        // ten minutes in: only warm or watched
        XCTAssertEqual(s.action(now: 700, warm: true, watched: false, searching: true, current: "a", due: all), .probe(["c"]))
    }

    func testTheFallbackLastsOnlyWhileTheTargetAnswersNobody() {
        XCTAssertFalse(AutoSchedule.nextFallback(current: false, targetAnswered: true, fallbackAnswered: true))
        XCTAssertFalse(AutoSchedule.nextFallback(current: false, targetAnswered: false, fallbackAnswered: false))   // a blip: nobody answers → stay
        XCTAssertTrue(AutoSchedule.nextFallback(current: false, targetAnswered: false, fallbackAnswered: true))
        XCTAssertFalse(AutoSchedule.nextFallback(current: true, targetAnswered: true, fallbackAnswered: false))     // the scout answers: back
        XCTAssertTrue(AutoSchedule.nextFallback(current: true, targetAnswered: false, fallbackAnswered: true))
    }
}
