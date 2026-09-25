import XCTest
@testable import verceltics

final class AmbientRouteTests: XCTestCase {

    func testWorkspaceURLsRoundTrip() {
        for workspace in PrimaryWorkspace.allCases {
            let route = AmbientRoute.workspace(workspace)
            XCTAssertEqual(AmbientRoute.parse(route.url), route, workspace.rawValue)
            XCTAssertEqual(route.workspace, workspace)
        }
    }

    func testLatestDeployOpensHosting() {
        let route = AmbientRoute.latestDeploy
        XCTAssertEqual(AmbientRoute.parse(route.url), .latestDeploy)
        XCTAssertEqual(route.workspace, .hosting)
    }

    func testForeignSchemesAreIgnored() {
        XCTAssertNil(AmbientRoute.parse(URL(string: "https://verceltics.com/hosting")!))
        XCTAssertNil(AmbientRoute.parse(URL(string: "verceltics://unknown/path")!))
        XCTAssertNil(AmbientRoute.parse(URL(string: "verceltics://deploy/not-a-thing")!))
    }

    func testBareDeployHostStillOpensHosting() {
        XCTAssertEqual(AmbientRoute.parse(URL(string: "verceltics://deploy")!), .latestDeploy)
    }

    func testPendingWorkspaceIsStoredAndConsumedOnce() {
        let defaults = UserDefaults(suiteName: "AmbientRouteTests.\(UUID().uuidString)")!
        AmbientRoute.store(.workspace(.sites), defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: lastPrimaryWorkspaceKey), "sites")
        XCTAssertEqual(AmbientRoute.consumePendingWorkspace(defaults: defaults), .sites)
        XCTAssertNil(AmbientRoute.consumePendingWorkspace(defaults: defaults))
    }

    func testLatestDeployCopyUsesTheHeadline() {
        let snapshot = AmbientSnapshot(
            capturedAt: .now,
            deployments: [
                AmbientDeploymentSnapshot(
                    projectName: "verceltics",
                    provider: .vercel,
                    state: .building,
                    statusText: "BUILDING",
                    updatedAt: .now
                )
            ]
        )
        XCTAssertEqual(
            LatestDeployStatusCopy.dialog(from: snapshot),
            "verceltics on Vercel is building."
        )
    }

    func testLatestDeployCopySaysSoWhenNothingIsCached() {
        XCTAssertEqual(
            LatestDeployStatusCopy.dialog(from: nil),
            "Verceltics has no recent deployments. Open the app to refresh."
        )
    }

    func testStaleCopyAsksTheUserToRefresh() {
        let snapshot = AmbientSnapshot(
            capturedAt: Date(timeIntervalSinceNow: -8_000),
            deployments: [
                AmbientDeploymentSnapshot(
                    projectName: "verceltics",
                    provider: .netlify,
                    state: .ready,
                    statusText: "ready",
                    updatedAt: Date(timeIntervalSinceNow: -8_000)
                )
            ]
        )
        XCTAssertTrue(
            LatestDeployStatusCopy.dialog(from: snapshot).contains("when last checked")
        )
    }
}
