import Foundation
import UserNotifications

/// Delivers `AmbientAlert` values as local notifications.
///
/// Local only — no APNs, no server, nothing leaves the device. What to alert about is decided by
/// `AmbientAlertRules`, which is unit tested; this only schedules.
nonisolated enum AmbientAlertScheduler {
    /// Ask only when the user opts into alerts, never at launch. A permission prompt with no context
    /// is the fastest way to get a permanent denial.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Schedules an alert unless one with the same identity is already pending or was delivered.
    ///
    /// De-duplication matters more than it looks: background refresh runs at times iOS chooses, and
    /// a domain sitting inside an expiry bucket would otherwise be announced on every wake.
    static func schedule(_ alert: AmbientAlert) async {
        let center = UNUserNotificationCenter.current()
        let identifier = alert.dedupeKey

        let pending = await center.pendingNotificationRequests()
        guard !pending.contains(where: { $0.identifier == identifier }) else { return }

        let delivered = await center.deliveredNotifications()
        guard !delivered.contains(where: { $0.request.identifier == identifier }) else { return }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.interruptionLevel = alert.isUrgent ? .timeSensitive : .active

        // No trigger: deliver as soon as the system allows, since the condition is already true.
        try? await center.add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        )
    }

    /// Drops the record of an alert so the same condition can be announced again later, for example
    /// after a failed deploy is retried.
    static func forget(_ alert: AmbientAlert) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [alert.dedupeKey])
        center.removeDeliveredNotifications(withIdentifiers: [alert.dedupeKey])
    }
}

private extension AmbientAlert {
    /// A broken deploy and an imminent domain loss are worth a time-sensitive delivery. A routine
    /// renewal reminder weeks out is not.
    var isUrgent: Bool {
        switch self {
        case .deploymentFailed: true
        case .deploymentReady: false
        case .domainExpiring(_, let daysRemaining): daysRemaining <= 3
        }
    }
}
