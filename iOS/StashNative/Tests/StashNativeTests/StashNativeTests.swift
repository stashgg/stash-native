import XCTest
import WebKit
import StashNative
import RegressionSupport

final class StashNativeTests: XCTestCase {
    func testV3DefaultsAndIndependentCopy() {
        XCTAssertEqual(StashNative.sdkVersion(), "3.0.0")
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
            StashGeometryProbe(1032, 1344, true, 0, Double(defaults.preferredContentWidth),
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

    func testShortCardContentShrinksButExpandedIgnoresMeasurement() {
        XCTAssertEqual(geometry(390, 844, measured: 220)["resting"]!, 220)
        XCTAssertEqual(geometry(390, 844, measured: 2000)["resting"]!, 560)
        XCTAssertEqual(geometry(390, 844, expanded: true, measured: 120)["height"]!,
                       geometry(390, 844, expanded: true)["height"]!)
    }

    func testMaximumContentHeightAndExtremeMarginStayInsideBounds() {
        let capped = StashGeometryProbe(1000, 1000, true, 80, 480, 560, 320, 16) as! [String: NSNumber]
        XCTAssertEqual(capped["height"]?.doubleValue, 320)
        let tiny = StashGeometryProbe(80, 70, true, 0, 480, 560, 0, 1000) as! [String: NSNumber]
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

    func testHeightHintsRequireActiveDocumentAndMatchingUnzoomedViewport() {
        let valid: [String: Any] = ["height": 320, "viewportWidth": 390, "scale": 1, "documentId": "current"]
        XCTAssertTrue(StashHeightHintProbe(valid, "current", 390, 1, 390))
        XCTAssertFalse(StashHeightHintProbe(valid, "old", 390, 1, 390))
        XCTAssertFalse(StashHeightHintProbe(valid, "current", 768, 1, 390))
        XCTAssertFalse(StashHeightHintProbe(valid, "current", 390, 2, 390))
        for invalid in [Double.nan, Double.infinity, -1, 0] {
            var payload = valid
            payload["height"] = invalid
            XCTAssertFalse(StashHeightHintProbe(payload, "current", 390, 1, 390))
        }
        var wrongType = valid
        wrongType["height"] = "320"
        XCTAssertFalse(StashHeightHintProbe(wrongType, "current", 390, 1, 390))
    }

    func testAutomaticMeasurementResetRequiresMatchingDocumentAndViewport() {
        let reset: [String: Any] = ["reset": true, "viewportWidth": 390, "scale": 1, "documentId": "current"]
        XCTAssertTrue(StashHeightHintProbe(reset, "current", 390, 1, 390))
        XCTAssertFalse(StashHeightHintProbe(reset, "old", 390, 1, 390))
        XCTAssertFalse(StashHeightHintProbe(reset, "current", 480, 1, 390))
        var wrongType = reset
        wrongType["reset"] = "true"
        XCTAssertFalse(StashHeightHintProbe(wrongType, "current", 390, 1, 390))
    }

    func testObserverHasExplicitIntrinsicRootAndNoScrollHeightFeedback() {
        let source = StashMeasurementSource() ?? ""
        XCTAssertTrue(source.contains("[data-stash-content]"))
        XCTAssertTrue(source.contains("ResizeObserver"))
        XCTAssertFalse(source.contains("scrollHeight"))
        XCTAssertTrue(source.contains("documentId"))
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

    private func geometry(_ width: Double, _ height: Double, expanded: Bool = false,
                          measured: Double = 0) -> [String: Double] {
        let result = StashGeometryProbe(width, height, expanded, measured, 480, 560, 0, 16)
        return (result as! [String: NSNumber]).mapValues(\.doubleValue)
    }
}

final class ContentMeasurementTests: XCTestCase {
    @MainActor func testStylesheetsAddedOrRewrittenAfterLoadUpdateEligibility() async throws {
        let fixture = try await MeasurementFixture("""
        <style>html,body{margin:0}</style><main data-stash-content><div style="height:120px"></div></main>
        """)
        defer { fixture.close() }
        await fixture.expect(.height(120), "initial")
        try await fixture.step("""
        const late=document.createElement('style');late.id='late';late.textContent='main{min-height:50vh}';
        document.head.appendChild(late);
        """)
        await fixture.expect(.reset, "stylesheet added after load")
        try await fixture.step("document.getElementById('late').remove();")
        await fixture.expect(.height(120), "stylesheet removed")
        try await fixture.step("""
        const sheet=document.createElement('style');sheet.id='rewritten';sheet.textContent='.unused{height:10px}';
        document.head.appendChild(sheet);
        """)
        try await fixture.step("document.getElementById('rewritten').textContent='main{height:50%}';")
        await fixture.expect(.reset, "STYLE textContent change")
        try await fixture.step("document.getElementById('rewritten').firstChild.data='main{color:red}';")
        await fixture.expect(.height(120), "STYLE text node change")
        // CSSOM edits schedule no measurement; the next DOM mutation does.
        try await fixture.step("document.styleSheets[0].insertRule('body{max-height:100dvh}',0);touch();")
        await fixture.expect(.reset, "CSSOM insertRule")
        try await fixture.step("document.styleSheets[0].deleteRule(0);touch();")
        await fixture.expect(.height(120), "CSSOM deleteRule")
        try await fixture.step("document.getElementById('rewritten').textContent='@media all{.unused{color:red}}';")
        try await fixture.step("document.getElementById('rewritten').sheet.cssRules[0].insertRule('main{block-size:var(--h)}',0);touch();")
        await fixture.expect(.reset, "insertRule inside a grouping rule")
        try await fixture.step("document.getElementById('rewritten').remove();")
        await fixture.expect(.height(120), "grouping rule removed")
        let unreadable = try await fixture.step("""
        const link=document.createElement('link');link.rel='stylesheet';link.href='stashcss://styles.invalid/late.css';
        const loaded=new Promise(resolve=>{link.onload=()=>resolve('load');link.onerror=()=>resolve('error');});
        document.head.appendChild(link);
        const state=await loaded;
        try{link.sheet.cssRules;return state+':readable';}catch(error){return state+':unreadable';}
        """)
        XCTAssertEqual(unreadable as? String, "load:unreadable")
        try await fixture.step("document.querySelector('main div').textContent='after cross-origin load';")
        await fixture.expect(.reset, "cross-origin stylesheet")
        let count = fixture.messages.count
        for index in 0..<3 { try await fixture.step("document.querySelector('main div').textContent='mutation \(index)';") }
        XCTAssertEqual(fixture.messages.count, count, "an unreadable stylesheet keeps the wrapper ineligible")
        try await fixture.step("document.querySelector('link[rel=stylesheet]').remove();")
        await fixture.expect(.height(120), "cross-origin stylesheet removed")
    }

    @MainActor func testCachedViewportRulesStillMatchClassChanges() async throws {
        let fixture = try await MeasurementFixture("""
        <style>html,body{margin:0}.tall{height:50vh}.framed main{max-height:80%}main::before{height:50vh}
        @media all{.inner{min-height:10vmin}}</style>
        <main data-stash-content><div style="height:120px"></div></main>
        """)
        defer { fixture.close() }
        await fixture.expect(.height(120), "unmatched viewport rules and a pseudo-element rule")
        try await fixture.step("document.querySelector('main').classList.add('tall');")
        await fixture.expect(.reset, "wrapper gains a cached viewport class")
        try await fixture.step("document.querySelector('main').classList.remove('tall');")
        await fixture.expect(.height(120), "wrapper class removed")
        try await fixture.step("document.body.classList.add('framed');")
        await fixture.expect(.reset, "ancestor class makes a descendant rule match")
        try await fixture.step("document.body.classList.remove('framed');document.documentElement.classList.add('inner');")
        await fixture.expect(.reset, "nested grouping rule matches an ancestor")
        try await fixture.step("document.documentElement.classList.remove('inner');")
        await fixture.expect(.height(120), "ancestor class removed")
    }

    @MainActor func testLargeStylesheetDoesNotRescanOnEveryMutationFrame() async throws {
        var css = ""
        for index in 0..<3000 {
            switch index % 10 {
            case 0: css += "@media (min-width: \(300 + index % 700)px) { .m\(index) { padding: \(index % 9)px; } " +
                ".m\(index) > span { color: rgb(\(index % 255),1,2); } }\n"
            case 1: css += ".h\(index) { min-height: \(index % 90)vh; }\n"
            case 2: css += "div.card .row:nth-child(\(index % 7 + 1)) .c\(index):hover { height: 50%; }\n"
            default: css += ".k\(index) { margin: \(index % 13)px \(index % 5)px; font-size: \(10 + index % 8)px; " +
                "background: #\(String(format: "%06x", index * 2654435 % 0xFFFFFF)); }\n"
            }
        }
        var rows = ""
        for index in 0..<400 {
            rows += "<div class='row k\(index * 10 + 3)'><span class='m\(index * 10)'>Row \(index)</span>" +
                "<button class='c\(index * 10 + 2)'>Buy</button></div>"
        }
        let timer = """
        window.__measureTimes=[];const raf=window.requestAnimationFrame.bind(window);
        window.requestAnimationFrame=function(callback){return raf(function(time){const start=performance.now();callback(time);
        if(callback.name==='measure')window.__measureTimes.push(performance.now()-start);});};
        """
        // Same sheet and nesting as the audit probe that measured the uncached scan.
        let fixture = try await MeasurementFixture("<style>body{margin:0}\(css)</style><div id='app'><div class='layout'>" +
            "<div class='page'><section class='checkout'><div class='panel'><div class='content'><main data-stash-content>" +
            "<div class='card'>\(rows)</div></main></div></div></section></div></div></div>", before: timer)
        defer { fixture.close() }
        let result = try await fixture.step("""
        window.__measureTimes=[];
        for(let burst=0;burst<40;burst++){const rows=document.querySelectorAll('.row');
        for(let i=0;i<20;i++)rows[(burst*20+i)%rows.length].firstChild.textContent='Row '+burst+':'+i;
        await frame();await frame();}
        const times=window.__measureTimes.slice().sort((a,b)=>a-b);
        return {count:times.length,median:times[Math.floor(times.length/2)],
        height:document.querySelector('main').getBoundingClientRect().height};
        """) as? [String: Any]
        let count = (result?["count"] as? NSNumber)?.intValue ?? 0
        let median = (result?["median"] as? NSNumber)?.doubleValue ?? .infinity
        XCTAssertGreaterThanOrEqual(count, 30, "measurement must run for each mutation burst")
        // An uncached scan of this sheet measured 5-7 ms per frame on the iPhone Duo simulator.
        print("Content measurement at 3000 rules: \(count) frames, median \(median) ms")
        XCTAssertLessThan(median, 3, "median measurement frame \(median) ms at 3000 rules")
        let height = (result?["height"] as? NSNumber)?.doubleValue ?? 0
        await fixture.expect(.height(height), "unmatched viewport rules keep the wrapper eligible")
    }
}

@MainActor private final class MeasurementFixture {
    enum State: Equatable { case height(Double), reset, none }

    let web: WKWebView
    private let window: UIWindow
    private let previous: UIWindow?
    private let recorder = MeasurementRecorder()
    private let resources = MeasurementResources()
    var messages: [[String: Any]] { recorder.messages }

    init(_ body: String, before: String? = nil) async throws {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        controller.add(recorder, name: "stashContentHeight")
        if let before {
            controller.addUserScript(WKUserScript(source: before, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        controller.addUserScript(WKUserScript(source: StashMeasurementSource() ?? "", injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        configuration.setURLSchemeHandler(resources, forURLScheme: "stashpage")
        configuration.setURLSchemeHandler(resources, forURLScheme: "stashcss")
        resources.page = "<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>" +
            "</head><body>\(body)</body></html>"
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), configuration: configuration)
        previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        window = previous?.windowScene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: web.frame)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.addSubview(web)
        web.load(URLRequest(url: URL(string: "stashpage://checkout.invalid/index.html")!))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { [web] _, _ in !web.isLoading && web.url != nil },
                                               object: nil)
        _ = await XCTWaiter.fulfillment(of: [loaded], timeout: WebViewFixture.startupTimeout)
        try await step("")
    }

    func close() {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "stashContentHeight")
        web.stopLoading()
        window.isHidden = true
        previous?.makeKey()
    }

    @discardableResult func step(_ body: String) async throws -> Any? {
        try await web.callAsyncJavaScript("""
        const frame=()=>new Promise(resolve=>requestAnimationFrame(()=>resolve()));
        const touch=()=>{document.body.dataset.touch=String(Math.random());};
        const result=await (async()=>{\(body)\n})();
        await frame();await frame();await frame();
        return result;
        """, arguments: [:], in: nil, contentWorld: .page)
    }

    func expect(_ expected: State, _ label: String, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while state != expected && Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(state, expected, label, file: file, line: line)
    }

    private var state: State {
        guard let last = recorder.messages.last else { return .none }
        if last["reset"] as? Bool == true { return .reset }
        return (last["height"] as? NSNumber).map { .height($0.doubleValue) } ?? .none
    }
}

private final class MeasurementRecorder: NSObject, WKScriptMessageHandler {
    var messages: [[String: Any]] = []
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { messages.append(body) }
    }
}

// Serves the page and a stylesheet from different origins, so the stylesheet is unreadable.
private final class MeasurementResources: NSObject, WKURLSchemeHandler {
    var page = ""
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let css = url.scheme == "stashcss"
        let data = Data((css ? "main{color:red}" : page).utf8)
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: css ? "text/css" : "text/html",
                                             expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
