import XCTest
@testable import SkyRayCore

final class SubscriptionTests: XCTestCase {
    func testUserInfoParsesTheApiShape() {
        let info = SubscriptionHeaders.parseUserInfo("upload=0; download=1234567; total=21474836480; expire=1790000000")!
        XCTAssertEqual(info.upload, 0); XCTAssertEqual(info.download, 1234567)
        XCTAssertEqual(info.total, 21474836480); XCTAssertEqual(info.expire, 1790000000)
    }
    func testUserInfoKeepsServerSemanticsForZero() {
        let info = SubscriptionHeaders.parseUserInfo("upload=0; download=0; total=0; expire=0")!
        XCTAssertEqual(info.total, 0); XCTAssertEqual(info.expire, 0)
        XCTAssertEqual(SubscriptionHeaders.daysLeft(expire: 0), Int64.max)
    }
    func testUserInfoToleratesGarbage() {
        XCTAssertNil(SubscriptionHeaders.parseUserInfo(nil))
        XCTAssertNil(SubscriptionHeaders.parseUserInfo(""))
        XCTAssertNil(SubscriptionHeaders.parseUserInfo("nonsense"))
        let partial = SubscriptionHeaders.parseUserInfo("download=5; total=abc; expire=")!
        XCTAssertEqual(partial.download, 5); XCTAssertEqual(partial.total, -1); XCTAssertEqual(partial.expire, -1); XCTAssertEqual(partial.upload, -1)
        XCTAssertEqual(SubscriptionHeaders.parseUserInfo("download=12.7")!.download, 12)
    }
    func testDaysLeftRoundsUpAndNeverGoesNegative() {
        let now: Int64 = 1_700_000_000
        XCTAssertEqual(SubscriptionHeaders.daysLeft(expire: now + 1, now: now), 1)
        XCTAssertEqual(SubscriptionHeaders.daysLeft(expire: now + 86400, now: now), 1)
        XCTAssertEqual(SubscriptionHeaders.daysLeft(expire: now + 86401, now: now), 2)
        XCTAssertEqual(SubscriptionHeaders.daysLeft(expire: now - 5, now: now), 0)
        XCTAssertNil(SubscriptionHeaders.daysLeft(expire: -1, now: now))
    }
    func testHeaderTextDecodesBase64OrPassesPlain() {
        XCTAssertEqual(SubscriptionHeaders.decodeHeaderText("base64:RXRoYVZQTg=="), "EthaVPN")
        XCTAssertEqual(SubscriptionHeaders.decodeHeaderText("base64:2LPZhNin2YU="), "سلام")
        XCTAssertEqual(SubscriptionHeaders.decodeHeaderText("  plain "), "plain")
        XCTAssertNil(SubscriptionHeaders.decodeHeaderText(""))
        XCTAssertNil(SubscriptionHeaders.decodeHeaderText("base64:***"))
        XCTAssertNil(SubscriptionHeaders.decodeHeaderText(nil))
    }
    func testUpdateIntervalIsHoursToMinutesWithAFloor() {
        XCTAssertEqual(SubscriptionHeaders.updateIntervalMinutes("12"), 720)
        XCTAssertEqual(SubscriptionHeaders.updateIntervalMinutes("1"), 60)
        XCTAssertEqual(SubscriptionHeaders.updateIntervalMinutes("3"), 180)
        XCTAssertEqual(SubscriptionHeaders.updateIntervalMinutes("0.1"), Etha.minUpdateMinutes)
        XCTAssertNil(SubscriptionHeaders.updateIntervalMinutes("0"))
        XCTAssertNil(SubscriptionHeaders.updateIntervalMinutes("x"))
        XCTAssertNil(SubscriptionHeaders.updateIntervalMinutes(nil))
        XCTAssertEqual(Etha.defaultUpdateMinutes, 180)
    }
    func testSubLinkRecognition() {
        let host = Etha.subHost
        XCTAssertTrue(EthaLink.isSubLink("https://\(host)/sub/0123456789abcdef"))
        XCTAssertTrue(EthaLink.isSubLink("https://\(host)/sub/0123456789abcdef#EthaVPN"))
        XCTAssertTrue(EthaLink.isSubLink("HTTPS://\(host.uppercased())/sub/0123456789abcdef"))
        XCTAssertFalse(EthaLink.isSubLink("http://\(host)/sub/0123456789abcdef"))
        XCTAssertFalse(EthaLink.isSubLink("https://evil.example/sub/0123456789abcdef"))
        XCTAssertFalse(EthaLink.isSubLink("https://\(host)/sub/"))
        XCTAssertFalse(EthaLink.isSubLink("https://\(host)/sub/abc"))
        XCTAssertFalse(EthaLink.isSubLink("https://\(host)/sub/0123456789abcdef/x"))
        XCTAssertFalse(EthaLink.isSubLink("https://\(host)/dl/"))
        XCTAssertFalse(EthaLink.isSubLink("vless://x"))
        XCTAssertFalse(EthaLink.isSubLink(nil))
        XCTAssertFalse(EthaLink.isSubLink("not a url at all ://"))
    }
    func testExtractsTheLinkFromPastedText() {
        let link = "https://\(Etha.subHost)/sub/0123456789abcdef"
        XCTAssertEqual(EthaLink.extract(from: "🔗 Your link:\n\(link)\n\nTap it."), link)
        XCTAssertEqual(EthaLink.extract(from: "لینک شما: \(link)، بعد وصل شوید."), link)
        XCTAssertEqual(EthaLink.extract(from: link), link)
        // the invisible marks of a right-to-left message around the link (they are not spaces)
        XCTAssertEqual(EthaLink.extract(from: "\u{200F}\(link)\u{200F}"), link)
        XCTAssertEqual(EthaLink.extract(from: "لینک شما:\n\u{2068}\(link)\u{2069}."), link)
        XCTAssertEqual(EthaLink.extract(from: "\(link)\u{200F}."), link)
        XCTAssertNil(EthaLink.extract(from: "nothing here"))
        XCTAssertNil(EthaLink.extract(from: nil))
        XCTAssertEqual(EthaLink.canonical(link + "#EthaVPN"), link)
        XCTAssertEqual(EthaLink.name(of: link + "#My%20Sub"), "My Sub")
        XCTAssertEqual(EthaLink.name(of: link), "EthaVPN")
        XCTAssertEqual(EthaLink.token(of: link + "#x"), "0123456789abcdef")
    }
    func testOldAddressesMoveToTheCurrentOne() {
        let old = "https://fra.mobileiphone.org/sub/0123456789abcdef#EthaVPN"
        let now = "https://fra.skyrayconfig.org/sub/0123456789abcdef#EthaVPN"
        XCTAssertEqual(EthaLink.migratedUrl(old), now)
        XCTAssertEqual(EthaLink.migratedUrl("https://fra.mobileiphonez.org/sub/0123456789abcdef"), "https://fra.skyrayconfig.org/sub/0123456789abcdef")
        XCTAssertNil(EthaLink.migratedUrl("https://fra.skyrayconfig.org/sub/0123456789abcdef"))
        XCTAssertNil(EthaLink.migratedUrl("https://evil.example/sub/0123456789abcdef"))
        XCTAssertNil(EthaLink.migratedUrl("https://fra.mobileiphone.org/dl/"))
        XCTAssertFalse(EthaLink.isSubLink(old))
        XCTAssertEqual(EthaLink.normalized(old), now)
        XCTAssertEqual(EthaLink.normalized(" \(now) "), now)
        XCTAssertNil(EthaLink.normalized("vless://x"))
        XCTAssertEqual(EthaLink.extract(from: "Your link: \(old), tap it."), now)
        XCTAssertTrue(EthaLink.sameAccount(old, "https://fra.skyrayconfig.org/sub/0123456789abcdef#Other"))
        XCTAssertFalse(EthaLink.sameAccount(old, "https://fra.skyrayconfig.org/sub/fedcba9876543210"))
        XCTAssertFalse(EthaLink.sameAccount(nil, old))
        XCTAssertFalse(EthaLink.sameAccount(old, nil))
    }
    func testOldAppFilesYieldTheLink() {
        let profiles = #"[{"name":"EthaVPN-WS-cdn-CleanIP1-443","outboundJSON":"{}","shareLink":"vless://x","subscriptionURL":"https://fra.mobileiphone.org/sub/0123456789abcdef"}]"#
        XCTAssertEqual(OldAppFiles.firstLink(in: Data(profiles.utf8)), "https://fra.skyrayconfig.org/sub/0123456789abcdef")
        let subs = #"[{"url":"https://fra.skyrayconfig.org/sub/0123456789abcdef","title":"Reza","lastUpdated":"2026-09-30T00:00:00Z"}]"#
        XCTAssertEqual(OldAppFiles.firstLink(in: Data(subs.utf8)), "https://fra.skyrayconfig.org/sub/0123456789abcdef")
        XCTAssertNil(OldAppFiles.firstLink(in: Data(#"[{"url":"https://other.example/sub/0123456789abcdef"}]"#.utf8)))
        XCTAssertNil(OldAppFiles.firstLink(in: Data("not json".utf8)))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skyray-old-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertNil(OldAppFiles.link(inContainer: dir))
        try? Data(profiles.utf8).write(to: dir.appendingPathComponent("profiles.json"))
        XCTAssertEqual(OldAppFiles.link(inContainer: dir), "https://fra.skyrayconfig.org/sub/0123456789abcdef")
        try? FileManager.default.removeItem(at: dir)
    }
    func testApplyHeadersFillsTheInfoAndLeavesItAloneOtherwise() {
        var info = SubscriptionInfo()
        XCTAssertFalse(SubscriptionHeaders.apply(["content-type": "text/plain"], to: &info))
        XCTAssertEqual(info.total, -1); XCTAssertNil(info.infoUpdated)
        let headers = [
            "subscription-userinfo": "upload=0; download=100; total=0; expire=0",
            "profile-title": "base64:UmV6YQ==",
            "announce": "base64:2LPZhNin2YU=",
            "support-url": "https://t.me/freeandsecurevpn",
            "profile-web-page-url": "https://x/sub/0123456789abcdef",
            "profile-update-interval": "12",
        ]
        XCTAssertTrue(SubscriptionHeaders.apply(headers, to: &info))
        XCTAssertEqual(info.download, 100); XCTAssertEqual(info.total, 0); XCTAssertEqual(info.expire, 0)
        XCTAssertEqual(info.profileTitle, "Reza"); XCTAssertEqual(info.announce, "سلام")
        XCTAssertEqual(info.supportURL, "https://t.me/freeandsecurevpn"); XCTAssertEqual(info.webPageURL, "https://x/sub/0123456789abcdef")
        XCTAssertEqual(info.updateIntervalMinutes, 720); XCTAssertNotNil(info.infoUpdated)
        SubscriptionHeaders.apply(["announce": ""], to: &info)
        XCTAssertNil(info.announce)
        SubscriptionHeaders.apply(["subscription-userinfo": "garbage"], to: &info)
        XCTAssertEqual(info.download, 100)
    }
    func testBase64DecoderHandlesPaddingAndUrlAlphabet() {
        XCTAssertEqual(Base64Lenient.decodeString("aGVsbG8="), "hello")
        XCTAssertEqual(Base64Lenient.decodeString("aGVsbG8"), "hello")
        XCTAssertEqual(Base64Lenient.decodeString("aGVs\nbG8="), "hello")
        XCTAssertEqual(Base64Lenient.decodeString("aGVsbG8_LQ"), "hello?-")
        XCTAssertNil(Base64Lenient.decode("!!"))
        XCTAssertNil(Base64Lenient.decode(""))
    }
    func testStaleWhenNeverFetchedOrOlderThanAnHour() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        XCTAssertTrue(SubscriptionHeaders.isStale(nil, now: now))
        XCTAssertTrue(SubscriptionHeaders.isStale(Date(timeIntervalSince1970: 0), now: now))
        XCTAssertTrue(SubscriptionHeaders.isStale(now.addingTimeInterval(-3600), now: now))
        XCTAssertFalse(SubscriptionHeaders.isStale(now.addingTimeInterval(-3599.999), now: now))
        XCTAssertFalse(SubscriptionHeaders.isStale(now, now: now))
    }
    func testQuotaTextDropsTheDecimalOfAWholeNumber() {
        let gb: Int64 = 1 << 30
        XCTAssertEqual(SubscriptionHeaders.quotaText(bytes: 120 * gb), "120 GB")
        XCTAssertEqual(SubscriptionHeaders.quotaText(bytes: Int64(70.2 * Double(gb))), "70.2 GB")
        XCTAssertEqual(SubscriptionHeaders.quotaText(bytes: 120 * gb - 1), "120 GB")     // 119.99… reads 120, never 120.0
        XCTAssertEqual(SubscriptionHeaders.quotaText(bytes: gb), "1 GB")
        XCTAssertEqual(SubscriptionHeaders.quotaText(bytes: gb + gb / 2), "1.5 GB")
        XCTAssertEqual(SubscriptionHeaders.quotaText(bytes: 214_748_365), "205 MB")     // the trial's 0.2 GB
        XCTAssertEqual(SubscriptionHeaders.quotaText(bytes: 512 * 1024), "512 KB")
    }
}
