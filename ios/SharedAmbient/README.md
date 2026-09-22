# SharedAmbient

Foundation and theme types compiled into both the `verceltics` app and the
`VercelticsWidgets` extension. Keep this folder free of Keychain access,
RevenueCat, and `ProviderVisuals` so the widget stays credential-free and
extension-safe.

The snapshot is written to the App Group when that container is provisioned,
and otherwise to Application Support. Do not add an entitlements file here
until the group exists in the developer portal.
