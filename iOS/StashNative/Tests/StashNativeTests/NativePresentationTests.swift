import XCTest
import RegressionSupport

final class NativePresentationTests: XCTestCase {
    @MainActor func testCardsUseNativeSheetAcrossWindowShapes() throws {
        let result = try XCTUnwrap(StashNativePresentationProbe())
        XCTAssertEqual(result.count, 4)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }

    @MainActor func testInvalidPresentersAndRetiredSessionsCannotCreateCheckout() throws {
        let result = try XCTUnwrap(StashPresentationLifetimeProbe())
        XCTAssertEqual(result.count, 5)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }
}
