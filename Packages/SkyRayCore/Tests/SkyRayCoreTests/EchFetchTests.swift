import XCTest
@testable import SkyRayCore

final class EchFetchTests: XCTestCase {
    private func line(_ id: String, _ link: String, order: Int = 0) -> Line {
        Line(id: id, link: link, remark: id, transport: nil, endpointLabel: nil, port: nil, order: order, outboundJSON: "{}")
    }

    func testAddressOfAShareLink() {
        XCTAssertEqual(EchFetch.address(ofLink: "vless://0b0f7c1e-aaaa-bbbb-cccc-000000000001@104.18.36.216:443?encryption=none&type=xhttp#EthaVPN-XHTTP-api-CleanIP1-443"), "104.18.36.216")
        XCTAssertEqual(EchFetch.address(ofLink: "vless://id@api.example.org:2053?type=ws#name"), "api.example.org")
        XCTAssertEqual(EchFetch.address(ofLink: "vless://id@104.21.33.75:8443#no-query"), "104.21.33.75")
        XCTAssertEqual(EchFetch.address(ofLink: "vless://id@104.21.33.75"), "104.21.33.75")
        XCTAssertNil(EchFetch.address(ofLink: "vless://id@[2606:4700::1]:443?type=ws"))
        XCTAssertNil(EchFetch.address(ofLink: "vless://no-address-here"))
        XCTAssertNil(EchFetch.address(ofLink: "not a link"))
        XCTAssertNil(EchFetch.address(ofLink: "vless://id@:443"))
    }

    func testCandidateAddressesKeepOrderDropRepeatsAndNonIPv4() {
        let stored = ["104.21.67.176", " 172.67.179.3 ", "104.21.67.176", "api.xicomm.net", "2606:4700::1", "", "1.2.3", "300.1.1.1", "1.2.3.4.5", "١.٢.٣.٤"]
        XCTAssertEqual(EchFetch.candidateAddresses(stored), ["104.21.67.176", "172.67.179.3"])
    }

    func testCandidateAddressesAreCapped() {
        let stored = (1...10).map { "104.21.67.\($0)" }
        let picked = EchFetch.candidateAddresses(stored)
        XCTAssertEqual(picked.count, EchFetch.maxStoredAddresses)
        XCTAssertEqual(picked, Array(stored.prefix(EchFetch.maxStoredAddresses)))   // the first ones: the selected line leads
    }

    func testStoredAddressesPutTheSelectedLineFirst() {
        let lines = [
            line("a", "vless://id@104.18.36.216:443?type=xhttp#one", order: 0),
            line("b", "vless://id@api.example.org:443?type=xhttp#two", order: 1),
            line("c", "vless://id@104.21.33.75:2053?type=ws#three", order: 2)
        ]
        XCTAssertEqual(EchFetch.storedAddresses(lines: lines, selectedLineId: nil), ["104.18.36.216", "api.example.org", "104.21.33.75"])
        XCTAssertEqual(EchFetch.storedAddresses(lines: lines, selectedLineId: "c"), ["104.21.33.75", "104.18.36.216", "api.example.org"])
        XCTAssertEqual(EchFetch.storedAddresses(lines: lines, selectedLineId: "gone"), ["104.18.36.216", "api.example.org", "104.21.33.75"])
        XCTAssertEqual(EchFetch.storedAddresses(lines: [], selectedLineId: "c"), [])
        // what the core is offered: IPv4 only, the selected line's first
        XCTAssertEqual(EchFetch.candidateAddresses(EchFetch.storedAddresses(lines: lines, selectedLineId: "c")), ["104.21.33.75", "104.18.36.216"])
    }

    func testRequestCarriesTheKeyTheResolversAndTheAddresses() throws {
        let request = EchFetch.request(url: "https://fra.skyrayconfig.org/sub/0123456789abcdef", stored: ["104.21.67.176"], userAgent: "SkyRay/1.3.6 (ios)")
        XCTAssertEqual(request.addresses, ["104.21.67.176"])
        XCTAssertEqual(request.pinnedAddresses, Etha.echAddresses)
        XCTAssertEqual(request.resolvers, Etha.echResolvers)
        XCTAssertEqual(request.lookupName, Etha.echLookupName)
        XCTAssertEqual(request.pinnedKey, Etha.echPinnedKey)
        XCTAssertEqual(request.timeoutMs, EchFetch.timeoutMs)
        XCTAssertEqual(request.interface, "")                          // no tunnel up: no binding
        let bound = EchFetch.request(url: "https://fra.skyrayconfig.org/sub/0123456789abcdef", stored: [], userAgent: "x", interface: "en0", timeoutMs: EchFetch.secondWayTimeoutMs)
        XCTAssertEqual(bound.interface, "en0")
        XCTAssertLessThan(EchFetch.secondWayTimeoutMs, EchFetch.timeoutMs)

        // the core reads these keys by name (echfetch.go's json tags): a renamed property would arrive empty
        let json = try XCTUnwrap(request.json())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["url", "addresses", "pinnedAddresses", "resolvers", "lookupName", "pinnedKey", "userAgent", "timeoutMs", "interface"])
        XCTAssertEqual(object["url"] as? String, "https://fra.skyrayconfig.org/sub/0123456789abcdef")
        XCTAssertEqual(object["userAgent"] as? String, "SkyRay/1.3.6 (ios)")
        XCTAssertEqual((object["timeoutMs"] as? NSNumber)?.int64Value, EchFetch.timeoutMs)
    }

    func testThePinnedValuesAreWhatTheCoreCanUse() throws {
        // ECHConfigList: a two-byte length, then one ECHConfig of version 0xfe0d
        let key = try XCTUnwrap(Data(base64Encoded: Etha.echPinnedKey))
        XCTAssertEqual(Int(key[0]) << 8 | Int(key[1]), key.count - 2)
        XCTAssertEqual(key[2], 0xFE); XCTAssertEqual(key[3], 0x0D)
        XCTAssertFalse(Etha.echResolvers.isEmpty)
        XCTAssertEqual(EchFetch.candidateAddresses(Etha.echResolvers).count, min(Etha.echResolvers.count, EchFetch.maxStoredAddresses))   // resolvers are IPv4 literals
        for address in Etha.echAddresses { XCTAssertEqual(EchFetch.candidateAddresses([address]), [address]) }
        XCTAssertNotEqual(Etha.echLookupName, Etha.subHost)             // the link host is never put into a DNS query
    }

    func testAGoodAnswerIsRead() throws {
        let json = #"{"status":200,"headers":{"profile-update-interval":"3","subscription-userinfo":"upload=0; download=5; total=0; expire=0"},"body":"dmxlc3M6Ly9hYmM=","echAccepted":true,"address":"104.21.67.176","keySource":"dns:8.8.8.8","error":""}"#
        let result = try XCTUnwrap(EchFetchResult.parse(json))
        XCTAssertTrue(result.answered)
        XCTAssertEqual(result.status, 200)
        XCTAssertEqual(result.body, "dmxlc3M6Ly9hYmM=")
        XCTAssertEqual(result.headers["profile-update-interval"], "3")
        XCTAssertEqual(result.address, "104.21.67.176")
        XCTAssertEqual(result.keySource, "dns:8.8.8.8")
        var info = SubscriptionInfo()
        SubscriptionHeaders.apply(result.headers, to: &info)
        XCTAssertEqual(info.download, 5)
        XCTAssertEqual(info.updateIntervalMinutes, 180)
        XCTAssertEqual(SubscriptionBody.decode(Data(result.body.utf8)), ["vless://abc"])
    }

    func testOnlyAFetchThatReachedNobodyIsWorthAnotherWay() throws {
        // the server answered — expired or unknown: another way out would hear the same
        XCTAssertTrue(try XCTUnwrap(EchFetchResult.parse(#"{"status":403,"headers":{},"body":"{\"detail\":\"expired\"}","echAccepted":true,"address":"a","keySource":"retry","error":""}"#)).answered)
        XCTAssertTrue(try XCTUnwrap(EchFetchResult.parse(#"{"status":404,"echAccepted":true}"#)).answered)
        // nobody answered
        let failed = try XCTUnwrap(EchFetchResult.parse(#"{"status":0,"headers":{},"body":"","echAccepted":false,"address":"","keySource":"","error":"ech: dial tcp 104.21.67.176:443: i/o timeout"}"#))
        XCTAssertFalse(failed.answered)
        XCTAssertEqual(failed.failure, "ech: dial tcp 104.21.67.176:443: i/o timeout")
        let noEch = try XCTUnwrap(EchFetchResult.parse(#"{"status":200,"body":"x"}"#))
        XCTAssertFalse(noEch.answered)
        XCTAssertEqual(noEch.failure, "ECH not accepted")
        XCTAssertFalse(try XCTUnwrap(EchFetchResult.parse(#"{"echAccepted":true}"#)).answered)
        XCTAssertNil(EchFetchResult.parse(""))
        XCTAssertNil(EchFetchResult.parse("not json"))
        XCTAssertNil(EchFetchResult.parse("[1,2]"))
    }
}
