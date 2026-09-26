import Foundation
import BackgroundTasks
import SkyRayCore

/// The background refresh: asked for after every fetch at the header's interval; iOS decides the moment.
enum RefreshScheduler {
    static func schedule(after minutes: Int64) {
        let request = BGAppRefreshTaskRequest(identifier: Etha.refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(TimeInterval(max(minutes, Etha.minUpdateMinutes) * 60))
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Etha.refreshTaskID)
        do { try BGTaskScheduler.shared.submit(request) } catch { AppLog.warn("background refresh not scheduled: \(error)") }
    }

    static func cancel() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Etha.refreshTaskID) }

    static func handle(_ task: BGAppRefreshTask) {
        let work = Task {
            let store = SkyRayStore.appGroup()
            var ok = false
            if store.loadSnapshot() != nil {
                ok = (try? await SubscriptionImporter(store: store).refresh()) != nil
            }
            if !ok { schedule(after: Etha.defaultUpdateMinutes) }
            task.setTaskCompleted(success: ok)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
