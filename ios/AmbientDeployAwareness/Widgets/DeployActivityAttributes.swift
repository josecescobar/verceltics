import ActivityKit
import Foundation

/// Shape of the Live Activity for an in-flight deployment.
///
/// Add this file to **both** the app target and the widget extension target: the app requests and
/// updates the activity, and the extension renders it.
///
/// `ContentState` is intentionally small. Every update is delivered to the system, so it carries the
/// few things that actually change during a deploy and nothing that does not.
struct DeployActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Normalized lifecycle, so the presentation does not have to interpret provider strings.
        var state: DeploymentState
        /// The provider's own wording, shown verbatim because a Vercel user expects to read `READY`.
        var statusText: String
        /// When the deploy started, so the presentation can run its own timer rather than being
        /// updated once a second.
        var startedAt: Date
        /// Set once the deploy settles, which freezes the elapsed timer at the final duration.
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

        /// Range for a SwiftUI timer view. Once finished, the interval is closed so it stops moving.
        var elapsedRange: ClosedRange<Date> {
            let end = finishedAt ?? Date.distantFuture
            // A closed range must not be inverted, which a clock change could otherwise cause.
            return startedAt...max(startedAt, end)
        }
    }

    var projectName: String
    var provider: AccountProvider
    /// `production` or `preview` for Vercel; the equivalent branch or environment elsewhere.
    var target: String?
    var commitSubject: String?
    /// Opened when the activity is tapped.
    var inspectorURL: URL?
}
