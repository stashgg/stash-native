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
        guard await waitForPage(web) else { return }
        let results = try await evaluate(web,
            "return await Promise.all([stash_sdk.getTelemetry(),stash_sdk.getTelemetry()]);") as! [[String: Any]]
        let first = try XCTUnwrap(results[0]["timing"] as? [String: Any])
        let second = try XCTUnwrap(results[1]["timing"] as? [String: Any])
        XCTAssertEqual(first["firstCallAt"] as? Int, second["firstCallAt"] as? Int)
        XCTAssertNotNil(first["pageLoadedAt"] as? Int)
        XCTAssertNotNil(first["pageLoadTimeMs"] as? Int)
        // NSNumber 1 would satisfy `as? Bool`; the page must see JSON booleans as on Android.
        let types = try await evaluate(web, """
            const value = await stash_sdk.getTelemetry();
            return [typeof value.presentation.keyboardVisible, typeof value.presentation.portraitApplied,
                    typeof value.power.lowPowerMode];
            """) as? [String]
        XCTAssertEqual(types, ["boolean", "boolean", "boolean"])
        let blocked = try await evaluate(web, """
            try {
              await document.querySelector('iframe').contentWindow.webkit.messageHandlers.stashTelemetry.postMessage({});
              return false;
            } catch (error) { return true; }
            """)
        XCTAssertEqual(blocked as? Bool, true)
        web.loadHTMLString("<html><body>Next document</body></html>", baseURL: URL(string: "https://next.invalid"))
        guard await waitForPage(web) else { return }
        let next = try await evaluate(web, "return await stash_sdk.getTelemetry();") as! [String: Any]
        let nextTiming = try XCTUnwrap(next["timing"] as? [String: Any])
        XCTAssertEqual(nextTiming["firstCallAt"] as? Int, first["firstCallAt"] as? Int)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(nextTiming["pageLoadStartedAt"] as? Int),
                                   try XCTUnwrap(first["pageLoadedAt"] as? Int))
    }

    // Android's TelemetryTest asserts the same paths; pages see one key order on both platforms.
    private static let sharedKeyOrder = [
        "schemaVersion", "platform",
        "hardware", "hardware.manufacturer", "hardware.model", "hardware.memoryBytes",
        "os", "os.version", "os.apiLevel",
        "app", "app.id", "app.version", "app.build", "app.targetSdkVersion",
        "runtime", "runtime.sdkVersion", "runtime.webViewEngine", "runtime.webViewPackage", "runtime.webViewVersion",
        "presentation", "presentation.state", "presentation.keyboardVisible",
        "presentation.window", "presentation.window.width", "presentation.window.height",
        "presentation.card", "presentation.card.width", "presentation.card.height",
        "presentation.safeAreaInsets", "presentation.safeAreaInsets.top", "presentation.safeAreaInsets.right",
        "presentation.safeAreaInsets.bottom", "presentation.safeAreaInsets.left",
        "presentation.fold", "presentation.fold.state", "presentation.fold.orientation",
        "presentation.fold.separating",
        "presentation.orientationPreference", "presentation.portraitApplied", "presentation.multiWindow",
        "power", "power.lowPowerMode", "power.thermalState",
        "timing", "timing.firstCallAt", "timing.pageLoadStartedAt", "timing.pageLoadedAt", "timing.pageLoadTimeMs"
    ]

    @MainActor func testEveryCallReturnsKeysInTheOrderSharedWithAndroid() async throws {
        let fixture = try XCTUnwrap(StashTelemetryFixture())
        defer { StashEndTelemetryFixture(fixture) }
        let web = try XCTUnwrap(fixture["web"] as? WKWebView)
        web.loadHTMLString("<html><body>Telemetry order</body></html>", baseURL: URL(string: "https://checkout.invalid"))
        guard await waitForPage(web) else { return }
        let calls = try await evaluate(web, """
            const paths = (value, prefix) => Object.keys(value).flatMap(key => {
              const child = value[key], path = prefix ? prefix + '.' + key : key;
              return child && typeof child === 'object' ? [path, ...paths(child, path)] : [path];
            });
            const values = await Promise.all([1, 2, 3, 4, 5].map(() => stash_sdk.getTelemetry()));
            return values.map(value => paths(value, ''));
            """) as! [[String]]
        XCTAssertEqual(calls.count, 5)
        for paths in calls { XCTAssertEqual(paths, Self.sharedKeyOrder) }
    }

    @MainActor private func evaluate(_ web: WKWebView, _ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                continuation.resume(with: result)
            }
        }
    }

    @MainActor private func waitForPage(_ web: WKWebView, file: StaticString = #filePath,
                                      line: UInt = #line) async -> Bool {
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !web.isLoading && web.url != nil
        }, object: web)
        loaded.expectationDescription = "Telemetry fixture loaded"
        return await WebViewFixture.waitForLoad(loaded, file:file, line:line)
    }
}
