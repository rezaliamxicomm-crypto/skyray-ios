import Foundation
import SkyRayCore

/// Development builds only: launch arguments from scripts/deploy-device.sh, and a copy of the logs where the Mac
/// can fetch them (the App Group container is out of devicectl's reach; the app's Documents folder is not).
enum DevTools {
    @MainActor
    static func applyLaunchArguments(model: AppModel) async {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let link = defaults.string(forKey: "ImportLink"), !link.isEmpty {
            AppLog.info("dev: -ImportLink")
            await model.importLink(link, source: .link)
        } else if defaults.bool(forKey: "AutoConnect"), model.hasSubscription, !model.vpn.isActive {
            AppLog.info("dev: -AutoConnect")
            await model.connectTapped()
        }
        if defaults.bool(forKey: "Disconnect"), model.vpn.isActive {
            AppLog.info("dev: -Disconnect")
            model.vpn.stop()
        }
        #endif
    }

    static func mirrorLogs(from store: SkyRayStore) {
        #if DEBUG
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for url in [store.appLogURL, store.tunnelLogURL, store.xrayLogURL] {
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        #endif
    }
}
