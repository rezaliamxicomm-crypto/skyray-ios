import XCTest
@testable import SkyRayCore

final class ExitsTests: XCTestCase {
    func testTheHeaderParsesInOrderAndSkipsBadItems() {
        let l = Exits.parse("de|Germany|DE|ok|0|203.0.113.3;us|United States|US|down|90|203.0.113.21;X|bad;tr|Turkey|TR|off|40")
        XCTAssertEqual(l.map(\.code), ["de", "us", "tr"])
        XCTAssertEqual(l[1].name, "United States"); XCTAssertEqual(l[1].country, "US"); XCTAssertEqual(l[1].rtt, 90); XCTAssertEqual(l[1].probe, "203.0.113.21")
        XCTAssertFalse(l[0].routed); XCTAssertTrue(l[1].routed); XCTAssertFalse(l[1].ok); XCTAssertEqual(l[2].probe, "")
        XCTAssertEqual(Exits.parse(""), []); XCTAssertEqual(Exits.parse(nil), [])
    }

    func testFlags() {
        XCTAssertEqual(Exits.flag("US"), "\u{1F1FA}\u{1F1F8}")
        XCTAssertEqual(Exits.flag("de"), "\u{1F1E9}\u{1F1EA}")
        XCTAssertEqual(Exits.flag(""), "\u{1F310}"); XCTAssertEqual(Exits.flag("USA"), "\u{1F310}")
    }

    func testTheLowestVersionAndTheComparison() {
        XCTAssertEqual(Exits.minVersion("android=3.0.0;ios=3.1.0"), "3.1.0")
        XCTAssertEqual(Exits.minVersion("android=3.0.0;ios=3.1.0", platform: "android"), "3.0.0")
        XCTAssertNil(Exits.minVersion("android=3.0.0")); XCTAssertNil(Exits.minVersion("ios=3")); XCTAssertNil(Exits.minVersion(nil))
        XCTAssertTrue(Exits.isBelow("2.1.3", min: "3.0.0")); XCTAssertFalse(Exits.isBelow("3.0.0", min: "3.0.0")); XCTAssertFalse(Exits.isBelow("3.0.1", min: "3.0.0"))
        XCTAssertTrue(Exits.isBelow("3.0", min: "3.0.1"))
    }

    func testAnotherCountryReloadsTheTunnelAndTheSameOneDoesNot() {
        XCTAssertTrue(Exits.moved(from: "ca", to: "us")); XCTAssertTrue(Exits.moved(from: "", to: "ca")); XCTAssertTrue(Exits.moved(from: "us", to: nil))   // a country, another, back to Auto
        XCTAssertFalse(Exits.moved(from: "us", to: "us")); XCTAssertFalse(Exits.moved(from: nil, to: "")); XCTAssertFalse(Exits.moved(from: "", to: nil))   // the same word: nothing to reload for
        XCTAssertFalse(Exits.moved(from: " us", to: "us ")); XCTAssertTrue(Exits.moved(from: nil, to: "ca"))
    }

    /// 3.0.2: another country is its own word to the tunnel — `reload` restarts Xray alone, and Xray's stop lets what is open run on
    /// (3.0.1 changed nothing for a page on a kept connection); `reloadCut` drops what is open first. The flag that carries it from
    /// the fetch to the order is kept like `linesChanged` and goes with the subscription.
    func testAnotherCountryIsItsOwnOrderToTheTunnelAndItsFlagIsKept() throws {
        XCTAssertEqual(TunnelRequest.reloadCut.cmd, "reloadCut"); XCTAssertEqual(TunnelRequest.reload.cmd, "reload"); XCTAssertNotEqual(TunnelRequest.reloadCut, TunnelRequest.reload)
        let wire = try JSONEncoder().encode(TunnelRequest.reloadCut)
        XCTAssertEqual(try JSONDecoder().decode(TunnelRequest.self, from: wire), TunnelRequest.reloadCut)
        let store = SkyRayStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("skyray-exit-\(UUID().uuidString)"))
        XCTAssertFalse(store.exitMoved)
        store.linesChanged = true; store.exitMoved = true
        XCTAssertTrue(store.exitMoved); XCTAssertTrue(store.linesChanged)
        store.exitMoved = false
        XCTAssertFalse(store.exitMoved); XCTAssertTrue(store.linesChanged)      // the two are read and cleared one by one
        store.exitMoved = true
        store.wipe(rememberingDeletedLink: nil)
        XCTAssertFalse(store.exitMoved); XCTAssertFalse(store.linesChanged)
    }

    func testTheDeviceLimitsRefusal() {
        let d = Exits.devicesRefusal("{\"detail\":\"devices\",\"limit\":2,\"active\":3}")
        XCTAssertEqual(d?.limit, 2); XCTAssertEqual(d?.active, 3)
        XCTAssertEqual(Exits.devicesRefusal("{\"detail\":\"devices\"}")?.limit, 0)
        XCTAssertNil(Exits.devicesRefusal("{\"detail\":\"expired\"}")); XCTAssertNil(Exits.devicesRefusal(""))
    }
}
