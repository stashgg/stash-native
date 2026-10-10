import XCTest
import RegressionSupport

final class NativePresentationTests: XCTestCase {
    @MainActor func testContentPansPreserveScrollingAndClaimOnlyExpansionOrEdgePulls() throws {
        let result = try XCTUnwrap(StashContentPanPolicyProbe())
        XCTAssertEqual(result.count, 9)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }

    @MainActor func testCardViewportFillsEveryEdgeDuringResizing() throws {
        let result = try XCTUnwrap(StashCardViewportCoverageProbe())
        XCTAssertEqual(result.count, 2)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }

    func testWebScrollingDefersHeightUpdatesAndReservesDismissalForNativeChrome() {
        let done = expectation(description: "scroll interaction")
        DispatchQueue.main.async {
            StashScrollInteractionProbe { result in
                guard let result else { XCTFail("Missing scroll results"); done.fulfill(); return }
                XCTAssertEqual(result.count, 10)
                for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
    }

    @MainActor func testEntranceCorrectionPreservesNativeAnimationAndRejectsUnknownMotion() throws {
        let result = try XCTUnwrap(StashNativeEntranceProbe())
        XCTAssertEqual(result.count, 17)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }

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
