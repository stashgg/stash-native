import XCTest
import RegressionSupport

final class CodeLinkTests: XCTestCase {
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
