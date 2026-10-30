import Foundation

/// The service's constants — the same values as the Android app's AppConfig.ETHA_*.
public enum Etha {
    /// The link's only address (operator's rule). Links on an earlier address are moved to it, never used as they are.
    public static let subHost = "fra.skyrayconfig.org"
    public static let subHosts = [subHost]
    public static let oldSubHosts = ["fra.mobileiphonez.org", "fra.mobileiphone.org"]
    /// The link hop inside Iran: the service's second address for the link, for networks that filter the link host's
    /// name. A link on one of these names is ours too (moved to subHost like one on an old address). The fetch takes
    /// the hop after the two ECH ways gave nothing: plain, by the core, dialled at the address the service last named
    /// in the header X-Etha-Link-Hops ("host=ip,host=ip"), else at linkHops — so the spare name can take over without
    /// a release. The same values as the Android app's AppConfig.ETHA_HOP_SUB_HOSTS / ETHA_LINK_HOPS.
    public static let hopSubHosts = ["www.harlow-systems.org", "harlow-systems.org", "www.selvanemetricsz.com", "selvanemetricsz.com"]
    /// The transports whose lines dial a Cloudflare address: only those addresses serve the ECH fetch (a relay answers with its cover site).
    public static let cloudflareTransports: Set<String> = ["XHTTP", "SPLITHTTP", "WS", "HTTPUPGRADE"]
    public static let linkHops = [LinkHop(host: "www.harlow-systems.org", ip: "185.83.210.148")]
    public static let linkHopsHeader = "x-etha-link-hops"
    public static let hopTimeoutMs: Int64 = 12_000
    public static let subPath = "/sub/"
    public static let subName = "EthaVPN"
    public static let supportURL = "https://t.me/Ethaconfigbot?start=app_support"
    /// "Share this app": the two stores and the bot, the bot link with its own registry code
    public static let shareURL = "https://t.me/Ethaconfigbot?start=app_share"
    /// "Open Telegram" in the add-your-link box (Paste found no link): the bot answers with the customer's link message
    public static let linkURL = "https://t.me/Ethaconfigbot?start=app_link"
    public static let playURL = "https://play.google.com/store/apps/details?id=com.allion.skyray"
    public static let appStoreURL = "https://apps.apple.com/app/id6809038308"
    /// "Rate SkyRay" (Settings): the App Store's own page for writing a review
    public static let reviewURL = appStoreURL + "?action=write-review"
    public static let privacyURL = "https://allionapp.com/skyray-privacy"
    public static let appGroup = "group.com.allion.skyray"
    /// The extension's App ID as the previous SkyRay registered it: the phones' VPN configuration names it.
    public static let tunnelBundleID = "com.allion.skyray.PacketTunnel"
    public static let refreshTaskID = "com.allion.skyray.refresh"
    /// The API's Profile-Update-Interval is 3 h; the floor is what the Android app applies too.
    public static let defaultUpdateMinutes: Int64 = 180
    public static let minUpdateMinutes: Int64 = 15
    /// A silent refresh on open when the last fetch is older than this.
    public static let staleAfter: TimeInterval = 3600
    /// Measured delays are trusted for this long before Connect looks for a better line to start on.
    public static let delayFresh: TimeInterval = 600
    /// Auto (AutoPolicy, AutoEngine): the service's header with the numbers, the balancer's tag in the tunnel's config.
    public static let autoHeader = "x-etha-auto"
    public static let hintHeader = "x-etha-hint"
    public static let sigAtHeader = "x-etha-sig-at"
    /// The box's signing keys (Ed25519, raw public halves, base64): A in use, B the spare the operator holds. The core
    /// (echfetch/signature.go) verifies every answer against them; one whose signature is missing, forged or made with a
    /// key not here counts as no answer (SubscriptionImporter). Generated 2026-10-30 (/opt/staging/auto-2.1, keygen).
    public static let signKeys = ["x1P7PGU48fnmDii+oUqRq2BNEc/JKhldw2oDKIYC9RY=", "nEb0S15kOFA081vRo8SwKijoFZopS5Ot4zrHRoxqT6I="]
    /// An answer signed longer ago than this is taken only when no fresher one arrives in the race (a hop replaying an old
    /// answer); one older than the last accepted is never taken.
    public static let signedStaleAfter: Int64 = 3600
    /// An answer signed longer ago than this is refused outright, whatever else answered (a hop replaying a captured answer).
    public static let signedMaxAge: Int64 = 172_800
    /// The held signed time never runs further ahead of the phone's clock than this (a box clock ahead must not strand the phone).
    public static let signedHeldAhead: Int64 = 86_400
    public static let autoBalancerTag = "auto"
    /// Auto measures every line with two HEAD requests to the box's own probe target (a TEST-NET address Xray on the box
    /// sends to a 204 on loopback: no third party, no TLS); the fallback is tried once when no line answers the target.
    public static let probeURL = "http://203.0.113.1/"
    public static let probeFallbackURL = "https://www.gstatic.com/generate_204"
    /// What Auto measured, sent on the next subscription fetch as this header (LineReport); the box stores it.
    public static let linesHeader = "X-Etha-Lines"
    /// The hop starts this long after the two ECH ways on a fetch — at once on a network where it answered last time.
    public static let hopHeadStartMs: Int64 = 3_000
    public static let pingTimeoutSeconds = 8
    public static let connectGuard: TimeInterval = 25

    // The tunnel: the utun's addresses, the loopback ports when libXray names no free ones.
    public static let tunnelMTU = 1500
    public static let tunnelIPv4 = "198.18.0.1"
    public static let tunnelRemoteIPv4 = "198.18.0.2"
    public static let tunnelIPv6 = "fd00:5379:5261:7900::1"
    public static let tunnelDNS = ["1.1.1.1"]
    public static let socksPortFallback = 10808
    public static let probePortFallback = 41284
    public static let apiPortFallback = 41285

    // Our own link is fetched with Encrypted Client Hello enforced (EchFetch → LibXray's CGoFetchSubscriptionEch,
    // echfetch/ in this repo), past the tunnel and then through it; when nobody answered on either way, through the
    // link hop inside Iran (plain, linkHops); only when that gave nothing either is it fetched once more without ECH
    // by name, the last resort (SubscriptionImporter). The ECH key (Cloudflare's configuration, one for every zone) is asked over plain UDP DNS of these
    // resolvers, all at once, as the HTTPS record of the ECH public name — what the lines' own ECH lookups ask; when
    // none answers, the pinned key is offered and the server's retry key replaces it. The connection goes to a
    // Cloudflare address the app already knows — the stored lines' addresses, then these pinned ones — never to the
    // host's A record. The pinned addresses and key are what DNS said on 2026-10-04; stale is fine. Last in the list a
    // name, not an address: the ECH public name, resolved by the phone's own resolver — on a network without IPv4
    // (IPv6 only, NAT64: where Apple reviews apps) no IPv4 address can be dialled, only a name; any Cloudflare address
    // serves the link host. The same values as the Android app's AppConfig.ETHA_ECH_*.
    public static let echResolvers = ["8.8.8.8", "1.1.1.1", "9.9.9.9"]
    public static let echLookupName = "cloudflare-ech.com"
    public static let echAddresses = ["104.21.67.176", "172.67.179.3", echLookupName]
    public static let echPinnedKey = "AEX+DQBB+AAgACD1pZvdD5sHHANMZyCYm0HK9WMgj+BzRP7oSbbFgbGsNQAEAAEAAQASY2xvdWRmbGFyZS1lY2guY29tAAA="

    /// Must start with "SkyRay/" (the server records it as the customer's app) and never with "Mozilla/".
    public static func userAgent(version: String) -> String { "SkyRay/\(version) (ios)" }
}
