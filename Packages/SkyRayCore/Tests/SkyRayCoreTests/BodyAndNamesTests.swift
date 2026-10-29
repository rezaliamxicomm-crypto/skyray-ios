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
