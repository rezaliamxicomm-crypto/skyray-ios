import Foundation
import SkyRayCore

/// The first launch after the update from SkyRay 1.1.6 (the previous codebase in the same App Store record): the
/// customer's link is taken once from that app's files in the shared App Group, so nobody imports it again.
enum OldAppImport {
    @MainActor
    static func attempt(model: AppModel) async {
        let store = model.store
        guard !store.oldAppImportTried else { return }
        store.oldAppImportTried = true
        guard !model.hasSubscription,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Etha.appGroup),
              let link = OldAppFiles.link(inContainer: container) else { return }
        AppLog.info("the previous app's files hold the customer's link; importing it")
        await model.importLink(link, source: .link)
    }
}
