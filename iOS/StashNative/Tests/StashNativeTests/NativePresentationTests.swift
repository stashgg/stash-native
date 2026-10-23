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
        // Rotation and restoration each wait up to 20 seconds for the scene to settle.
        wait(for: [done], timeout: 60)
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

    private func runCardStack(_ cover: String, _ trigger: String, autoClose: Bool = true,
                              check: @escaping ([String: Any]) -> Void) {
        let done = expectation(description: "\(cover) \(trigger) autoClose=\(autoClose)")
        DispatchQueue.main.async {
            StashCardStackProbe(cover, trigger, autoClose) { result in
                let result = result as? [String: Any] ?? [:]
                for key in ["presented", "overlayShown"] {
                    XCTAssertEqual((result[key] as? NSNumber)?.boolValue, true, "\(cover) \(trigger): \(key) \(result)")
                }
                check(result)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 40)
    }

    private func assertFlags(_ result: [String: Any], _ keys: [String], _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        for key in keys {
            XCTAssertEqual((result[key] as? NSNumber)?.boolValue, true, "\(label): \(key)", file: file, line: line)
        }
    }

    // A card that closes while it presents keepOpen Safari or a page dialog takes them with it, ends once,
    // and leaves nothing on the host.
    func testClosingACardRemovesWhatItPresents() {
        let closes: [(String, String, [String])] = [
            ("safari", "dismiss", ["externalPayment", "cardDismissed"]),
            ("safari", "reset", ["externalPayment"]),
            ("safari", "ownerRelease", ["externalPayment"]),
            ("safari", "success", ["externalPayment", "paymentSuccess"]),
            ("safari", "failure", ["externalPayment", "paymentFailure"]),
            ("safari", "windowClose", ["externalPayment", "cardDismissed"]),
            ("safari", "networkError", ["externalPayment", "networkError"]),
            ("alert", "dismiss", ["cardDismissed"]),
            ("alert", "reset", []),
            ("alert", "networkError", ["networkError"]),
        ]
        for (cover, trigger, events) in closes {
            runCardStack(cover, trigger) { result in
                let label = "\(cover) \(trigger)"
                self.assertFlags(result, ["ended", "rootCleared", "cardGone", "sessionEnded", "overlayCleared"], label)
                XCTAssertEqual(result["events"] as? [String], events, label)
                // WebKit's panel completion runs exactly once, so the page script returns.
                if cover == "alert" { XCTAssertEqual((result["scriptReturns"] as? NSNumber)?.intValue, 1, label) }
            }
        }
        // A closing handoff from under keepOpen Safari replaces the whole card with the browser.
        runCardStack("safari", "handoff") { result in
            self.assertFlags(result, ["browserPresented", "cardGone", "overlayCleared"], "handoff")
            XCTAssertEqual(result["events"] as? [String], ["externalPayment", "externalPayment"])
        }
    }

    // keepOpen Safari leaves through closeBrowser or a host dismissal: the card stays, no browser event is
    // emitted, and the page can open Safari again.
    func testKeepOpenSafariClosedOutsideDoneReturnsToTheCard() {
        for trigger in ["closeBrowser", "hostDismissOverlay"] {
            runCardStack("safari", trigger) { result in
                self.assertFlags(result, ["returned", "clearedOnReturn", "reopened", "cardOpen"], trigger)
                XCTAssertEqual(result["events"] as? [String], ["externalPayment", "externalPayment"], trigger)
            }
        }
    }

    // dismissSafariViewController(withResult:) closes keepOpen Safari. The live page reports the same payment,
    // so the player's payment is reported exactly once in either order.
    func testKeepOpenSafariResultReportsThePaymentOnce() {
        for trigger in ["result", "pageThenResult"] {
            runCardStack("safari", trigger, autoClose: true) { result in
                let label = "\(trigger) autoClose"
                self.assertFlags(result, ["rootCleared", "cardGone", "sessionEnded", "overlayCleared"], label)
                XCTAssertEqual(result["events"] as? [String], ["externalPayment", "paymentSuccess"], label)
            }
            runCardStack("safari", trigger, autoClose: false) { result in
                let label = "\(trigger) manual close"
                self.assertFlags(result, ["returned", "cardOpen", "overlayCleared"], label)
                XCTAssertEqual(result["events"] as? [String], ["externalPayment", "paymentSuccess"], label)
            }
        }
    }

    private func runResetReopen(_ mode: String, check: @escaping ([String: Any]) -> Void) {
        let done = expectation(description: "reset reopen \(mode)")
        DispatchQueue.main.async {
            StashResetReopenProbe(mode) { result in
                let result = result as? [String: Any] ?? [:]
                self.assertFlags(result, ["firstAnimating", "admitted", "deferred", "settled", "firstGone"], mode)
                check(result)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 20)
    }

    // Reset during the entrance animation, then reopen: the new card presents from the host once the old one
    // has left, without a dismissal event.
    func testReopenAfterResetDuringEntrancePresentsFromTheHost() {
        runResetReopen("present") { result in
            self.assertFlags(result, ["secondOnRoot", "active"], "present")
            XCTAssertEqual(result["events"] as? [String], [])
        }
    }

    // A deferred open was accepted: if the host can no longer present when it runs, it ends with exactly one final
    // event, like any accepted open that fails late. A reset while it waits stays silent.
    func testDeferredReopenThatCannotPresentEndsWithOneFinalEvent() {
        let cases: [(String, [String])] = [
            ("detached", ["cardDismissed"]),
            ("occupied", ["cardDismissed"]),
            ("browserDetached", ["browserDismissed"]),
            ("reset", []),
        ]
        for (mode, events) in cases {
            runResetReopen(mode) { result in
                self.assertFlags(result, ["ended"], mode)
                XCTAssertEqual(result["events"] as? [String], events, mode)
            }
        }
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
