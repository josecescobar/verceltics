import SwiftUI
import WidgetKit

/// Home and Lock Screen widget showing the most relevant deployment.
///
/// It renders only the snapshot the app last wrote. It never calls a provider, because credentials
/// use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and are unreadable from an extension on a
/// locked device — and loosening that to make a widget slightly fresher is not a trade worth making.
struct DeployStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DeployStatusWidget", provider: DeployStatusProvider()) { entry in
            DeployStatusView(entry: entry)
                .containerBackground(AppTheme.canvas, for: .widget)
        }
        .configurationDisplayName("Deploy status")
        .description("The latest deployment across your connected providers.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct DeployStatusEntry: TimelineEntry {
    let date: Date
    let deployment: AmbientDeploymentSnapshot?
    let isStale: Bool
}

struct DeployStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeployStatusEntry {
        DeployStatusEntry(
            date: .now,
            deployment: AmbientDeploymentSnapshot(
                projectName: "verceltics",
                provider: .vercel,
                state: .building,
                statusText: "BUILDING",
                updatedAt: .now
            ),
            isStale: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DeployStatusEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeployStatusEntry>) -> Void) {
        let entry = currentEntry()
        // An in-flight deploy changes on the order of a minute; a finished one does not, so asking
        // for a refresh sooner would only spend the extension's budget.
        let nextRefresh = entry.deployment?.state.isInFlight == true
            ? Date.now.addingTimeInterval(60)
            : Date.now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func currentEntry() -> DeployStatusEntry {
        guard let snapshot = AmbientSnapshotStore.read() else {
            return DeployStatusEntry(date: .now, deployment: nil, isStale: false)
        }
        return DeployStatusEntry(
            date: .now,
            deployment: snapshot.headline,
            isStale: snapshot.isStale()
        )
    }
}

struct DeployStatusView: View {
    let entry: DeployStatusEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let deployment = entry.deployment {
            content(deployment)
        } else {
            // An empty widget should say what to do, not just look broken.
            VStack(alignment: .leading, spacing: 4) {
                Text("No deployments yet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Open Verceltics to connect a provider.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private func content(_ deployment: AmbientDeploymentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol(deployment.state))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tone(deployment.state))
                Text(deployment.statusText.capitalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tone(deployment.state))
                    .lineLimit(1)
            }

            Text(deployment.projectName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)

            if family != .accessoryRectangular {
                Text(deployment.provider.displayName)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 0)

            // Say when this was true rather than implying it is live right now.
            Text(entry.isStale ? "Updated \(relative(deployment.updatedAt)) · open to refresh"
                              : "Updated \(relative(deployment.updatedAt))")
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(deployment.projectName) on \(deployment.provider.displayName), \(deployment.state.displayName)"
        )
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func symbol(_ state: DeploymentState) -> String {
        switch state {
        case .queued: "clock"
        case .initializing: "circle.dotted"
        case .building: "hammer"
        case .deploying: "arrow.up.circle"
        case .ready: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .canceled: "slash.circle"
        case .superseded: "arrow.triangle.2.circlepath"
        case .unknown: "questionmark.circle"
        }
    }

    private func tone(_ state: DeploymentState) -> Color {
        switch state {
        case .queued, .initializing: AppTheme.warning
        case .building, .deploying: AppTheme.signal
        case .ready: AppTheme.success
        case .failed: AppTheme.danger
        case .canceled, .superseded, .unknown: AppTheme.textSecondary
        }
    }
}
