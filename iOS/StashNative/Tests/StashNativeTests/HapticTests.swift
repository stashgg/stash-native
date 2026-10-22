import XCTest
import WebKit
import RegressionSupport

final class HapticTests: XCTestCase {
    @MainActor func testRealBridgeConfirmationFrameFilteringAndLifecycle() async throws {
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = previous?.windowScene.map(UIWindow.init(windowScene:))
            ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previous?.makeKey()
        }
        let fixture = try XCTUnwrap(StashHapticFixture(presenter))
        defer { StashEndHapticFixture(fixture) }
        let web = try XCTUnwrap(fixture["web"] as? WKWebView)
        web.loadHTMLString("<html><body>Haptics<iframe srcdoc='<p>iframe</p>'></iframe></body></html>",
                           baseURL: URL(string: "https://checkout.invalid"))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !web.isLoading && web.url != nil
        }, object: web)
        loaded.expectationDescription = "Haptic bridge fixture loaded"
        guard await WebViewFixture.waitForLoad(loaded) else { return }
        XCTAssertFalse(web.isLoading)
        let returnsUndefined = try await evaluate(web, """
            const result = stash_sdk.triggerHaptic();
            await stash_sdk.getTelemetry();
            return result === undefined;
            """)
        XCTAssertEqual(returnsUndefined as? Bool, true)
        let events = try XCTUnwrap(fixture["events"] as? [[String: Bool]])
        XCTAssertEqual(events, [["success": true, "mainThread": true]])

        _ = try await evaluate(web, """
            document.querySelector('iframe').contentWindow.webkit.messageHandlers.stashTriggerHaptic.postMessage({});
            await stash_sdk.getTelemetry();
            return true;
            """)
        XCTAssertEqual((fixture["events"] as? NSArray)?.count, 1, "Subframes cannot request iOS feedback")

        // 'long' and 1 select the long haptic; anything else stays the short confirmation.
        _ = try await evaluate(web, """
            stash_sdk.triggerHaptic('long');
            stash_sdk.triggerHaptic(1);
            stash_sdk.triggerHaptic('loud');
            await stash_sdk.getTelemetry();
            return true;
            """)
        let typed = try XCTUnwrap(fixture["events"] as? [[String: Bool]])
        XCTAssertEqual(Array(typed.dropFirst()), [["long": true, "mainThread": true], ["long": true, "mainThread": true],
                                                  ["success": true, "mainThread": true]])
        let session = try XCTUnwrap(fixture["session"] as? NSObject)
        let aliases = try await evaluate(web, """
            return stash_sdk.lock === stash_sdk.onPurchaseProcessing &&
                stash_sdk.unlock === stash_sdk.onProcessingCompleted &&
                typeof stash_sdk.externalBrowser === 'function' && typeof stash_sdk.openExternalBrowser === 'function';
            """)
        XCTAssertEqual(aliases as? Bool, true)
        _ = try await evaluate(web, "stash_sdk.lock(); await stash_sdk.getTelemetry(); return true;")
        XCTAssertEqual(session.value(forKey: "processing") as? Bool, true)
        _ = try await evaluate(web, "stash_sdk.unlock(); await stash_sdk.getTelemetry(); return true;")
        XCTAssertEqual(session.value(forKey: "processing") as? Bool, false)
        let lifecycle = try XCTUnwrap(StashHapticLifecycleProbe(fixture) as? [String: Bool])
        for (name, passed) in lifecycle { XCTAssertTrue(passed, name) }
    }

    @MainActor private func evaluate(_ web: WKWebView, _ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                continuation.resume(with: result)
            }
        }
    }
}
