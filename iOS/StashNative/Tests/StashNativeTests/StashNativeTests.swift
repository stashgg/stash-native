import XCTest
import StashNative
import RegressionSupport

final class StashNativeTests: XCTestCase {
    func testV3DefaultsAndIndependentCopy() {
        XCTAssertEqual(StashNativeCard.sdkVersion(), "3.0.0")
        let card = StashNativeCardConfig()
        XCTAssertEqual(card.preferredContentWidth, 400)
        XCTAssertEqual(card.preferredContentHeight, 560)
        XCTAssertEqual(card.maximumContentHeight, 720)
        XCTAssertEqual(card.edgeMargin, 16)
        XCTAssertTrue(card.allowDismiss)
        XCTAssertTrue(card.autoClose)
        XCTAssertEqual(card.orientationPreference, .followHost)
        let copy = card.copy() as! StashNativeCardConfig
        card.preferredContentWidth = 900
        XCTAssertEqual(copy.preferredContentWidth, 400)
    }

    func testConfigurationRejectsNonfiniteAndNegativeSizes() {
        let result = StashConfigurationProbe() as! [String: NSNumber]
        XCTAssertEqual(result["width"]?.doubleValue, 400)
        XCTAssertEqual(result["height"]?.doubleValue, 560)
        XCTAssertEqual(result["maximum"]?.doubleValue, 720)
        XCTAssertEqual(result["margin"]?.doubleValue, 16)
        XCTAssertEqual(result["copiedDismiss"]?.boolValue, true)
    }

    func testDefaultCardBoundsTabletExpansionAndAllowsExplicitAvailableHeight() {
        let defaults = StashNativeCardConfig()
        func resolve(_ maximum: Double) -> [String: NSNumber] {
            StashGeometryProbe(1032, 1344, true, 0, Double(defaults.preferredContentWidth),
                Double(defaults.preferredContentHeight), maximum, Double(defaults.edgeMargin)) as! [String: NSNumber]
        }
        let bounded = resolve(Double(defaults.maximumContentHeight))
        XCTAssertEqual(bounded["width"]?.doubleValue, 400)
        XCTAssertEqual(bounded["resting"]?.doubleValue, 560)
        XCTAssertEqual(bounded["height"]?.doubleValue, 720)
        let available = resolve(0)
        XCTAssertEqual(available["height"]?.doubleValue, 1312)
        XCTAssertEqual(available["resting"]?.doubleValue, 560)
        for invalid in [Double.nan, Double.infinity, -1] {
            XCTAssertEqual(resolve(invalid)["height"]?.doubleValue, 720)
        }
    }

    func testCardFitsEveryContainerAndPreservesExpandedMeaning() {
        for width in [120.0, 320, 390, 599, 600, 768, 1366] {
            for height in [100.0, 300, 568, 844, 1024] {
                for expanded in [false, true] {
                    let result = geometry(width, height, expanded: expanded)
                    XCTAssertGreaterThanOrEqual(result["x"]!, 11)
                    XCTAssertGreaterThanOrEqual(result["y"]!, 23)
                    XCTAssertLessThanOrEqual(result["x"]! + result["width"]!, 11 + width + 0.01)
                    XCTAssertLessThanOrEqual(result["y"]! + result["height"]!, 23 + height + 0.01)
                    XCTAssertGreaterThanOrEqual(result["expanded"]!, result["resting"]!)
                    if width < 600 {
                        XCTAssertEqual(result["width"]!, width)
                        XCTAssertEqual(result["y"]! + result["height"]!, 23 + height, accuracy: 0.01)
                    } else {
                        XCTAssertLessThanOrEqual(result["width"]!, 480)
                        XCTAssertEqual(result["y"]! + result["height"]! / 2, 23 + height / 2, accuracy: 0.01)
                    }
                }
            }
        }
    }

    func testShortCardContentShrinksButExpandedIgnoresMeasurement() {
        XCTAssertEqual(geometry(390, 844, measured: 220)["resting"]!, 220)
        XCTAssertEqual(geometry(390, 844, measured: 2000)["resting"]!, 560)
        XCTAssertEqual(geometry(390, 844, expanded: true, measured: 120)["height"]!,
                       geometry(390, 844, expanded: true)["height"]!)
    }

    func testMaximumContentHeightAndExtremeMarginStayInsideBounds() {
        let capped = StashGeometryProbe(1000, 1000, true, 80, 480, 560, 320, 16) as! [String: NSNumber]
        XCTAssertEqual(capped["height"]?.doubleValue, 320)
        let tiny = StashGeometryProbe(80, 70, true, 0, 480, 560, 0, 1000) as! [String: NSNumber]
        XCTAssertLessThanOrEqual(tiny["height"]!.doubleValue, 70)
        XCTAssertGreaterThanOrEqual(tiny["height"]!.doubleValue, 0)
    }

    func testReservedRegionsChooseFocusedPaneThenTrailingOrLowerTie() {
        let result = StashReservedRegionProbe() as! [String: NSNumber]
        XCTAssertEqual(result["trailingX"]?.doubleValue, 510)
        XCTAssertEqual(result["rtlX"]?.doubleValue, 0)
        XCTAssertEqual(result["focusedX"]?.doubleValue, 0)
        XCTAssertEqual(result["lowerY"]?.doubleValue, 410)
    }

    func testHeightHintsRequireActiveDocumentAndMatchingUnzoomedViewport() {
        let valid: [String: Any] = ["height": 320, "viewportWidth": 390, "scale": 1, "documentId": "current"]
        XCTAssertTrue(StashHeightHintProbe(valid, "current", 390, 1, 390))
        XCTAssertFalse(StashHeightHintProbe(valid, "old", 390, 1, 390))
        XCTAssertFalse(StashHeightHintProbe(valid, "current", 768, 1, 390))
        XCTAssertFalse(StashHeightHintProbe(valid, "current", 390, 2, 390))
        for invalid in [Double.nan, Double.infinity, -1, 0] {
            var payload = valid
            payload["height"] = invalid
            XCTAssertFalse(StashHeightHintProbe(payload, "current", 390, 1, 390))
        }
        var wrongType = valid
        wrongType["height"] = "320"
        XCTAssertFalse(StashHeightHintProbe(wrongType, "current", 390, 1, 390))
    }

    func testAutomaticMeasurementResetRequiresMatchingDocumentAndViewport() {
        let reset: [String: Any] = ["reset": true, "viewportWidth": 390, "scale": 1, "documentId": "current"]
        XCTAssertTrue(StashHeightHintProbe(reset, "current", 390, 1, 390))
        XCTAssertFalse(StashHeightHintProbe(reset, "old", 390, 1, 390))
        XCTAssertFalse(StashHeightHintProbe(reset, "current", 480, 1, 390))
        var wrongType = reset
        wrongType["reset"] = "true"
        XCTAssertFalse(StashHeightHintProbe(wrongType, "current", 390, 1, 390))
    }

    func testObserverHasExplicitIntrinsicRootAndNoScrollHeightFeedback() {
        let source = StashMeasurementSource() ?? ""
        XCTAssertTrue(source.contains("[data-stash-content]"))
        XCTAssertTrue(source.contains("ResizeObserver"))
        XCTAssertFalse(source.contains("scrollHeight"))
        XCTAssertTrue(source.contains("documentId"))
    }

    func testURLNormalizationPreservesSignedQueryBytes() {
        let result = StashURLProbe() as! [String: String]
        XCTAssertEqual(result["bare"], "https://example.invalid/path")
        XCTAssertEqual(result["javascript"], "")
        XCTAssertTrue(result["themed"]!.contains("token=a%2Bb%26c"))
        XCTAssertTrue(result["themed"]!.hasSuffix("#section"))
    }

    private func geometry(_ width: Double, _ height: Double, expanded: Bool = false,
                          measured: Double = 0) -> [String: Double] {
        let result = StashGeometryProbe(width, height, expanded, measured, 480, 560, 0, 16)
        return (result as! [String: NSNumber]).mapValues(\.doubleValue)
    }
}
