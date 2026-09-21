import XCTest
@testable import verceltics

final class AmbientSpotlightTests: XCTestCase {

    func testProjectRecordsCarryTheNameAndDomain() throws {
        let project = try JSONDecoder().decode(Project.self, from: Data("""
        {"id":"prj_1","name":"verceltics","accountId":"team_1","framework":"nextjs"}
        """.utf8))

        let record = try XCTUnwrap(SpotlightRecordBuilder.projects([project]).first)
        XCTAssertEqual(record.kind, .project)
        XCTAssertEqual(record.title, "verceltics")
        XCTAssertEqual(record.uniqueIdentifier, "project:prj_1")
        XCTAssertEqual(record.workspace, .hosting)
        XCTAssertTrue(record.keywords.contains("nextjs"))
    }

    func testDomainRecordsOpenRegistrars() {
        let domain = RegistrarDomain(
            name: "Verceltics.com",
            status: "active",
            createdAt: nil,
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            autoRenew: true,
            locked: true,
            privacyEnabled: true,
            nameservers: [],
            metadata: [:]
        )
        let record = SpotlightRecordBuilder.domains([domain])[0]
        XCTAssertEqual(record.uniqueIdentifier, "domain:verceltics.com")
        XCTAssertEqual(record.workspace, .registrars)
        XCTAssertEqual(
            SpotlightRecordBuilder.route(forUniqueIdentifier: record.uniqueIdentifier),
            .workspace(.registrars)
        )
    }

    func testSnapshotRecordsCoverDeploysAndDomains() {
        let snapshot = AmbientSnapshot(
            capturedAt: .now,
            deployments: [
                AmbientDeploymentSnapshot(
                    id: "dpl_1",
                    projectName: "verceltics",
                    provider: .awsAmplify,
                    state: .building,
                    statusText: "RUNNING",
                    updatedAt: .now
                )
            ],
            domains: [
                AmbientDomainSnapshot(name: "verceltics.com", expiresAt: .now)
            ]
        )
        let records = SpotlightRecordBuilder.snapshot(snapshot)
        XCTAssertEqual(records.map(\.kind), [.deployment, .domain])
        XCTAssertEqual(
            SpotlightRecordBuilder.route(forUniqueIdentifier: records[0].uniqueIdentifier),
            .latestDeploy
        )
        XCTAssertEqual(
            SpotlightRecordBuilder.route(forUniqueIdentifier: records[1].uniqueIdentifier),
            .workspace(.registrars)
        )
    }

    func testUnknownIdentifiersFallBackToHosting() {
        XCTAssertEqual(
            SpotlightRecordBuilder.route(forUniqueIdentifier: "mystery:1"),
            .workspace(.hosting)
        )
    }
}
