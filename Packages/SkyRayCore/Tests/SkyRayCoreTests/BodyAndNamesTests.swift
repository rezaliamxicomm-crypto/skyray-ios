import XCTest
@testable import SkyRayCore

final class BodyAndNamesTests: XCTestCase {
    private let a = "vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?encryption=none&security=tls&sni=cdn.example&type=ws&host=cdn.example&path=%2Fws#EthaVPN-WS-cdn-CleanIP1-443"
    private let b = "vless://11111111-2222-3333-4444-555555555555@cdn.example:2053?encryption=none&security=tls&type=xhttp&mode=packet-up#EthaVPN-XHTTP-cdn-Domain-2053"

    func testBodyDecodesBase64WithCRLFAndTrailingNewline() {
        let body = Data((a + "\r\n" + b + "\n").utf8).base64EncodedString() + "\n"
        XCTAssertEqual(SubscriptionBody.decode(Data(body.utf8)), [a, b])
    }
    func testBodyAcceptsUnpaddedUrlSafeAndPlain() {
        let std = Data((a + "\n" + b).utf8).base64EncodedString()
        let unpadded = std.replacingOccurrences(of: "=", with: "")
        let urlSafe = unpadded.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        XCTAssertEqual(SubscriptionBody.decode(Data(unpadded.utf8)), [a, b])
        XCTAssertEqual(SubscriptionBody.decode(Data(urlSafe.utf8)), [a, b])
        XCTAssertEqual(SubscriptionBody.decode(Data((a + "\n\n" + b + "\nnot a link\n").utf8)), [a, b])
        XCTAssertEqual(SubscriptionBody.decode(Data("!!".utf8)), [])
        XCTAssertEqual(SubscriptionBody.decode(Data()), [])
    }
    func testLineNames() {
        XCTAssertEqual(LineName.display("EthaVPN-XHTTP-fra-CleanIP3-8443"), "CleanIP3 · XHTTP/8443")
        XCTAssertEqual(LineName.display("EthaVPN-WS-fra-Domain-443"), "Domain · WS/443")
        XCTAssertEqual(LineName.display("EthaVPN-XHTTP-cdn-CleanIP1-443"), "CleanIP1 · XHTTP/443")
        XCTAssertEqual(LineName.display("EthaVPN-WS-cdn-Domain-443"), "Domain · WS/443")
        XCTAssertEqual(LineName.display("My own server"), "My own server")
        let p = LineName.parse("EthaVPN-XHTTP-cdn-CleanIP7-2053")!
        XCTAssertEqual(p.transport, "XHTTP"); XCTAssertEqual(p.label, "CleanIP7"); XCTAssertEqual(p.port, 2053)
        XCTAssertNil(LineName.parse("EthaVPN-XHTTP-cdn-CleanIP7"))
    }
    func testServerRows() {
        let names = ["a": "EthaVPN-XHTTP-fra-CleanIP1-443", "b": "EthaVPN-WS-fra-CleanIP2-443", "c": "EthaVPN-XHTTP-fra-Domain-2053", "d": "Custom line"]
        let rows = ServerRows.rows([.init(id: "a", delayMs: 120, order: 0), .init(id: "b", delayMs: 0, order: 1), .init(id: "c", delayMs: -1, order: 2), .init(id: "d", delayMs: 80, order: 3)],
                                   nameOf: { names[$0]! }, auto: "Auto (fastest)", untested: "not tested", failed: "failed")
        XCTAssertEqual(rows.count, 5)
        XCTAssertNil(rows[0].id); XCTAssertEqual(rows[0].text, "Auto (fastest)")
        XCTAssertEqual(rows.dropFirst().map { $0.id }, ["d", "a", "b", "c"])
        XCTAssertEqual(rows[1].text, "80 ms  ·  Custom line")
        XCTAssertEqual(rows[2].text, "120 ms  ·  CleanIP1 · XHTTP/443")
        XCTAssertEqual(rows[3].text, "not tested  ·  CleanIP2 · WS/443")
        XCTAssertEqual(rows[4].text, "failed  ·  Domain · XHTTP/2053")
        XCTAssertEqual(ServerRows.currentLabel(pinned: true, currentName: "EthaVPN-WS-fra-Domain-443", auto: "Auto", autoPicked: { "Auto · \($0)" }), "Domain · WS/443")
        XCTAssertEqual(ServerRows.currentLabel(pinned: false, currentName: "EthaVPN-WS-fra-Domain-443", auto: "Auto", autoPicked: { "Auto · \($0)" }), "Auto · Domain · WS/443")
        XCTAssertEqual(ServerRows.currentLabel(pinned: false, currentName: nil, auto: "Auto", autoPicked: { "Auto · \($0)" }), "Auto")
    }
    func testRotation() {
        func line(_ id: String, _ order: Int) -> Line { Line(id: id, link: "", remark: "EthaVPN-WS-cdn-\(id)-443", transport: "WS", endpointLabel: id, port: 443, order: order, outboundJSON: "{}") }
        let lines = [line("a", 0), line("b", 1), line("c", 2)]
        let first = LineRotation.next(current: "a", tried: [], lines: lines, results: ["b": 300, "c": 90])!
        XCTAssertEqual(first.id, "c"); XCTAssertEqual(first.tried, ["a"])
        let second = LineRotation.next(current: "c", tried: first.tried, lines: lines, results: [:])!
        XCTAssertEqual(second.id, "b")
        XCTAssertNil(LineRotation.next(current: "b", tried: second.tried, lines: lines, results: [:]))
        XCTAssertEqual(LineRotation.nextProbeDelay(failures: 0), 180)
        XCTAssertEqual(LineRotation.nextProbeDelay(failures: 1), 20)
    }
    func testMessagesRoundTrip() throws {
        let req = TunnelRequest.switchTo("abc")
        let data = try JSONEncoder().encode(req)
        XCTAssertEqual(try JSONDecoder().decode(TunnelRequest.self, from: data), req)
        var reply = TunnelReply(); reply.state = "connected"; reply.lastProbeMs = 123
        let back = try JSONDecoder().decode(TunnelReply.self, from: try JSONEncoder().encode(reply))
        XCTAssertEqual(back, reply)
        XCTAssertEqual(try JSONDecoder().decode(TunnelReply.self, from: Data("{}".utf8)).ok, true)
    }
}
