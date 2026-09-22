# Ambient deploy awareness — widget extension

The Widget Extension target is now in the Xcode project:

- `ios/VercelticsWidgets/` — `WidgetBundle`, Live Activity, and Home Screen widget
- `ios/SharedAmbient/` — types compiled into both the app and the extension

## Remaining device setup

1. In the developer portal, create the App Group `group.com.apoorvdarshan.verceltics`.
2. Add that group to both `verceltics` and `VercelticsWidgets`. Until it exists, the app
   writes the snapshot to Application Support, which only the app can read.
3. Confirm Live Activities and the Deploy status widget on a device. Unsigned CI builds
   skip entitlement validation (`CODE_SIGNING_ALLOWED=NO`).

Do not copy widget sources back into `ios/verceltics/`. The extension has its own `@main`.
The draft files that used to live in `Widgets/` were replaced by the real target.

## Already wired

- `NSSupportsLiveActivities`, `UIBackgroundModes=fetch`, and
  `BGTaskSchedulerPermittedIdentifiers` are in `verceltics-Info.plist`.
- `AmbientBackgroundRefresh.register()` runs at launch.
- Opening a Vercel project, a hosting resource, or a deployment detail starts a foreground
  poller for anything in flight.
- Failed deploys and domain expiry raise local notifications via `AmbientAlertRules`.
- Tapping the widget opens `verceltics://deploy/latest`.

Live Activities update while the app is running plus whatever `BGAppRefreshTask` windows iOS
grants. Realtime updates while closed would need a push server, which this app does not have.
