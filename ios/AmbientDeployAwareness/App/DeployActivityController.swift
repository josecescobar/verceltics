import ActivityKit
import Foundation

/// Bridges `DeploymentTracker` to ActivityKit.
///
/// All of the "should something happen" logic lives in `DeploymentTracker`, which is unit tested.
/// This type only performs what the tracker decided, so the untestable part stays as thin as
/// possible.
@MainActor
final class DeployActivityController {
    private var tracker = DeploymentTracker()
    private var activity: Activity<DeployActivityAttributes>?
    private let startedAt: Date
    private let attributes: DeployActivityAttributes

    init(attributes: DeployActivityAttributes, startedAt: Date = .now) {
        self.attributes = attributes
        self.startedAt = startedAt
    }

    /// Whether the user has Live Activities enabled for this app. There is no way to turn this on
    /// from inside the app, so callers should simply skip tracking when it is off.
    static var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Feed every observed status here. Ordering and de-duplication are handled by the tracker.
    func observe(rawStatus: String?, provider: AccountProvider) async {
        let state = DeploymentState(rawStatus: rawStatus, provider: provider)
        let statusText = rawStatus ?? state.displayName

        switch tracker.ingest(state) {
        case .ignored:
            return
        case .start(let state):
            await start(state: state, statusText: statusText)
        case .update(let state):
            await update(state: state, statusText: statusText, finished: false)
        case .end(let state):
            await update(state: state, statusText: statusText, finished: true)
        }
    }

    /// True while an activity is on screen.
    var isTracking: Bool {
        tracker.isTracking
    }

    // MARK: - ActivityKit

    private func start(state: DeploymentState, statusText: String) async {
        guard Self.isAvailable, activity == nil else { return }

        let content = ActivityContent(
            state: DeployActivityAttributes.ContentState(
                state: state,
                statusText: statusText,
                startedAt: startedAt
            ),
            staleDate: staleDate()
        )

        do {
            // `.token` push updates would need a server to send them, which this app deliberately
            // does not have, so updates come from the app itself while it is running.
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            // A refused activity is not worth interrupting the user over; the app's own UI still
            // shows the deploy.
            activity = nil
        }
    }

    private func update(state: DeploymentState, statusText: String, finished: Bool) async {
        guard let activity else { return }

        let contentState = DeployActivityAttributes.ContentState(
            state: state,
            statusText: statusText,
            startedAt: startedAt,
            finishedAt: finished ? Date.now : nil
        )

        if finished {
            // Leave the result up briefly so a glance catches it, rather than vanishing the moment
            // the deploy lands.
            await activity.end(
                ActivityContent(state: contentState, staleDate: nil),
                dismissalPolicy: .after(.now.addingTimeInterval(state.isFailure ? 300 : 60))
            )
            self.activity = nil
        } else {
            await activity.update(
                ActivityContent(state: contentState, staleDate: staleDate())
            )
        }
    }

    /// Marks the activity stale if the app has not been able to refresh it for a while, so the
    /// system can dim it instead of presenting an old status as current.
    private func staleDate() -> Date {
        .now.addingTimeInterval(4 * 60)
    }

    /// Dismiss anything still on screen, for sign-out or account removal.
    func cancel() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }
}
