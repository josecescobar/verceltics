import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island presentations for an in-flight deployment.
///
/// The Dynamic Island is small enough that only one thing can be legible at a time, so the
/// hierarchy is: what is happening, then how long it has been happening, then which project.
struct DeployLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeployActivityAttributes.self) { context in
            lockScreen(context: context)
                .activityBackgroundTint(AppTheme.canvas)
                .activitySystemActionForegroundColor(AppTheme.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.projectName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    } icon: {
                        statusIcon(context.state.state)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsed(context.state)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.textSecondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        progressBar(context.state.state)
                        HStack(spacing: 6) {
                            Text(context.state.statusText.capitalized)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(tone(context.state.state))
                            if let target = context.attributes.target, !target.isEmpty {
                                Text("·").foregroundStyle(AppTheme.textTertiary)
                                Text(target.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .lineLimit(1)
                    }
                }
            } compactLeading: {
                statusIcon(context.state.state)
            } compactTrailing: {
                // Minutes only. Seconds in the compact slot are unreadable and cause the pill to
                // resize constantly as digits change width.
                elapsed(context.state, includeSeconds: false)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(tone(context.state.state))
            } minimal: {
                statusIcon(context.state.state)
            }
            .widgetURL(context.attributes.inspectorURL)
            .keylineTint(tone(context.state.state))
        }
    }

    // MARK: - Lock Screen

    private func lockScreen(context: ActivityViewContext<DeployActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                statusIcon(context.state.state)
                Text(context.attributes.projectName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                elapsed(context.state)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }

            progressBar(context.state.state)

            HStack(spacing: 6) {
                Text(context.state.statusText.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone(context.state.state))
                Text("·").foregroundStyle(AppTheme.textTertiary)
                Text(context.attributes.provider.displayName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                if let target = context.attributes.target, !target.isEmpty {
                    Text("·").foregroundStyle(AppTheme.textTertiary)
                    Text(target.capitalized)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)

            if let subject = context.attributes.commitSubject, !subject.isEmpty {
                Text(subject)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
    }

    // MARK: - Pieces

    /// An indeterminate deploy has no percentage to report, so the bar conveys phase rather than
    /// fake precision: it fills as the deploy advances through queued, building, and deploying.
    private func progressBar(_ state: DeploymentState) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.skeleton)
                Capsule()
                    .fill(tone(state))
                    .frame(width: geometry.size.width * phaseFraction(state))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private func phaseFraction(_ state: DeploymentState) -> CGFloat {
        switch state {
        case .queued: 0.15
        case .initializing: 0.35
        case .building: 0.6
        case .deploying: 0.85
        case .ready, .failed, .canceled, .superseded: 1
        case .unknown: 0.5
        }
    }

    private func statusIcon(_ state: DeploymentState) -> some View {
        Image(systemName: symbol(state))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(tone(state))
            .accessibilityLabel(state.displayName)
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

    /// A live timer the system advances itself, so a long build does not need an update per second.
    private func elapsed(
        _ state: DeployActivityAttributes.ContentState,
        includeSeconds: Bool = true
    ) -> some View {
        Text(
            timerInterval: state.elapsedRange,
            pauseTime: state.finishedAt,
            countsDown: false,
            showsHours: includeSeconds
        )
    }
}
