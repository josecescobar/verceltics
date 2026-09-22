import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Coordinates the ambient surfaces that sit on top of the deploy state machine.
///
/// Views hand it whatever they just loaded. It writes the shared snapshot, raises alerts on
/// genuine transitions, and starts a foreground poller for anything still in flight. Live
/// Activity presentation is requested here; `VercelticsWidgets` renders the Lock Screen
/// and Dynamic Island. WidgetKit timelines reload whenever the snapshot is written.
@MainActor
final class AmbientAwareness {
    static let shared = AmbientAwareness()

    private var lastDeploymentState: [String: DeploymentState] = [:]
    private var deployments: [String: AmbientDeploymentSnapshot] = [:]
    private var domains: [String: AmbientDomainSnapshot] = [:]
    private var pollTasks: [String: Task<Void, Never>] = [:]
    private var statusHandlers: [String: [@MainActor (String) -> Void]] = [:]
#if canImport(ActivityKit)
    private var activities: [String: DeployActivityController] = [:]
#endif
    private var didLoadPersisted = false

    init() {}

    // MARK: - Ingest

    func publish(deployments incoming: [AmbientDeploymentSnapshot]) {
        loadPersistedIfNeeded()
        for item in incoming {
            consider(item)
        }
        persist()
    }

    func publish(domains incoming: [AmbientDomainSnapshot]) {
        loadPersistedIfNeeded()
        for domain in incoming {
            domains[domain.name.lowercased()] = domain
            if let alert = AmbientAlertRules.domainExpiryAlert(
                domain: domain.name,
                expiresAt: domain.expiresAt
            ) {
                Task { await AmbientAlertScheduler.schedule(alert) }
            }
        }
        persist()
    }

    /// Starts (or keeps) a poller for an in-flight deploy. Terminal deploys are recorded and left.
    func watch(
        _ snapshot: AmbientDeploymentSnapshot,
        onStatus: (@MainActor (String) -> Void)? = nil,
        fetchStatus: @escaping @MainActor () async -> String?
    ) {
        loadPersistedIfNeeded()
        consider(snapshot)
        persist()

        guard snapshot.state.isInFlight else { return }
        let key = snapshot.trackingKey
        if let onStatus {
            statusHandlers[key, default: []].append(onStatus)
        }
        guard pollTasks[key] == nil else { return }

        let startedAt = Date.now
        pollTasks[key] = Task { [weak self] in
            await self?.poll(
                key: key,
                startedAt: startedAt,
                fetchStatus: fetchStatus
            )
        }
    }

    func cancelWatch(_ key: String) {
        pollTasks[key]?.cancel()
        pollTasks[key] = nil
        statusHandlers[key] = nil
#if canImport(ActivityKit)
        let controller = activities.removeValue(forKey: key)
        Task { await controller?.cancel() }
#endif
    }

    func refreshFromBackground() async {
        loadPersistedIfNeeded()
        for domain in domains.values {
            if let alert = AmbientAlertRules.domainExpiryAlert(
                domain: domain.name,
                expiresAt: domain.expiresAt
            ) {
                await AmbientAlertScheduler.schedule(alert)
            }
        }
        reloadWidgets()
    }

    // MARK: - Internals

    private func consider(_ snapshot: AmbientDeploymentSnapshot) {
        let key = snapshot.trackingKey
        let previous = lastDeploymentState[key]
        deployments[key] = snapshot

        if let alert = AmbientAlertRules.deploymentAlert(
            project: snapshot.projectName,
            provider: snapshot.provider,
            previous: previous,
            current: snapshot.state
        ) {
            Task { await AmbientAlertScheduler.schedule(alert) }
        }

        lastDeploymentState[key] = snapshot.state
    }

    private func poll(
        key: String,
        startedAt: Date,
        fetchStatus: @escaping @MainActor () async -> String?
    ) async {
        var tracker = DeploymentTracker()
        if let initial = deployments[key] {
            _ = tracker.ingest(initial.state)
            await present(key: key, outcome: .start(initial.state), snapshot: initial)
        }

        while !Task.isCancelled {
            let elapsed = Date.now.timeIntervalSince(startedAt)
            let raw: String?
            do {
                raw = await fetchStatus()
            }
            let provider = deployments[key]?.provider ?? .vercel
            let decision = DeploymentPollLoop.decide(
                elapsed: elapsed,
                rawStatus: raw,
                provider: provider,
                tracker: &tracker
            )

            if let raw {
                for handler in statusHandlers[key] ?? [] {
                    handler(raw)
                }
            }
            if let raw, let current = deployments[key] {
                let next = AmbientDeploymentSnapshot(
                    id: current.id,
                    projectName: current.projectName,
                    provider: current.provider,
                    state: DeploymentState(rawStatus: raw, provider: provider),
                    statusText: raw,
                    updatedAt: .now,
                    targetURL: current.targetURL,
                    commitSubject: current.commitSubject
                )
                consider(next)
                persist()
                await present(key: key, outcome: decision.outcome, snapshot: next)
            }

            guard decision.continuePolling else {
                if decision.timedOut || decision.disappeared {
                    cancelWatch(key)
                }
                break
            }
            do {
                try await Task.sleep(for: .seconds(decision.nextInterval))
            } catch {
                break
            }
        }

        pollTasks[key] = nil
    }

    private func present(
        key: String,
        outcome: DeploymentTracker.Outcome,
        snapshot: AmbientDeploymentSnapshot
    ) async {
#if canImport(ActivityKit)
        switch outcome {
        case .ignored:
            return
        case .start:
            let controller = activities[key] ?? DeployActivityController(
                attributes: DeployActivityAttributes(
                    projectName: snapshot.projectName,
                    provider: snapshot.provider,
                    target: nil,
                    commitSubject: snapshot.commitSubject,
                    inspectorURL: snapshot.targetURL.flatMap(URL.init(string:))
                )
            )
            activities[key] = controller
            await controller.apply(outcome: outcome, statusText: snapshot.statusText)
        case .update, .end:
            await activities[key]?.apply(outcome: outcome, statusText: snapshot.statusText)
            if case .end = outcome {
                activities[key] = nil
            }
        }
#endif
    }

    private func loadPersistedIfNeeded() {
        guard !didLoadPersisted else { return }
        didLoadPersisted = true
        guard let snapshot = AmbientSnapshotStore.read() else { return }
        for item in snapshot.deployments {
            deployments[item.trackingKey] = item
            lastDeploymentState[item.trackingKey] = item.state
        }
        for domain in snapshot.domains {
            domains[domain.name.lowercased()] = domain
        }
    }

    private func persist() {
        let snapshot = AmbientSnapshot(
            capturedAt: .now,
            deployments: Array(deployments.values),
            domains: Array(domains.values)
        )
        try? AmbientSnapshotStore.write(snapshot)
        AmbientSpotlightIndex.indexSnapshot(snapshot)
        reloadWidgets()
    }

    private func reloadWidgets() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
#endif
    }
}

extension AmbientAwareness {
    func publishVercel(
        deployments: [RecentDeployment],
        project: Project,
        token: String
    ) {
        let snapshots = deployments.map { $0.ambientSnapshot(project: project) }
        publish(deployments: snapshots)

        if let latest = snapshots.first(where: { $0.state.isInFlight }),
           latest.state.isInFlight {
            watch(latest) {
                let fetched = try? await VercelAPI(token: token).fetchDeployment(
                    id: latest.id,
                    projectId: project.id,
                    teamId: project.teamId
                )
                return fetched?.displayState
            }
        }
    }

    func publishHosting(
        deployments: [HostingDeployment],
        resource: HostingResource,
        provider: AccountProvider,
        fetch: @escaping @MainActor () async -> [HostingDeployment]
    ) {
        let snapshots = deployments.map { $0.ambientSnapshot(resource: resource, provider: provider) }
        publish(deployments: snapshots)

        if let latest = snapshots.first(where: { $0.state.isInFlight }) {
            let watchedID = latest.id
            watch(latest) {
                let loaded = await fetch()
                return loaded.first(where: { $0.id == watchedID })?.status
            }
        }
    }

    func publishRegistrarDomains(_ incoming: [RegistrarDomain]) {
        publish(domains: incoming.compactMap { domain in
            guard let expiresAt = domain.expiresAt else { return nil }
            return AmbientDomainSnapshot(name: domain.name, expiresAt: expiresAt)
        })
    }
}

extension RecentDeployment {
    func ambientSnapshot(project: Project) -> AmbientDeploymentSnapshot {
        AmbientDeploymentSnapshot(
            id: id,
            projectName: project.name,
            provider: .vercel,
            state: DeploymentState(rawStatus: displayState, provider: .vercel),
            statusText: displayState,
            updatedAt: date ?? .now,
            targetURL: inspectorUrl ?? url.map { "https://\($0)" },
            commitSubject: meta?.githubCommitMessage
        )
    }
}

extension HostingDeployment {
    func ambientSnapshot(resource: HostingResource, provider: AccountProvider) -> AmbientDeploymentSnapshot {
        AmbientDeploymentSnapshot(
            id: id,
            projectName: resource.name,
            provider: provider,
            state: DeploymentState(rawStatus: status, provider: provider),
            statusText: status,
            updatedAt: createdAt ?? .now,
            targetURL: url,
            commitSubject: commitMessage
        )
    }
}
