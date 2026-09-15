import Foundation

/// Normalized deployment lifecycle used for status tone, in-flight detection, and Live Activities.
///
/// Provider vocabularies collide: `RUNNING` is an in-progress build job on AWS Amplify but a healthy
/// machine on Fly, and `ACTIVE` is a finished deployment on DigitalOcean but an in-progress one on
/// Cloudflare Pages. Classification therefore has to be scoped to the provider that produced the
/// string rather than matched globally.
///
/// This type is deliberately Foundation-only so it can be shared with an extension target and
/// covered by unit tests.
nonisolated enum DeploymentState: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case queued
    case initializing
    case building
    case deploying
    case ready
    case failed
    case canceled
    case superseded
    /// The provider returned a value this table does not recognize. Callers should fall back to
    /// their previous behavior rather than treating it as a definitive state.
    case unknown

    /// True while the provider is still working and the outcome is not yet decided.
    var isInFlight: Bool {
        switch self {
        case .queued, .initializing, .building, .deploying: true
        case .ready, .failed, .canceled, .superseded, .unknown: false
        }
    }

    /// True once the deployment has settled and will not change again.
    var isTerminal: Bool {
        switch self {
        case .ready, .failed, .canceled, .superseded: true
        case .queued, .initializing, .building, .deploying, .unknown: false
        }
    }

    /// True only when the deployment errored. Canceled and superseded deploys also never shipped,
    /// but neither is something to alert someone about.
    var isFailure: Bool {
        self == .failed
    }

    /// Short human label. Provider text is preferred in list UI; this is for surfaces that need a
    /// consistent vocabulary, such as a Live Activity.
    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .initializing: "Initializing"
        case .building: "Building"
        case .deploying: "Deploying"
        case .ready: "Ready"
        case .failed: "Failed"
        case .canceled: "Canceled"
        case .superseded: "Superseded"
        case .unknown: "Unknown"
        }
    }

    // MARK: - Persistence

    /// Decodes leniently so a snapshot written by a newer build, which may know states this one
    /// does not, degrades to `.unknown` instead of failing the whole payload.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DeploymentState(rawValue: raw) ?? .unknown
    }

    // MARK: - Normalization

    init(rawStatus: String?, provider: AccountProvider) {
        guard let rawStatus else {
            self = .unknown
            return
        }

        let token = Self.token(rawStatus)
        guard !token.isEmpty else {
            self = .unknown
            return
        }

        if let mapped = Self.providerTables[provider]?[token] {
            self = mapped
            return
        }
        if let mapped = Self.sharedTable[token] {
            self = mapped
            return
        }
        self = .unknown
    }

    /// Lowercases and collapses the separators providers disagree on, so `PENDING_BUILD`,
    /// `pending-build`, and `Pending Build` all resolve to the same key.
    private static func token(_ rawStatus: String) -> String {
        rawStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    // MARK: - Provider vocabularies

    private static let providerTables: [AccountProvider: [String: DeploymentState]] = [
        .vercel: [
            "queued": .queued,
            "initializing": .initializing,
            "building": .building,
            "ready": .ready,
            "error": .failed,
            "canceled": .canceled,
            "cancelled": .canceled,
            "deleted": .superseded,
        ],
        .netlify: [
            "new": .queued,
            "pending_review": .queued,
            "accepted": .queued,
            "enqueued": .queued,
            "retrying": .queued,
            "building": .building,
            "preparing": .deploying,
            "prepared": .deploying,
            "uploading": .deploying,
            "uploaded": .deploying,
            "processing": .deploying,
            "ready": .ready,
            "error": .failed,
            "failed": .failed,
            "rejected": .failed,
            "canceled": .canceled,
            "cancelled": .canceled,
            "skipped": .canceled,
            "deleted": .superseded,
        ],
        .railway: [
            "queued": .queued,
            "waiting": .queued,
            "needs_approval": .queued,
            "initializing": .initializing,
            "building": .building,
            "deploying": .deploying,
            "success": .ready,
            // A sleeping Railway deployment is still the live one, just idled down.
            "sleeping": .ready,
            "failed": .failed,
            "crashed": .failed,
            "skipped": .canceled,
            "removing": .superseded,
            "removed": .superseded,
        ],
        .render: [
            "created": .queued,
            "queued": .queued,
            "build_in_progress": .building,
            "pre_deploy_in_progress": .deploying,
            "update_in_progress": .deploying,
            "live": .ready,
            "build_failed": .failed,
            "pre_deploy_failed": .failed,
            "update_failed": .failed,
            "canceled": .canceled,
            "cancelled": .canceled,
            "deactivated": .superseded,
        ],
        .digitalOcean: [
            "pending_build": .queued,
            "pending_deploy": .queued,
            "building": .building,
            // Previously matched no branch at all and rendered without a status signal.
            "deploying": .deploying,
            "active": .ready,
            "superseded": .superseded,
            "error": .failed,
            "canceled": .canceled,
            "cancelled": .canceled,
            "unknown": .unknown,
        ],
        .heroku: [
            "pending": .deploying,
            "succeeded": .ready,
            "success": .ready,
            // Synthesized by HostingProviderAPI when a release reports no explicit status.
            "current": .ready,
            "released": .ready,
            "failed": .failed,
        ],
        .fly: [
            // Fly deployment rows are machines, so the vocabulary is machine state.
            "created": .queued,
            "starting": .deploying,
            "replacing": .deploying,
            "started": .ready,
            "stopping": .superseded,
            "stopped": .superseded,
            "suspending": .superseded,
            "suspended": .superseded,
            "destroying": .canceled,
            "destroyed": .canceled,
            "failed": .failed,
        ],
        .firebase: [
            "created": .deploying,
            "cloning": .deploying,
            "finalized": .ready,
            // Synthesized by HostingProviderAPI when a release carries no version status.
            "released": .ready,
            "deleted": .superseded,
            "abandoned": .superseded,
            "expired": .superseded,
            "version_status_unspecified": .unknown,
        ],
        .awsAmplify: [
            "pending": .queued,
            "provisioning": .initializing,
            // An Amplify job that is RUNNING is mid-build, not a success.
            "running": .building,
            "succeed": .ready,
            "succeeded": .ready,
            "failed": .failed,
            "canceling": .canceled,
            "cancelling": .canceled,
            "canceled": .canceled,
            "cancelled": .canceled,
        ],
        .cloudflare: [
            // Cloudflare Pages exposes `latest_stage.status`; the stage name carries the phase.
            "idle": .queued,
            "active": .building,
            "success": .ready,
            "failure": .failed,
            "failed": .failed,
            "canceled": .canceled,
            "cancelled": .canceled,
            "skipped": .canceled,
        ],
    ]

    /// Consulted when a provider table has no entry for the value. Only unambiguous tokens belong
    /// here; anything whose meaning depends on the provider must stay in the provider table.
    private static let sharedTable: [String: DeploymentState] = [
        "queued": .queued,
        "pending": .queued,
        "waiting": .queued,
        "new": .queued,
        "enqueued": .queued,
        "initializing": .initializing,
        "provisioning": .initializing,
        "building": .building,
        "build_in_progress": .building,
        "deploying": .deploying,
        "uploading": .deploying,
        "processing": .deploying,
        "ready": .ready,
        "success": .ready,
        "succeed": .ready,
        "succeeded": .ready,
        "live": .ready,
        "published": .ready,
        "complete": .ready,
        "completed": .ready,
        "error": .failed,
        "failed": .failed,
        "failure": .failed,
        "crashed": .failed,
        "fatal": .failed,
        "canceled": .canceled,
        "cancelled": .canceled,
        "skipped": .canceled,
        "superseded": .superseded,
        "deleted": .superseded,
        "expired": .superseded,
    ]
}
