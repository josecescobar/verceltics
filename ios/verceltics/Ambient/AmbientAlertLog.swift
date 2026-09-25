import Foundation

/// Remembers which `AmbientAlert` keys have already been delivered.
///
/// `UNUserNotificationCenter` only knows about pending and still-visible notifications. Once
/// the user dismisses one, the next `publish` or background refresh would fire it again.
/// This log is the durable half of that de-dupe.
nonisolated enum AmbientAlertLog {
    static let defaultsKey = "ambient.notifiedAlertKeys"

    static func contains(_ key: String, defaults: UserDefaults = .standard) -> Bool {
        notified(defaults: defaults).contains(key)
    }

    static func remember(_ key: String, defaults: UserDefaults = .standard) {
        var keys = notified(defaults: defaults)
        keys.insert(key)
        defaults.set(Array(keys), forKey: defaultsKey)
    }

    static func forget(_ key: String, defaults: UserDefaults = .standard) {
        var keys = notified(defaults: defaults)
        keys.remove(key)
        defaults.set(Array(keys), forKey: defaultsKey)
    }

    private static func notified(defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    }
}
