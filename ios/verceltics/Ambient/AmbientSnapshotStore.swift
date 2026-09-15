import Foundation

/// On-disk store for the snapshot a widget — or a later launch — reads.
///
/// Prefers the App Group container so an extension can see it, and falls back to Application
/// Support when the group is not provisioned yet. Either way the file is protected and excluded
/// from backup, matching the Sites cache in `KeychainHelper`.
nonisolated enum AmbientSnapshotStore {
    static let appGroupIdentifier = "group.com.apoorvdarshan.verceltics"

    private static let fileName = "ambient-snapshot.json"

    nonisolated enum Failure: Error {
        case directoryUnavailable
    }

    /// Chooses a directory. Extracted so the fallback order can be tested without touching disk
    /// containers that do not exist on Linux.
    static func resolveDirectory(appGroup: URL?, applicationSupport: URL?) -> URL? {
        if let appGroup {
            return appGroup.appendingPathComponent("Ambient", isDirectory: true)
        }
        if let applicationSupport {
            return applicationSupport
                .appendingPathComponent("Verceltics", isDirectory: true)
                .appendingPathComponent("Ambient", isDirectory: true)
        }
        return nil
    }

    static func write(_ snapshot: AmbientSnapshot) throws {
        let data = try AmbientSnapshotCodec.encode(snapshot)
        let url = try fileURL()

        try data.write(to: url, options: .atomic)

#if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
#endif

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }

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

    private static func fileURL() throws -> URL {
        let appGroup: URL?
#if os(iOS)
        appGroup = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
#else
        appGroup = nil
#endif
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        guard let directory = resolveDirectory(
            appGroup: appGroup,
            applicationSupport: applicationSupport
        ) else {
            throw Failure.directoryUnavailable
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }
}
