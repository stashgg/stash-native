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

    // UIKit ignores the width of a zero-height preferred size and draws a 540-point sheet in phone landscape.
    func testLandscapePhoneCardDrawsConfiguredWidth() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("Compact-height phone window") }
        let done = expectation(description: "landscape card width")
        DispatchQueue.main.async {
            StashLandscapeCardWidthProbe(400) { result in
                for key in ["rotated", "presented", "active", "restoredPortrait"] {
                    XCTAssertEqual((result[key] as? NSNumber)?.boolValue, true, key)
                }
                let window = (result["windowWidth"] as? NSNumber)?.doubleValue ?? 0
                XCTAssertGreaterThanOrEqual(window, 600, "The landscape window must take the wide-container path")
                XCTAssertEqual((result["cardWidth"] as? NSNumber)?.doubleValue ?? 0, 400, accuracy: 1)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 20)
    }

    // Floating tablet cards fade in, like Android; phone cards rise from the bottom edge.
    func testTabletCardFadesInWhilePhoneCardsSlideUp() throws {
        let result = StashCardTransitionProbe() as! [String: NSNumber]
        XCTAssertEqual(result["tablet"]?.intValue, UIModalTransitionStyle.crossDissolve.rawValue)
        XCTAssertEqual(result["phone"]?.intValue, UIModalTransitionStyle.coverVertical.rawValue)
        XCTAssertEqual(result["phoneLandscape"]?.intValue, UIModalTransitionStyle.coverVertical.rawValue)
    }

    // externalBrowser(url, {keepOpen: true}) presents Safari over the card and returns to it.
    func testKeepOpenBrowserReturnsToTheOpenCard() throws {
        let done = expectation(description: "keepOpen browser")
        DispatchQueue.main.async {
            StashKeepOpenBrowserProbe { result in
                for key in ["presented", "browserShown", "tracked", "returned", "cardStillPresented",
                            "sessionActive", "overlayCleared"] {
                    XCTAssertEqual((result[key] as? NSNumber)?.boolValue, true, key)
                }
                XCTAssertEqual(result["eventsWhileOpen"] as? [String], ["externalPayment"])
                XCTAssertEqual(result["events"] as? [String], ["externalPayment"])
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 25)
    }

    // UIKit moves the card's frame off screen when dismissal starts; the content must stay drawn while it animates out.
    func testDismissalKeepsWebContentUntilTheCardLeaves() throws {
        let done = expectation(description: "dismissal content")
        DispatchQueue.main.async {
            StashDismissalContentProbe { result in
                for key in ["presented", "dismissed"] {
                    XCTAssertEqual((result[key] as? NSNumber)?.boolValue, true, key)
                }
                let before = (result["beforeHeight"] as? NSNumber)?.doubleValue ?? 0
                XCTAssertGreaterThan(before, 0)
                XCTAssertGreaterThan((result["samples"] as? NSNumber)?.intValue ?? 0, 0)
                XCTAssertEqual((result["minimumHeight"] as? NSNumber)?.doubleValue ?? 0, before, accuracy: 0.5)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 15)
    }

    @MainActor func testInvalidPresentersAndRetiredSessionsCannotCreateCheckout() throws {
        let result = try XCTUnwrap(StashPresentationLifetimeProbe())
        XCTAssertEqual(result.count, 5)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }
}
