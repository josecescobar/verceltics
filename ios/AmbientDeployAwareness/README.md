# Ambient deploy awareness — widget extension

The app target now owns the state machine, foreground poller, snapshot store, local alerts,
background refresh registration, and the ActivityKit request side.

**What is still staged here is only the widget UI.** These files have a `@main` `WidgetBundle`
and would collide with the app's entry point if they were added to `ios/verceltics/`. They also
need a Widget Extension target, which should be created in Xcode rather than hand-written into
`project.pbxproj`.

## Create the extension

1. In Xcode: **File → New → Target → Widget Extension**, named `VercelticsWidgets`. Check
   *Include Live Activity*.
2. Replace the generated stub with:
   - `Widgets/VercelticsWidgetBundle.swift`
   - `Widgets/DeployLiveActivity.swift`
   - `Widgets/DeployStatusWidget.swift`
3. Add these existing app files to the **extension** target as well (do not copy them):
   - `ios/verceltics/Models/DeploymentState.swift`
   - `ios/verceltics/Models/AmbientSnapshot.swift`
   - `ios/verceltics/Ambient/AmbientSnapshotStore.swift`
   - `ios/verceltics/Ambient/DeployActivityAttributes.swift`
4. Add an **App Group** `group.com.apoorvdarshan.verceltics` to both targets. Until that exists,
   the app writes the snapshot to Application Support, which only the app can read.
5. The extension needs `AppTheme` tokens. Either add `ProviderVisuals.swift` or lift the few
   colors `DeployLiveActivity` uses.

`DeployActivityAttributes.swift` in this folder is the earlier draft. Prefer the copy in
`ios/verceltics/Ambient/` so the app and the extension share one type.

## Already wired in the app

- `NSSupportsLiveActivities`, `UIBackgroundModes=fetch`, and
  `BGTaskSchedulerPermittedIdentifiers` are in `verceltics-Info.plist`.
- `AmbientBackgroundRefresh.register()` runs at launch.
- Opening a Vercel project, a hosting resource, or a deployment detail starts a foreground
  poller for anything in flight.
- Failed deploys and domain expiry raise local notifications via `AmbientAlertRules`.

Live Activities will not render until the extension exists. The request is made anyway; iOS
refuses it quietly if there is no presentation.
