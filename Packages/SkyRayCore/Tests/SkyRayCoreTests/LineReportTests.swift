import XCTest
@testable import SkyRayCore

final class LineReportTests: XCTestCase {
    func testALabelIsTheNameWithoutOurPrefix() {
        XCTAssertEqual(LineReport.label("EthaVPN-REALITY-relay-FRA9-443"), "REALITY-relay-FRA9-443")
        XCTAssertEqual(LineReport.label(" EthaVPN-XHTTP-api-CleanIP1-443 "), "XHTTP-api-CleanIP1-443")
        XCTAssertNil(LineReport.label("Some other provider"))
        XCTAssertNil(LineReport.label("EthaVPN-with spaces-443"))
        XCTAssertNil(LineReport.label(nil))
    }

    func testTheHeaderCarriesEveryMeasuredLineOfOurs() {
        let h = LineReport.build(now: Date(timeIntervalSince1970: 1_761_770_000.9), trigger: "manual", inUseRemark: "EthaVPN-REALITY-relay-FRA9-443", switched: true, results: [
            ("EthaVPN-REALITY-relay-FRA9-443", 298), ("EthaVPN-XHTTP-api-CleanIP1-443", -1), ("EthaVPN-WS-ECH3-CleanIP2-443", 0), ("Other provider line", 120)])
        XCTAssertEqual(h, "v=1;t=1761770000;trig=manual;use=REALITY-relay-FRA9-443;sw=1;l=REALITY-relay-FRA9-443:298,XHTTP-api-CleanIP1-443:-1")
        XCTAssertNil(LineReport.build(now: Date(), trigger: "auto", inUseRemark: nil, switched: false, results: [("Other", 5), ("EthaVPN-X-y-z-1", 0)]))
    }

    func testTheHeaderStaysSmall() throws {
        let many = (1...200).map { ("EthaVPN-XHTTP-api-CleanIP\($0)-443", Int64($0)) }
        let h = try XCTUnwrap(LineReport.build(now: Date(), trigger: "auto", inUseRemark: nil, switched: false, results: many))
        XCTAssertEqual(h.components(separatedBy: "l=")[1].split(separator: ",").count, LineReport.maxLines)
        XCTAssertLessThan(h.count, 4096)
    }

    func testTheFingerprintIgnoresOrderAndIds() {
        func line(_ id: String, _ link: String) -> Line { Line(id: id, link: link, remark: "r", transport: nil, endpointLabel: nil, port: nil, order: 0, outboundJSON: "{}") }
        let a = LineReport.fingerprint([line("1", "vless://u@1.1.1.1:443#x"), line("2", "vless://u@2.2.2.2:443#y")])
        let b = LineReport.fingerprint([line("9", "vless://u@2.2.2.2:443#y"), line("8", "vless://u@1.1.1.1:443#x")])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, LineReport.fingerprint([line("1", "vless://u@1.1.1.1:443#x"), line("2", "vless://u@3.3.3.3:443#y")]))
    }
}
