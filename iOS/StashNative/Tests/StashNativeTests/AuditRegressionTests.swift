import XCTest
import StashNative
import RegressionSupport

final class AuditRegressionTests: XCTestCase {
    func testPaymentRetryAndCompletionCallbacksAndNetworkCloseOrder() {
        let done = expectation(description: "callbacks")
        DispatchQueue.main.async {
            let result = StashCallbackProbe() as! [String: NSNumber]
            XCTAssertEqual(result["successes"]?.intValue, 2)
            XCTAssertEqual(result["failures"]?.intValue, 2)
            XCTAssertEqual(result["dismissals"]?.intValue, 0)
            XCTAssertEqual(result["retryRemainsOpen"]?.boolValue, true)
            XCTAssertEqual(result["closedAfterSuccess"]?.boolValue, true)
            XCTAssertEqual(result["closedAfterFailure"]?.boolValue, true)
            XCTAssertEqual(result["networkErrors"]?.intValue, 1)
            XCTAssertEqual(result["closedBeforeNetworkCallback"]?.boolValue, true)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testPageCloseIgnoresAllowDismissButRespectsReplacementAndProcessing() {
        for source in ["bridge", "window", "cancel"] {
            for (replace, processing, allowDismiss, survives) in [
                (true, false, true, true), (true, false, false, true),
                (false, true, true, true), (false, true, false, true),
                (false, false, false, false), (false, false, true, false)
            ] {
                let done = expectation(description: "queued \(source) close, allowDismiss=\(allowDismiss)")
                DispatchQueue.main.async {
                    StashQueuedCloseProbe(source, replace, processing, allowDismiss) { presented, dismissals in
                        XCTAssertEqual(presented, survives, done.expectationDescription)
                        XCTAssertEqual(dismissals, survives ? 0 : 1, done.expectationDescription)
                        done.fulfill()
                    }
                }
                wait(for: [done], timeout: 5)
            }
        }
    }

    func testDismissResetBrowserOrderAndRetiredSessionIsolation() {
        let done = expectation(description: "lifecycle")
        DispatchQueue.main.async {
            let result = StashLifecycleProbe() as! [String: NSNumber]
            for (name, value) in result { XCTAssertTrue(value.boolValue, name) }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testDetentSemanticStateSurvivesConstraintsAndKeyboard() {
        let done = expectation(description: "presentation state")
        DispatchQueue.main.async {
            let result = StashPresentationStateProbe() as! [String: NSNumber]
            for (name, value) in result { XCTAssertTrue(value.boolValue, name) }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testConfigurationSnapshotsBeforeMainQueueDispatch() {
        let done = expectation(description: "snapshot")
        StashConfigSnapshotProbe { width in
            XCTAssertEqual(width, 432)
            done.fulfill()
        }
        // The result depends only on ordering. This is often the first test after launch, when a hosted runner
        // can hold the main queue for several seconds; the ceiling only bounds a hang.
        wait(for: [done], timeout: 30)
    }

    func testMainFrameFailureAfterLoadEndsCheckoutAsNetworkError() {
        let done = expectation(description: "post-load failure")
        DispatchQueue.main.async {
            let result = StashPostLoadFailureProbe() as! [String: NSNumber]
            XCTAssertEqual(result["presented"]?.boolValue, true)
            XCTAssertEqual(result["processingLocked"]?.boolValue, true)
            XCTAssertEqual(result["networkErrorDelivered"]?.boolValue, true)
            XCTAssertEqual(result["noDismissCallback"]?.boolValue, true)
            XCTAssertEqual(result["cardClosedBeforeCallback"]?.boolValue, true)
            XCTAssertEqual(result["notPresented"]?.boolValue, true)
            XCTAssertEqual(result["cancelledFailureIgnored"]?.boolValue, true)
            XCTAssertEqual(result["provisionalFailureAfterLoadFails"]?.boolValue, true)
            XCTAssertEqual(result["rendererLossWhileProcessingFails"]?.boolValue, true)
            XCTAssertEqual(result.count, 9)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testNavigationActionPolicyDecidesOnceAndRoutesExternalURLs() {
        assertProbe("navigation action", count: 9, StashNavigationPolicyProbe)
    }

    func testNavigationResponsePolicyFailsBeforeLoadAndStopsBudgetOnSuccess() {
        assertProbe("navigation response", count: 5, StashNavigationResponseProbe)
    }

    func testLoadBudgetRetriesAtTenSecondsAndFailsAtFifteen() {
        assertProbe("load budget", count: 6, StashLoadBudgetProbe)
    }

    func testNewWindowRequestsRouteResultsOrOpenExternallyWithoutCreatingWebViews() {
        assertProbe("new window", count: 4, StashNewWindowProbe)
    }

    func testJavaScriptDialogCompletionsRunExactlyOnceWhenBusyOrTornDown() {
        assertProbe("javascript dialogs", count: 6, StashJavaScriptDialogProbe)
    }

    private func assertProbe(_ name: String, count: Int, _ probe: @escaping () -> [AnyHashable: Any]?) {
        let done = expectation(description: name)
        DispatchQueue.main.async {
            let result = probe() as! [String: NSNumber]
            XCTAssertEqual(result.count, count, name)
            for (key, value) in result { XCTAssertTrue(value.boolValue, "\(name): \(key)") }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testDetachedPresenterAndInvalidURLDoNotAdmitSession() {
        let done = expectation(description: "invalid presentation")
        DispatchQueue.main.async {
            let sdk = StashNative.sharedInstance()
            let presenter = UIViewController()
            sdk.openCard(withURL: "https://example.invalid", from: presenter, config: nil)
            sdk.openBrowser(withURL: "javascript:alert(1)", from: presenter)
            XCTAssertFalse(sdk.isCurrentlyPresented)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}
