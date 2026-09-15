# Ambient deploy awareness — staged integration

**Nothing in this folder is compiled.** It sits beside `ios/verceltics/` rather than inside it, so
it is outside the project's `PBXFileSystemSynchronizedRootGroup` and no target picks it up. Moving a
file into `ios/verceltics/` is what adds it to the app target.

## Why it is staged instead of wired up

The verified part of this feature — the provider-aware deploy state machine, the tracking reducer,
the alert rules, and the shared snapshot format — is already in `ios/verceltics/Models/` and covered
by tests. It is all Foundation-only, on purpose, so it could be executed and proven correct.

The code in this folder touches ActivityKit, WidgetKit, BackgroundTasks, and UserNotifications, and
**it has never been compiled.** The environment it was written in has no Apple SDK and no Xcode, and
the repository's `ios-tests` job cannot run because this repo is a fork with GitHub Actions
disabled, so nothing verified it.

Adding uncompiled framework code to the app target would risk two failures that are much worse than
a missing feature:

- A single API mistake fails the build, and the app stops building for everyone.
- `BGTaskScheduler.register(forTaskWithIdentifier:)` **throws at launch** when the identifier is
  absent from `Info.plist`. Wired up blind, that is a launch crash, not a degraded feature.

So this is deliberately staged: review it in Xcode, where the compiler can check it, and move it in.

### Unblocking real verification

Enabling GitHub Actions on this fork (Settings → Actions → General → *Allow all actions and
reusable workflows*) makes `.github/workflows/ci.yml` run, which builds and tests the iOS app on a
`macos-26` runner. That turns everything below into something CI can verify on a pull request.

## Integration order

Each step builds and runs on its own, so stop anywhere.

### 1. Live Activity for in-flight deploys

1. In Xcode: **File → New → Target → Widget Extension**, named `VercelticsWidgets`. Check *Include
   Live Activity*. Xcode creates the target, the embed-extensions build phase, and the
   `NSSupportsLiveActivities` key correctly — which is exactly the part that is risky to hand-write
   into `project.pbxproj`.
2. Move `Widgets/DeployActivityAttributes.swift` into the new extension folder and add it to **both**
   the app target and the extension target. The app creates activities; the extension renders them.
3. Move `Widgets/DeployLiveActivity.swift` and `Widgets/VercelticsWidgetBundle.swift` into the
   extension target, replacing the stub Xcode generated.
4. Move `App/DeployActivityController.swift` into `ios/verceltics/Ambient/`.
5. Add `NSSupportsLiveActivities` to the **app** target. The project sets
   `GENERATE_INFOPLIST_FILE = YES`, so either add
   `INFOPLIST_KEY_NSSupportsLiveActivities = YES` to build settings, or add the key to
   `ios/verceltics-Info.plist`.
6. The extension needs `AppTheme` and `DeploymentState` for tone and labels. `DeploymentState.swift`
   is Foundation-only and can be added to the extension target as-is. `ProviderVisuals.swift` pulls
   in far more, so either add the whole file or lift the small token set the widget needs.

### 2. Widgets and shared snapshot

1. Add an **App Group** — `group.com.apoorvdarshan.verceltics` — to both targets. This needs the
   Apple Developer portal; CI runs with `CODE_SIGNING_ALLOWED=NO` and will not surface provisioning
   problems.
2. Move `App/AmbientSnapshotStore.swift` into `ios/verceltics/Ambient/` and add it to both targets.
   Set `appGroupIdentifier` to match.
3. Have the dashboard call `AmbientSnapshotStore.write(_:)` after a refresh, and
   `WidgetCenter.shared.reloadAllTimelines()` after writing.
4. Move `Widgets/DeployStatusWidget.swift` into the extension target.

Credentials stay put. `KeychainHelper` uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and no
`kSecAttrAccessGroup`, so an extension cannot read them while the device is locked. **Keep it that
way.** The widget renders the last snapshot the app wrote, which preserves the documented privacy
posture. Relaxing that attribute to let a widget call providers directly would weaken a stated
guarantee for a cosmetic gain.

### 3. Background alerts

1. Add the **Background Modes** capability to the app target with *Background fetch*.
2. Add `BGTaskSchedulerPermittedIdentifiers` containing `com.apoorvdarshan.verceltics.refresh` to
   the app's `Info.plist`. **Do this before** wiring up registration — see the launch-crash note
   above.
3. Move `App/AmbientAlertScheduler.swift` and `App/AmbientBackgroundRefresh.swift` into
   `ios/verceltics/Ambient/`.
4. Register the task at launch and request notification authorization the first time a user opts in,
   not at startup.

## The honest constraint on Live Activity updates

Updating a Live Activity while the app is closed normally uses ActivityKit push tokens over APNs,
which requires a server. Verceltics documents that it runs no credential proxy and no provider-data
server, and that guarantee is worth more than realtime updates.

So updates advance while the app is in the foreground, plus whatever `BGAppRefreshTask` windows iOS
chooses to grant. A deploy that finishes while the app is closed is reflected the next time the
system wakes the app, not the instant it happens. That is a deliberate privacy tradeoff, and
`DeploymentPollPolicy` widens its interval as a deploy runs long for the same reason.
