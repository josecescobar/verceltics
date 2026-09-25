import Foundation

/// One deployment as an ambient surface needs to render it.
///
/// `statusText` keeps the provider's own wording, because a Vercel user expects to read `READY`,
/// while `state` carries the normalized meaning used for tone and in-flight decisions.
nonisolated struct AmbientDeploymentSnapshot: Codable, Equatable, Sendable {
    let id: String
    let projectName: String
    let provider: AccountProvider
    let state: DeploymentState
    let statusText: String
    let updatedAt: Date
    let targetURL: String?
    let commitSubject: String?
    /// `production` / `preview` on Vercel; a branch elsewhere. Optional so older snapshots stay readable.
    let target: String?

    init(
        id: String? = nil,
        projectName: String,
        provider: AccountProvider,
        state: DeploymentState,
        statusText: String,
        updatedAt: Date,
        targetURL: String? = nil,
        commitSubject: String? = nil,
        target: String? = nil
    ) {
        self.id = id ?? "\(provider.rawValue):\(projectName)"
        self.projectName = projectName
        self.provider = provider
        self.state = state
        self.statusText = statusText
        self.updatedAt = updatedAt
        self.targetURL = targetURL
        self.commitSubject = commitSubject
        self.target = target
    }

    /// Stable identity for the in-memory map. The default `id` already includes the provider
    /// prefix, so do not prefix it again — that used to produce `vercel:vercel:app` next to
    /// `vercel:dpl_xxx` for the same project.
    var trackingKey: String {
        let prefix = "\(provider.rawValue):"
        return id.hasPrefix(prefix) ? id : prefix + id
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectName = try container.decode(String.self, forKey: .projectName)
        provider = try container.decode(AccountProvider.self, forKey: .provider)
        state = try container.decode(DeploymentState.self, forKey: .state)
        statusText = try container.decode(String.self, forKey: .statusText)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        targetURL = try container.decodeIfPresent(String.self, forKey: .targetURL)
        commitSubject = try container.decodeIfPresent(String.self, forKey: .commitSubject)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? "\(provider.rawValue):\(projectName)"
    }
}

/// Versioned envelope for the data an extension reads.
///
/// A widget runs in a separate process and cannot reach the app's in-memory caches, so the app has
/// to hand it a small, self-describing payload. This deliberately carries no credentials: it holds
/// only what is already on screen, so it can live at rest under file protection without widening
/// what an extension is trusted with.
nonisolated struct AmbientDomainSnapshot: Codable, Equatable, Sendable {
    let name: String
    let expiresAt: Date
}

nonisolated struct AmbientSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    /// A widget does not need deep history, and a bounded payload keeps decode cost predictable.
    static let maxEntries = 8

    let version: Int
    let capturedAt: Date
    let deployments: [AmbientDeploymentSnapshot]
    let domains: [AmbientDomainSnapshot]

    init(
        capturedAt: Date,
        deployments: [AmbientDeploymentSnapshot],
        domains: [AmbientDomainSnapshot] = []
    ) {
        self.version = Self.currentVersion
        self.capturedAt = capturedAt
        // Newest first, then truncated, so the entries a widget shows are the relevant ones.
        self.deployments = deployments
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(Self.maxEntries)
            .map { $0 }
        self.domains = domains
            .sorted { $0.expiresAt < $1.expiresAt }
            .prefix(Self.maxEntries)
            .map { $0 }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        deployments = try container.decode([AmbientDeploymentSnapshot].self, forKey: .deployments)
        // Added after the first snapshots were written; older payloads stay readable.
        domains = try container.decodeIfPresent([AmbientDomainSnapshot].self, forKey: .domains) ?? []
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
