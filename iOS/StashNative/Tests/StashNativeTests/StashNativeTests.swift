import XCTest
@testable import StashNative

final class StashNativeTests: XCTestCase {

    // -- Version --

    func testSdkVersionIsNonEmpty() {
        let v = StashNativeCard.sdkVersion()
        XCTAssertFalse(v.isEmpty)
    }

    func testSdkVersionContainsDot() {
        let v = StashNativeCard.sdkVersion()
        XCTAssertTrue(v.contains("."), "Version should be semver-like")
    }

    // -- Singleton --

    func testSharedInstanceReturnsSameObject() {
        let a = StashNativeCard.sharedInstance()
        let b = StashNativeCard.sharedInstance()
        XCTAssertTrue(a === b)
    }

    // -- CardConfig defaults --

    func testCardConfigDefaults() {
        let cfg = StashNativeCardConfig()
        XCTAssertFalse(cfg.forcePortrait)
        XCTAssertEqual(cfg.cardHeightRatioPortrait, 0.68, accuracy: 0.001)
        XCTAssertEqual(cfg.cardWidthRatioLandscape, 0.7, accuracy: 0.01)
        XCTAssertEqual(cfg.cardHeightRatioLandscape, 0.9, accuracy: 0.01)
        XCTAssertEqual(cfg.tabletWidthRatioPortrait, 0.4, accuracy: 0.01)
        XCTAssertEqual(cfg.tabletHeightRatioPortrait, 0.5, accuracy: 0.01)
        XCTAssertEqual(cfg.tabletWidthRatioLandscape, 0.3, accuracy: 0.01)
        XCTAssertEqual(cfg.tabletHeightRatioLandscape, 0.6, accuracy: 0.01)
        XCTAssertNil(cfg.backgroundColor)
    }

    // -- ModalConfig defaults --

    func testModalConfigDefaults() {
        let cfg = StashNativeModalConfig()
        XCTAssertTrue(cfg.allowDismiss)
        XCTAssertEqual(cfg.phoneWidthRatioPortrait, 0.80, accuracy: 0.001)
        XCTAssertEqual(cfg.phoneHeightRatioPortrait, 0.50, accuracy: 0.001)
        XCTAssertEqual(cfg.phoneWidthRatioLandscape, 0.50, accuracy: 0.001)
        XCTAssertEqual(cfg.phoneHeightRatioLandscape, 0.80, accuracy: 0.001)
        XCTAssertEqual(cfg.tabletWidthRatioPortrait, 0.40, accuracy: 0.001)
        XCTAssertEqual(cfg.tabletHeightRatioPortrait, 0.30, accuracy: 0.001)
        XCTAssertEqual(cfg.tabletWidthRatioLandscape, 0.30, accuracy: 0.001)
        XCTAssertEqual(cfg.tabletHeightRatioLandscape, 0.40, accuracy: 0.001)
        XCTAssertNil(cfg.backgroundColor)
    }

    func testModalConfigCustomInit() {
        let cfg = StashNativeModalConfig(
            phoneWidthPortrait: 0.5,
            phoneHeightPortrait: 0.6,
            phoneWidthLandscape: 0.7,
            phoneHeightLandscape: 0.8,
            tabletWidthPortrait: 0.3,
            tabletHeightPortrait: 0.4,
            tabletWidthLandscape: 0.2,
            tabletHeightLandscape: 0.9,
            allowDismiss: false
        )
        XCTAssertFalse(cfg.allowDismiss)
        XCTAssertEqual(cfg.phoneWidthRatioPortrait, 0.5, accuracy: 0.001)
        XCTAssertEqual(cfg.phoneHeightRatioPortrait, 0.6, accuracy: 0.001)
        XCTAssertEqual(cfg.tabletHeightRatioLandscape, 0.9, accuracy: 0.001)
    }

    // -- PopupSizeConfig --

    func testPopupSizeConfigDefaults() {
        let cfg = StashNativePopupSizeConfig()
        XCTAssertGreaterThan(cfg.portraitWidthMultiplier, 0.0)
        XCTAssertGreaterThan(cfg.portraitHeightMultiplier, 0.0)
        XCTAssertGreaterThan(cfg.landscapeWidthMultiplier, 0.0)
        XCTAssertGreaterThan(cfg.landscapeHeightMultiplier, 0.0)
    }

    func testPopupSizeConfigCustomInit() {
        let cfg = StashNativePopupSizeConfig(
            portraitWidth: 1.0, portraitHeight: 1.5,
            landscapeWidth: 1.2, landscapeHeight: 1.1
        )
        XCTAssertEqual(cfg.portraitWidthMultiplier, 1.0, accuracy: 0.001)
        XCTAssertEqual(cfg.portraitHeightMultiplier, 1.5, accuracy: 0.001)
        XCTAssertEqual(cfg.landscapeWidthMultiplier, 1.2, accuracy: 0.001)
        XCTAssertEqual(cfg.landscapeHeightMultiplier, 1.1, accuracy: 0.001)
    }

    // -- State queries --

    func testInitialStateNotProcessing() {
        let card = StashNativeCard.sharedInstance()
        XCTAssertFalse(card.isPurchaseProcessing)
    }

    // -- Nil/empty URL safety --

    func testOpenCardNilUrlDoesNotCrash() {
        StashNativeCard.sharedInstance().openCard(withURL: "", config: nil)
    }

    func testOpenModalNilUrlDoesNotCrash() {
        StashNativeCard.sharedInstance().openModal(withURL: "", config: nil)
    }

    func testOpenBrowserEmptyUrlDoesNotCrash() {
        StashNativeCard.sharedInstance().openBrowser(withURL: "")
    }
}
