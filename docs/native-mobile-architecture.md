# Native mobile architecture

Verceltics has two independent native mobile applications:

- `ios/` is SwiftUI-only. Its existing provider clients, state, Keychain records, local snapshots, navigation, and Liquid Glass integrations remain native iOS code.
- `android/` is Kotlin and Jetpack Compose-only. Android-native lifecycle, input, haptics, accessibility, storage, and Material behavior live in this project.

There is no Flutter or Dart runtime, generated Flutter bridge, or shared cross-platform UI module in either application. Provider identifiers and API behavior are ported deliberately, but platform UI, lifecycle, and secure storage are not shared binaries.

## Data and backend boundaries

- Restoring the SwiftUI application does not migrate, rewrite, or delete existing iOS Keychain records, preferences, or protected snapshots.
- Android has a separate application sandbox. Credentials are encrypted with keys held by Android Keystore and stored only in app-private, backup-excluded storage; ordinary preferences must never contain credentials.
- Credentials and provider data are not copied between iOS and Android. Installing or updating one platform cannot alter the other platform's data.
- The existing iOS provider clients and request policies remain unchanged during the Android migration.
- Provider requests continue to go directly from the device to the selected provider's HTTPS API. The Android port must preserve the same host validation, redirect, timeout, response-size, cancellation, and destructive-action safeguards before a provider is marked complete.

## Screen-by-screen migration rule

Each Android provider moves through the same gates:

1. Preserve the canonical provider identifier and authentication contract.
2. Build the native Compose connection, loading, empty, error, search, refresh, and detail states.
3. Add Android Keystore-backed account persistence and the provider HTTPS client.
4. Cover domain and request behavior with unit tests.
5. Exercise the user-visible flow on a dedicated Android emulator and inspect screenshots, the accessibility tree, and runtime logs.

A catalog entry is not considered provider parity. A provider is complete only after all relevant gates pass.

## Screen-by-screen status

| Platform / slice | Status | Scope |
|---|---|---|
| iOS SwiftUI | Preserved | Existing UI, Liquid Glass integration, local data, and all 27 provider integrations remain native and operational. |
| Android app shell and catalog | Implemented | Native Compose navigation and discoverability for 10 hosting providers, 8 registrars, and 9 site services. |
| Android Vercel | Implemented | Token connection and validation, protected account persistence, projects, analytics, loading/error/empty states, search, refresh, and details. |
| Android PageSpeed & CrUX | Implemented | Protected API-key connection, Lighthouse and field-data audits, cached restore, history, loading/error/empty states, refresh, and details. |
| Android Netlify | Implemented read-only flow | Protected token connection, cached restore, sites, domains, build controls, published deployments, deploy history, build history, cancellation reconciliation, refresh, and details. Mutations remain intentionally excluded. |
| Android Cloudflare | Implemented read-only flow | Protected scoped-token connection, cached restore, themed account switching, searchable zones/Pages/Workers inventory, refresh, cancellation reconciliation, and read-only resource details. DNS, analytics, storage, security, advanced API tooling, and mutations remain pending. |
| Android Google Search Console | Implemented read-only flow | Native PKCE Google OAuth, encrypted credential restore/refresh, cached searchable properties, performance query controls and pagination, sitemaps, URL inspection, adaptive Compose states, cancellation reconciliation, and tests. A source build must supply its own Google Android OAuth client configuration. |
| Android remaining providers | Catalogued, not yet parity-complete | Provider API clients and detail workflows will be migrated and tested one screen at a time. |

The matrix describes source parity, not store availability. It should be updated whenever a provider passes or falls back from the completion gates above.

## Ambient deploy awareness (iOS)

Deployment status is normalized per provider rather than globally. Provider vocabularies collide —
`RUNNING` is a build in progress on AWS Amplify but a healthy machine on Fly, and `active` is a
finished deployment on DigitalOcean but an in-progress one on Cloudflare Pages — so a single
substring matcher cannot classify all of them.

- `DeploymentState` maps each provider's own vocabulary to one lifecycle and exposes `isInFlight`
  and `isTerminal`. Unrecognized values fall back to the legacy classifier, so an unmapped provider
  string keeps its previous appearance.
- `AppStatusTone.deployment(_:provider:)` is used for deployment statuses. Resource health rows stay
  on `AppStatusTone.status(_:)`, where `Running` legitimately means healthy.
- `DeploymentTracker` decides when an ambient surface should present, update, or dismiss.
  `AmbientAlertRules` decides what is worth a notification. `AmbientSnapshot` is the credential-free
  payload an extension reads, since a widget cannot reach the app's in-memory caches.

These are Foundation-only and unit tested. The app now also runs a foreground poller, writes the
shared snapshot, schedules local alerts, and registers `BGAppRefreshTask`. Live Activity
*requests* are made from the app. The Lock Screen, Dynamic Island, and Home Screen widget UI live
in the `VercelticsWidgets` extension. Shared types (`AccountProvider`, `DeploymentState`,
`AmbientSnapshot`, the snapshot store, `DeployActivityAttributes`, and `AppTheme`) compile from
`ios/SharedAmbient` into both targets.

`AppTheme` lives in SharedAmbient so the widget can share colors without compiling
`ProviderVisuals.swift`. Siri and Shortcuts can ask for the latest cached deploy or open a
workspace. Spotlight indexes projects, Cloudflare zones, registrar domains, and the ambient
snapshot after those screens load.

The App Group `group.com.apoorvdarshan.verceltics` is the preferred snapshot container. Until that
group is provisioned in the developer portal, the store falls back to Application Support, which
only the app can read. Do not add entitlements files until the group exists.

Live Activities update while the app is running plus whatever `BGAppRefreshTask` windows iOS grants.
Realtime updates while closed would need ActivityKit push tokens over APNs, and therefore a server,
which contradicts the data boundary above. That is a deliberate tradeoff.

## Continuous integration

CI keeps the native projects independent:

- iOS tests run with `xcodebuild` against an iOS simulator.
- Android runs JVM tests, Android Lint, and a debug assembly through the Gradle wrapper.
- No Flutter bootstrap, analysis, test, or framework-generation step is required.

GitHub Actions must be enabled for these to run. On a fork it is disabled by default, which leaves
`ios-tests` unable to verify iOS changes at all.
