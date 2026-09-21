#if canImport(AppIntents)
import AppIntents
import Foundation

enum WorkspaceAppEnum: String, AppEnum {
    case hosting
    case registrars
    case sites

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workspace")

    static var caseDisplayRepresentations: [WorkspaceAppEnum: DisplayRepresentation] = [
        .hosting: "Hosting",
        .registrars: "Registrars",
        .sites: "Sites",
    ]

    var workspace: PrimaryWorkspace {
        switch self {
        case .hosting: .hosting
        case .registrars: .registrars
        case .sites: .sites
        }
    }
}

/// Reports the most relevant cached deployment without opening the app.
struct LatestDeployStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Latest deploy status"
    static var description = IntentDescription(
        "Reports the most recent deployment Verceltics has seen, using the last cached snapshot."
    )
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = LatestDeployStatusCopy.dialog(from: AmbientSnapshotStore.read())
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

/// Opens Hosting, Registrars, or Sites.
struct OpenWorkspaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Open workspace"
    static var description = IntentDescription("Opens Hosting, Registrars, or Sites in Verceltics.")
    static var openAppWhenRun = true

    @Parameter(title: "Workspace")
    var workspace: WorkspaceAppEnum

    init() {
        workspace = .hosting
    }

    init(workspace: WorkspaceAppEnum) {
        self.workspace = workspace
    }

    func perform() async throws -> some IntentResult {
        AmbientRoute.store(.workspace(workspace.workspace))
        return .result()
    }
}

struct VercelticsShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .navy }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LatestDeployStatusIntent(),
            phrases: [
                "Latest deploy in \(.applicationName)",
                "What's the latest deploy in \(.applicationName)",
                "Deploy status in \(.applicationName)",
            ],
            shortTitle: "Latest deploy",
            systemImageName: "hammer"
        )
        AppShortcut(
            intent: OpenWorkspaceIntent(workspace: .hosting),
            phrases: [
                "Open hosting in \(.applicationName)",
                "Open \(.applicationName) hosting",
            ],
            shortTitle: "Open hosting",
            systemImageName: "server.rack"
        )
        AppShortcut(
            intent: OpenWorkspaceIntent(workspace: .registrars),
            phrases: [
                "Open registrars in \(.applicationName)",
                "Open domains in \(.applicationName)",
            ],
            shortTitle: "Open registrars",
            systemImageName: "globe.americas.fill"
        )
        AppShortcut(
            intent: OpenWorkspaceIntent(workspace: .sites),
            phrases: [
                "Open sites in \(.applicationName)",
                "Open \(.applicationName) sites",
            ],
            shortTitle: "Open sites",
            systemImageName: "chart.xyaxis.line"
        )
    }
}
#endif
