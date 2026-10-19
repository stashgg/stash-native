import XCTest
import RegressionSupport

final class NativePresentationTests: XCTestCase {
    @MainActor func testContentPansPrioritizeExpansionAndPreservePageScrolling() throws {
        let result = try XCTUnwrap(StashContentPanPolicyProbe())
        XCTAssertEqual(result.count, 10)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }

    @MainActor func testContentExpansionTracksDragAndSettlesOnlyOnRelease() throws {
        guard #available(iOS 16.0, *) else { throw XCTSkip("Custom detents require iOS 16") }
        let result = try XCTUnwrap(StashContentExpansionProbe())
        XCTAssertEqual(result.count, 10)
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

    func testHostDismissalEndsSessionWithDismissalEvent() {
        for mode in ["card", "chain", "browser", "covered"] {
            let done = expectation(description: "host dismissal: \(mode)")
            DispatchQueue.main.async {
                StashHostDismissalProbe(mode) { result in
                    guard let result else { XCTFail("Missing \(mode) results"); done.fulfill(); return }
                    XCTAssertEqual(result.count, mode == "covered" ? 3 : 4, mode)
                    for (key, value) in result { XCTAssertEqual(value as? Bool, true, "\(mode): \(key)") }
                    done.fulfill()
                }
            }
            wait(for: [done], timeout: 15)
        }
    }

    @MainActor func testInvalidPresentersAndRetiredSessionsCannotCreateCheckout() throws {
        let result = try XCTUnwrap(StashPresentationLifetimeProbe())
        XCTAssertEqual(result.count, 5)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }
}
