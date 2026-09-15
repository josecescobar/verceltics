import XCTest
@testable import verceltics

@MainActor
final class DeploymentStateTests: XCTestCase {

    // MARK: - Regressions the provider-blind classifier produced

    func testAmplifyRunningIsABuildNotASuccess() {
        // AWS Amplify reports RUNNING while a build job is still executing. The shared substring
        // classifier matched "running" and painted it as a completed success.
        XCTAssertEqual(DeploymentState(rawStatus: "RUNNING", provider: .awsAmplify), .building)
        XCTAssertTrue(DeploymentState(rawStatus: "RUNNING", provider: .awsAmplify).isInFlight)
        XCTAssertEqual(tone(for: "RUNNING", provider: .awsAmplify), "progress")
    }

    func testFlyStartedMachineStaysASuccess() {
        // The same idea in reverse: a started Fly machine really is healthy, so the fix must not
        // demote it.
        XCTAssertEqual(DeploymentState(rawStatus: "started", provider: .fly), .ready)
        XCTAssertEqual(tone(for: "started", provider: .fly), "success")
    }

    func testDigitalOceanDeployingPhaseGetsAProgressSignal() {
        // No branch of the old classifier matched "deploying", so this rendered as neutral with no
        // status signal at all.
        XCTAssertEqual(DeploymentState(rawStatus: "DEPLOYING", provider: .digitalOcean), .deploying)
        XCTAssertTrue(DeploymentState(rawStatus: "DEPLOYING", provider: .digitalOcean).isInFlight)
        XCTAssertEqual(tone(for: "DEPLOYING", provider: .digitalOcean), "progress")
    }

    func testDigitalOceanSupersededIsTerminalWithoutBeingAFailure() {
        let state = DeploymentState(rawStatus: "SUPERSEDED", provider: .digitalOcean)
        XCTAssertEqual(state, .superseded)
        XCTAssertTrue(state.isTerminal)
        XCTAssertFalse(state.isFailure)
        XCTAssertEqual(tone(for: "SUPERSEDED", provider: .digitalOcean), "neutral")
    }

    // MARK: - Provider vocabularies

    func testVercelVocabulary() {
        expect(provider: .vercel, [
            "QUEUED": .queued,
            "INITIALIZING": .initializing,
            "BUILDING": .building,
            "READY": .ready,
            "ERROR": .failed,
            "CANCELED": .canceled,
            "DELETED": .superseded,
        ])
    }

    func testNetlifyVocabulary() {
        expect(provider: .netlify, [
            "new": .queued,
            "pending_review": .queued,
            "accepted": .queued,
            "enqueued": .queued,
            "retrying": .queued,
            "building": .building,
            "preparing": .deploying,
            "prepared": .deploying,
            "uploading": .deploying,
            "uploaded": .deploying,
            "processing": .deploying,
            "ready": .ready,
            "error": .failed,
            "failed": .failed,
            "rejected": .failed,
            "canceled": .canceled,
            "skipped": .canceled,
            "deleted": .superseded,
        ])
    }

    func testRailwayVocabulary() {
        expect(provider: .railway, [
            "QUEUED": .queued,
            "WAITING": .queued,
            "NEEDS_APPROVAL": .queued,
            "INITIALIZING": .initializing,
            "BUILDING": .building,
            "DEPLOYING": .deploying,
            "SUCCESS": .ready,
            "SLEEPING": .ready,
            "FAILED": .failed,
            "CRASHED": .failed,
            "SKIPPED": .canceled,
            "REMOVING": .superseded,
            "REMOVED": .superseded,
        ])
    }

    func testRenderVocabulary() {
        expect(provider: .render, [
            "created": .queued,
            "queued": .queued,
            "build_in_progress": .building,
            "pre_deploy_in_progress": .deploying,
            "update_in_progress": .deploying,
            "live": .ready,
            "build_failed": .failed,
            "pre_deploy_failed": .failed,
            "update_failed": .failed,
            "canceled": .canceled,
            "deactivated": .superseded,
        ])
    }

    func testDigitalOceanVocabulary() {
        expect(provider: .digitalOcean, [
            "PENDING_BUILD": .queued,
            "PENDING_DEPLOY": .queued,
            "BUILDING": .building,
            "DEPLOYING": .deploying,
            "ACTIVE": .ready,
            "SUPERSEDED": .superseded,
            "ERROR": .failed,
            "CANCELED": .canceled,
            "UNKNOWN": .unknown,
        ])
    }

    func testHerokuVocabulary() {
        expect(provider: .heroku, [
            "pending": .deploying,
            "succeeded": .ready,
            "current": .ready,
            "released": .ready,
            "failed": .failed,
        ])
    }

    func testFlyMachineVocabulary() {
        expect(provider: .fly, [
            "created": .queued,
            "starting": .deploying,
            "replacing": .deploying,
            "started": .ready,
            "stopping": .superseded,
            "stopped": .superseded,
            "suspended": .superseded,
            "destroying": .canceled,
            "destroyed": .canceled,
            "failed": .failed,
        ])
    }

    func testFirebaseVocabulary() {
        expect(provider: .firebase, [
            "CREATED": .deploying,
            "CLONING": .deploying,
            "FINALIZED": .ready,
            "RELEASED": .ready,
            "DELETED": .superseded,
            "ABANDONED": .superseded,
            "EXPIRED": .superseded,
            "VERSION_STATUS_UNSPECIFIED": .unknown,
        ])
    }

    func testAmplifyVocabulary() {
        expect(provider: .awsAmplify, [
            "PENDING": .queued,
            "PROVISIONING": .initializing,
            "RUNNING": .building,
            "SUCCEED": .ready,
            "FAILED": .failed,
            "CANCELLING": .canceled,
            "CANCELLED": .canceled,
        ])
    }

    func testCloudflarePagesVocabulary() {
        expect(provider: .cloudflare, [
            "idle": .queued,
            "active": .building,
            "success": .ready,
            "failure": .failed,
            "canceled": .canceled,
            "skipped": .canceled,
        ])
    }

    /// `ACTIVE` finishes a DigitalOcean deployment but starts a Cloudflare Pages one. This is the
    /// collision that makes provider scoping necessary.
    func testActiveMeansOppositeThingsOnDifferentProviders() {
        XCTAssertEqual(DeploymentState(rawStatus: "active", provider: .digitalOcean), .ready)
        XCTAssertEqual(DeploymentState(rawStatus: "active", provider: .cloudflare), .building)
    }

    // MARK: - Normalization

    func testSeparatorsAndCasingAreNormalized() {
        for raw in ["PENDING_BUILD", "pending-build", "Pending Build", "  pending_build  "] {
            XCTAssertEqual(
                DeploymentState(rawStatus: raw, provider: .digitalOcean),
                .queued,
                "expected \(raw) to normalize"
            )
        }
    }

    func testMissingOrEmptyStatusIsUnknown() {
        XCTAssertEqual(DeploymentState(rawStatus: nil, provider: .vercel), .unknown)
        XCTAssertEqual(DeploymentState(rawStatus: "", provider: .vercel), .unknown)
        XCTAssertEqual(DeploymentState(rawStatus: "   ", provider: .vercel), .unknown)
    }

    func testUnlistedProviderValuesFallBackToTheSharedVocabulary() {
        // "published" is not in the Vercel table but is unambiguous everywhere it appears.
        XCTAssertEqual(DeploymentState(rawStatus: "published", provider: .vercel), .ready)
    }

    func testGenuinelyUnrecognizedValuesStayUnknown() {
        XCTAssertEqual(DeploymentState(rawStatus: "flurbled", provider: .vercel), .unknown)
    }

    // MARK: - Invariants

    func testInFlightAndTerminalAreMutuallyExclusiveAndCoverEveryKnownState() {
        for state in DeploymentState.allCases {
            if state == .unknown {
                XCTAssertFalse(state.isInFlight, "unknown must not claim to be in flight")
                XCTAssertFalse(state.isTerminal, "unknown must not claim to be terminal")
                continue
            }
            XCTAssertNotEqual(
                state.isInFlight,
                state.isTerminal,
                "\(state.rawValue) must be exactly one of in-flight or terminal"
            )
        }
    }

    func testOnlyFailedCountsAsAFailure() {
        for state in DeploymentState.allCases {
            XCTAssertEqual(state.isFailure, state == .failed, "\(state.rawValue) failure flag")
        }
    }

    func testEveryStateHasANonEmptyDisplayName() {
        for state in DeploymentState.allCases {
            XCTAssertFalse(state.displayName.isEmpty, "\(state.rawValue) needs a label")
        }
    }

    // MARK: - Tone routing

    func testUnknownDeploymentValuesKeepTheLegacyClassifierAppearance() {
        // Anything the provider tables miss must look exactly as it did before, so adopting the
        // state machine cannot regress an unmapped provider string.
        for raw in ["Degraded", "Maintenance", "Idle", "flurbled"] {
            XCTAssertEqual(
                tone(for: raw, provider: .vercel),
                legacyTone(for: raw),
                "expected \(raw) to keep its previous tone"
            )
        }
    }

    func testResourceHealthClassifierIsUntouched() {
        // Resource rows (Fly/Heroku app health) still go through AppStatusTone.status, where
        // "Running" legitimately means healthy — the opposite of Amplify's deployment RUNNING.
        XCTAssertEqual(legacyTone(for: "Running"), "success")
        XCTAssertEqual(legacyTone(for: "Stopped"), "danger")
        XCTAssertEqual(legacyTone(for: "Degraded"), "neutral")
    }

    // MARK: - Helpers

    private func expect(
        provider: AccountProvider,
        _ expectations: [String: DeploymentState],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (raw, expected) in expectations {
            XCTAssertEqual(
                DeploymentState(rawStatus: raw, provider: provider),
                expected,
                "\(provider.rawValue) \"\(raw)\"",
                file: file,
                line: line
            )
        }
    }

    /// `AppStatusTone` has no `Equatable` conformance to rely on, so compare stable labels instead.
    private func tone(for raw: String, provider: AccountProvider) -> String {
        label(AppStatusTone.deployment(raw, provider: provider))
    }

    private func legacyTone(for raw: String) -> String {
        label(AppStatusTone.status(raw))
    }

    private func label(_ tone: AppStatusTone) -> String {
        switch tone {
        case .success: "success"
        case .warning: "warning"
        case .danger: "danger"
        case .progress: "progress"
        case .neutral: "neutral"
        }
    }
}
