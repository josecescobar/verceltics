import Foundation

/// Shared on-disk store for the snapshot a widget reads.
///
/// `AppMemoryCache` is process-local, so an extension cannot see it. This follows the same pattern
/// `KeychainHelper` already uses for the Sites cache — atomic write, file protection, excluded from
/// backup — relocated into the App Group container so both processes can reach it.
///
/// Add this file to the app target and the widget extension target.
nonisolated enum AmbientSnapshotStore {
    /// Must match the App Group added to both targets in the Apple Developer portal.
    static let appGroupIdentifier = "group.com.apoorvdarshan.verceltics"

    private static let fileName = "ambient-snapshot.json"

    nonisolated enum Failure: Error {
        case appGroupUnavailable
    }

    // MARK: - Writing

    /// Called by the app after a dashboard refresh. Failures are surfaced so the caller can decide;
    /// a missing App Group is a configuration mistake, not a runtime condition to swallow.
    static func write(_ snapshot: AmbientSnapshot) throws {
        let data = try AmbientSnapshotCodec.encode(snapshot)
        let url = try fileURL()

        try data.write(to: url, options: .atomic)

        // A widget may be asked to render before first unlock, so the snapshot has to be readable
        // then. It holds no credentials, which is what makes this acceptable.
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }

    // MARK: - Reading

    /// Called by the extension. Returns `nil` rather than throwing, because a widget has nothing
    /// useful to do with an error other than render its empty state.
    static func read() -> AmbientSnapshot? {
        guard
            let url = try? fileURL(),
            FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? AmbientSnapshotCodec.decode(data)
    }

    static func clear() {
        guard let url = try? fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Location

    private static func fileURL() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw Failure.appGroupUnavailable
        }
        let directory = container.appendingPathComponent("Ambient", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }
}
