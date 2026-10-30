import XCTest
@testable import SkyRayCore

final class AutoDecisionTests: XCTestCase {
    let p = AutoPolicy()
    func c(_ id: String, _ ms: Int64, _ order: Int = 0) -> AutoDecision.Candidate { AutoDecision.Candidate(id: id, ms: ms, order: order) }

    func testAFailedLineInUseFailsOverToTheBestKnownAtOnce() {
        var d = AutoDecision()
        d.lastSwitchAt = 95                                                     // moved five seconds ago: the dwell does not hold a failover
        XCTAssertEqual(d.target(now: 100, phase: .passEnd, current: c("a", -1), candidates: [c("a", -1), c("b", 300, 1), c("c", 200, 2)], policy: p), "c")
        XCTAssertEqual(d.target(now: 100, phase: .failover, current: c("a", 200), candidates: [c("a", 200), c("b", 300, 1)], policy: p), "b")
        XCTAssertNil(d.target(now: 100, phase: .failover, current: c("a", -1), candidates: [c("a", -1), c("b", -1, 1)], policy: p))   // nothing known good
    }

    func testTheFirstPassMovesOnceAndOnlyForAClearlyBetterLine() {
        var d = AutoDecision()
        XCTAssertNil(d.target(now: 1, phase: .first, current: c("a", 393), candidates: [c("a", 393), c("b", 300, 1)], policy: p))      // 300 is not twice the margin better
        XCTAssertEqual(d.target(now: 2, phase: .first, current: c("a", 393), candidates: [c("a", 393), c("b", 203, 1)], policy: p), "b")
        XCTAssertNil(d.target(now: 3, phase: .first, current: c("b", 203), candidates: [c("b", 203), c("c", 100, 2)], policy: p))       // one move in the first pass
    }

    func testSteadyStateNeedsPersistenceAndRespectsTheDwell() {
        var d = AutoDecision()
        let lines = [c("a", 200), c("b", 160, 1)]                              // b ahead by 20 %: by the margin, not twice
        XCTAssertNil(d.target(now: 180, phase: .passEnd, current: c("a", 200), candidates: lines, policy: p))       // first pass end: noted
        XCTAssertEqual(d.leading["b"], 1)
        XCTAssertEqual(d.target(now: 360, phase: .passEnd, current: c("a", 200), candidates: lines, policy: p), "b")   // second: moves
        XCTAssertEqual(d.lastSwitchAt, 360)
        // a line ahead by twice the margin moves at one pass end, but not within the dwell
        XCTAssertNil(d.target(now: 400, phase: .passEnd, current: c("b", 160), candidates: [c("b", 160), c("c", 90, 2)], policy: p))
        XCTAssertEqual(d.target(now: 450, phase: .passEnd, current: c("b", 160), candidates: [c("b", 160), c("c", 90, 2)], policy: p), "c")
        // the lead must be consecutive
        var e = AutoDecision()
        _ = e.target(now: 180, phase: .passEnd, current: c("a", 200), candidates: [c("a", 200), c("b", 160, 1)], policy: p)
        XCTAssertNil(e.target(now: 360, phase: .passEnd, current: c("a", 200), candidates: [c("a", 200), c("b", 195, 1)], policy: p))   // the lead is gone
        XCTAssertEqual(e.leading, [:])
    }

    func testAManualTestMovesByTheMarginAlone() {
        var d = AutoDecision(); d.lastSwitchAt = 99
        XCTAssertEqual(d.target(now: 100, phase: .manual, current: c("a", 200), candidates: [c("a", 200), c("b", 160, 1)], policy: p), "b")
        XCTAssertNil(d.target(now: 101, phase: .manual, current: c("b", 160), candidates: [c("b", 160), c("a", 150, 0)], policy: p))     // 10 ms: under the floor
    }

    /// An hour of steady state with every line's time wandering ±10 % around the same value: nobody moves. A line that
    /// then settles 30 % below the line in use for two passes: exactly one move. The line in use dying: one failover.
    func testSimulationNoiseMovesNobodyARealLeadMovesOnceADeathMovesAtOnce() {
        var d = AutoDecision()
        var rng = SystemRandomNumberGenerator()
        var current = "r1"; var moves = 0
        let base: [String: Int64] = ["r1": 200, "r2": 205, "x1": 220, "w1": 210]
        for pass in 1...20 {                                                   // an hour of passes
            let cands = base.map { id, ms in c(id, ms + Int64.random(in: -(ms / 10)...(ms / 10), using: &rng), ["r1", "r2", "x1", "w1"].firstIndex(of: id)!) }
            if let t = d.target(now: Double(pass * 180), phase: .passEnd, current: cands.first { $0.id == current }!, candidates: cands, policy: p) { current = t; moves += 1 }
        }
        XCTAssertEqual(moves, 0, "noise of ±10 % must not move anyone")
        for pass in 21...24 {                                                  // r2 settles clearly ahead
            let cands = [c("r1", 200), c("r2", 140, 1), c("x1", 220, 2), c("w1", 210, 3)]
            if let t = d.target(now: Double(pass * 180), phase: .passEnd, current: cands.first { $0.id == current }!, candidates: cands, policy: p) { current = t; moves += 1 }
        }
        XCTAssertEqual(moves, 1); XCTAssertEqual(current, "r2")
        let dead = [c("r1", 200), c("r2", -1, 1), c("x1", 220, 2), c("w1", 210, 3)]
        XCTAssertEqual(d.target(now: 25 * 180, phase: .failover, current: c("r2", -1, 1), candidates: dead, policy: p), "r1")
    }
}
