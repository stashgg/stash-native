import XCTest
import RegressionSupport

final class NativeSheetGeometryTests: XCTestCase {


    @MainActor func testIntrinsicHeightCompensatesOnlyMissingNativeSafeAreaReserve() async throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Probe requires the reserved-region test host") }
        let result: [String: NSNumber] = await withCheckedContinuation { continuation in
            StashNativeIntrinsicSafeAreaProbe { value in
                continuation.resume(returning: value as! [String: NSNumber])
            }
        }
        XCTAssertEqual(result["compactBefore"]?.doubleValue, 220)
        XCTAssertEqual(result["tabletBefore"]?.doubleValue, 220)
        XCTAssertEqual(result["floatingBefore"]?.doubleValue, 194)
        for name in ["compact", "tablet", "floating"] {
            XCTAssertEqual(result[name + "Usable"]?.doubleValue, 220, name)
        }
        XCTAssertEqual(result["compactCompensation"]?.doubleValue, 0)
        XCTAssertEqual(result["tabletCompensation"]?.doubleValue, 0)
        XCTAssertEqual(result["floatingCompensation"]?.doubleValue, 26)
        XCTAssertEqual(result["cappedDetent"]?.doubleValue, 256)
        XCTAssertEqual(result["nativeMaximumWins"]?.doubleValue, 230)
        XCTAssertEqual(result["dragKeepsCompensation"]?.boolValue, true)
    }

    func testNativeSurfaceUsesContentBoundsWithoutAdditionalChrome() throws {
        func probe(_ bounds: CGRect, _ expanded: Bool = false,
                   _ measured: CGFloat = 0, _ preferred: CGFloat = 560, _ maximum: CGFloat = 900) throws -> (CGRect, CGFloat, CGFloat) {
            let value = try XCTUnwrap(StashChromeSurfaceGeometryProbe(bounds, expanded, measured, preferred, maximum))
            return (try XCTUnwrap((value["frame"] as? NSValue)?.cgRectValue),
                    CGFloat(try XCTUnwrap(value["resting"] as? NSNumber).doubleValue),
                    CGFloat(try XCTUnwrap(value["expanded"] as? NSNumber).doubleValue))
        }
        let large = CGRect(x:11,y:23,width:1000,height:1200)
        let resting = try probe(large)
        XCTAssertEqual(resting.0.height, 560)
        XCTAssertEqual(resting.1, 560)
        XCTAssertEqual(try probe(large, true).0.height, 900)
        XCTAssertEqual(try probe(large, false, 120).0.height, 120)
        for bounds in [CGRect(x:0,y:0,width:667,height:101), CGRect(x:0,y:495.5,width:669,height:421.5),
                       CGRect(x:11,y:23,width:390,height:12)] {
            let result = try probe(bounds, true)
            XCTAssertTrue(bounds.contains(result.0))
            XCTAssertGreaterThanOrEqual(result.0.height, 0)
            XCTAssertEqual(result.0.height-result.2, 0, accuracy:0.001)
        }
        XCTAssertEqual(try probe(CGRect(x:0,y:0,width:667,height:101), true).0.height, 69)
    }

    @MainActor func testNativeWebContentPaintsOnlyThroughTheBottomSystemSafeArea() throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Reserved regions require iOS27.1") }
        let result = StashNativeBottomPaintProbe() as! [String: NSNumber]
        for key in ["transitionalHeight", "settledHeight"] {
            XCTAssertEqual(result[key]?.doubleValue, 587, key)
        }
        for key in ["transitionalInset", "settledInset"] {
            XCTAssertEqual(result[key]?.doubleValue, 26, key)
        }
        for key in ["initialCorrection", "pendingCorrection", "propagatedCorrection"] {
            XCTAssertEqual(result[key]?.doubleValue, 20, key)
        }
        XCTAssertEqual(result["releasedCorrection"]?.doubleValue, 0)
        XCTAssertEqual(result["sameTotalCorrection"]?.doubleValue, 28)
        XCTAssertEqual(result["offscreenCorrection"]?.doubleValue, 100)
        XCTAssertEqual(result["compactWidth"]?.doubleValue, 450)
        XCTAssertEqual(result["compactHeight"]?.doubleValue, 468)
        XCTAssertEqual(result["compactInset"]?.doubleValue, 34)
        XCTAssertEqual(result["reservedBandBottom"]?.doubleValue, 460)
        XCTAssertEqual(result["reservedBandInset"]?.doubleValue, 10)
        XCTAssertEqual(result["floatingHeight"]?.doubleValue, 468)
        XCTAssertEqual(result["floatingInset"]?.doubleValue, 34)
        XCTAssertEqual(result["keyboardBottom"]?.doubleValue, 389)
        XCTAssertEqual(result["keyboardInset"]?.doubleValue, 0)
        XCTAssertEqual(result["keyboardContentInsetCleared"]?.boolValue, true)
        XCTAssertEqual(result["dividerBottom"]?.doubleValue, 200)
        XCTAssertEqual(result["dividerInset"]?.doubleValue, 0)
        XCTAssertEqual(result["coveredEmpty"]?.boolValue, true)
    }

    @MainActor func testNativeContentUsesHostSafeBoundsWhileFoldInsetsSettle() throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Reserved regions require iOS27.1") }
        let result = StashNativeHostSafeAreaProbe() as! [String: NSNumber]
        XCTAssertEqual(result["transitionalHeight"]?.doubleValue, 577)
        XCTAssertEqual(result["settledHeight"]?.doubleValue, 577)
        XCTAssertEqual(result["compactWidth"]?.doubleValue, 450)
        XCTAssertEqual(result["compactHeight"]?.doubleValue, 450)
        XCTAssertEqual(result["sameWindow"]?.boolValue, true)
    }

    @MainActor func testNativeDetentsResolveIndependentlyBeforeAndAfterExpansion() throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Reserved regions require iOS27.1") }
        let result = StashNativeExpansionProbe() as! [String: NSNumber]
        for key in ["restingBefore", "restingAfter", "resolvedResting", "restingDuringKeyboard"] {
            XCTAssertEqual(result[key]?.doubleValue, 450, key)
        }
        for key in ["expandedBefore", "expandedAfter", "resolvedExpanded"] {
            XCTAssertEqual(result[key]?.doubleValue, 620, key)
        }
        XCTAssertEqual(result["detentsBefore"]?.intValue, 2)
        XCTAssertEqual(result["singleBefore"]?.boolValue, false)
        for key in ["bridgeExpanded", "cappedSingle", "restoredExpanded", "keyboardOverride", "keyboardRestored"] {
            XCTAssertEqual(result[key]?.boolValue, true, key)
        }
        for key in ["zeroMaximumStaysSingle", "nonzeroMaximumRestoresDetents"] {
            XCTAssertEqual(result[key]?.boolValue, true, key)
        }
    }

    @MainActor func testNativeDragKeepsVisibleContentSafeWithoutResettingSelection() throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Reserved regions require iOS27.1") }
        let result = StashNativeExpansionProbe() as! [String: NSNumber]
        XCTAssertEqual(result["movingContentX"]?.doubleValue, 0)
        XCTAssertEqual(result["movingContentY"]?.doubleValue, 0)
        XCTAssertEqual(result["movingContentWidth"]?.doubleValue, 374)
        for key in ["delegateExpanded", "delegateRelayout", "dragPreservesSelection", "dragDefersLayout"] {
            XCTAssertEqual(result[key]?.boolValue, true, key)
        }
        for key in ["passivePreservesSelection", "explicitCollapseSelectsResting"] {
            XCTAssertEqual(result[key]?.boolValue, true, key)
        }
    }

    func testRestingNativeSheetKeepsWholeSurfaceBelowCornerOcclusion() {
        let result = StashNativeSurfaceProbe() as! [String: NSNumber]
        XCTAssertEqual(result["availableWidth"]?.doubleValue, 466)
        XCTAssertEqual(result["contentHeight"]?.doubleValue, 450)
        XCTAssertEqual(result["detentHeight"]?.doubleValue, 450)
        XCTAssertEqual(result["surfaceTop"]?.doubleValue, 186)
    }

    func testNativeGrabberAddsNoMeasuredContentReserve() {
        let result = StashNativeSurfaceProbe() as! [String: NSNumber]
        XCTAssertEqual(result["shortHeight"]?.doubleValue, 240)
        XCTAssertEqual(result["unobstructedWidth"]?.doubleValue, 466)
        XCTAssertEqual(result["blockedHeight"]?.doubleValue, 0)
    }

    @MainActor func testNativeSheetUsesDetentsForConfiguredAndMeasuredHeight() {
        let result = StashNativePaneProbe() as! [String: NSNumber]
        XCTAssertEqual(result["width"]?.doubleValue, 400)
        XCTAssertEqual(result["anchored"]?.boolValue, false)
        for key in ["initialHeight", "restingPreferredHeight", "expandedPreferredHeight"] {
            XCTAssertEqual(result[key]?.doubleValue, 0, key)
        }
        XCTAssertEqual(result["restingDetent"]?.doubleValue, 300)
        XCTAssertEqual(result["intrinsicDetent"]?.doubleValue, 120)
        XCTAssertEqual(result["expandedDetent"]?.doubleValue, 620)
    }

    @MainActor func testKeyboardUsesMaximumNativeDetentWithoutSubtractingKeyboardAgain() {
        let result = StashNativeKeyboardProbe() as! [String: NSNumber]
        XCTAssertEqual(result["resting"]?.doubleValue, 450)
        XCTAssertEqual(result["docked"]?.doubleValue, 620)
        XCTAssertEqual(result["floating"]?.doubleValue, 620)
    }

    @MainActor func testKeyboardExpandsShortNativeCardThenRestoresResting() {
        let result = StashNativeKeyboardProbe() as! [String: NSNumber]
        XCTAssertEqual(result["shortResting"]?.doubleValue, 320)
        XCTAssertEqual(result["shortKeyboard"]?.doubleValue, 620)
        XCTAssertEqual(result["restingTop"]?.doubleValue, 316)
        XCTAssertEqual(result["keyboardSelectsExpanded"]?.boolValue, true)
        XCTAssertEqual(result["preservesResting"]?.boolValue, true)
        XCTAssertEqual(result["restoresResting"]?.boolValue, true)
        XCTAssertEqual(result["restored"]?.doubleValue, 320)
    }

    @MainActor func testCompactDividerFallsBackToUsablePaneAndPreservesPlacementPolicy() throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Reserved regions require iOS27.1") }
        let result = StashCompactDividerProbe() as! [String: NSNumber]
        XCTAssertEqual(result["trailingX"]?.doubleValue, 271)
        XCTAssertEqual(result["width"]?.doubleValue, 240)
        XCTAssertEqual(result["height"]?.doubleValue, 700)
        XCTAssertEqual(result["rtlX"]?.doubleValue, 11)
        XCTAssertEqual(result["preferredX"]?.doubleValue, 11)
        XCTAssertEqual(result["statusY"]?.doubleValue, 193)
        XCTAssertEqual(result["statusWidth"]?.doubleValue, 500)
        XCTAssertEqual(result["horizontalY"]?.doubleValue, 370)
        XCTAssertEqual(result["coveredEmpty"]?.boolValue, true)
    }
}
