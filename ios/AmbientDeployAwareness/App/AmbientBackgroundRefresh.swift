import BackgroundTasks
import Foundation
import WidgetKit

/// Background refresh that keeps the widget snapshot warm and raises alerts.
///
/// ## Register before you schedule
///
/// `BGTaskScheduler.register` **throws** when `taskIdentifier` is missing from the app's
/// `BGTaskSchedulerPermittedIdentifiers`, and it must be called before the app finishes launching.
/// Add the identifier to `Info.plist` and enable the Background Modes → Background fetch capability
/// first, or the app will crash on launch.
///
/// iOS decides if and when this runs. Treat every execution as a bonus, never as a schedule.
@MainActor
enum AmbientBackgroundRefresh {
    static let taskIdentifier = "com.apoorvdarshan.verceltics.refresh"

    /// The earliest the system should consider running the task. It routinely waits much longer.
    private static let minimumInterval: TimeInterval = 30 * 60

    /// Call from `application(_:didFinishLaunchingWithOptions:)` or an equivalent App launch hook.
    static func register(handler: @escaping @Sendable () async -> Void) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask, handler: handler)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        // Throws when background refresh is disabled by the user or by Low Power Mode, which is a
        // normal condition rather than an error worth surfacing.
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask, handler: @escaping @Sendable () async -> Void) {
        // Always queue the next one first. Skipping this on an early return silently ends all future
        // background refresh.
        schedule()

        let work = Task {
            await handler()
            WidgetCenter.shared.reloadAllTimelines()
            task.setTaskCompleted(success: true)
        }

        // The system can reclaim the runtime at any moment; leaving the task uncompleted counts
        // against future scheduling.
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
