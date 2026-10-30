import XCTest
@testable import SkyRayCore

final class HintTests: XCTestCase {
    func testTheHeaderIsParsedAndArrangesTheLines() {
        let h = Hint.parse("v=1;o=REALITY-relay-FRA4-443,REALITY-relay-FRA1-443,WS-www-CleanIP2-443;d=XHTTP-api-CleanIP1-443,XHTTP-api-CleanIP1-ECH3-443;out=0;n=12")!
        XCTAssertEqual(h.order, ["REALITY-relay-FRA4-443", "REALITY-relay-FRA1-443", "WS-www-CleanIP2-443"])
        XCTAssertEqual(h.dead, ["XHTTP-api-CleanIP1-443", "XHTTP-api-CleanIP1-ECH3-443"])
        XCTAssertFalse(h.outage); XCTAssertEqual(h.phones, 12)
        let mine = ["REALITY-relay-FRA1-443", "REALITY-relay-FRA4-443", "XHTTP-api-CleanIP1-443", "XHTTP-api-CleanIP1-ECH3-443", "WS-www-CleanIP2-443", "WS-www-CleanIP9-443"]
        XCTAssertEqual(h.arrange(mine), ["REALITY-relay-FRA4-443", "REALITY-relay-FRA1-443", "WS-www-CleanIP2-443", "WS-www-CleanIP9-443", "XHTTP-api-CleanIP1-443", "XHTTP-api-CleanIP1-ECH3-443"])
        XCTAssertEqual(Hint.parse("v=1;o=;d=;out=1;n=7")?.outage, true)
    }

    func testWhatIsNotAHint() {
        XCTAssertNil(Hint.parse(nil)); XCTAssertNil(Hint.parse("")); XCTAssertNil(Hint.parse("v=2;o=a"))
        XCTAssertNil(Hint.parse("v=1;o=;d=;out=0;n=0"))                      // nothing in it
        XCTAssertNil(Hint.parse("v=1;o=" + String(repeating: "a,", count: 3000)))
        XCTAssertEqual(Hint.parse("v=1;o=good-1-x-443,bad label,good-1-x-443,toolong" + String(repeating: "z", count: 60))?.order, ["good-1-x-443"])
    }
}
