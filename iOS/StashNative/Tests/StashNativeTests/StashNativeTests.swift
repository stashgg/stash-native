import XCTest
import StashNative
import RegressionSupport

final class StashNativeTests: XCTestCase {
    func testV3DefaultsAndIndependentCopy() {
        XCTAssertEqual(StashNative.getVersion(), "3.0.0")
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
            StashGeometryProbe(1032, 1344, true, Double(defaults.preferredContentWidth),
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

    func testRestingHeightIsPreferredHeightLimitedByAvailableSpace() {
        XCTAssertEqual(geometry(390, 844)["resting"]!, 560)
        XCTAssertEqual(geometry(390, 844)["height"]!, 560)
        XCTAssertEqual(geometry(390, 400)["resting"]!, 384)
        XCTAssertEqual(geometry(390, 844, expanded: true)["height"]!, 828)
    }

    func testMaximumContentHeightAndExtremeMarginStayInsideBounds() {
        let capped = StashGeometryProbe(1000, 1000, true, 480, 560, 320, 16) as! [String: NSNumber]
        XCTAssertEqual(capped["height"]?.doubleValue, 320)
        let tiny = StashGeometryProbe(80, 70, true, 480, 560, 0, 1000) as! [String: NSNumber]
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

    func testURLNormalizationPreservesSignedQueryBytes() {
        let result = StashURLProbe() as! [String: String]
        XCTAssertEqual(result["bare"], "https://example.invalid/path")
        XCTAssertEqual(result["javascript"], "")
        XCTAssertTrue(result["themed"]!.contains("token=a%2Bb%26c"))
        XCTAssertTrue(result["themed"]!.hasSuffix("#section"))
    }

    // Same vectors as Android's UrlNormalizationTest.
    func testURLNormalizationMatchesAndroidAcceptanceRule() {
        XCTAssertNil(StashNormalizedURLProbe(nil))
        XCTAssertNil(StashNormalizedURLProbe(""))
        XCTAssertNil(StashNormalizedURLProbe("   "))
        for blocked in ["javascript:alert(1)", "JAVASCRIPT:void(0)", "data:text/html,<h1>x</h1>", "file:///etc/passwd",
                        "mailto:a@example.invalid", "ftp://example.invalid", "https://"] {
            XCTAssertNil(StashNormalizedURLProbe(blocked), blocked)
        }
        XCTAssertEqual(StashNormalizedURLProbe(" example.invalid/path "), "https://example.invalid/path")
        XCTAssertEqual(StashNormalizedURLProbe("HTTPS://example.invalid/path"), "https://example.invalid/path")
        XCTAssertEqual(StashNormalizedURLProbe("localhost:8080/a"), "https://localhost:8080/a")
        XCTAssertEqual(StashNormalizedURLProbe(" HTTPS://Example.invalid/pay?x=1#f "), "https://Example.invalid/pay?x=1#f")
        XCTAssertEqual(StashNormalizedURLProbe("HTTP://example.invalid"), "http://example.invalid")
    }

    private func geometry(_ width: Double, _ height: Double, expanded: Bool = false) -> [String: Double] {
        let result = StashGeometryProbe(width, height, expanded, 480, 560, 0, 16)
        return (result as! [String: NSNumber]).mapValues(\.doubleValue)
    }
}
