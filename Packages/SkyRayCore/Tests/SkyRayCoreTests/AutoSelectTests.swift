import XCTest
@testable import SkyRayCore

final class AutoSelectTests: XCTestCase {
    private func c(_ id: String, _ delay: Int64, _ order: Int) -> AutoSelect.Candidate { .init(id: id, delayMs: delay, order: order) }

    func testLowestPositiveDelayWins() {
        XCTAssertEqual(AutoSelect.best([c("a", 400, 0), c("b", 140, 1), c("c", 90, 2)]), "c")
    }
    func testOnlyAnExactTieFallsBackToBodyOrder() {
        XCTAssertEqual(AutoSelect.best([c("clean1", 95, 0), c("clean2", 300, 1), c("domain", 80, 3)]), "domain")
        XCTAssertEqual(AutoSelect.best([c("clean1", 80, 0), c("domain", 80, 3)]), "clean1")
        XCTAssertEqual(AutoSelect.best([c("a", 400, 0), c("b", 120, 1), c("c", 121, 2)]), "b")
    }
    func testUntestedAndFailedAreNeverChosen() {
        XCTAssertNil(AutoSelect.best([c("a", 0, 0), c("b", -1, 1)]))
        XCTAssertEqual(AutoSelect.best([c("a", 0, 0), c("b", 500, 1), c("c", -1, 2)]), "b")
        XCTAssertNil(AutoSelect.best([]))
    }
    func testExcludedAreSkipped() {
        let list = [c("a", 50, 0), c("b", 60, 1), c("c", 70, 2)]
        XCTAssertEqual(AutoSelect.best(list, exclude: ["a"]), "b")
        XCTAssertEqual(AutoSelect.best(list, exclude: ["a", "b"]), "c")
        XCTAssertNil(AutoSelect.best(list, exclude: ["a", "b", "c"]))
    }
    func testFreshness() {
        let now = Date()
        XCTAssertFalse(AutoSelect.resultsFresh(lastTestAt: nil, now: now))
        XCTAssertTrue(AutoSelect.resultsFresh(lastTestAt: now.addingTimeInterval(-599), now: now))
        XCTAssertFalse(AutoSelect.resultsFresh(lastTestAt: now.addingTimeInterval(-600), now: now))
    }
}
