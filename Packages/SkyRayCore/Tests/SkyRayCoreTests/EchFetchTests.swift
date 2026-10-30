import XCTest
@testable import SkyRayCore

final class EchFetchTests: XCTestCase {
    /// A line as the importer makes one: its transport read from the link's type (the real one comes from the remark).
    private func line(_ id: String, _ link: String, order: Int = 0) -> Line {
        let transport = link.contains("type=ws") ? "WS" : (link.contains("type=xhttp") ? "XHTTP" : nil)
        return Line(id: id, link: link, remark: id, transport: transport, endpointLabel: nil, port: nil, order: order, outboundJSON: "{}")
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
        XCTAssertEqual(Set(object.keys), ["url", "addresses", "pinnedAddresses", "resolvers", "lookupName", "pinnedKey", "userAgent", "timeoutMs", "interface", "plain", "headers", "signKeys"])
        XCTAssertEqual(object["signKeys"] as? [String], Etha.signKeys)    // the box's two public keys: the core checks the answer's signature against them
        XCTAssertEqual(object["headers"] as? [String: String], [:])             // no report to carry: an empty map, the core ignores it
        XCTAssertEqual(object["plain"] as? Bool, false)                 // the ECH ways never ask for the plain one
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
        // the pinned list: IPv4 addresses, then one name for the phone's resolver (a network without IPv4 reaches only a name)
        for address in Etha.echAddresses.dropLast() { XCTAssertEqual(EchFetch.candidateAddresses([address]), [address]) }
        XCTAssertEqual(Etha.echAddresses.last, Etha.echLookupName)
        XCTAssertNotEqual(Etha.echLookupName, Etha.subHost)             // the link host is never put into a DNS query
    }

    func testAGoodAnswerIsRead() throws {
        let json = #"{"status":200,"headers":{"profile-update-interval":"3","subscription-userinfo":"upload=0; download=5; total=0; expire=0"},"body":"dmxlc3M6Ly9hYmM=","echAccepted":true,"signed":"ok","signedAt":1800000000,"address":"104.21.67.176","keySource":"dns:8.8.8.8","error":""}"#
        let result = try XCTUnwrap(EchFetchResult.parse(json))
        XCTAssertTrue(result.answered)
        XCTAssertEqual(result.status, 200)
        XCTAssertEqual(result.body, "dmxlc3M6Ly9hYmM=")
        XCTAssertEqual(result.headers["profile-update-interval"], "3")
        XCTAssertEqual(result.address, "104.21.67.176")
        XCTAssertEqual(result.keySource, "dns:8.8.8.8")
        XCTAssertEqual(result.signed, "ok"); XCTAssertEqual(result.signedAt, 1_800_000_000); XCTAssertTrue(result.trusted)
        var info = SubscriptionInfo()
        SubscriptionHeaders.apply(result.headers, to: &info)
        XCTAssertEqual(info.download, 5)
        XCTAssertEqual(info.updateIntervalMinutes, 180)
        XCTAssertEqual(SubscriptionBody.decode(Data(result.body.utf8)), ["vless://abc"])
    }

    func testOnlyAFetchThatReachedNobodyIsWorthAnotherWay() throws {
        // the server answered — expired or unknown: another way out would hear the same (an expiry carries the box's signature, 2.1)
        XCTAssertTrue(try XCTUnwrap(EchFetchResult.parse(#"{"status":403,"headers":{},"body":"{\"detail\":\"expired\"}","echAccepted":true,"address":"a","keySource":"retry","signed":"ok","signedAt":1800000000,"error":""}"#)).answered)
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

    func testHopRequestIsPlainAtTheHopsAddress() {
        let hop = LinkHop(host: "www.harlow-systems.org", ip: "185.83.210.148")
        let req = EchFetch.hopRequest(token: "0123456789abcdef", hop: hop, userAgent: "SkyRay/1 (ios)", interface: "en0")
        XCTAssertEqual(req.url, "https://www.harlow-systems.org/sub/0123456789abcdef")
        XCTAssertEqual(req.addresses, ["185.83.210.148"])
        XCTAssertTrue(req.plain); XCTAssertEqual(req.interface, "en0"); XCTAssertEqual(req.timeoutMs, Etha.hopTimeoutMs)
        XCTAssertTrue(req.pinnedAddresses.isEmpty); XCTAssertTrue(req.resolvers.isEmpty); XCTAssertEqual(req.pinnedKey, ""); XCTAssertEqual(req.lookupName, "")
        XCTAssertTrue(req.json()?.contains("\"plain\":true") ?? false)
        XCTAssertFalse(EchFetch.request(url: "https://x/sub/y", stored: [], userAgent: "u").plain)   // the ECH ways stay ECH
    }

    func testLinkHopsParseInOrderAndSkipGarbage() {
        let hops = EchFetch.parseHops(" www.harlow-systems.org=185.83.210.148 , WWW.Spare.Example=10.0.0.1,bad,=1.2.3.4,host=300.1.1.1,-x.y=1.2.3.4, www.harlow-systems.org=185.83.210.148")
        XCTAssertEqual(hops, [LinkHop(host: "www.harlow-systems.org", ip: "185.83.210.148"), LinkHop(host: "www.spare.example", ip: "10.0.0.1")])
        XCTAssertEqual(EchFetch.format(hops), "www.harlow-systems.org=185.83.210.148,www.spare.example=10.0.0.1")
        XCTAssertTrue(EchFetch.parseHops(nil).isEmpty); XCTAssertTrue(EchFetch.parseHops(" ").isEmpty); XCTAssertTrue(EchFetch.parseHops("garbage").isEmpty)
        XCTAssertEqual(EchFetch.parseHops(EchFetch.format(Etha.linkHops)), Etha.linkHops)
        XCTAssertTrue(Etha.linkHops.allSatisfy { Etha.hopSubHosts.contains($0.host) })   // a link on the hop's name is ours
    }

    func testPlainAnsweredIsAnyStatusWithoutError() {
        var r = EchFetchResult(); r.status = 403; r.keySource = "plain"; r.signed = "ok"; r.signedAt = 1_800_000_000
        XCTAssertTrue(r.plainAnswered); XCTAssertFalse(r.answered); XCTAssertEqual(r.failure, "status 403")
        r.error = "plain: dial"; XCTAssertFalse(r.plainAnswered)
        var e = EchFetchResult(); e.status = 0; XCTAssertFalse(e.plainAnswered)
        var u = EchFetchResult(); u.status = 404; u.keySource = "plain"; XCTAssertTrue(u.plainAnswered)   // other statuses carry no signature
    }

    /// The box's own word (2.1): a subscription (200) or an expiry (403) counts only with the box's signature, on every way.
    func testASubscriptionOrAnExpiryCountsOnlyWithTheBoxsSignature() {
        XCTAssertEqual(Etha.signKeys.count, 2)                                                    // A in use, B the spare
        var ok = EchFetchResult(); ok.status = 200; ok.body = "dmxlc3M6Ly8="; ok.echAccepted = true; ok.signed = "ok"; ok.signedAt = 1_800_000_000
        XCTAssertTrue(ok.trusted); XCTAssertTrue(ok.answered)
        for verdict in ["", "none", "bad", "unknown-key", "nokeys"] {
            var r = ok; r.signed = verdict
            XCTAssertFalse(r.trusted, verdict); XCTAssertFalse(r.answered, verdict)
            XCTAssertEqual(r.failure, "status 200, signature \(verdict.isEmpty ? "unchecked (old core)" : verdict)")
            var hop = r; hop.echAccepted = false; hop.keySource = "plain"
            XCTAssertFalse(hop.plainAnswered, verdict)                                            // the hop's answer is checked the same way
        }
        var expired = EchFetchResult(); expired.status = 403; expired.echAccepted = true; expired.signed = "bad"
        XCTAssertFalse(expired.answered)                                                          // a forged expiry is no answer
        var other = EchFetchResult(); other.status = 500; other.echAccepted = true; other.signed = "none"
        XCTAssertTrue(other.answered)
        XCTAssertFalse(ok.stale(now: 1_800_000_000 + 3600)); XCTAssertTrue(ok.stale(now: 1_800_000_000 + 3601))
        var unsigned404 = EchFetchResult(); unsigned404.status = 404; XCTAssertFalse(unsigned404.stale(now: 2_000_000_000))
    }

    func testTheReportTravelsAsAHeaderOnEveryWayAndTheHopWaitsForEch() throws {
        let h = ["X-Etha-Lines": "v=1;t=1;trig=manual;use=;sw=0;l=XHTTP-api-CleanIP1-443:200"]
        let direct = EchFetch.request(url: "https://fra.skyrayconfig.org/sub/0123456789abcdef", stored: [], userAgent: "x", headers: h)
        XCTAssertEqual(direct.headers, h)
        let hop = EchFetch.hopRequest(token: "0123456789abcdef", hop: LinkHop(host: "www.harlow-systems.org", ip: "185.83.210.148"), userAgent: "x", headers: h)
        XCTAssertEqual(hop.headers, h)
        XCTAssertTrue(hop.plain)
        let json = try XCTUnwrap(direct.json())
        XCTAssertTrue(json.contains("\"headers\":{\"X-Etha-Lines\":"))
        XCTAssertEqual(EchFetch.hopHeadStartMs(rememberedWay: nil), Etha.hopHeadStartMs)
        XCTAssertEqual(EchFetch.hopHeadStartMs(rememberedWay: "ech"), Etha.hopHeadStartMs)
        XCTAssertEqual(EchFetch.hopHeadStartMs(rememberedWay: "hop"), 0)
    }

    func testOnlyTheCloudflareLinesLendTheirAddresses() {
        // since 2026-10-24 the first lines are the relays: their addresses answer with a cover site, never with ECH
        func line(_ id: String, _ transport: String?, _ address: String, order: Int) -> Line {
            Line(id: id, link: "vless://u@\(address):443?type=tcp#x", remark: id, transport: transport, endpointLabel: nil, port: 443, order: order, outboundJSON: "{}")
        }
        let lines = [line("r1", "REALITY", "45.1.2.3", order: 0), line("x1", "XHTTP", "104.21.67.176", order: 1),
                     line("w1", "WS", "172.67.179.3", order: 2), line("u", nil, "1.2.3.4", order: 3)]
        XCTAssertEqual(EchFetch.storedAddresses(lines: lines, selectedLineId: "r1"), ["104.21.67.176", "172.67.179.3"])
        XCTAssertEqual(EchFetch.storedAddresses(lines: lines, selectedLineId: "w1"), ["172.67.179.3", "104.21.67.176"])
    }
}
