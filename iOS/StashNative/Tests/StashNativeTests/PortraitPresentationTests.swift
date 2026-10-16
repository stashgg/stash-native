import XCTest
import RegressionSupport
import StashNative

final class PortraitPresentationTests: XCTestCase {
    func testBrowserConfigDefaultsAndCopiesIndependently() throws {
        let config = StashNativeBrowserConfig()
        XCTAssertEqual(config.orientationPreference, .followHost)
        config.orientationPreference = .portrait
        let copy = try XCTUnwrap(config.copy() as? StashNativeBrowserConfig)
        config.orientationPreference = .followHost
        XCTAssertEqual(copy.orientationPreference, .portrait)
    }

    @MainActor func testBrowserConfigSnapshotsBeforeDispatchAndNormalizesUnknownPreferences() async throws {
        let results: [AnyHashable: Any] = await withCheckedContinuation { continuation in
            StashBrowserConfigurationProbe { continuation.resume(returning: $0 ?? [:]) }
        }
        XCTAssertEqual(results["orientations"] as? [Int], [1, 0, 0])
        XCTAssertEqual(results["allBrowsers"] as? Bool, true)
    }

    @MainActor func testBrowserOpeningCanBeCancelledWhileWaitingForPortraitGeometry() throws {
        let results = try XCTUnwrap(StashBrowserPreparationProbe())
        XCTAssertEqual(results.count, 6)
        for (key, value) in results { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }

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
