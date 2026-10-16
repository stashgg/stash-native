import XCTest
import WebKit
import RegressionSupport

final class LoadingPresentationTests: XCTestCase {
    @MainActor func testLoadingSurfaceConcealsPagePaintUntilReveal() throws {
        let result = try XCTUnwrap(StashLoadingCoverBackgroundProbe())
        XCTAssertEqual(result.count, 4)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }

    @MainActor func testCheckoutReadinessWaitsForVisiblePlaceholdersWhileWebViewIsTransparent() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 560))
        let (window, previous) = host(web)
        defer { web.stopLoading(); window.isHidden = true; previous?.makeKey() }
        web.alpha = 0
        let source = try XCTUnwrap(StashInitialContentReadinessSource())
        let skeleton = "<div class='animate-skeletonOpacityFluctuation' style='width:200px;height:80px'></div>"
        for address in ["https://checkout.stash.gg/pay", "https://checkout.stashstaging.com/pay"] {
            try await load(web, address)
            for finished in [false, true] {
                for (style, expected) in [("", false), ("display:none", true), ("opacity:0", true),
                                           ("position:absolute;top:10000px", true)] {
                    let value = try await evaluate(web,
                        "document.body.innerHTML = '<section style=\"' + style + '\">' + skeleton + '</section><button>Pay</button>';\n" + source,
                        ["style": style, "skeleton": skeleton, "finished": finished])
                    XCTAssertEqual(value as? Bool, expected, "\(address) \(style) finished=\(finished)")
                }
            }
            let latePlaceholder = "document.body.innerHTML = '<button>Pay</button>';\n" +
                "requestAnimationFrame(() => document.body.insertAdjacentHTML('afterbegin', skeleton));\n" + source
            let late = try await evaluate(web, latePlaceholder, ["skeleton": skeleton, "finished": true])
            XCTAssertEqual(late as? Bool, false)
            let ready = try await evaluate(web, "document.body.innerHTML = '<button>Pay</button>';\n" + source,
                                           ["finished": true])
            XCTAssertEqual(ready as? Bool, true)
        }
        try await load(web, "https://custom.invalid/pay")
        let generic = try await evaluate(web, "document.body.innerHTML = skeleton;\n" + source,
                                         ["skeleton": skeleton, "finished": true])
        XCTAssertEqual(generic as? Bool, true)
    }

    @MainActor func testCheckoutThemeReadinessUsesOnlyCurrentExactOriginAndOneValidTheme() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 560))
        let (window, previous) = host(web)
        defer { web.stopLoading(); window.isHidden = true; previous?.makeKey() }
        let scoped = ["https://checkout.stash.gg/pay?theme=dark", "https://checkout.stashstaging.com/pay?theme=light"]
        for address in scoped {
            let expected = address.hasSuffix("dark") ? "dark" : "light"
            let opposite = expected == "dark" ? "light" : "dark"
            try await load(web, address)
            let actualURL = try await evaluate(web, "return document.URL", [:])
            XCTAssertEqual(actualURL as? String, address)
            for finished in [false, true] {
                for marker in ["", opposite] {
                    let value = try await evaluate(web,
                        "document.documentElement.dataset.colorScheme = marker;\n" + StashInitialContentReadinessSource(),
                        ["marker": marker, "finished": finished])
                    XCTAssertEqual(value as? Bool, false, "\(address) marker=\(marker) finished=\(finished)")
                }
                let value = try await evaluate(web,
                    "document.documentElement.dataset.colorScheme = marker;\n" + StashInitialContentReadinessSource(),
                    ["marker": expected, "finished": finished])
                XCTAssertEqual(value as? Bool, true, "\(address) matching theme")
            }
        }
        let generic = [
            "https://custom.invalid/pay?theme=dark", "https://checkout.stash.gg.example.com/pay?theme=dark",
            "https://checkout.stashstaging.com.example.com/pay?theme=dark", "http://checkout.stash.gg/pay?theme=dark",
            "https://checkout.stash.gg@custom.invalid/pay?theme=dark", "https://user@checkout.stash.gg/pay?theme=dark",
            "https://checkout.stash.gg:444/pay?theme=dark", "https://checkout.stash.gg/pay",
            "https://checkout.stash.gg/pay?theme=", "https://checkout.stash.gg/pay?theme=system",
            "https://checkout.stash.gg/pay?theme=DARK", "https://checkout.stash.gg/pay?theme=dark&theme=light",
            "https://checkout.stash.gg/pay?theme=dark&theme=dark"
        ]
        for address in generic {
            try await load(web, address)
            for finished in [false, true] {
                let value = try await evaluate(web, StashInitialContentReadinessSource(), ["finished": finished])
                XCTAssertEqual(value as? Bool, true, "\(address) retains generic readiness")
            }
        }
    }

    @MainActor func testCheckoutThemeReadinessRechecksAfterPaintAndUsesLiveDocument() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 560))
        let (window, previous) = host(web)
        defer { web.stopLoading(); window.isHidden = true; previous?.makeKey() }
        try await load(web, "https://checkout.stash.gg/pay?theme=dark")
        let source = try XCTUnwrap(StashInitialContentReadinessSource())
        let late = try await evaluate(web,
            "document.documentElement.dataset.colorScheme = 'light';\n" + source, ["finished": true])
        XCTAssertEqual(late as? Bool, false)
        let applied = try await evaluate(web,
            "document.documentElement.dataset.colorScheme = 'dark';\n" + source, ["finished": true])
        XCTAssertEqual(applied as? Bool, true)
        let changed = "document.documentElement.dataset.colorScheme = 'dark';\n" +
            "window.__readinessFrames = 0;\n" +
            "const original = requestAnimationFrame; window.requestAnimationFrame = callback => original(time => {\n" +
            " window.__readinessFrames++; document.documentElement.dataset.colorScheme = 'light'; callback(time); });\n" +
            "try {\n" + source + "\n} finally { window.requestAnimationFrame = original; }"
        let changedResult = try await evaluate(web, changed, ["finished": true])
        XCTAssertEqual(changedResult as? Bool, false)
        let frames = try await evaluate(web, "return window.__readinessFrames", [:])
        XCTAssertEqual((frames as? NSNumber)?.intValue, 2)
        try await load(web, "https://custom.invalid/redirected?theme=dark")
        let redirected = try await evaluate(web, source, ["finished": true])
        XCTAssertEqual(redirected as? Bool, true)
    }

    @MainActor private func host(_ web: WKWebView) -> (UIWindow, UIWindow?) {
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = previous?.windowScene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: web.frame)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.addSubview(web)
        return (window, previous)
    }

    @MainActor private func load(_ web: WKWebView, _ address: String) async throws {
        let loaded = expectation(description: "readiness fixture loaded")
        let navigation = LoadingNavigation { loaded.fulfill() }
        web.navigationDelegate = navigation
        web.loadHTMLString("<meta name='viewport' content='width=device-width'><html style='color-scheme:light dark' data-color-scheme='light'><body><button>Continue checkout</button></body></html>", baseURL: URL(string: address))
        await fulfillment(of: [loaded], timeout: 15)
        web.navigationDelegate = nil
    }

    @MainActor func testLoadingCoverMatchesFullWebBounds() throws {
        let result = try XCTUnwrap(StashChromeLoadingCoverProbe())
        XCTAssertEqual(result.count, 1)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing:key)) }
    }

    @MainActor func testTopChromePaintFollowsOnlyCurrentDocument() throws {
        let result = try XCTUnwrap(StashTopChromeLifecycleProbe())
        XCTAssertEqual(result.count, 11)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing:key)) }
    }

    @MainActor func testInitialCoverRejectsStaleWorkAndNeverReturnsAfterReveal() {
        let result = StashLoadingPresentationProbe() as! [String: NSNumber]
        for key in ["initiallyCovered", "retryRejectsOldReply", "retryKeepsDeadline", "provisionalStallReleasesCover",
                    "revealed", "navigationStaysVisible",
                    "recoveryStaysVisible", "deadlineRevealsWithoutError", "backgroundKeepsCover", "backgroundReplyKeepsCover",
                    "closeDiscardsReply", "errorStopsLoading"] {
            XCTAssertEqual(result[key]?.boolValue, true, key)
        }
    }

    @MainActor func testReadinessRequiresVisibleContentUntilNavigationFinishes() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 560))
        let host = UIViewController()
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window: UIWindow
        if let scene = previous?.windowScene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: web.frame)
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.addSubview(web)
        defer {
            web.navigationDelegate = nil
            web.stopLoading()
            window.isHidden = true
            previous?.makeKey()
        }
        let loaded = expectation(description: "readiness document loaded")
        let navigation = LoadingNavigation { loaded.fulfill() }
        web.navigationDelegate = navigation
        web.loadHTMLString("<meta name='viewport' content='width=device-width'><body></body>", baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        let cases: [(String, Bool)] = [
            ("", false),
            ("<p style='display:none'>Hidden checkout</p>", false),
            ("<p style='opacity:0'>Invisible checkout</p>", false),
            ("<p style='position:absolute;top:10000px'>Outside viewport</p>", false),
            ("<button>Continue checkout</button>", true),
            ("<p>Checkout is ready</p>", true)
        ]
        for (markup, expected) in cases {
            let script = "document.body.innerHTML = markup;\n" + StashInitialContentReadinessSource()
            let value = try await evaluate(web, script, ["markup": markup, "finished": false])
            XCTAssertEqual((value as? NSNumber)?.boolValue, expected, markup)
        }
        let emptyFinished = try await evaluate(web,
            "document.body.replaceChildren();\n" + StashInitialContentReadinessSource(), ["finished": true])
        XCTAssertEqual((emptyFinished as? NSNumber)?.boolValue, true)

        let pausedFrames = "const original = requestAnimationFrame; window.requestAnimationFrame = () => 0;\n" +
            "try {\n" + StashInitialContentReadinessSource() +
            "\n} finally { window.requestAnimationFrame = original; }"
        let readyWithoutFrames = try await evaluate(web, pausedFrames, ["finished": true])
        XCTAssertEqual((readyWithoutFrames as? NSNumber)?.boolValue, true)
    }

    @MainActor private func evaluate(_ web: WKWebView, _ script: String, _ arguments: [String: Any]) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .defaultClient) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class LoadingNavigation: NSObject, WKNavigationDelegate {
    private let didLoad: () -> Void
    init(didLoad: @escaping () -> Void) { self.didLoad = didLoad }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { didLoad() }
}
