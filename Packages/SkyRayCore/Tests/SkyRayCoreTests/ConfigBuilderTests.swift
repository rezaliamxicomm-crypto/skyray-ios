import XCTest
@testable import SkyRayCore

final class ConfigBuilderTests: XCTestCase {
    private let outbound = #"{"tag":"whatever","protocol":"vless","settings":{"vnext":[{"address":"1.2.3.4","port":443,"users":[{"id":"u","encryption":"none"}]}]},"streamSettings":{"network":"ws","security":"tls"},"mux":{"enabled":true}}"#

    private func json(_ s: String) throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any] }

    func testTunnelConfigShape() throws {
        let s = try XrayConfigBuilder.tunnelConfig(outboundJSON: outbound, socksPort: 10808, probePort: 41000, assetDir: "/assets", xrayLogPath: "/logs/xray.log")
        let c = try json(s)
        XCTAssertEqual((c["env"] as! [String: String])["XRAY_LOCATION_ASSET"], "/assets")
        let outbounds = c["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds.first?["tag"] as? String, "proxy")
        XCTAssertNil(outbounds.first?["mux"])
        XCTAssertEqual(outbounds.map { $0["tag"] as! String }, ["proxy", "direct", "block", "dns-out"])
        XCTAssertFalse(s.contains("geosite:private"))
        XCTAssertFalse(s.contains("dialerProxy"))
        var withMux = XrayConfigBuilder.Options(); withMux.mux = true
        let muxed = try json(try XrayConfigBuilder.tunnelConfig(outboundJSON: outbound, socksPort: 1, probePort: 2, assetDir: "/a", xrayLogPath: "/l", options: withMux))
        let mux = (muxed["outbounds"] as! [[String: Any]]).first?["mux"] as! [String: Any]
        XCTAssertEqual(mux["enabled"] as? Bool, true); XCTAssertEqual(mux["concurrency"] as? Int, 8)
        let routing = c["routing"] as! [String: Any]
        XCTAssertEqual(routing["domainMatcher"] as? String, "linear")
        let rules = routing["rules"] as! [[String: Any]]
        XCTAssertTrue(rules.contains { ($0["port"] as? String) == "443" && ($0["network"] as? String) == "udp" && ($0["outboundTag"] as? String) == "block" })
        XCTAssertTrue(rules.contains { ($0["port"] as? String) == "53" && ($0["outboundTag"] as? String) == "dns-out" && ($0["inboundTag"] as? [String]) == ["socks"] })
        XCTAssertTrue(rules.contains { ($0["inboundTag"] as? [String]) == ["dns-module"] && ($0["ip"] as? [String]) == ["178.22.122.100"] && ($0["outboundTag"] as? String) == "direct" })
        let levels = (c["policy"] as! [String: Any])["levels"] as! [String: [String: Any]]
        XCTAssertEqual(levels["8"]?["bufferSize"] as? Int, 4)
        XCTAssertEqual((c["dns"] as! [String: Any])["queryStrategy"] as? String, "UseIPv4")
        let inbounds = c["inbounds"] as! [[String: Any]]
        XCTAssertEqual(inbounds.map { $0["tag"] as! String }, ["socks", "probe"])
        XCTAssertEqual(inbounds[0]["port"] as? Int, 10808)
        XCTAssertEqual((inbounds[0]["settings"] as! [String: Any])["udp"] as? Bool, true)
        XCTAssertEqual(inbounds[1]["port"] as? Int, 41000)
    }
    func testFragmentAddsTheDialer() throws {
        var options = XrayConfigBuilder.Options(); options.fragment = true
        let c = try json(try XrayConfigBuilder.tunnelConfig(outboundJSON: outbound, socksPort: 1, probePort: 2, assetDir: "/a", xrayLogPath: "/l", options: options))
        let outbounds = c["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds.map { $0["tag"] as! String }, ["proxy", "fragment", "direct", "block", "dns-out"])
        let sockopt = (outbounds[0]["streamSettings"] as! [String: Any])["sockopt"] as! [String: Any]
        XCTAssertEqual(sockopt["dialerProxy"] as? String, "fragment")
        let fragment = (outbounds[1]["settings"] as! [String: Any])["fragment"] as! [String: String]
        XCTAssertEqual(fragment["packets"], "tlshello")
        let ping = try json(try XrayConfigBuilder.pingConfig(outboundJSON: outbound, bindInterface: "en0", options: options))
        let pingOutbounds = ping["outbounds"] as! [[String: Any]]
        XCTAssertEqual(pingOutbounds.count, 2)
        let fragSockopt = (pingOutbounds[1]["streamSettings"] as! [String: Any])["sockopt"] as! [String: Any]
        XCTAssertEqual(fragSockopt["interface"] as? String, "en0")
    }
    func testPingConfigBindsOnlyWhenAsked() throws {
        let plain = try json(try XrayConfigBuilder.pingConfig(outboundJSON: outbound))
        let ob = (plain["outbounds"] as! [[String: Any]])[0]
        XCTAssertEqual(ob["tag"] as? String, "proxy")
        XCTAssertNil(ob["mux"])
        XCTAssertNil((ob["streamSettings"] as! [String: Any])["sockopt"])
        let bound = try json(try XrayConfigBuilder.pingConfig(outboundJSON: outbound, bindInterface: "en0"))
        let sockopt = ((bound["outbounds"] as! [[String: Any]])[0]["streamSettings"] as! [String: Any])["sockopt"] as! [String: Any]
        XCTAssertEqual(sockopt["interface"] as? String, "en0")
    }
    func testTestConfigRoutesEachInboundToItsLine() throws {
        let c = try json(try XrayConfigBuilder.testConfig(lines: [(id: "a", outboundJSON: outbound, port: 43001), (id: "b", outboundJSON: outbound, port: 43002)], bindInterface: "en0"))
        let inbounds = c["inbounds"] as! [[String: Any]]
        XCTAssertEqual(inbounds.map { $0["tag"] as! String }, ["in-a", "in-b"])
        XCTAssertEqual(inbounds[1]["port"] as? Int, 43002)
        let outbounds = c["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds.map { $0["tag"] as! String }, ["out-a", "out-b", "block"])
        XCTAssertEqual(((outbounds[0]["streamSettings"] as! [String: Any])["sockopt"] as! [String: Any])["interface"] as? String, "en0")
        XCTAssertNil(outbounds[0]["mux"])
        let rules = (c["routing"] as! [String: Any])["rules"] as! [[String: Any]]
        XCTAssertEqual(rules.count, 3)
        XCTAssertEqual(rules[0]["inboundTag"] as? [String], ["in-a"]); XCTAssertEqual(rules[0]["outboundTag"] as? String, "out-a")
        XCTAssertEqual(rules[2]["outboundTag"] as? String, "block")
        var frag = XrayConfigBuilder.Options(); frag.fragment = true
        let f = try json(try XrayConfigBuilder.testConfig(lines: [(id: "a", outboundJSON: outbound, port: 1)], options: frag))
        XCTAssertEqual((f["outbounds"] as! [[String: Any]]).map { $0["tag"] as! String }, ["out-a", "fragment-a", "block"])
    }
    func testInvalidOutboundThrows() {
        XCTAssertThrowsError(try XrayConfigBuilder.pingConfig(outboundJSON: "not json"))
    }
    func testStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skyray-store-\(UUID().uuidString)")
        let store = SkyRayStore(root: dir)
        XCTAssertNil(store.loadSnapshot())
        var info = SubscriptionInfo(); info.download = 5
        let snap = SubscriptionSnapshot(url: "https://x/sub/0123456789abcdef", name: "EthaVPN", fetchedAt: Date(timeIntervalSince1970: 1000), info: info,
                                        lines: [Line(id: "a", link: "vless://x", remark: "EthaVPN-WS-cdn-CleanIP1-443", transport: "WS", endpointLabel: "CleanIP1", port: 443, order: 0, outboundJSON: "{}")])
        store.saveSnapshot(snap)
        XCTAssertEqual(store.loadSnapshot(), snap)
        store.updateSelection { $0.selectedLineId = "a"; $0.pinned = true; $0.results["a"] = 42 }
        XCTAssertEqual(store.selection.selectedLineId, "a"); XCTAssertTrue(store.selection.pinned); XCTAssertEqual(store.selection.delay(of: "a"), 42)
        store.declarationAccepted = true
        store.wipe(rememberingDeletedLink: snap.url)
        XCTAssertNil(store.loadSnapshot()); XCTAssertNil(store.selection.selectedLineId)
        XCTAssertEqual(store.deletedLink, snap.url); XCTAssertTrue(store.declarationAccepted)
        try? FileManager.default.removeItem(at: dir)
    }
}
