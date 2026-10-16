import XCTest
import RegressionSupport
import StashNative

final class CodeLinkTests: XCTestCase {
    @MainActor func testPreviewDetachesAfterQueuedCaptureStops() async throws {
        let value = await withCheckedContinuation { continuation in
            StashCodeLinkCaptureOrderingProbe { continuation.resume(returning: $0) }
        }
        let result = try XCTUnwrap(value as? [String: Bool])
        for key in ["stopEntered", "disposalDeferred", "stoppedBeforeDetach", "finalStopOnly", "detachedOnMain"] {
            XCTAssertEqual(result[key], true, key)
        }
    }

    @MainActor func testDefaultAndEmptyTextKeepExistingCopy() throws {
        let config = StashNativeCodeLinkConfig()
        XCTAssertTrue(config.showCallout)
        config.headerText = ""
        config.calloutTitle = ""
        config.calloutSubtitle = ""
        config.cameraUnavailableText = ""
        config.connectedText = ""
        for options in [nil, config] {
            let result = try XCTUnwrap(StashCodeLinkConfiguredLayoutProbe(
                CGSize(width: 400, height: 560), options) as? [String: Any])
            XCTAssertEqual(result["headerText"] as? String, "Scan QR code")
            XCTAssertEqual(result["calloutTitle"] as? String, "Scan the webshop code")
            XCTAssertEqual(result["calloutSubtitle"] as? String, "Keep the QR code centered inside the frame.")
            XCTAssertEqual(result["showCallout"] as? Bool, true)
            XCTAssertEqual(result["spinnerOnly"] as? Bool, true)
            XCTAssertEqual(result["cameraUnavailableText"] as? String, "Camera unavailable")
            XCTAssertEqual(result["unavailableMessageHidden"] as? Bool, true)
            XCTAssertEqual(result["connectedText"] as? String, "Connected")
        }
    }

    @MainActor func testCustomCopyWrapsAndHiddenCalloutReclaimsSpace() throws {
        let config = StashNativeCodeLinkConfig()
        config.headerText = "Propojte svůj účet"
        config.calloutTitle = "Naskenujte kód obchodu"
        config.calloutSubtitle = "Umístěte QR kód doprostřed rámečku.\nاستخدم رمز المتجر"
        config.cameraUnavailableText = "Kamera není dostupná"
        config.connectedText = "Připojeno"
        let copy = try XCTUnwrap(config.copy() as? StashNativeCodeLinkConfig)
        config.headerText = "changed"
        config.cameraUnavailableText = nil
        config.connectedText = nil
        XCTAssertEqual(copy.headerText, "Propojte svůj účet")
        XCTAssertEqual(copy.cameraUnavailableText, "Kamera není dostupná")
        XCTAssertEqual(copy.connectedText, "Připojeno")
        for size in [CGSize(width: 320, height: 480), CGSize(width: 400, height: 330),
                     CGSize(width: 400, height: 560), CGSize(width: 660, height: 330)] {
            copy.showCallout = true
            let shown = try XCTUnwrap(StashCodeLinkConfiguredLayoutProbe(size, copy) as? [String: Any])
            XCTAssertEqual(shown["headerText"] as? String, copy.headerText)
            XCTAssertEqual(shown["calloutTitle"] as? String, copy.calloutTitle)
            XCTAssertEqual(shown["calloutSubtitle"] as? String, copy.calloutSubtitle)
            XCTAssertEqual(shown["cameraUnavailableText"] as? String, copy.cameraUnavailableText)
            XCTAssertEqual(shown["unavailableMessageHidden"] as? Bool, true)
            XCTAssertEqual(shown["connectedText"] as? String, copy.connectedText)
            XCTAssertEqual(shown["controlsSeparate"] as? Bool, true, "\(size)")
            XCTAssertEqual(shown["bounded"] as? Bool, true, "\(size)")
            XCTAssertEqual(shown["snapshot"] as? Bool, true)
            copy.showCallout = false
            let hidden = try XCTUnwrap(StashCodeLinkConfiguredLayoutProbe(size, copy) as? [String: Any])
            XCTAssertEqual(hidden["showCallout"] as? Bool, false)
            XCTAssertEqual(hidden["controlsSeparate"] as? Bool, true)
            XCTAssertEqual(hidden["bounded"] as? Bool, true)
            XCTAssertEqual(hidden["calloutTitle"] as? String, "")
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(hidden["frameWidth"] as? Double),
                                       try XCTUnwrap(shown["frameWidth"] as? Double))
        }
    }

    @MainActor func testDetectionDismissalCancellationAndErrorCallbacks() async throws {
        let value = await withCheckedContinuation { continuation in
            StashCodeLinkLifecycleProbe { continuation.resume(returning: $0) }
        }
        let result = try XCTUnwrap(value as? [String: Bool])
        for key in ["errorKeepsCard", "emptyIgnored", "waitsForConfirmation", "waitsForDismissal", "scannedOnce",
                    "closedBeforeCallback", "stopped", "cancelledOnce", "resetSilent"] {
            XCTAssertEqual(result[key], true, key)
        }
    }

    @MainActor func testDismissAndResetDuringConfirmationCancelPendingScan() async throws {
        for reset in [false, true] {
            let value = await withCheckedContinuation { continuation in
                StashCodeLinkInterruptedConfirmationProbe(reset) { continuation.resume(returning: $0) }
            }
            let result = try XCTUnwrap(value as? [String: Bool])
            for key in ["noScanCallback", "dismissalsCorrect", "stopped", "replacementUntouched"] {
                XCTAssertEqual(result[key], true, "\(key), reset=\(reset)")
            }
        }
    }

    @MainActor func testScannerFrameStaysCenteredAndSeparateFromControls() throws {
        for size in [CGSize(width: 320, height: 400), CGSize(width: 375, height: 560),
                     CGSize(width: 402, height: 720), CGSize(width: 400, height: 560),
                     CGSize(width: 400, height: 330)] {
            let result = try XCTUnwrap(StashCodeLinkLayoutProbe(size) as? [String: Any])
            XCTAssertEqual(result["bounded"] as? Bool, true, "\(size)")
            XCTAssertEqual(result["controlsSeparate"] as? Bool, true, "\(size)")
            let width = try XCTUnwrap(result["frameWidth"] as? Double)
            XCTAssertGreaterThan(width, 90)
            XCTAssertEqual(result["frameHeight"] as? Double, width)
            XCTAssertEqual(result["centerX"] as? Double, Double(size.width / 2))
            XCTAssertEqual(result["closeTargetWidth"] as? Double, 44)
            XCTAssertEqual(result["closeTargetHeight"] as? Double, 44)
        }
    }
}
