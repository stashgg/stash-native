import XCTest
import StashNative
import RegressionSupport

final class AuditRegressionTests: XCTestCase {
    func testPaymentRetryAndCompletionCallbacksAndNetworkCloseOrder() {
        let done = expectation(description: "callbacks")
        DispatchQueue.main.async {
            let result = StashCallbackProbe() as! [String: NSNumber]
            XCTAssertEqual(result["successes"]?.intValue, 2)
            XCTAssertEqual(result["failures"]?.intValue, 1)
            XCTAssertEqual(result["dismissals"]?.intValue, 0)
            XCTAssertEqual(result["retryRemainsOpen"]?.boolValue, true)
            XCTAssertEqual(result["closedAfterSuccess"]?.boolValue, true)
            XCTAssertEqual(result["networkErrors"]?.intValue, 1)
            XCTAssertEqual(result["closedBeforeNetworkCallback"]?.boolValue, true)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testQueuedPageCloseRespectsReplacementProcessingAndDismissPolicy() {
        for (replace, processing, allowDismiss, survives) in [
            (true, false, true, true), (false, true, true, true),
            (false, false, false, true), (false, false, true, false)
        ] {
            let done = expectation(description: "queued close")
            DispatchQueue.main.async {
                StashQueuedCloseProbe(replace, processing, allowDismiss) { presented, dismissals in
                    XCTAssertEqual(presented, survives)
                    XCTAssertEqual(dismissals, survives ? 0 : 1)
                    done.fulfill()
                }
            }
            wait(for: [done], timeout: 5)
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
        wait(for: [done], timeout: 5)
    }

    func testDetachedPresenterAndInvalidURLDoNotAdmitSession() {
        let done = expectation(description: "invalid presentation")
        DispatchQueue.main.async {
            let sdk = StashNativeCard.sharedInstance()
            let presenter = UIViewController()
            sdk.openCard(withURL: "https://example.invalid", from: presenter, config: nil)
            sdk.openBrowser(withURL: "javascript:alert(1)", from: presenter)
            XCTAssertFalse(sdk.isCurrentlyPresented)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}
