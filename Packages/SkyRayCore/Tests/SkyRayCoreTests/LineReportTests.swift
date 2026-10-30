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

    func testTheFingerprintIgnoresCloudflaresEchConfigurationButNotTheRest() {
        func line(_ link: String) -> Line { Line(id: UUID().uuidString, link: link, remark: "EthaVPN-WS-www-CleanIP1-ECH3-443", transport: "WS", endpointLabel: nil, port: 443, order: 0, outboundJSON: "{}") }
        let a = "vless://u1@1.1.1.1:443?type=ws&security=tls&sni=www.example.org&ech=AAAAconfigOne#x"
        let b = "vless://u1@1.1.1.1:443?type=ws&security=tls&sni=www.example.org&ech=BBBBconfigTwo#x"
        XCTAssertEqual(LineReport.fingerprint([line(a)]), LineReport.fingerprint([line(b)]))
        XCTAssertNotEqual(LineReport.fingerprint([line(a)]), LineReport.fingerprint([line(a.replacingOccurrences(of: "u1@", with: "u2@"))]))   // a new user id is a change
        XCTAssertNotEqual(LineReport.fingerprint([line(a)]), LineReport.fingerprint([line(a.replacingOccurrences(of: "1.1.1.1", with: "2.2.2.2"))]))
        // the XHTTP download leg carries the configuration inside extra=
        let extra1 = "%7B%22downloadSettings%22%3A%7B%22address%22%3A%22d.example.org%22%2C%22tlsSettings%22%3A%7B%22serverName%22%3A%22d.example.org%22%2C%22echConfigList%22%3A%22AAAA%22%7D%7D%7D"
        let extra2 = "%7B%22downloadSettings%22%3A%7B%22address%22%3A%22d.example.org%22%2C%22tlsSettings%22%3A%7B%22serverName%22%3A%22d.example.org%22%2C%22echConfigList%22%3A%22BBBB%22%7D%7D%7D"
        let x1 = "vless://u1@1.1.1.1:443?type=xhttp&extra=\(extra1)&ech=AAAA#x"
        let x2 = "vless://u1@1.1.1.1:443?type=xhttp&extra=\(extra2)&ech=BBBB#x"
        XCTAssertEqual(LineReport.fingerprint([line(x1)]), LineReport.fingerprint([line(x2)]))
        let x3 = "vless://u1@1.1.1.1:443?type=xhttp&extra=\(extra1.replacingOccurrences(of: "d.example.org", with: "e.example.org"))&ech=AAAA#x"
        XCTAssertNotEqual(LineReport.fingerprint([line(x1)]), LineReport.fingerprint([line(x3)]))   // another download host is a change
        XCTAssertEqual(LineReport.stableLink("vless://u@h:443"), "vless://u@h:443")
        XCTAssertEqual(LineReport.stableLink("vless://u@h:443?ech=zzz"), "vless://u@h:443")
    }

    func testTheRateRidesAfterTheSwitchFlagOnlyWhenThereIsOne() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let with = LineReport.build(now: now, trigger: "auto", inUseRemark: "EthaVPN-REALITY-relay-FRA4-443", switched: false, results: [("EthaVPN-REALITY-relay-FRA4-443", 200)], rateKbps: 18500)
        XCTAssertEqual(with, "v=1;t=1800000000;trig=auto;use=REALITY-relay-FRA4-443;sw=0;r=18500;l=REALITY-relay-FRA4-443:200")
        let without = LineReport.build(now: now, trigger: "auto", inUseRemark: "EthaVPN-REALITY-relay-FRA4-443", switched: false, results: [("EthaVPN-REALITY-relay-FRA4-443", 200)])
        XCTAssertEqual(without, "v=1;t=1800000000;trig=auto;use=REALITY-relay-FRA4-443;sw=0;l=REALITY-relay-FRA4-443:200")
    }

    func testTheConnectTimesRideAfterTheLinesOnlyForLinesNamedThere() {
        let h = LineReport.build(now: Date(timeIntervalSince1970: 1_800_000_000), trigger: "manual", inUseRemark: "EthaVPN-REALITY-relay-FRA4-443", switched: false, results: [
            ("EthaVPN-REALITY-relay-FRA4-443", 200), ("EthaVPN-WS-www-CleanIP1-443", -1), ("EthaVPN-XHTTP-www-CleanIP1-443", 0)],   // the third not measured
            colds: ["EthaVPN-REALITY-relay-FRA4-443": 540, "EthaVPN-XHTTP-www-CleanIP1-443": 900, "EthaVPN-WS-www-CleanIP1-443": -1])
        XCTAssertEqual(h, "v=1;t=1800000000;trig=manual;use=REALITY-relay-FRA4-443;sw=0;l=REALITY-relay-FRA4-443:200,WS-www-CleanIP1-443:-1;c=REALITY-relay-FRA4-443:540")
    }
}
