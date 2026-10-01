import Foundation

/// The service's constants — the same values as the Android app's AppConfig.ETHA_*.
public enum Etha {
    /// The link's only address (operator's rule). Links on an earlier address are moved to it, never used as they are.
    public static let subHost = "fra.skyrayconfig.org"
    public static let subHosts = [subHost]
    public static let oldSubHosts = ["fra.mobileiphonez.org", "fra.mobileiphone.org"]
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
    /// Measured delays are trusted for this long before Connect tests again.
    public static let delayFresh: TimeInterval = 600
    public static let watchdogInterval: TimeInterval = 180
    public static let watchdogRetry: TimeInterval = 20
    public static let watchdogFailures = 2
    public static let probeURL = "https://www.gstatic.com/generate_204"
    public static let probeFallbackURL = "https://www.google.com/generate_204"
    public static let pingTimeoutSeconds = 8
    public static let connectGuard: TimeInterval = 25
    public static let testGuard: TimeInterval = 60

    // The tunnel: the utun's addresses, the loopback ports when libXray names no free ones.
    public static let tunnelMTU = 1500
    public static let tunnelIPv4 = "198.18.0.1"
    public static let tunnelRemoteIPv4 = "198.18.0.2"
    public static let tunnelIPv6 = "fd00:5379:5261:7900::1"
    public static let tunnelDNS = ["1.1.1.1"]
    public static let socksPortFallback = 10808
    public static let probePortFallback = 41284

    /// Must start with "SkyRay/" (the server records it as the customer's app) and never with "Mozilla/".
    public static func userAgent(version: String) -> String { "SkyRay/\(version) (ios)" }
}
