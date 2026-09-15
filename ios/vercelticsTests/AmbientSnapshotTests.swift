import XCTest
@testable import verceltics

final class AmbientSnapshotTests: XCTestCase {

    private let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(
        _ name: String,
        _ state: DeploymentState,
        minutesAgo: Int,
        statusText: String? = nil
    ) -> AmbientDeploymentSnapshot {
        AmbientDeploymentSnapshot(
            projectName: name,
            provider: .vercel,
            state: state,
            statusText: statusText ?? state.displayName.uppercased(),
            updatedAt: capturedAt.addingTimeInterval(Double(-minutesAgo) * 60)
        )
    }

    // MARK: - Shaping

    func testEntriesAreOrderedNewestFirst() {
        let snapshot = AmbientSnapshot(capturedAt: capturedAt, deployments: [
            entry("old", .ready, minutesAgo: 90),
            entry("newest", .ready, minutesAgo: 1),
            entry("middle", .ready, minutesAgo: 30),
        ])
        XCTAssertEqual(snapshot.deployments.map(\.projectName), ["newest", "middle", "old"])
    }

    func testPayloadIsBounded() {
        let many = (0..<40).map { entry("p\($0)", .ready, minutesAgo: $0) }
        let snapshot = AmbientSnapshot(capturedAt: capturedAt, deployments: many)
        XCTAssertEqual(snapshot.deployments.count, AmbientSnapshot.maxEntries)
        // Truncation must keep the newest, not an arbitrary slice.
        XCTAssertEqual(snapshot.deployments.first?.projectName, "p0")
    }

    func testVersionIsStamped() {
        let snapshot = AmbientSnapshot(capturedAt: capturedAt, deployments: [])
        XCTAssertEqual(snapshot.version, AmbientSnapshot.currentVersion)
    }

    // MARK: - Headline selection

    func testHeadlinePrefersAnInFlightDeployOverANewerFinishedOne() {
        // A running build is the most time-sensitive thing a single-slot widget can show, even when
        // another project finished more recently.
        let snapshot = AmbientSnapshot(capturedAt: capturedAt, deployments: [
            entry("just-shipped", .ready, minutesAgo: 1),
            entry("still-building", .building, minutesAgo: 20),
        ])
        XCTAssertEqual(snapshot.headline?.projectName, "still-building")
    }

    func testHeadlineFallsBackToTheNewestWhenNothingIsRunning() {
        let snapshot = AmbientSnapshot(capturedAt: capturedAt, deployments: [
            entry("older", .ready, minutesAgo: 40),
            entry("newer", .failed, minutesAgo: 2),
        ])
        XCTAssertEqual(snapshot.headline?.projectName, "newer")
    }

    func testHeadlineIsNilWhenEmpty() {
        XCTAssertNil(AmbientSnapshot(capturedAt: capturedAt, deployments: []).headline)
    }

    // MARK: - Staleness

    func testStaleness() {
        let snapshot = AmbientSnapshot(capturedAt: capturedAt, deployments: [])
        XCTAssertFalse(snapshot.isStale(now: capturedAt, maxAge: 3_600))
        XCTAssertFalse(snapshot.isStale(now: capturedAt.addingTimeInterval(3_599), maxAge: 3_600))
        XCTAssertTrue(snapshot.isStale(now: capturedAt.addingTimeInterval(3_601), maxAge: 3_600))
    }

    // MARK: - Codec

    func testRoundTripPreservesEverything() throws {
        let original = AmbientSnapshot(capturedAt: capturedAt, deployments: [
            AmbientDeploymentSnapshot(
                projectName: "verceltics",
                provider: .awsAmplify,
                state: .building,
                statusText: "RUNNING",
                updatedAt: capturedAt,
                targetURL: "https://verceltics.com",
                commitSubject: "fix: refine launcher icon spacing"
            ),
        ])

        let decoded = try AmbientSnapshotCodec.decode(AmbientSnapshotCodec.encode(original))
        XCTAssertEqual(decoded, original)
        // The provider's own wording survives alongside the normalized state.
        XCTAssertEqual(decoded.deployments.first?.statusText, "RUNNING")
        XCTAssertEqual(decoded.deployments.first?.state, .building)
    }

    func testPayloadCarriesNoCredentialFields() throws {
        let data = try AmbientSnapshotCodec.encode(
            AmbientSnapshot(capturedAt: capturedAt, deployments: [entry("verceltics", .ready, minutesAgo: 1)])
        )
        let json = String(decoding: data, as: UTF8.self).lowercased()
        for forbidden in ["token", "authorization", "apikey", "api_key", "secret", "password", "credential"] {
            XCTAssertFalse(json.contains(forbidden), "snapshot must not carry \(forbidden)")
        }
    }

    func testAFuturePayloadVersionIsRejected() throws {
        let json = """
        {"version":99,"capturedAt":"2023-11-14T22:13:20Z","deployments":[]}
        """
        XCTAssertThrowsError(try AmbientSnapshotCodec.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? AmbientSnapshotCodec.Failure, .unsupportedVersion(99))
        }
    }

    func testLegacyPayloadsWithoutIdOrDomainsStillDecode() throws {
        let json = """
        {"version":1,"capturedAt":"2023-11-14T22:13:20Z","deployments":[
          {"projectName":"verceltics","provider":"vercel","state":"ready",
           "statusText":"READY","updatedAt":"2023-11-14T22:13:20Z"}
        ]}
        """
        let snapshot = try AmbientSnapshotCodec.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.deployments.first?.id, "vercel:verceltics")
        XCTAssertTrue(snapshot.domains.isEmpty)
    }

    func testDomainsAreKeptSoonestFirstAndBounded() {
        let later = capturedAt.addingTimeInterval(86_400 * 40)
        let sooner = capturedAt.addingTimeInterval(86_400 * 3)
        let snapshot = AmbientSnapshot(
            capturedAt: capturedAt,
            deployments: [],
            domains: (0..<20).map {
                AmbientDomainSnapshot(
                    name: "d\($0).com",
                    expiresAt: $0 == 0 ? later : sooner.addingTimeInterval(Double($0))
                )
            }
        )
        XCTAssertEqual(snapshot.domains.count, AmbientSnapshot.maxEntries)
        XCTAssertEqual(snapshot.domains.first?.name, "d1.com")
        XCTAssertFalse(snapshot.domains.contains(where: { $0.name == "d0.com" }))
    }

    func testSnapshotStorePrefersTheAppGroupOverApplicationSupport() {
        let appGroup = URL(fileURLWithPath: "/tmp/app-group")
        let support = URL(fileURLWithPath: "/tmp/application-support")
        XCTAssertEqual(
            AmbientSnapshotStore.resolveDirectory(appGroup: appGroup, applicationSupport: support),
            appGroup.appendingPathComponent("Ambient", isDirectory: true)
        )
    }

    func testSnapshotStoreFallsBackToApplicationSupport() {
        let support = URL(fileURLWithPath: "/tmp/application-support")
        XCTAssertEqual(
            AmbientSnapshotStore.resolveDirectory(appGroup: nil, applicationSupport: support),
            support
                .appendingPathComponent("Verceltics", isDirectory: true)
                .appendingPathComponent("Ambient", isDirectory: true)
        )
        XCTAssertNil(AmbientSnapshotStore.resolveDirectory(appGroup: nil, applicationSupport: nil))
    }

    func testAnUnrecognizedStateDecodesAsUnknownRatherThanFailing() throws {
        // Forward compatibility: a snapshot from a newer build must not break the whole payload.
        let json = """
        {"version":1,"capturedAt":"2023-11-14T22:13:20Z","deployments":[
          {"projectName":"verceltics","provider":"vercel","state":"teleporting",
           "statusText":"TELEPORTING","updatedAt":"2023-11-14T22:13:20Z"}
        ]}
        """
        let snapshot = try AmbientSnapshotCodec.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.deployments.first?.state, .unknown)
        XCTAssertEqual(snapshot.deployments.first?.statusText, "TELEPORTING")
    }
}
