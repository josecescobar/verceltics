#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Bridges `DeploymentTracker` outcomes to ActivityKit.
///
/// The tracker is unit tested; this type only performs what the tracker decided.
@MainActor
final class DeployActivityController {
    private var activity: Activity<DeployActivityAttributes>?
    private let startedAt: Date
    private let attributes: DeployActivityAttributes

    init(attributes: DeployActivityAttributes, startedAt: Date = .now) {
        self.attributes = attributes
        self.startedAt = startedAt
    }

    static var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func apply(outcome: DeploymentTracker.Outcome, statusText: String) async {
        switch outcome {
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

    private func start(state: DeploymentState, statusText: String) async {
        guard Self.isAvailable, activity == nil else { return }

        // After a relaunch, iOS may still be showing the previous activity for this project.
        // Adopt it instead of requesting a second one.
        if let existing = Activity<DeployActivityAttributes>.activities.first(where: {
            $0.attributes.projectName == attributes.projectName
                && $0.attributes.provider == attributes.provider
        }) {
            activity = existing
            await update(state: state, statusText: statusText, finished: false)
            return
        }

        let content = ActivityContent(
            state: DeployActivityAttributes.ContentState(
                state: state,
                statusText: statusText,
                startedAt: startedAt
            ),
            staleDate: staleDate()
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
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

    private func staleDate() -> Date {
        .now.addingTimeInterval(4 * 60)
    }

    func cancel() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }
}
#endif
