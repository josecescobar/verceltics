import Foundation

/// One deployment as an ambient surface needs to render it.
///
/// `statusText` keeps the provider's own wording, because a Vercel user expects to read `READY`,
/// while `state` carries the normalized meaning used for tone and in-flight decisions.
nonisolated struct AmbientDeploymentSnapshot: Codable, Equatable, Sendable {
    let projectName: String
    let provider: AccountProvider
    let state: DeploymentState
    let statusText: String
    let updatedAt: Date
    let targetURL: String?
    let commitSubject: String?

    init(
        projectName: String,
        provider: AccountProvider,
        state: DeploymentState,
        statusText: String,
        updatedAt: Date,
        targetURL: String? = nil,
        commitSubject: String? = nil
    ) {
        self.projectName = projectName
        self.provider = provider
        self.state = state
        self.statusText = statusText
        self.updatedAt = updatedAt
        self.targetURL = targetURL
        self.commitSubject = commitSubject
    }
}

/// Versioned envelope for the data an extension reads.
///
/// A widget runs in a separate process and cannot reach the app's in-memory caches, so the app has
/// to hand it a small, self-describing payload. This deliberately carries no credentials: it holds
/// only what is already on screen, so it can live at rest under file protection without widening
/// what an extension is trusted with.
nonisolated struct AmbientSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    /// A widget does not need deep history, and a bounded payload keeps decode cost predictable.
    static let maxEntries = 8

    let version: Int
    let capturedAt: Date
    let deployments: [AmbientDeploymentSnapshot]

    init(capturedAt: Date, deployments: [AmbientDeploymentSnapshot]) {
        self.version = Self.currentVersion
        self.capturedAt = capturedAt
        // Newest first, then truncated, so the entries a widget shows are the relevant ones.
        self.deployments = deployments
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(Self.maxEntries)
            .map { $0 }
    }

    /// Whether the payload is too old to present as current.
    func isStale(now: Date = .now, maxAge: TimeInterval = 60 * 60) -> Bool {
        now.timeIntervalSince(capturedAt) > maxAge
    }

    /// The deployment a single-slot widget should show: an in-flight one if there is one, since a
    /// running build is the most time-sensitive thing the user could see, otherwise the newest.
    var headline: AmbientDeploymentSnapshot? {
        deployments.first { $0.state.isInFlight } ?? deployments.first
    }
}

// MARK: - Codec

nonisolated enum AmbientSnapshotCodec {
    nonisolated enum Failure: Error, Equatable {
        case unsupportedVersion(Int)
    }

    static func encode(_ snapshot: AmbientSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> AmbientSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(AmbientSnapshot.self, from: data)
        // Refuse a payload written by a build that changed the shape, rather than rendering
        // something half-understood.
        guard snapshot.version <= AmbientSnapshot.currentVersion else {
            throw Failure.unsupportedVersion(snapshot.version)
        }
        return snapshot
    }
}
