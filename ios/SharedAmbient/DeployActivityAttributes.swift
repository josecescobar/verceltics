#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Shape of the Live Activity for an in-flight deployment.
///
/// The widget extension, once added in Xcode, needs this type as well. Until then the app can
/// still request an activity; iOS will not render it without an extension.
struct DeployActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var state: DeploymentState
        var statusText: String
        var startedAt: Date
        var finishedAt: Date?

        init(
            state: DeploymentState,
            statusText: String,
            startedAt: Date,
            finishedAt: Date? = nil
        ) {
            self.state = state
            self.statusText = statusText
            self.startedAt = startedAt
            self.finishedAt = finishedAt
        }

        var elapsedRange: ClosedRange<Date> {
            let end = finishedAt ?? Date.distantFuture
            return startedAt...max(startedAt, end)
        }
    }

    var projectName: String
    var provider: AccountProvider
    var target: String?
    var commitSubject: String?
    var inspectorURL: URL?
}
#endif
