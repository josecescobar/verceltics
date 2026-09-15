import XCTest
@testable import verceltics

final class AmbientAlertRulesTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func expiry(inDays days: Int) -> Date {
        now.addingTimeInterval(Double(days) * 86_400)
    }

    // MARK: - Deployment alerts

    func testAFreshFailureRaisesAnAlert() {
        XCTAssertEqual(
            AmbientAlertRules.deploymentAlert(
                project: "verceltics",
                provider: .vercel,
                previous: .building,
                current: .failed
            ),
            .deploymentFailed(project: "verceltics", provider: .vercel)
        )
    }

    func testAFailureIsNotRepeatedOnceItHasSettled() {
        // The second refresh sees the same terminal state and must stay quiet.
        XCTAssertNil(
            AmbientAlertRules.deploymentAlert(
                project: "verceltics",
                provider: .vercel,
                previous: .failed,
                current: .failed
            )
        )
    }

    func testAFailureOnAFirstReadStillAlerts() {
        XCTAssertEqual(
            AmbientAlertRules.deploymentAlert(
                project: "verceltics",
                provider: .netlify,
                previous: nil,
                current: .failed
            ),
            .deploymentFailed(project: "verceltics", provider: .netlify)
        )
    }

    func testSuccessIsOptIn() {
        XCTAssertNil(
            AmbientAlertRules.deploymentAlert(
                project: "verceltics",
                provider: .vercel,
                previous: .building,
                current: .ready
            )
        )
        XCTAssertEqual(
            AmbientAlertRules.deploymentAlert(
                project: "verceltics",
                provider: .vercel,
                previous: .building,
                current: .ready,
                notifyOnSuccess: true
            ),
            .deploymentReady(project: "verceltics", provider: .vercel)
        )
    }

    func testCanceledAndSupersededAreNotNews() {
        for state in [DeploymentState.canceled, .superseded] {
            XCTAssertNil(
                AmbientAlertRules.deploymentAlert(
                    project: "verceltics",
                    provider: .vercel,
                    previous: .building,
                    current: state
                ),
                "\(state.rawValue) should stay quiet"
            )
        }
    }

    func testInFlightStatesNeverAlert() {
        for state in DeploymentState.allCases where !state.isTerminal {
            XCTAssertNil(
                AmbientAlertRules.deploymentAlert(
                    project: "verceltics",
                    provider: .vercel,
                    previous: nil,
                    current: state,
                    notifyOnSuccess: true
                ),
                "\(state.rawValue) should stay quiet"
            )
        }
    }

    // MARK: - Domain expiry

    func testDistantExpiryDoesNotAlert() {
        XCTAssertNil(
            AmbientAlertRules.domainExpiryAlert(
                domain: "verceltics.com",
                expiresAt: expiry(inDays: 45),
                now: now,
                calendar: utc
            )
        )
    }

    func testExpiryBucketsCollapseToTheNextThreshold() {
        let expectations: [(days: Int, bucket: Int)] = [
            (30, 30), (29, 30), (15, 30),
            (14, 14), (8, 14),
            (7, 7), (4, 7),
            (3, 3),
            (1, 1),
            (0, 0),
        ]
        for expectation in expectations {
            XCTAssertEqual(
                AmbientAlertRules.domainExpiryAlert(
                    domain: "verceltics.com",
                    expiresAt: expiry(inDays: expectation.days),
                    now: now,
                    calendar: utc
                ),
                .domainExpiring(domain: "verceltics.com", daysRemaining: expectation.bucket),
                "\(expectation.days) days out"
            )
        }
    }

    func testAnAlreadyExpiredDomainReportsZeroRatherThanNegative() {
        XCTAssertEqual(
            AmbientAlertRules.daysRemaining(from: now, until: expiry(inDays: -5), calendar: utc),
            0
        )
        XCTAssertEqual(
            AmbientAlertRules.domainExpiryAlert(
                domain: "verceltics.com",
                expiresAt: expiry(inDays: -5),
                now: now,
                calendar: utc
            ),
            .domainExpiring(domain: "verceltics.com", daysRemaining: 0)
        )
    }

    func testEachBucketFiresAtMostOnce() {
        // Two refreshes on different days inside the same bucket produce the same dedupe key, so
        // only one notification survives.
        let first = AmbientAlertRules.domainExpiryAlert(
            domain: "verceltics.com",
            expiresAt: expiry(inDays: 20),
            now: now,
            calendar: utc
        )
        let second = AmbientAlertRules.domainExpiryAlert(
            domain: "verceltics.com",
            expiresAt: expiry(inDays: 18),
            now: now,
            calendar: utc
        )
        XCTAssertEqual(first?.dedupeKey, second?.dedupeKey)
    }

    // MARK: - Presentation

    func testDedupeKeysDistinguishConditions() {
        let keys = Set([
            AmbientAlert.deploymentFailed(project: "a", provider: .vercel).dedupeKey,
            AmbientAlert.deploymentReady(project: "a", provider: .vercel).dedupeKey,
            AmbientAlert.deploymentFailed(project: "a", provider: .netlify).dedupeKey,
            AmbientAlert.deploymentFailed(project: "b", provider: .vercel).dedupeKey,
            AmbientAlert.domainExpiring(domain: "a.com", daysRemaining: 7).dedupeKey,
            AmbientAlert.domainExpiring(domain: "a.com", daysRemaining: 3).dedupeKey,
        ])
        XCTAssertEqual(keys.count, 6)
    }

    func testDomainDedupeKeyIsCaseInsensitive() {
        XCTAssertEqual(
            AmbientAlert.domainExpiring(domain: "Verceltics.com", daysRemaining: 7).dedupeKey,
            AmbientAlert.domainExpiring(domain: "verceltics.com", daysRemaining: 7).dedupeKey
        )
    }

    func testEveryAlertHasCopy() {
        let alerts: [AmbientAlert] = [
            .deploymentFailed(project: "verceltics", provider: .vercel),
            .deploymentReady(project: "verceltics", provider: .vercel),
            .domainExpiring(domain: "verceltics.com", daysRemaining: 0),
            .domainExpiring(domain: "verceltics.com", daysRemaining: 1),
            .domainExpiring(domain: "verceltics.com", daysRemaining: 7),
        ]
        for alert in alerts {
            XCTAssertFalse(alert.title.isEmpty, "\(alert) title")
            XCTAssertFalse(alert.body.isEmpty, "\(alert) body")
        }
    }
}
