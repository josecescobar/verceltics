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
        tracker: inout DeploymentTracker,
        consecutiveMisses: Int = 0
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

        // A missing row is not a failure. The deploy may have been deleted, paged out of the
        // list, or hidden by a transient `try?`. One empty read is a blip; several in a row
        // means it is gone.
        guard let rawStatus else {
            let disappeared = consecutiveMisses >= DeploymentPollPolicy.missingStatusLimit
            return DeploymentPollDecision(
                outcome: .ignored,
                continuePolling: !disappeared,
                nextInterval: DeploymentPollPolicy.interval(elapsed: elapsed),
                timedOut: false,
                disappeared: disappeared
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
