import Foundation

/// One tick of the foreground poller that keeps an in-flight deploy's ambient surfaces current.
///
/// The loop itself is async and talks to a provider; this type is the decision at each tick so the
/// interesting cases can be unit tested: timeout, a deploy that vanished, unknown mid-flight, and
/// the moment it settles.
nonisolated struct DeploymentPollDecision: Equatable, Sendable {
    var outcome: DeploymentTracker.Outcome
    var continuePolling: Bool
    var nextInterval: TimeInterval
    var timedOut: Bool
    var disappeared: Bool
}

nonisolated enum DeploymentPollLoop {
    static func decide(
        elapsed: TimeInterval,
        rawStatus: String?,
        provider: AccountProvider,
        tracker: inout DeploymentTracker
    ) -> DeploymentPollDecision {
        if DeploymentPollPolicy.shouldTimeOut(elapsed: elapsed) {
            return DeploymentPollDecision(
                outcome: .ignored,
                continuePolling: false,
                nextInterval: 0,
                timedOut: true,
                disappeared: false
            )
        }

        // A missing row is not a failure. The deploy may have been deleted or paged out of the
        // list the API returns; treating that as a crash would page someone for nothing.
        guard let rawStatus else {
            return DeploymentPollDecision(
                outcome: .ignored,
                continuePolling: false,
                nextInterval: 0,
                timedOut: false,
                disappeared: true
            )
        }

        let outcome = tracker.ingest(DeploymentState(rawStatus: rawStatus, provider: provider))
        let continuePolling: Bool
        switch outcome {
        case .start, .update:
            continuePolling = true
        case .end:
            continuePolling = false
        case .ignored:
            continuePolling = tracker.isTracking
        }

        return DeploymentPollDecision(
            outcome: outcome,
            continuePolling: continuePolling,
            nextInterval: DeploymentPollPolicy.interval(elapsed: elapsed),
            timedOut: false,
            disappeared: false
        )
    }
}
