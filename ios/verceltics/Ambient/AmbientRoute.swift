import Foundation

/// In-app destinations Siri, Shortcuts, and Spotlight can request.
///
/// Deep links do not open a specific project screen. The app's navigation is
/// workspace-first, so a route lands on Hosting, Registrars, or Sites. That is
/// enough for a voice command and for a search result; finer navigation still
/// happens inside the app.
nonisolated enum AmbientRoute: Equatable, Sendable {
    static let scheme = "verceltics"
    static let pendingWorkspaceKey = "ambient.pendingWorkspace"
    static let pendingDidChange = Notification.Name("ambient.pendingWorkspaceDidChange")

    case workspace(PrimaryWorkspace)
    case latestDeploy

    var workspace: PrimaryWorkspace {
        switch self {
        case .workspace(let workspace): workspace
        case .latestDeploy: .hosting
        }
    }

    var url: URL {
        switch self {
        case .workspace(let workspace):
            URL(string: "\(Self.scheme)://workspace/\(workspace.rawValue)")!
        case .latestDeploy:
            URL(string: "\(Self.scheme)://deploy/latest")!
        }
    }

    static func parse(_ url: URL) -> AmbientRoute? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = url.host?.lowercased() ?? ""
        let path = url.pathComponents.filter { $0 != "/" }

        if host == "workspace", let raw = path.first, let workspace = PrimaryWorkspace(rawValue: raw) {
            return .workspace(workspace)
        }
        if host == "deploy" {
            guard path.isEmpty || path == ["latest"] else { return nil }
            return .latestDeploy
        }
        return nil
    }

    static func store(_ route: AmbientRoute, defaults: UserDefaults = .standard) {
        defaults.set(route.workspace.rawValue, forKey: lastPrimaryWorkspaceKey)
        defaults.set(route.workspace.rawValue, forKey: pendingWorkspaceKey)
        NotificationCenter.default.post(name: pendingDidChange, object: nil)
    }

    static func consumePendingWorkspace(defaults: UserDefaults = .standard) -> PrimaryWorkspace? {
        guard let raw = defaults.string(forKey: pendingWorkspaceKey) else { return nil }
        defaults.removeObject(forKey: pendingWorkspaceKey)
        return PrimaryWorkspace(rawValue: raw)
    }
}

/// Spoken or listed copy for the latest cached deploy. Kept separate from
/// App Intents so the wording can be unit tested without the AppIntents SDK.
nonisolated enum LatestDeployStatusCopy {
    static func dialog(from snapshot: AmbientSnapshot?) -> String {
        guard let headline = snapshot?.headline else {
            return "Verceltics has no recent deployments. Open the app to refresh."
        }
        if snapshot?.isStale() == true {
            return "\(headline.projectName) on \(headline.provider.displayName) was \(headline.state.displayName.lowercased()) when last checked. Open Verceltics to refresh."
        }
        return "\(headline.projectName) on \(headline.provider.displayName) is \(headline.state.displayName.lowercased())."
    }
}
