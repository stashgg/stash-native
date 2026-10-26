import XCTest
import RegressionSupport

final class InstanceLifetimeTests: XCTestCase {
    private func checkOwnerRelease(background: Bool, portrait: Bool) {
        let done = expectation(description: "independent owner release")
        DispatchQueue.main.async {
            StashInstanceOwnerReleaseProbe(background, portrait) { values in
                let result = values as! [String: NSNumber]
                XCTAssertEqual(result["pendingPortrait"]?.boolValue, portrait)
                XCTAssertEqual(result["callbacks"]?.intValue, 0)
                for name in ["admitted", "ownerReleased", "sessionReleased", "webReleased",
                             "portraitReleased", "timerInvalidated", "sessionReleasedOnMain"] {
                    XCTAssertEqual(result[name]?.boolValue, true, name)
                }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
    }

    func testLastOwnerReleaseTearsDownWebContentWithoutCallbacks() {
        checkOwnerRelease(background: false, portrait: false)
    }

    func testBackgroundOwnerReleaseRetiresOnMainQueue() {
        checkOwnerRelease(background: true, portrait: false)
    }

    func testOwnerReleaseCancelsPendingPortraitPreparation() {
        checkOwnerRelease(background: false, portrait: true)
    }

    func testResetDuringDismissalDetachesOwnerBeforeItsRelease() {
        let done = expectation(description: "retirement during dismissal")
        DispatchQueue.main.async {
            let result = StashInstanceClosingOwnerReleaseProbe() as! [String: NSNumber]
            for name in ["pending", "detached", "ownerReleased", "sessionReleased", "silent"] {
                XCTAssertEqual(result[name]?.boolValue, true, name)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testIndependentPresenterThemesSurviveBrowserHandoff() {
        let done = expectation(description: "instance themes")
        DispatchQueue.main.async {
            let result = StashInstanceThemeProbe() as! [String: Any]
            XCTAssertEqual(result["darkURL"] as? String,
                           "https://example.invalid?token=a%2Bb%26c&theme=dark#section")
            XCTAssertEqual(result["lightURL"] as? String, "https://example.invalid?theme=light")
            for name in ["darkWeb", "darkSurface", "lightSurface", "darkHandoff", "lightHandoff", "lightBrowser"] {
                XCTAssertEqual((result[name] as? NSNumber)?.boolValue, true, name)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
    private func checkCallbacks(_ probe: @escaping () -> [AnyHashable: Any]) {
        let done = expectation(description: "callback contract")
        DispatchQueue.main.async {
            for (name, value) in probe() {
                XCTAssertEqual((value as? NSNumber)?.boolValue, true, String(describing: name))
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testNamedDismissalsIdentifyCardScanAndBrowser() {
        let done = expectation(description: "named dismissal routing")
        DispatchQueue.main.async {
            let result = StashCallbackDismissalProbe()
            XCTAssertEqual(result["events"] as? [String], result["expected"] as? [String])
            for name in ["cardAdmitted", "scannerAdmitted", "handoffKeepsSession", "handoffUsesReplacement", "closed",
                         "silentBrowserClosed", "silentHandoffClosed"] {
                XCTAssertEqual((result[name] as? NSNumber)?.boolValue, true, name)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testPresentationFailingAfterAcceptedOpenEndsWithItsFinalEvent() {
        let done = expectation(description: "late presentation failure")
        DispatchQueue.main.async {
            StashLatePresentationFailureProbe { result in
                XCTAssertEqual(result["handoffEvents"] as? [String], ["handoff", "browser-dismissed"])
                XCTAssertEqual(result["cardEvents"] as? [String], ["card-dismissed"])
                XCTAssertEqual(result["resetEvents"] as? [String], [])
                for name in ["handoffClosed", "cardAdmitted", "cardClosed", "resetClosed"] {
                    XCTAssertEqual((result[name] as? NSNumber)?.boolValue, true, name)
                }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
    }

    func testReplacingReceiverDuringSelectorCheckUsesOneLiveSnapshot() {
        checkCallbacks { StashCallbackLiveReceiverProbe(false) }
    }

    func testClearingReceiverDuringSelectorCheckFinishesTheExecutingEvent() {
        checkCallbacks { StashCallbackLiveReceiverProbe(true) }
    }

    func testReentrantReceiverAndSessionReplacementPreserveEventTiming() {
        checkCallbacks { StashCallbackReentrantProbe() }
    }

    func testClosingPaymentResultArrivesAfterTeardownAndAllowsReopening() {
        checkCallbacks { StashCallbackReopenProbe() }
    }

    func testDelayedScannerAndBrowserEventsUseLiveReceiverAndRejectStaleSession() {
        checkCallbacks { StashCallbackDelayedProbe() }
    }

    func testCallbackRegistrationIsIndependentAndPaymentEventsCanRepeat() {
        checkCallbacks { StashCallbackIsolationProbe() }
    }

}
