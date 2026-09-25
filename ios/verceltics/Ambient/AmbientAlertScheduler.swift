import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Delivers `AmbientAlert` values as local notifications.
///
/// Local only — no APNs, no server. What to alert about is decided by `AmbientAlertRules`; this
/// only schedules. Authorization is requested on the first alert, never at launch.
nonisolated enum AmbientAlertScheduler {
#if canImport(UserNotifications)
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

    static func schedule(_ alert: AmbientAlert) async {
        let center = UNUserNotificationCenter.current()
        let identifier = alert.dedupeKey
        guard !AmbientAlertLog.contains(identifier) else { return }

        let pending = await center.pendingNotificationRequests()
        guard !pending.contains(where: { $0.identifier == identifier }) else { return }

        let delivered = await center.deliveredNotifications()
        guard !delivered.contains(where: { $0.request.identifier == identifier }) else { return }

        if await !isAuthorized() {
            guard await requestAuthorization() else { return }
        }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.interruptionLevel = alert.isUrgent ? .timeSensitive : .active

        do {
            try await center.add(
                UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            )
            AmbientAlertLog.remember(identifier)
        } catch {
            return
        }
    }

    static func forget(_ alert: AmbientAlert) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [alert.dedupeKey])
        center.removeDeliveredNotifications(withIdentifiers: [alert.dedupeKey])
        AmbientAlertLog.forget(alert.dedupeKey)
    }
#else
    static func schedule(_ alert: AmbientAlert) async {}
    static func forget(_ alert: AmbientAlert) {}
#endif
}

private extension AmbientAlert {
    var isUrgent: Bool {
        switch self {
        case .deploymentFailed: true
        case .deploymentReady: false
        case .domainExpiring(_, let daysRemaining): daysRemaining <= 3
        }
    }
}
