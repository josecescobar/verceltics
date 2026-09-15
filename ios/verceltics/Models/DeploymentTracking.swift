import Foundation

/// Decides when an in-flight deployment should present, update, or dismiss an ambient surface such
/// as a Live Activity.
///
/// The decision logic is kept separate from ActivityKit and from networking so it can be unit
/// tested. Feed it every status you observe, in order, and act on the returned outcome.
nonisolated struct DeploymentTracker: Equatable, Sendable {
    nonisolated enum Outcome: Equatable, Sendable {
        /// Nothing to do. Either the status did not change, it was unrecognized, or the deployment
        /// had already settled before anything was presented.
        case ignored
        case start(DeploymentState)
        case update(DeploymentState)
        case end(DeploymentState)
    }

    private var tracked: DeploymentState?
    private var hasStarted = false
    private var hasFinished = false

    init() {}

    /// True once a surface has been presented and not yet dismissed.
    var isTracking: Bool {
        hasStarted && !hasFinished
    }

    /// The last state acted upon.
    var state: DeploymentState? {
        tracked
    }

    mutating func ingest(_ state: DeploymentState) -> Outcome {
        // A settled deployment never reopens, so late or out-of-order polls are dropped.
        guard !hasFinished else { return .ignored }

        // Never present or dismiss on a status the state machine could not classify; doing so
        // would flicker a surface on an unmapped provider string.
        guard state != .unknown else { return .ignored }

        if state.isTerminal {
            hasFinished = true
            guard hasStarted else {
                // The deployment was already done the first time it was seen. There is nothing on
                // screen to dismiss, and announcing a finish nobody saw start is noise.
                return .ignored
            }
            tracked = state
            return .end(state)
        }

        guard hasStarted else {
            hasStarted = true
            tracked = state
            return .start(state)
        }

        guard tracked != state else { return .ignored }
        tracked = state
        return .update(state)
    }
}

/// Cadence for polling an in-flight deployment.
///
/// Deploys are fast at first and then long-tailed, so the interval widens as one runs on. Without
/// ActivityKit push tokens — which would require a server this app deliberately does not have —
/// polling only advances while the app is running, so the goal is to stay responsive early without
/// hammering the provider on a long build.
nonisolated enum DeploymentPollPolicy {
    /// Give up tracking after this long so a stuck deployment cannot poll forever.
    static let timeout: TimeInterval = 20 * 60

    static func interval(elapsed: TimeInterval) -> TimeInterval {
        switch max(0, elapsed) {
        case ..<60: 5
        case ..<300: 10
        default: 30
        }
    }

    static func shouldTimeOut(elapsed: TimeInterval) -> Bool {
        elapsed >= timeout
    }
}
