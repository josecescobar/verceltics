import XCTest
@testable import verceltics

final class DeploymentTrackingTests: XCTestCase {

    // MARK: - Presenting and dismissing

    func testAnInFlightDeploymentStartsThenEnds() {
        var tracker = DeploymentTracker()
        XCTAssertFalse(tracker.isTracking)

        XCTAssertEqual(tracker.ingest(.building), .start(.building))
        XCTAssertTrue(tracker.isTracking)

        XCTAssertEqual(tracker.ingest(.ready), .end(.ready))
        XCTAssertFalse(tracker.isTracking)
        XCTAssertEqual(tracker.state, .ready)
    }

    func testEveryPhaseChangeProducesASingleUpdate() {
        var tracker = DeploymentTracker()
        XCTAssertEqual(tracker.ingest(.queued), .start(.queued))
        XCTAssertEqual(tracker.ingest(.initializing), .update(.initializing))
        XCTAssertEqual(tracker.ingest(.building), .update(.building))
        XCTAssertEqual(tracker.ingest(.deploying), .update(.deploying))
        XCTAssertEqual(tracker.ingest(.ready), .end(.ready))
    }

    func testPollingTheSameStateRepeatedlyIsIgnored() {
        var tracker = DeploymentTracker()
        XCTAssertEqual(tracker.ingest(.building), .start(.building))
        XCTAssertEqual(tracker.ingest(.building), .ignored)
        XCTAssertEqual(tracker.ingest(.building), .ignored)
        XCTAssertTrue(tracker.isTracking)
    }

    func testAFailedDeploymentStillEnds() {
        var tracker = DeploymentTracker()
        XCTAssertEqual(tracker.ingest(.building), .start(.building))
        XCTAssertEqual(tracker.ingest(.failed), .end(.failed))
        XCTAssertFalse(tracker.isTracking)
    }

    // MARK: - Cases that must not present anything

    func testADeploymentThatIsAlreadyFinishedNeverPresents() {
        // Opening a project whose last deploy shipped days ago must not flash a Live Activity.
        for terminal in [DeploymentState.ready, .failed, .canceled, .superseded] {
            var tracker = DeploymentTracker()
            XCTAssertEqual(tracker.ingest(terminal), .ignored, "\(terminal.rawValue)")
            XCTAssertFalse(tracker.isTracking, "\(terminal.rawValue)")
        }
    }

    func testUnknownStatusNeverPresents() {
        var tracker = DeploymentTracker()
        XCTAssertEqual(tracker.ingest(.unknown), .ignored)
        XCTAssertFalse(tracker.isTracking)
    }

    func testUnknownStatusMidFlightDoesNotDismissAnActiveSurface() {
        // A provider hiccup returning something unmapped must not tear down a live surface.
        var tracker = DeploymentTracker()
        XCTAssertEqual(tracker.ingest(.building), .start(.building))
        XCTAssertEqual(tracker.ingest(.unknown), .ignored)
        XCTAssertTrue(tracker.isTracking)
        XCTAssertEqual(tracker.ingest(.ready), .end(.ready))
    }

    func testNothingIsEmittedAfterTheDeploymentSettles() {
        var tracker = DeploymentTracker()
        XCTAssertEqual(tracker.ingest(.building), .start(.building))
        XCTAssertEqual(tracker.ingest(.ready), .end(.ready))

        // Late or out-of-order polls must not reopen a finished deployment.
        XCTAssertEqual(tracker.ingest(.building), .ignored)
        XCTAssertEqual(tracker.ingest(.ready), .ignored)
        XCTAssertEqual(tracker.ingest(.failed), .ignored)
        XCTAssertFalse(tracker.isTracking)
    }

    // MARK: - Poll cadence

    func testPollIntervalWidensAsADeploymentRunsLong() {
        XCTAssertEqual(DeploymentPollPolicy.interval(elapsed: 0), 5)
        XCTAssertEqual(DeploymentPollPolicy.interval(elapsed: 59), 5)
        XCTAssertEqual(DeploymentPollPolicy.interval(elapsed: 60), 10)
        XCTAssertEqual(DeploymentPollPolicy.interval(elapsed: 299), 10)
        XCTAssertEqual(DeploymentPollPolicy.interval(elapsed: 300), 30)
        XCTAssertEqual(DeploymentPollPolicy.interval(elapsed: 3_600), 30)
    }

    func testPollIntervalToleratesNonsenseElapsedValues() {
        XCTAssertEqual(DeploymentPollPolicy.interval(elapsed: -10), 5)
    }

    func testTrackingTimesOut() {
        XCTAssertFalse(DeploymentPollPolicy.shouldTimeOut(elapsed: 0))
        XCTAssertFalse(DeploymentPollPolicy.shouldTimeOut(elapsed: DeploymentPollPolicy.timeout - 1))
        XCTAssertTrue(DeploymentPollPolicy.shouldTimeOut(elapsed: DeploymentPollPolicy.timeout))
        XCTAssertTrue(DeploymentPollPolicy.shouldTimeOut(elapsed: DeploymentPollPolicy.timeout + 1))
    }

    // MARK: - Integration with the state machine

    func testAVercelDeploymentLifecycleDrivenByRawProviderStrings() {
        var tracker = DeploymentTracker()
        let observed = ["QUEUED", "INITIALIZING", "BUILDING", "BUILDING", "READY"]
        let outcomes = observed.map { raw in
            tracker.ingest(DeploymentState(rawStatus: raw, provider: .vercel))
        }

        XCTAssertEqual(outcomes, [
            .start(.queued),
            .update(.initializing),
            .update(.building),
            .ignored,
            .end(.ready),
        ])
    }

    func testAnAmplifyBuildIsTrackedRatherThanTreatedAsFinished() {
        // Before the state machine, RUNNING classified as a success, so nothing would have been
        // tracked at all.
        var tracker = DeploymentTracker()
        XCTAssertEqual(
            tracker.ingest(DeploymentState(rawStatus: "RUNNING", provider: .awsAmplify)),
            .start(.building)
        )
        XCTAssertEqual(
            tracker.ingest(DeploymentState(rawStatus: "SUCCEED", provider: .awsAmplify)),
            .end(.ready)
        )
    }
}
