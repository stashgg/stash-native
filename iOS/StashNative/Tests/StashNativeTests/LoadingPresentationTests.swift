import XCTest
import WebKit
import RegressionSupport

final class LoadingPresentationTests: XCTestCase {
    @MainActor func testLoadingSurfaceConcealsPagePaintUntilReveal() throws {
        let result = try XCTUnwrap(StashLoadingCoverBackgroundProbe())
        XCTAssertEqual(result.count, 4)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }

    @MainActor func testCheckoutReadinessTreatsPlaceholdersAsDrawnContentWhileWebViewIsTransparent() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 560))
        let (window, previous) = host(web)
        defer { web.stopLoading(); window.isHidden = true; previous?.makeKey() }
        web.alpha = 0
        let source = try XCTUnwrap(StashInitialContentReadinessSource())
        let skeleton = "<div class='animate-skeletonOpacityFluctuation' style='width:200px;height:80px'></div>"
        for address in ["https://checkout.stash.gg/pay", "https://checkout.stashstaging.com/pay"] {
            guard await load(web, address) else { return }
            for finished in [false, true] {
                let beside = try await evaluate(web,
                    "document.body.innerHTML = skeleton + '<button>Pay</button>';\n" + source,
                    ["skeleton": skeleton, "finished": finished])
                XCTAssertEqual(beside as? Bool, true, "\(address) visible placeholder finished=\(finished)")
            }
            // Before the load event, a visible placeholder alone is drawn content; a hidden one is not.
            for (style, expected) in [("", true), ("display:none", false), ("opacity:0", false),
                                       ("position:absolute;top:10000px", false)] {
                let value = try await evaluate(web,
                    "document.body.innerHTML = '<section style=\"' + style + '\">' + skeleton + '</section>';\n" + source,
                    ["style": style, "skeleton": skeleton, "finished": false])
                XCTAssertEqual(value as? Bool, expected, "\(address) placeholder only, \(style)")
            }
            let latePlaceholder = "document.body.innerHTML = '<button>Pay</button>';\n" +
                "requestAnimationFrame(() => document.body.insertAdjacentHTML('afterbegin', skeleton));\n" + source
            let late = try await evaluate(web, latePlaceholder, ["skeleton": skeleton, "finished": true])
            XCTAssertEqual(late as? Bool, true)
        }
        guard await load(web, "https://custom.invalid/pay") else { return }
        let generic = try await evaluate(web, "document.body.innerHTML = skeleton;\n" + source,
                                         ["skeleton": skeleton, "finished": false])
        XCTAssertEqual(generic as? Bool, true)
    }

    @MainActor func testReadinessIgnoresThemeSoFixedThemeCheckoutsReveal() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 560))
        let (window, previous) = host(web)
        defer { web.stopLoading(); window.isHidden = true; previous?.makeKey() }
        web.alpha = 0
        let source = try XCTUnwrap(StashInitialContentReadinessSource())
        // A Stash checkout that renders a fixed theme, or none, must still reveal: the requested theme never gates it.
        for address in ["https://checkout.stash.gg/pay?theme=dark", "https://checkout.stashstaging.com/pay?theme=light"] {
            guard await load(web, address) else { return }
            for marker in ["light", "dark", "", "system"] {
                for finished in [false, true] {
                    let withContent = try await evaluate(web,
                        "document.documentElement.dataset.colorScheme = marker;\n" +
                        "document.body.innerHTML = '<button>Pay</button>';\n" + source,
                        ["marker": marker, "finished": finished])
                    XCTAssertEqual(withContent as? Bool, true, "\(address) scheme=\(marker) finished=\(finished)")
                }
                // Before the document finishes, an empty body still waits for drawn content, theme aside.
                let empty = try await evaluate(web,
                    "document.documentElement.dataset.colorScheme = marker;\n" +
                    "document.body.replaceChildren();\n" + source,
                    ["marker": marker, "finished": false])
                XCTAssertEqual(empty as? Bool, false, "\(address) scheme=\(marker) empty")
            }
        }
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

    @MainActor private func load(_ web: WKWebView, _ address: String,
                                file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        let loaded = expectation(description: "readiness fixture loaded")
        let navigation = LoadingNavigation { loaded.fulfill() }
        web.navigationDelegate = navigation
        defer { web.navigationDelegate = nil }
        web.loadHTMLString("<meta name='viewport' content='width=device-width'><html style='color-scheme:light dark' data-color-scheme='light'><body><button>Continue checkout</button></body></html>", baseURL: URL(string: address))
        return await WebViewFixture.waitForLoad(loaded, file:file, line:line)
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
        guard await WebViewFixture.waitForLoad(loaded) else { return }
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
