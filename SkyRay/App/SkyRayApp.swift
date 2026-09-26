import SwiftUI
import SkyRayCore

@main
struct SkyRayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { url in Task { await model.handleIncoming(url) } }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { Task { await model.handleIncoming(url) } }
                }
                .task { await model.onLaunch() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.onActive() } }
        }
    }
}
