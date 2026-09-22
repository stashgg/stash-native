import XCTest
import StashNative
import RegressionSupport

final class AuditRegressionTests: XCTestCase {
    func testDefaultsBrowserValidationColorAndRepeatedPopupLayout() {
        let done = expectation(description: "main thread probes")
        DispatchQueue.main.async {
            let result = AuditSynchronous() as! [String: Any]
            XCTAssertEqual(result["nilRatio"] as! Double, Double(StashNativeCardConfig().cardHeightRatioPortrait), accuracy: 0.00001)
            XCTAssertFalse(result["nilPortrait"] as! Bool)
            XCTAssertEqual(result["browserExceptions"] as! [String], ["none", "none"])
            XCTAssertTrue(result["invalidHexFallsBack"] as! Bool)
            XCTAssertEqual(result["popupFirstWidth"] as! Double, result["popupNextWidth"] as! Double, accuracy: 0.01)
            XCTAssertTrue(RegressionAccessibility())
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testStalePortraitPollReleasesCapturedObjects() {
        let done = expectation(description: "poll releases")
        DispatchQueue.main.async {
            AuditRetention { retained in
                XCTAssertFalse(retained)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
    }

    func testSafariResultDeliveredOnceWhileDismissalIsPending() {
        let done = expectation(description: "Safari callback")
        DispatchQueue.main.async {
            AuditSafariThread { onMain, calls in
                XCTAssertTrue(onMain)
                XCTAssertEqual(calls, 1)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
    }

    func testOldDismissCompletionCannotClearReplacement() {
        let done = expectation(description: "dismiss completion")
        DispatchQueue.main.async {
            XCTAssertFalse(AuditDismissResetReopen())
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testFoundationURLNormalizationAndThemeEncoding() {
        let result = RegressionURLs() as! [String: String]
        XCTAssertEqual(result["bare"], "https://example.invalid/path")
        XCTAssertEqual(result["mailto"], "")
        XCTAssertEqual(result["javascript"], "")
        let components = URLComponents(string: result["themed"]!)!
        XCTAssertEqual(components.fragment, "section")
        XCTAssertEqual(components.queryItems?.filter { $0.name == "theme" }.map(\.value), ["dark"])
        XCTAssertEqual(components.queryItems?.first { $0.name == "token" }?.value, "a+b&c")
    }

    func testQueuedCloseCannotDismissReplacement() {
        let done = expectation(description: "replacement survives queued close")
        DispatchQueue.main.async {
            AuditQueuedClose(true, false) { survived, dismissals in
                XCTAssertTrue(survived)
                XCTAssertEqual(dismissals, 0)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
    }

    func testQueuedCloseRespectsProcessingStartedBeforeExecution() {
        let done = expectation(description: "processing blocks queued close")
        DispatchQueue.main.async {
            AuditQueuedClose(false, true) { survived, dismissals in
                XCTAssertTrue(survived)
                XCTAssertEqual(dismissals, 0)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
    }

    func testQueuedCloseDismissesCurrentCheckoutOnce() {
        let done = expectation(description: "current checkout closes once")
        DispatchQueue.main.async {
            AuditQueuedClose(false, false) { survived, dismissals in
                XCTAssertFalse(survived)
                XCTAssertEqual(dismissals, 1)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
    }
}
