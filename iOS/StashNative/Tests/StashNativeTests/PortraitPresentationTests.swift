import XCTest
import RegressionSupport

final class PortraitPresentationTests: XCTestCase {
    @MainActor func testOrientationHooksPreserveHostsOtherScenesAndInheritedMethods() throws {
        let results = try XCTUnwrap(StashPortraitHooksProbe())
        XCTAssertEqual(results.count, 7)
        for (key, value) in results { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }

    @MainActor func testCancellationCompletesPendingPreparationOnce() throws {
        let results = try XCTUnwrap(StashPortraitCancellationProbe())
        XCTAssertEqual(results.count, 7)
        for (key, value) in results { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }

    @MainActor func testDismissalWaitsForOrientationRestorationBeforeCallingHost() throws {
        let results = try XCTUnwrap(StashPortraitFinishProbe())
        XCTAssertEqual(results.count, 3)
        for (key, value) in results { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }

    @MainActor func testBrowserSwipeDismissalRestoresOrientationAndCallsHostOnce() throws {
        let results = try XCTUnwrap(StashPortraitBrowserDismissProbe())
        XCTAssertEqual(results.count, 3)
        for (key, value) in results { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }
}
