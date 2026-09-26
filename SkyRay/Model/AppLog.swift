import Foundation
import SkyRayCore

/// The app's own log (App Group, shared with support through "Send logs").
enum AppLog {
    static var shared: RingLog?
    static func info(_ m: String) { shared?.info(m) }
    static func warn(_ m: String) { shared?.warn(m) }
    static func error(_ m: String) { shared?.error(m) }
}
