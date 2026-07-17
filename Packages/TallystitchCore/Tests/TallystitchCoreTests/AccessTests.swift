import XCTest
@testable import TallystitchCore

// Pins the lock-out rule. Two lines of logic, but it decides whether the app
// is usable at all and must agree with the web/RN implementations — so its
// behavior is fixed here, including the boundaries.
final class AccessTests: XCTestCase {
    private let future = Date().addingTimeInterval(30 * 86_400)
    private let past = Date().addingTimeInterval(-1 * 86_400)

    // MARK: - hasAppAccess

    func testActiveAlwaysHasAccess() {
        XCTAssertTrue(Access.hasAppAccess(status: .active, trialEndsAt: future))
        // An active subscriber keeps access even if their old trial date is long gone.
        XCTAssertTrue(Access.hasAppAccess(status: .active, trialEndsAt: past))
    }

    func testTrialingHasAccessUntilTrialEnds() {
        XCTAssertTrue(Access.hasAppAccess(status: .trialing, trialEndsAt: future))
        XCTAssertFalse(Access.hasAppAccess(status: .trialing, trialEndsAt: past))
    }

    func testExpiredTrialBoundaryIsLocked() {
        // trialEndsAt exactly now (or a hair before) must not grant access:
        // the rule is strictly `trialEndsAt > now`.
        XCTAssertFalse(Access.hasAppAccess(status: .trialing, trialEndsAt: Date().addingTimeInterval(-0.001)))
    }

    func testNonActiveNonTrialingStatusesAreLockedEvenWithFutureTrial() {
        for status: SubscriptionStatus in [.pastDue, .canceled, .incomplete] {
            XCTAssertFalse(Access.hasAppAccess(status: status, trialEndsAt: future),
                           "\(status) must be locked regardless of trial date")
        }
    }

    // MARK: - trialDaysRemaining

    func testTrialDaysRemainingCeilsPartialDays() {
        // Half a day left still reads as "1 day remaining" — never shows 0
        // to someone who can still get in.
        XCTAssertEqual(Access.trialDaysRemaining(trialEndsAt: Date().addingTimeInterval(0.5 * 86_400)), 1)
        XCTAssertEqual(Access.trialDaysRemaining(trialEndsAt: Date().addingTimeInterval(9.5 * 86_400)), 10)
    }

    func testTrialDaysRemainingClampsToZeroWhenExpired() {
        XCTAssertEqual(Access.trialDaysRemaining(trialEndsAt: past), 0)
        XCTAssertEqual(Access.trialDaysRemaining(trialEndsAt: Date().addingTimeInterval(-10 * 86_400)), 0)
    }
}
