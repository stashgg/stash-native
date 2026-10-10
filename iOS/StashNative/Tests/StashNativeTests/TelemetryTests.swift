import XCTest
import WebKit
import RegressionSupport

final class TelemetryTests: XCTestCase {
    @MainActor func testSchemaNavigationTimingAndSessionIsolation() throws {
        let probe = try XCTUnwrap(StashTelemetryLifecycleProbe() as? [String: Any])
        let initial = try XCTUnwrap(probe["initial"] as? [String: Any])
        XCTAssertEqual(Set(initial.keys), Set(["schemaVersion", "platform", "hardware", "os", "app",
                                              "runtime", "presentation", "power", "timing"]))
        XCTAssertEqual(initial["schemaVersion"] as? Int, 1)
        XCTAssertEqual(initial["platform"] as? String, "ios")
        let groups: [String: [String]] = [
            "hardware": ["manufacturer", "model", "memoryBytes"],
            "os": ["version", "apiLevel"],
            "app": ["id", "version", "build", "targetSdkVersion"],
            "runtime": ["sdkVersion", "webViewEngine", "webViewPackage", "webViewVersion"],
            "presentation": ["state", "keyboardVisible", "orientationPreference", "portraitApplied",
                             "window", "card", "safeAreaInsets", "multiWindow", "fold"],
            "power": ["lowPowerMode", "thermalState"],
            "timing": ["firstCallAt", "pageLoadStartedAt", "pageLoadedAt", "pageLoadTimeMs"]
        ]
        for (group, keys) in groups {
            let value = try XCTUnwrap(initial[group] as? [String: Any])
            XCTAssertEqual(Set(value.keys), Set(keys), group)
        }
        let timing = try XCTUnwrap(initial["timing"] as? [String: Any])
        XCTAssertTrue(timing["pageLoadedAt"] is NSNull)
        XCTAssertTrue(timing["pageLoadTimeMs"] is NSNull)
        let loaded = try XCTUnwrap((probe["loaded"] as? [String: Any])?["timing"] as? [String: Any])
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(loaded["pageLoadTimeMs"] as? Int), 125)
        let next = try XCTUnwrap((probe["next"] as? [String: Any])?["timing"] as? [String: Any])
        XCTAssertTrue(next["pageLoadedAt"] is NSNull, "Stale completion must not finish a newer load")
        XCTAssertEqual(next["firstCallAt"] as? Int, timing["firstCallAt"] as? Int)
        let changed = try XCTUnwrap((probe["finished"] as? [String: Any])?["presentation"] as? [String: Any])
        XCTAssertEqual(changed["state"] as? String, "expanded")
        XCTAssertEqual(changed["keyboardVisible"] as? Bool, true)
        for name in ["duplicatePreserved", "independent", "cleaned"] {
            XCTAssertEqual(probe[name] as? Bool, true, name)
        }
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: initial))
    }

    @MainActor func testRealWebViewPromiseConcurrentCallsAndIframeRejection() async throws {
        let fixture = try XCTUnwrap(StashTelemetryFixture())
        defer { StashEndTelemetryFixture(fixture) }
        let web = try XCTUnwrap(fixture["web"] as? WKWebView)
        web.loadHTMLString("<html><body>Telemetry<iframe srcdoc='<p>iframe</p>'></iframe></body></html>",
                           baseURL: URL(string: "https://checkout.invalid"))
        try await waitForPage(web)
        let results = try await evaluate(web,
            "return await Promise.all([stash_sdk.getTelemetry(),stash_sdk.getTelemetry()]);") as! [[String: Any]]
        let first = try XCTUnwrap(results[0]["timing"] as? [String: Any])
        let second = try XCTUnwrap(results[1]["timing"] as? [String: Any])
        XCTAssertEqual(first["firstCallAt"] as? Int, second["firstCallAt"] as? Int)
        XCTAssertNotNil(first["pageLoadedAt"] as? Int)
        XCTAssertNotNil(first["pageLoadTimeMs"] as? Int)
        let blocked = try await evaluate(web, """
            try {
              await document.querySelector('iframe').contentWindow.webkit.messageHandlers.stashTelemetry.postMessage({});
              return false;
            } catch (error) { return true; }
            """)
        XCTAssertEqual(blocked as? Bool, true)
        web.loadHTMLString("<html><body>Next document</body></html>", baseURL: URL(string: "https://next.invalid"))
        try await waitForPage(web)
        let next = try await evaluate(web, "return await stash_sdk.getTelemetry();") as! [String: Any]
        let nextTiming = try XCTUnwrap(next["timing"] as? [String: Any])
        XCTAssertEqual(nextTiming["firstCallAt"] as? Int, first["firstCallAt"] as? Int)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(nextTiming["pageLoadStartedAt"] as? Int),
                                   try XCTUnwrap(first["pageLoadedAt"] as? Int))
    }

    @MainActor private func evaluate(_ web: WKWebView, _ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                continuation.resume(with: result)
            }
        }
    }

    @MainActor private func waitForPage(_ web: WKWebView) async throws {
        for _ in 0..<100 {
            if !web.isLoading, web.url != nil {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Telemetry fixture did not finish loading")
    }
}
