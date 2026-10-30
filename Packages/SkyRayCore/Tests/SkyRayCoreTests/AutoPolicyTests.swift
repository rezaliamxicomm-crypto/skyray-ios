import XCTest
@testable import SkyRayCore

final class AutoPolicyTests: XCTestCase {
    private let p = AutoPolicy()
    private func c(_ id: String, _ delay: Int64, _ order: Int) -> AutoSelect.Candidate { AutoSelect.Candidate(id: id, delayMs: delay, order: order) }

    func testTheMarginIsAShareOfTheLineInUseWithAFloor() {
        XCTAssertTrue(p.shouldSwitch(currentMs: 400, bestMs: 330))      // 60 ms margin at 400
        XCTAssertFalse(p.shouldSwitch(currentMs: 400, bestMs: 345))
        XCTAssertTrue(p.shouldSwitch(currentMs: 100, bestMs: 70))       // the 25 ms floor applies under 167 ms
        XCTAssertFalse(p.shouldSwitch(currentMs: 100, bestMs: 80))
        XCTAssertFalse(p.shouldSwitch(currentMs: 200, bestMs: 200))
    }

    func testAFailedLineInUseIsLeftAtOnceAndAnUnmeasuredOneWaits() {
        XCTAssertTrue(p.shouldSwitch(currentMs: -1, bestMs: 900))
        XCTAssertFalse(p.shouldSwitch(currentMs: 0, bestMs: 50))
        XCTAssertFalse(p.shouldSwitch(currentMs: -1, bestMs: -1))
        XCTAssertFalse(p.shouldSwitch(currentMs: 300, bestMs: 0))
    }

    func testTheTargetIsTheBestLineOnlyWhenItEarnsTheMove() {
        let lines = [c("relay", 180, 0), c("clean1", 160, 1), c("clean2", -1, 2), c("ws", 0, 3)]
        XCTAssertNil(p.target(current: "relay", candidates: lines, pinned: false))        // 160 is not 27 (15 % of 180) under 180
        XCTAssertEqual(p.target(current: "relay", candidates: [c("relay", 180, 0), c("clean1", 150, 1)], pinned: false), "clean1")   // 150 is
        XCTAssertEqual(p.target(current: "clean2", candidates: lines, pinned: false), "clean1")
        XCTAssertEqual(p.target(current: nil, candidates: lines, pinned: false), "clean1")
        XCTAssertEqual(p.target(current: "gone", candidates: lines, pinned: false), "clean1")
        XCTAssertNil(p.target(current: "ws", candidates: lines, pinned: false))
        XCTAssertNil(p.target(current: "clean2", candidates: lines, pinned: true))
        XCTAssertNil(p.target(current: "relay", candidates: [c("relay", -1, 0), c("x", -1, 1)], pinned: false))
        XCTAssertNil(p.target(current: "clean1", candidates: lines, pinned: false))
    }

    func testAStallIsBytesOutAndNoneBackOverTheWindow() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let s = [AutoPolicy.Sample(at: t0, up: 1000, down: 5000), AutoPolicy.Sample(at: t0 + 4, up: 4000, down: 5000),
                 AutoPolicy.Sample(at: t0 + 8, up: 9000, down: 5000)]
        XCTAssertTrue(p.stalled(s, now: t0 + 8))
        XCTAssertFalse(p.stalled(s, now: t0 + 7))
        XCTAssertFalse(p.stalled([AutoPolicy.Sample(at: t0, up: 1000, down: 5000), AutoPolicy.Sample(at: t0 + 8, up: 1500, down: 5000)], now: t0 + 8))
        XCTAssertFalse(p.stalled([AutoPolicy.Sample(at: t0, up: 1000, down: 5000), AutoPolicy.Sample(at: t0 + 8, up: 9000, down: 5100)], now: t0 + 8))
        XCTAssertFalse(p.stalled([AutoPolicy.Sample(at: t0, up: 1000, down: 5000)], now: t0 + 8))
    }

    func testTheHeaderReplacesValuesWithinBoundsAndIgnoresTheRest() {
        let q = AutoPolicy.parse("round=120, failed=600;idle=300,margin=10,floor=40,stall=6,timeout=4,conc=16,fresh=900,colour=blue,round=x")
        XCTAssertEqual(q, AutoPolicy(roundSec: 120, failedRetrySec: 600, idleSec: 300, marginPct: 10, floorMs: 40, stallSec: 6, probeTimeoutSec: 4, concurrency: 16, freshSec: 900))
        XCTAssertEqual(AutoPolicy.parse(nil), AutoPolicy())
        XCTAssertEqual(AutoPolicy.parse(" "), AutoPolicy())
        XCTAssertEqual(AutoPolicy.parse("garbage"), AutoPolicy())
        XCTAssertEqual(AutoPolicy.parse("round=5,failed=1,idle=1,margin=200,floor=-3,stall=1,timeout=0,conc=0,fresh=-1"),
                       AutoPolicy(roundSec: 30, failedRetrySec: 30, idleSec: 60, marginPct: 90, floorMs: 0, stallSec: 3, probeTimeoutSec: 2, concurrency: 1, freshSec: 0))
        XCTAssertEqual(AutoPolicy.parse("margin=30", base: q).marginPct, 30)
        XCTAssertEqual(AutoPolicy.parse("margin=30", base: q).roundSec, 120)
    }

    func testTheSearchingCadenceComesFromTheHeaderToo() {
        XCTAssertEqual(AutoPolicy().searchSec, 60)
        XCTAssertEqual(AutoPolicy().searchFetchSec, 300)
        let q = AutoPolicy.parse("search=30,sfetch=120")
        XCTAssertEqual(q.searchSec, 30)
        XCTAssertEqual(q.searchFetchSec, 120)
        let clamped = AutoPolicy.parse("search=1,sfetch=99999")
        XCTAssertEqual(clamped.searchSec, 15)
        XCTAssertEqual(clamped.searchFetchSec, 3600)
    }

    func testTheSettlingRoundAndTheJitterComeFromTheHeaderToo() {
        XCTAssertEqual(AutoPolicy().settleSec, 10)
        XCTAssertEqual(AutoPolicy().jitterPct, 10)
        let q = AutoPolicy.parse("settle=0,jitter=50")
        XCTAssertEqual(q.settleSec, 0); XCTAssertEqual(q.jitterPct, 50)
        let clamped = AutoPolicy.parse("settle=999,jitter=99")
        XCTAssertEqual(clamped.settleSec, 120); XCTAssertEqual(clamped.jitterPct, 50)
        let p = AutoPolicy()
        XCTAssertEqual(p.jitteredRound(using: 0.5), 180, accuracy: 0.001)
        XCTAssertEqual(p.jitteredRound(using: 0), 162, accuracy: 0.001)      // 10 % either way: 162–198 s
        XCTAssertEqual(p.jitteredRound(using: 1), 198, accuracy: 0.001)
        XCTAssertEqual(AutoPolicy.parse("jitter=0").jitteredRound(using: 0.9), 180, accuracy: 0.001)
    }
}
