import Foundation

/// An alert the app can raise without being open.
///
/// Verceltics has no server by design, so these are delivered as on-device local notifications
/// scheduled from a background refresh rather than pushed through APNs.
nonisolated enum AmbientAlert: Equatable, Sendable {
    case deploymentFailed(project: String, provider: AccountProvider)
    case deploymentReady(project: String, provider: AccountProvider)
    /// `daysRemaining` is clamped at zero; an already-expired domain reports zero.
    case domainExpiring(domain: String, daysRemaining: Int)

    /// Stable identity for de-duplication, so the same condition is not announced twice.
    var dedupeKey: String {
        switch self {
        case .deploymentFailed(let project, let provider):
            "deployment-failed:\(provider.rawValue):\(project)"
        case .deploymentReady(let project, let provider):
            "deployment-ready:\(provider.rawValue):\(project)"
        case .domainExpiring(let domain, let daysRemaining):
            "domain-expiring:\(domain.lowercased()):\(daysRemaining)"
        }
    }

    var title: String {
        switch self {
        case .deploymentFailed(let project, _): "\(project) failed to deploy"
        case .deploymentReady(let project, _): "\(project) is live"
        case .domainExpiring(let domain, let daysRemaining):
            daysRemaining == 0 ? "\(domain) has expired" : "\(domain) expires soon"
        }
    }

    var body: String {
        switch self {
        case .deploymentFailed(_, let provider): "The latest \(provider.displayName) deployment did not finish."
        case .deploymentReady(_, let provider): "The latest \(provider.displayName) deployment is ready."
        case .domainExpiring(_, let daysRemaining):
            switch daysRemaining {
            case 0: "Renew it now to avoid losing the domain."
            case 1: "Renew it within the next day."
            default: "Renew it within \(daysRemaining) days."
            }
        }
    }
}

/// Decides which ambient alerts are worth raising.
///
/// Pure so the policy can be unit tested without scheduling real notifications.
nonisolated enum AmbientAlertRules {
    /// Days-remaining buckets at which a domain expiry alert fires. One alert per bucket, so a
    /// renewal window produces a handful of reminders rather than one per refresh.
    static let domainExpiryThresholds: [Int] = [30, 14, 7, 3, 1]

    /// A first-read failure older than this is history, not news. Opening five projects
    /// whose last deploys failed last week must not schedule five notifications.
    static let firstReadAlertMaxAge: TimeInterval = 6 * 60 * 60

    /// Raise an alert only when a deployment actually settles, and only when the transition is one
    /// the user has not already seen in the app.
    ///
    /// - Parameters:
    ///   - previous: the last state observed, or `nil` on a first read.
    ///   - current: the state just observed.
    ///   - notifyOnSuccess: successful deploys are the common case and mostly noise, so they are
    ///     opt-in.
    ///   - observedAt: when the current status was produced. A first-read failure older than
    ///     `firstReadAlertMaxAge` is treated as already-seen history.
    static func deploymentAlert(
        project: String,
        provider: AccountProvider,
        previous: DeploymentState?,
        current: DeploymentState,
        notifyOnSuccess: Bool = false,
        observedAt: Date? = nil,
        now: Date = .now
    ) -> AmbientAlert? {
        // Only a fresh transition is newsworthy. A status that was already terminal last time we
        // looked has been reported already.
        guard current.isTerminal else { return nil }
        if let previous, previous.isTerminal { return nil }
        if previous == nil, let observedAt, now.timeIntervalSince(observedAt) > firstReadAlertMaxAge {
            return nil
        }

        switch current {
        case .failed:
            return .deploymentFailed(project: project, provider: provider)
        case .ready:
            return notifyOnSuccess ? .deploymentReady(project: project, provider: provider) : nil
        // A deploy the user canceled, or one replaced by a newer deploy, is not news.
        case .canceled, .superseded:
            return nil
        case .queued, .initializing, .building, .deploying, .unknown:
            return nil
        }
    }

    static func domainExpiryAlert(
        domain: String,
        expiresAt: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AmbientAlert? {
        let days = daysRemaining(from: now, until: expiresAt, calendar: calendar)
        guard let bucket = expiryBucket(daysRemaining: days) else { return nil }
        return .domainExpiring(domain: domain, daysRemaining: bucket)
    }

    /// Whole days between two instants, compared by calendar day so a refresh at 09:00 and one at
    /// 23:00 on the same day agree. Never negative.
    static func daysRemaining(from now: Date, until expiry: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: expiry)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, days)
    }

    /// The threshold a given days-remaining value belongs to, or `nil` when expiry is still far off.
    static func expiryBucket(daysRemaining: Int) -> Int? {
        guard daysRemaining > 0 else { return 0 }
        return domainExpiryThresholds.sorted().first { daysRemaining <= $0 }
    }
}
