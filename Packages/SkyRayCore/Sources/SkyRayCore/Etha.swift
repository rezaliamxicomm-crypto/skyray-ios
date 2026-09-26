import Foundation

/// The service's constants — the same values as the Android app's AppConfig.ETHA_*.
public enum Etha {
    public static let subHost = "fra.mobileiphone.org"
    public static let subPath = "/sub/"
    public static let subName = "EthaVPN"
    public static let supportURL = "https://t.me/Ethaconfigbot?start=app_support"
    public static let privacyURL = "https://allionapp.com/skyray-privacy"
    public static let sourceURL = "https://github.com/rezaliamxicomm-crypto/skyray-ios"
    public static let appGroup = "group.com.allion.skyray"
    public static let tunnelBundleID = "com.allion.skyray.tunnel"
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

    /// Must start with "SkyRay/" (the server records it as the customer's app) and never with "Mozilla/".
    public static func userAgent(version: String) -> String { "SkyRay/\(version) (ios)" }
}
