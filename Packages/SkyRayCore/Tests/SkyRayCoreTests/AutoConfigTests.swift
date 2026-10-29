import XCTest
@testable import SkyRayCore

final class AutoConfigTests: XCTestCase {
    private let a = #"{"protocol":"vless","settings":{"vnext":[{"address":"1.2.3.4","port":443,"users":[{"id":"u"}]}]},"streamSettings":{"network":"tcp"},"tag":"proxy","mux":{"enabled":true}}"#
    private let b = #"{"protocol":"vless","settings":{"vnext":[{"address":"5.6.7.8","port":443,"users":[{"id":"u"}]}]},"streamSettings":{"network":"xhttp","xhttpSettings":{"path":"/p"}},"tag":"proxy"}"#

    private func build() throws -> [String: Any] {
        let json = try XrayConfigBuilder.autoConfig(lines: [(id: "l1", outboundJSON: a, probePort: 41301), (id: "l2", outboundJSON: b, probePort: 41302)],
                                                    socksPort: 10808, apiPort: 41285, assetDir: "/assets", xrayLogPath: "/log")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    func testEveryLineIsAnOutboundBehindOneRandomBalancer() throws {
        let c = try build()
        let outbounds = try XCTUnwrap(c["outbounds"] as? [[String: Any]])
        XCTAssertEqual(outbounds.map { $0["tag"] as? String }, ["line-l1", "line-l2", "direct", "block", "dns-out"])
        XCTAssertNil(outbounds[0]["mux"])   // the line's own mux is dropped, as in tunnelConfig
        let routing = try XCTUnwrap(c["routing"] as? [String: Any])
        let balancers = try XCTUnwrap(routing["balancers"] as? [[String: Any]])
        XCTAssertEqual(balancers.count, 1)
        XCTAssertEqual(balancers[0]["tag"] as? String, "auto")
        XCTAssertEqual(balancers[0]["selector"] as? [String], ["line-"])
        XCTAssertEqual((balancers[0]["strategy"] as? [String: Any])?["type"] as? String, "random")
        let api = try XCTUnwrap(c["api"] as? [String: Any])
        XCTAssertEqual(api["services"] as? [String], ["RoutingService"])
    }

    func testAProbeInboundPerLineReachesThatLineAloneAndTheRestGoesToTheBalancer() throws {
        let c = try build()
        let inbounds = try XCTUnwrap(c["inbounds"] as? [[String: Any]])
        XCTAssertEqual(inbounds.map { $0["tag"] as? String }, ["socks", "api", "probe-l1", "probe-l2"])
        XCTAssertEqual(inbounds[1]["port"] as? Int, 41285)
        XCTAssertEqual(inbounds[2]["port"] as? Int, 41301)
        XCTAssertEqual(inbounds[3]["port"] as? Int, 41302)
        let rules = try XCTUnwrap((c["routing"] as? [String: Any])?["rules"] as? [[String: Any]])
        XCTAssertEqual(rules.first?["outboundTag"] as? String, "api")
        let probeRules = rules.filter { ($0["inboundTag"] as? [String])?.first?.hasPrefix("probe-") == true }
        XCTAssertEqual(probeRules.map { $0["outboundTag"] as? String }, ["line-l1", "line-l2"])
        XCTAssertEqual(rules.last?["balancerTag"] as? String, "auto")
        XCTAssertEqual(rules.last?["network"] as? String, "tcp,udp")
        XCTAssertNil(rules.last?["outboundTag"])
        let dnsRules = rules.filter { ($0["inboundTag"] as? [String]) == ["dns-module"] }
        XCTAssertEqual(dnsRules.count, 2)
        XCTAssertEqual(dnsRules[1]["balancerTag"] as? String, "auto")
        XCTAssertFalse(rules.contains { ($0["outboundTag"] as? String) == "proxy" })
    }

    func testTheTagsAreTheIdsWithTheirPrefixes() {
        XCTAssertEqual(XrayConfigBuilder.lineTag("abc"), "line-abc")
        XCTAssertEqual(XrayConfigBuilder.probeTag("abc"), "probe-abc")
        XCTAssertThrowsError(try XrayConfigBuilder.autoConfig(lines: [], socksPort: 1, apiPort: 2, assetDir: "", xrayLogPath: ""))
    }
}
