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
