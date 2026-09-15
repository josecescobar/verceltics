#if canImport(BackgroundTasks)
import BackgroundTasks
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Background refresh that keeps the snapshot warm and re-evaluates domain expiry.
///
/// `BGTaskScheduler.register` throws when `taskIdentifier` is missing from
/// `BGTaskSchedulerPermittedIdentifiers`. That key is in `verceltics-Info.plist`; do not call
/// `register` without it.
@MainActor
enum AmbientBackgroundRefresh {
    static let taskIdentifier = "com.apoorvdarshan.verceltics.refresh"

    private static let minimumInterval: TimeInterval = 30 * 60

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()

        let work = Task {
            await AmbientAwareness.shared.refreshFromBackground()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
#endif
