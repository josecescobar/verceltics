import XCTest
@testable import verceltics

final class DeploymentPollLoopTests: XCTestCase {

    func testAnInFlightStatusKeepsPolling() {
        var tracker = DeploymentTracker()
        let decision = DeploymentPollLoop.decide(
            elapsed: 12,
            rawStatus: "BUILDING",
            provider: .vercel,
            tracker: &tracker
        )

        XCTAssertEqual(decision.outcome, .start(.building))
        XCTAssertTrue(decision.continuePolling)
        XCTAssertEqual(decision.nextInterval, 5)
        XCTAssertFalse(decision.timedOut)
        XCTAssertFalse(decision.disappeared)
    }

    func testATerminalStatusStopsTheLoop() {
        var tracker = DeploymentTracker()
        _ = DeploymentPollLoop.decide(
            elapsed: 0,
            rawStatus: "BUILDING",
            provider: .vercel,
            tracker: &tracker
        )
        let decision = DeploymentPollLoop.decide(
            elapsed: 20,
            rawStatus: "READY",
            provider: .vercel,
            tracker: &tracker
        )

        XCTAssertEqual(decision.outcome, .end(.ready))
        XCTAssertFalse(decision.continuePolling)
    }

    func testASingleMissingReadKeepsPolling() {
        var tracker = DeploymentTracker()
        _ = tracker.ingest(.building)
        let decision = DeploymentPollLoop.decide(
            elapsed: 10,
            rawStatus: nil,
            provider: .vercel,
            tracker: &tracker,
            consecutiveMisses: 1
        )

        XCTAssertEqual(decision.outcome, .ignored)
        XCTAssertFalse(decision.disappeared)
        XCTAssertTrue(decision.continuePolling)
        XCTAssertFalse(decision.timedOut)
        XCTAssertTrue(tracker.isTracking)
    }

    func testRepeatedMissingReadsCountAsDisappeared() {
        var tracker = DeploymentTracker()
        _ = tracker.ingest(.building)
        let decision = DeploymentPollLoop.decide(
            elapsed: 10,
            rawStatus: nil,
            provider: .vercel,
            tracker: &tracker,
            consecutiveMisses: DeploymentPollPolicy.missingStatusLimit
        )

        XCTAssertEqual(decision.outcome, .ignored)
        XCTAssertTrue(decision.disappeared)
        XCTAssertFalse(decision.continuePolling)
        XCTAssertFalse(decision.timedOut)
    }

    func testTimeoutWinsEvenIfTheDeployIsStillRunning() {
        var tracker = DeploymentTracker()
        _ = tracker.ingest(.building)
        let decision = DeploymentPollLoop.decide(
            elapsed: DeploymentPollPolicy.timeout,
            rawStatus: "BUILDING",
            provider: .vercel,
            tracker: &tracker
        )

        XCTAssertTrue(decision.timedOut)
        XCTAssertFalse(decision.continuePolling)
        XCTAssertEqual(decision.outcome, .ignored)
    }

    func testUnknownMidFlightDoesNotStopTheLoop() {
        var tracker = DeploymentTracker()
        _ = tracker.ingest(.building)
        let decision = DeploymentPollLoop.decide(
            elapsed: 90,
            rawStatus: "flurbled",
            provider: .vercel,
            tracker: &tracker
        )

        XCTAssertEqual(decision.outcome, .ignored)
        XCTAssertTrue(decision.continuePolling)
        XCTAssertEqual(decision.nextInterval, 10)
        XCTAssertTrue(tracker.isTracking)
    }

    func testAnAlreadyFinishedDeployNeverStartsPolling() {
        var tracker = DeploymentTracker()
        let decision = DeploymentPollLoop.decide(
            elapsed: 0,
            rawStatus: "READY",
            provider: .vercel,
            tracker: &tracker
        )

        XCTAssertEqual(decision.outcome, .ignored)
        XCTAssertFalse(decision.continuePolling)
        XCTAssertFalse(tracker.isTracking)
    }
}
