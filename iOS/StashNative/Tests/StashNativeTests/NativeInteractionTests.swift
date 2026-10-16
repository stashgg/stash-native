import XCTest
import WebKit
import RegressionSupport

private final class InteractionFixtureWindow: UIWindow {
    override var safeAreaInsets: UIEdgeInsets { .zero }
}

final class NativeInteractionTests: XCTestCase {
    @MainActor func testNativeBackingOwnershipResetsAndKVOReentry() throws {
        let result = try XCTUnwrap(StashPageBackingLifecycleProbe())
        XCTAssertEqual(result.count, 11)
        for (key, value) in result { XCTAssertEqual(value as? Bool, true, String(describing: key)) }
    }

    @MainActor private func assertBackingPaint(_ color: UIColor?, _ expected: [CGFloat], file: StaticString = #filePath, line: UInt = #line) {
        guard let color else { XCTFail("Missing paint", file:file, line:line); return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(color.getRed(&r, green:&g, blue:&b, alpha:&a), file:file, line:line)
        for (actual, wanted) in zip([r,g,b,a], expected) { XCTAssertEqual(actual,wanted,accuracy:0.0001,file:file,line:line) }
    }

    @MainActor func testBackingCoverageChangesWithoutChangingHeaderPaint() async throws {
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = previous?.windowScene.map(InteractionFixtureWindow.init(windowScene:)) ?? InteractionFixtureWindow(frame:CGRect(x:0,y:0,width:800,height:900))
        window.overrideUserInterfaceStyle = .light
        let presenter = UIViewController(); window.rootViewController = presenter; window.makeKeyAndVisible()
        let fixture = try XCTUnwrap(StashObservedChromeContentFixture(presenter,314))
        let web = try XCTUnwrap(fixture["web"] as? WKWebView)
        // Compare WebKit's automatic transparent-page fallback under the same host traits.
        let reference = WKWebView(frame: CGRect(x:0,y:0,width:32,height:32))
        reference.scrollView.contentInsetAdjustmentBehavior = .never
        reference.isUserInteractionEnabled = false
        presenter.view.addSubview(reference)
        let referenceLoaded = expectation(description: "unowned transparent reference loaded")
        let referenceNavigation = InteractionNavigation { referenceLoaded.fulfill() }
        reference.navigationDelegate = referenceNavigation
        reference.loadHTMLString("<meta name='viewport' content='width=device-width,initial-scale=1'><style>html,body{background:transparent}</style>",baseURL:URL(string:"https://checkout.invalid"))
        defer {
            reference.navigationDelegate = nil; reference.stopLoading(); reference.removeFromSuperview()
            StashEndChromeContentFixture(fixture); window.isHidden = true; previous?.makeKey()
        }
        await fulfillment(of:[referenceLoaded],timeout:15)
        XCTAssertEqual(reference.traitCollection.userInterfaceStyle,web.traitCollection.userInterfaceStyle)
        var initialRed: CGFloat = 0, initialGreen: CGFloat = 0, initialBlue: CGFloat = 0, initialAlpha: CGFloat = 0
        XCTAssertTrue(reference.underPageBackgroundColor.getRed(&initialRed,green:&initialGreen,blue:&initialBlue,alpha:&initialAlpha))
        let initialChannels = [initialRed,initialGreen,initialBlue,initialAlpha]
        web.loadHTMLString("""
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;overflow:hidden;background:rgb(235,237,232)}
        #panel{height:48px;background:rgb(247,249,244)}</style><main id="panel"></main>
        """,baseURL:URL(string:"https://checkout.invalid"))
        let panelColor = UIColor(red:247/255,green:249/255,blue:244/255,alpha:1)
        for _ in 0..<100 {
            if StashChromeFixtureInferredColor(fixture) == panelColor { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture),panelColor)
        XCTAssertNil(StashChromeFixtureBackingColor(fixture),"A shallow header must not replace body backing")
        assertBackingPaint(web.underPageBackgroundColor,[235/255,237/255,232/255,1])
        assertBackingPaint(web.backgroundColor,[235/255,237/255,232/255,1])
        _ = try await web.evaluateJavaScript("panel.style.height='100%'")
        for _ in 0..<50 {
            if StashChromeFixtureBackingColor(fixture) != nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        assertBackingPaint(StashChromeFixtureBackingColor(fixture),[247/255,249/255,244/255,1])
        assertBackingPaint(web.scrollView.backgroundColor,[247/255,249/255,244/255,1])
        assertBackingPaint(web.backgroundColor,[247/255,249/255,244/255,1])
        let before = try await web.evaluateJavaScript("({height:innerHeight,width:innerWidth,root:scrollY})") as! NSDictionary
        // The html/body paint changes while the qualifying surface stays opaque.
        _ = try await web.evaluateJavaScript("document.documentElement.style.backgroundColor='rgb(17,34,51)';document.body.style.backgroundColor='rgb(17,34,51)';panel.style.height=(innerHeight-2)+'px'")
        for _ in 0..<50 {
            if StashChromeFixtureBackingColor(fixture) == nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture),panelColor,"Edge color remains unchanged")
        XCTAssertNil(StashChromeFixtureBackingColor(fixture),"Coverage loss must be reported independently")
        assertBackingPaint(web.underPageBackgroundColor,[17/255,34/255,51/255,1])
        assertBackingPaint(web.scrollView.backgroundColor,[17/255,34/255,51/255,1])
        assertBackingPaint(web.backgroundColor,[17/255,34/255,51/255,1])
        _ = try await web.evaluateJavaScript("panel.style.height='100%'")
        for _ in 0..<50 {
            if StashChromeFixtureBackingColor(fixture) != nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        assertBackingPaint(StashChromeFixtureBackingColor(fixture),[247/255,249/255,244/255,1])
        _ = try await web.evaluateJavaScript("panel.removeAttribute('style')")
        for _ in 0..<50 {
            if StashChromeFixtureBackingColor(fixture) == nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture),panelColor)
        XCTAssertNil(StashChromeFixtureBackingColor(fixture))
        // After ownership clears, later body paint follows through the real KVO observer.
        _ = try await web.evaluateJavaScript("document.documentElement.style.backgroundColor='rgb(51,68,85)';document.body.style.backgroundColor='rgb(51,68,85)'")
        for _ in 0..<50 {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            if web.underPageBackgroundColor.getRed(&red,green:&green,blue:&blue,alpha:&alpha),
               abs(red-51/255) < 0.0001, abs(green-68/255) < 0.0001, abs(blue-85/255) < 0.0001 { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertNil(StashChromeFixtureBackingColor(fixture))
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture),panelColor)
        assertBackingPaint(web.underPageBackgroundColor,[51/255,68/255,85/255,1])
        assertBackingPaint(web.scrollView.backgroundColor,[51/255,68/255,85/255,1])
        assertBackingPaint(web.backgroundColor,[51/255,68/255,85/255,1])
        let after = try await web.evaluateJavaScript("({height:innerHeight,width:innerWidth,root:scrollY})") as! NSDictionary
        XCTAssertEqual(after,before)
        _ = try await web.evaluateJavaScript("panel.style.height='100%'")
        for _ in 0..<50 {
            if StashChromeFixtureBackingColor(fixture) != nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        assertBackingPaint(StashChromeFixtureBackingColor(fixture),[247/255,249/255,244/255,1])
        // A transparent page must not inherit the SDK's previous owned paint.
        _ = try await web.evaluateJavaScript("document.documentElement.style.backgroundColor='transparent';document.body.style.backgroundColor='transparent';panel.style.height='48px'")
        for _ in 0..<50 {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            if StashChromeFixtureBackingColor(fixture) == nil,
               web.underPageBackgroundColor.getRed(&red,green:&green,blue:&blue,alpha:&alpha),
               zip([red,green,blue,alpha],initialChannels).allSatisfy({ abs($0-$1) < 0.0001 }) { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertNil(StashChromeFixtureBackingColor(fixture))
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture),panelColor)
        assertBackingPaint(web.underPageBackgroundColor,initialChannels)
        assertBackingPaint(web.backgroundColor,initialChannels)
        assertBackingPaint(web.scrollView.backgroundColor,initialChannels)
    }

    @MainActor func testIdleRootOffsetUsesAdjustedInsetRangeAndPreservesActiveGestures() {
        let result = StashRootScrollOffsetProbe() as! [String: NSNumber]
        for key in ["negative", "positive", "valid", "safeMinimum", "safeMaximum", "activeGuards", "layoutGuards", "settled", "detached", "duplicateKeyboardInset", "explicitBottomInset", "keyboardOverlap", "keyboardGap", "undockedKeyboard", "genuineRootScroll"] {
            XCTAssertEqual(result[key]?.boolValue, true, key)
        }
    }

    @MainActor func testRootOffsetRepairPreservesNestedScrollValueAndSelection() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 647))
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = previousWindow?.windowScene.map(InteractionFixtureWindow.init(windowScene:)) ?? InteractionFixtureWindow(frame: web.frame)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.addSubview(web)
        defer {
            web.navigationDelegate = nil
            web.stopLoading()
            window.isHidden = true
            previousWindow?.makeKey()
        }
        let loaded = expectation(description: "fixed checkout loaded")
        let navigation = InteractionNavigation { loaded.fulfill() }
        web.navigationDelegate = navigation
        web.loadHTMLString("""
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;overflow:auto}
        #port{position:fixed;inset:0;overflow:auto}input{height:34px;font-size:16px}</style>
        <main id="port"><div style="height:300px"></div><input id="field" value="Retained checkout">
        <div style="height:600px"></div></main>
        """, baseURL: URL(string: "https://checkout.invalid"))
        await fulfillment(of: [loaded], timeout: 15)
        _ = try await web.evaluateJavaScript("""
        field.focus({preventScroll:true});field.setSelectionRange(2,7);port.scrollTop=52;
        """)
        let before = try await web.evaluateJavaScript("""
        ({nested:port.scrollTop,value:field.value,start:field.selectionStart,end:field.selectionEnd,
          focused:document.activeElement===field,root:document.documentElement.scrollTop})
        """) as! [String: Any]
        XCTAssertEqual(before["nested"] as? Double, 52)
        web.scrollView.setContentOffset(CGPoint(x: 0, y: -87), animated: false)
        XCTAssertEqual(web.scrollView.contentOffset.y, -87, accuracy: 0.5)
        XCTAssertTrue(StashNormalizeRootScrollOffset(web))
        let after = try await web.evaluateJavaScript("""
        ({nested:port.scrollTop,value:field.value,start:field.selectionStart,end:field.selectionEnd,
          focused:document.activeElement===field,root:document.documentElement.scrollTop})
        """) as! [String: Any]
        XCTAssertEqual(web.scrollView.contentOffset.y, 0, accuracy: 0.5)
        XCTAssertEqual(after["root"] as? Double, 0)
        XCTAssertEqual(after["nested"] as? Double, 52)
        XCTAssertEqual(after["value"] as? String, "Retained checkout")
        XCTAssertEqual(after["start"] as? Int, 2)
        XCTAssertEqual(after["end"] as? Int, 7)
        XCTAssertEqual(after["focused"] as? Bool, true)
    }


    @MainActor func testLateRootOffsetRepairsThroughSessionObserverWithoutChangingNestedState() async throws {
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = previous?.windowScene.map(InteractionFixtureWindow.init(windowScene:)) ??
            InteractionFixtureWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 900))
        let presenter = UIViewController()
        window.rootViewController = presenter; window.makeKeyAndVisible()
        // This fixture enters presentCheckout and installs the production session observers.
        let fixture = try XCTUnwrap(StashObservedChromeContentFixture(presenter, 425))
        let web = try XCTUnwrap(fixture["web"] as? WKWebView)
        defer {
            web.navigationDelegate = nil
            StashEndChromeContentFixture(fixture); window.isHidden = true; previous?.makeKey()
        }
        web.loadHTMLString("""
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;overflow:hidden}
        #port{position:fixed;inset:0;overflow:auto}input{height:34px;font-size:16px}</style>
        <main id="port"><div style="height:180px"></div>
        <input id="field" readonly value="Retained checkout"><div style="height:900px"></div></main>
        """, baseURL: URL(string: "https://checkout.invalid"))
        // The fixture's initial about:blank request can finish after loadHTMLString begins.
        // Observe this document's actual elements instead of an unrelated navigation callback.
        var fixtureReady = false
        for _ in 0..<150 {
            fixtureReady = (try? await web.evaluateJavaScript("document.readyState==='complete' && !!document.getElementById('port') && !!document.getElementById('field')")) as? Bool == true
            if fixtureReady { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(fixtureReady, "The late-offset fixture document must be ready")
        guard fixtureReady else { return }
        let ready: Any? = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript("""
            field.focus({preventScroll:true});field.setSelectionRange(2,7);port.scrollTop=52;
            await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
            return true;
            """, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        XCTAssertEqual(ready as? Bool, true)
        let readState = """
        ({nested:port.scrollTop,value:field.value,start:field.selectionStart,end:field.selectionEnd,
          focused:document.activeElement===field,root:document.documentElement.scrollTop})
        """
        let before = try await web.evaluateJavaScript(readState) as! NSDictionary
        XCTAssertEqual(before["nested"] as? Double, 52)
        XCTAssertEqual(before["focused"] as? Bool, true)
        XCTAssertEqual(web.scrollView.contentSize.height, web.scrollView.bounds.height, accuracy: 0.5)
        XCTAssertEqual(web.scrollView.adjustedContentInset, .zero)
        XCTAssertEqual(web.scrollView.contentOffset.y, 0, accuracy: 0.5)
        // Inject after layout/focus has settled; no explicit repair or layout call follows.
        for invalid in [177.6666666667, -87.0] {
            web.scrollView.setContentOffset(CGPoint(x: 0, y: invalid), animated: false)
            XCTAssertEqual(web.scrollView.contentOffset.y, invalid, accuracy: 0.5)
            for _ in 0..<50 {
                if abs(web.scrollView.contentOffset.y) < 0.5 { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertEqual(web.scrollView.contentOffset.y, 0, accuracy: 0.5,
                           "Late invalid offset must be repaired by the registered observer")
            let after = try await web.evaluateJavaScript(readState) as! NSDictionary
            XCTAssertEqual(after, before, "Nested scroll, focused input, value and selection must survive")
        }
    }

    @MainActor func testPrivateTopChromeProbeTracksNestedPaintAndClearsUnknown() async throws {
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = previousWindow?.windowScene.map(InteractionFixtureWindow.init(windowScene:)) ?? InteractionFixtureWindow(frame:CGRect(x:0,y:0,width:800,height:900))
        let presenter = UIViewController(); window.rootViewController = presenter; window.makeKeyAndVisible()
        let web = WKWebView(frame:.zero)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        let fixture = try XCTUnwrap(StashChromeContentFixture(web, presenter, 120))
        StashEnableChromeFixtureProbe(fixture)
        defer { StashEndChromeContentFixture(fixture); window.isHidden = true; previousWindow?.makeKey() }
        web.loadHTMLString("""
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;background:rgb(235,237,232)}main{height:120px;background:rgb(247,249,244)}input{margin-top:32px}</style>
        <main id="panel" style=""><input id="field" value="preserved"></main>
        """, baseURL:URL(string:"https://checkout.invalid"))
        for _ in 0..<100 {
            if StashChromeFixtureInferredColor(fixture) != nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        let panelColor = UIColor(red:247/255,green:249/255,blue:244/255,alpha:1)
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture), panelColor)
        let before = try await web.evaluateJavaScript("({html:document.documentElement.outerHTML,scroll:scrollY,height:innerHeight,value:field.value,probe:typeof __stashTopEdgeProbe,handler:!!(window.webkit&&webkit.messageHandlers&&webkit.messageHandlers.stashTopChrome)})") as! [String:Any]
        XCTAssertEqual(before["probe"] as? String, "undefined")
        XCTAssertEqual(before["handler"] as? Bool, false)
        _ = try await web.evaluateJavaScript("panel.style.backgroundImage='linear-gradient(red,blue)'")
        for _ in 0..<50 {
            if StashChromeFixtureInferredColor(fixture) == nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertNil(StashChromeFixtureInferredColor(fixture))
        _ = try await web.evaluateJavaScript("panel.style.backgroundImage=''")
        for _ in 0..<50 {
            if StashChromeFixtureInferredColor(fixture) != nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture), panelColor)
        let after = try await web.evaluateJavaScript("({html:document.documentElement.outerHTML,scroll:scrollY,height:innerHeight,value:field.value})") as! [String:Any]
        for key in ["html","value"] { XCTAssertEqual(after[key] as? String, before[key] as? String) }
        for key in ["scroll","height"] { XCTAssertEqual(after[key] as? Double, before[key] as? Double) }
    }

    @MainActor func testTopChromeUsesCoveringSurfaceWhenFocusedIframeCrossesEdge() async throws {
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = previousWindow?.windowScene.map(InteractionFixtureWindow.init(windowScene:)) ?? InteractionFixtureWindow(frame:CGRect(x:0,y:0,width:800,height:900))
        let presenter = UIViewController(); window.rootViewController = presenter; window.makeKeyAndVisible()
        let web = WKWebView(frame:.zero)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        let fixture = try XCTUnwrap(StashChromeContentFixture(web, presenter, 314))
        StashEnableChromeFixtureProbe(fixture)
        defer { StashEndChromeContentFixture(fixture); window.isHidden = true; previousWindow?.makeKey() }
        web.loadHTMLString("""
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;background:rgb(235,237,232)}
        #port{position:fixed;inset:0;overflow:auto}#panel{height:820px;background:rgb(247,249,244)}
        iframe{display:block;width:100%;height:34px;border:0}</style>
        <main id="port"><section id="panel"><div style="height:76px"></div>
        <iframe id="secure" title="Test payment field" srcdoc="<style>html,body{margin:0}input{height:34px;box-sizing:border-box;width:100%}</style><input id='field' readonly value='preserved'>"></iframe></section></main>
        """, baseURL:URL(string:"https://checkout.invalid"))
        let panelColor = UIColor(red:247/255,green:249/255,blue:244/255,alpha:1)
        for _ in 0..<100 {
            if StashChromeFixtureInferredColor(fixture) == panelColor,
               (try? await web.evaluateJavaScript("!!secure.contentDocument.getElementById('field')")) as? Bool == true { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture), panelColor)
        assertBackingPaint(StashChromeFixtureBackingColor(fixture),[247/255,249/255,244/255,1])
        _ = try await web.evaluateJavaScript("""
        window.savedDocument=document;window.savedChild=secure.contentDocument;
        const f=secure.contentDocument.getElementById('field');f.focus({preventScroll:true});f.setSelectionRange(2,7);port.scrollTop=0;
        window.state=()=>({html:document.documentElement.outerHTML,child:secure.contentDocument.documentElement.outerHTML,
          value:f.value,start:f.selectionStart,end:f.selectionEnd,focus:document.activeElement===secure&&secure.contentDocument.activeElement===f,
          documentSame:document===savedDocument&&secure.contentDocument===savedChild,height:innerHeight,width:innerWidth,
          scroll:port.scrollTop,root:scrollY,iframeTop:secure.getBoundingClientRect().top});true;
        """)
        let before = try await web.evaluateJavaScript("state()") as! [String:Any]
        XCTAssertEqual(before["focus"] as? Bool, true)
        XCTAssertEqual(before["height"] as? Double, 314)
        XCTAssertEqual(before["iframeTop"] as? Double, 76)
        _ = try await web.evaluateJavaScript("port.scrollTop=75")
        try await Task.sleep(nanoseconds:350_000_000)
        let iframeCoversEdge = try await web.evaluateJavaScript("[0.2,0.5,0.8].every(x=>document.elementFromPoint(innerWidth*x,1)===secure)") as? Bool
        XCTAssertEqual(iframeCoversEdge, true)
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture), panelColor)
        assertBackingPaint(StashChromeFixtureBackingColor(fixture),[247/255,249/255,244/255,1])
        let crossed = try await web.evaluateJavaScript("state()") as! [String:Any]
        XCTAssertEqual(crossed["scroll"] as? Double, 75)
        XCTAssertEqual(crossed["iframeTop"] as? Double, 1)
        for key in ["html","child","value"] { XCTAssertEqual(crossed[key] as? String,before[key] as? String,key) }
        for key in ["start","end","height","width","root"] { XCTAssertEqual(crossed[key] as? Double,before[key] as? Double,key) }
        for key in ["focus","documentSame"] { XCTAssertEqual(crossed[key] as? Bool,true,key) }
        XCTAssertEqual(web.scrollView.contentOffset,.zero)
        _ = try await web.evaluateJavaScript("port.scrollTop=0")
        try await Task.sleep(nanoseconds:250_000_000)
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture),panelColor)
        assertBackingPaint(StashChromeFixtureBackingColor(fixture),[247/255,249/255,244/255,1])
        let restored = try await web.evaluateJavaScript("state()") as! NSDictionary
        XCTAssertEqual(restored, before as NSDictionary)

        // A full-viewport replaced surface remains unknown, even over a solid panel.
        _ = try await web.evaluateJavaScript("""
        window.art=document.createElement('img');art.style.cssText='position:fixed;inset:0;width:100%;height:100%;z-index:2';
        art.src='data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg"><rect width="100%" height="100%" fill="red"/></svg>';document.body.append(art);
        """)
        for _ in 0..<50 {
            if StashChromeFixtureInferredColor(fixture) == nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertNil(StashChromeFixtureInferredColor(fixture))
        XCTAssertNil(StashChromeFixtureBackingColor(fixture))
        _ = try await web.evaluateJavaScript("art.remove()")
        for _ in 0..<50 {
            if StashChromeFixtureInferredColor(fixture) == panelColor { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture),panelColor)
        assertBackingPaint(StashChromeFixtureBackingColor(fixture),[247/255,249/255,244/255,1])
    }

    @MainActor func testTopChromeAllowsOnePixelViewportRoundingButRejectsClipping() async throws {
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = previousWindow?.windowScene.map(InteractionFixtureWindow.init(windowScene:)) ?? InteractionFixtureWindow(frame:CGRect(x:0,y:0,width:800,height:900))
        let presenter = UIViewController(); window.rootViewController = presenter; window.makeKeyAndVisible()
        let web = WKWebView(frame:.zero)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        let fixture = try XCTUnwrap(StashChromeContentFixture(web, presenter, 326))
        let controller = try XCTUnwrap(fixture["controller"] as? UIViewController)
        controller.view.frame = CGRect(x:0,y:0,width:637,height:326)
        controller.viewDidLayoutSubviews()
        StashEnableChromeFixtureProbe(fixture)
        defer { StashEndChromeContentFixture(fixture); window.isHidden = true; previousWindow?.makeKey() }
        web.loadHTMLString("""
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:326px;overflow:hidden;background:rgb(235,237,232)}
        #port{position:fixed;left:0;top:-1px;width:100%;height:326px;overflow:auto}
        #panel{position:relative;top:-155px;height:820.390625px;background:rgb(247,249,244)}
        iframe{display:block;width:100%;height:34px;border:0}</style>
        <main id="port"><section id="panel"><div style="height:157px"></div>
        <iframe id="secure" title="Test payment field" srcdoc="<style>html,body{margin:0}input{height:34px;box-sizing:border-box;width:100%}</style><input id='field' readonly value='preserved'>"></iframe></section></main>
        """, baseURL:URL(string:"https://checkout.invalid"))
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("!!(window.secure&&secure.contentDocument.getElementById('field'))")) as? Bool == true { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        _ = try await web.evaluateJavaScript("""
        window.savedDocument=document;window.savedChild=secure.contentDocument;
        const f=secure.contentDocument.getElementById('field');f.focus({preventScroll:true});f.setSelectionRange(2,7);
        window.state=()=>({html:document.documentElement.outerHTML,child:secure.contentDocument.documentElement.outerHTML,
          value:f.value,start:f.selectionStart,end:f.selectionEnd,focus:document.activeElement===secure&&secure.contentDocument.activeElement===f,
          documentSame:document===savedDocument&&secure.contentDocument===savedChild,height:innerHeight,width:innerWidth,
          scroll:port.scrollTop,root:scrollY,portTop:port.getBoundingClientRect().top,portBottom:port.getBoundingClientRect().bottom,
          panelTop:panel.getBoundingClientRect().top,panelHeight:panel.getBoundingClientRect().height,
          iframeTop:secure.getBoundingClientRect().top,edge:[.25,.5,.75].every(x=>document.elementFromPoint(innerWidth*x,1)===secure)});true;
        """)
        let before = try await web.evaluateJavaScript("state()") as! [String:Any]
        XCTAssertEqual(before["width"] as? Double,637)
        XCTAssertEqual(before["height"] as? Double,326)
        XCTAssertEqual(before["portTop"] as? Double,-1)
        XCTAssertEqual(before["portBottom"] as? Double,325)
        XCTAssertEqual(before["panelTop"] as? Double,-156)
        XCTAssertEqual(before["panelHeight"] as? Double,820.390625)
        XCTAssertEqual(before["iframeTop"] as? Double,1)
        XCTAssertEqual(before["edge"] as? Bool,true)
        XCTAssertEqual(before["focus"] as? Bool,true)
        let panelColor = UIColor(red:247/255,green:249/255,blue:244/255,alpha:1)
        for _ in 0..<50 {
            if StashChromeFixtureInferredColor(fixture) == panelColor { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture),panelColor)
        // A two-pixel clipping deficit is outside the bounded rounding allowance.
        _ = try await web.evaluateJavaScript("port.style.height='325px'")
        for _ in 0..<50 {
            if StashChromeFixtureInferredColor(fixture) == nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertNil(StashChromeFixtureInferredColor(fixture))
        let clippedBottom = try await web.evaluateJavaScript("port.getBoundingClientRect().bottom") as? Double
        XCTAssertEqual(clippedBottom,324)
        _ = try await web.evaluateJavaScript("port.removeAttribute('style')")
        for _ in 0..<50 {
            if StashChromeFixtureInferredColor(fixture) == panelColor { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture),panelColor)
        let restored = try await web.evaluateJavaScript("state()") as! NSDictionary
        XCTAssertEqual(restored,before as NSDictionary)
        // CSSOM clearing also restores paint without an explicit sample request.
        _ = try await web.evaluateJavaScript("port.style.height='325px'")
        for _ in 0..<50 {
            if StashChromeFixtureInferredColor(fixture) == nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertNil(StashChromeFixtureInferredColor(fixture))
        _ = try await web.evaluateJavaScript("port.style.height=''")
        for _ in 0..<50 {
            if StashChromeFixtureInferredColor(fixture) == panelColor { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertEqual(StashChromeFixtureInferredColor(fixture),panelColor)
        let cssomRestored = try await web.evaluateJavaScript("state()") as! [String:Any]
        for key in ["child","value"] { XCTAssertEqual(cssomRestored[key] as? String,before[key] as? String,key) }
        for key in ["start","end","width","height","root","scroll","portTop","portBottom","iframeTop"] {
            XCTAssertEqual(cssomRestored[key] as? Double,before[key] as? Double,key)
        }
        for key in ["focus","documentSame"] { XCTAssertEqual(cssomRestored[key] as? Bool,true,key) }
        XCTAssertEqual(web.scrollView.contentOffset,.zero)
    }

    @MainActor func testChromeReserveKeepsMeasuredLastActionVisibleThroughProcessing() async throws {
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = previousWindow?.windowScene.map(InteractionFixtureWindow.init(windowScene:)) ?? InteractionFixtureWindow(frame: CGRect(x:0,y:0,width:800,height:900))
        let presenter = UIViewController()
        window.rootViewController = presenter; window.makeKeyAndVisible()
        let web = WKWebView(frame: .zero)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        let fixture = try XCTUnwrap(StashChromeContentFixture(web, presenter, 120))
        defer {
            web.navigationDelegate = nil; web.stopLoading()
            StashEndChromeContentFixture(fixture)
            window.isHidden = true; previousWindow?.makeKey()
        }
        XCTAssertEqual((fixture["height"] as? NSNumber)?.doubleValue, 120)
        let expected = CGRect(x:0,y:0,width:390,height:120)
        XCTAssertEqual((fixture["webFrame"] as? NSValue)?.cgRectValue, expected)
        let loaded = expectation(description: "measured checkout loaded")
        let navigation = InteractionNavigation { loaded.fulfill() }
        web.navigationDelegate = navigation
        web.loadHTMLString("""
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0}main{height:120px}button{display:block;box-sizing:border-box;height:32px}</style>
        <main data-stash-content><div style="height:88px">Checkout</div><button id="last">Final action</button></main>
        """, baseURL: URL(string:"https://checkout.invalid"))
        await fulfillment(of:[loaded], timeout:15)
        let metrics = try await web.evaluateJavaScript("({height:innerHeight,last:last.getBoundingClientRect().bottom,marker:document.querySelector('main').getBoundingClientRect().height})") as! [String: Double]
        XCTAssertEqual(metrics["height"], 120)
        XCTAssertEqual(metrics["last"], 120)
        XCTAssertEqual(metrics["marker"], 120)
        XCTAssertEqual(StashChromeProcessingFrame(fixture, true), expected)
        XCTAssertEqual(StashChromeProcessingFrame(fixture, false), expected)
        XCTAssertEqual(web.scrollView.contentInset, .zero)
    }

    @MainActor func testNativeGrabberLeavesWebHeaderClearAndPreservesPolicy() throws {
        guard #available(iOS 16.0, *) else { throw XCTSkip("Custom content detents require iOS 16") }
        let result = StashNativeGrabberContentProbe() as! [String: NSNumber]
        for key in ["headerClear", "centered", "nativeVisible", "webReceivesInput", "unchanged",
                    "hiddenWhileProcessing", "restored", "resizedClear"] {
            XCTAssertEqual(result[key]?.boolValue, true, key)
        }
    }

    @MainActor func testNativeFocusRepairCoalescesFinalViewportAndRejectsHiddenOrClosedKeyboard() async {
        let result: [String: NSNumber] = await withCheckedContinuation { continuation in
            StashFocusSettleProbe { value in
                continuation.resume(returning: value as! [String: NSNumber])
            }
        }
        for key in ["finalViewport", "hideDiscardsRepair", "closeDiscardsRepair"] {
            XCTAssertEqual(result[key]?.boolValue, true, key)
        }
    }

    @MainActor func testFormAccessorySuppressionIsPerInstanceAndPreservesConcreteClasses() {
        let result = StashInputAccessoryProbe() as! [String: NSNumber]
        for key in ["hidden", "untouched", "originalClasses", "idempotent", "assistantHidden", "assistantUntouched"] {
            XCTAssertEqual(result[key]?.boolValue, true, key)
        }
    }

    @MainActor func testResizeRevealsFocusedFieldInNestedScrollerWithoutChangingSelection() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(
            source: StashNativeInteractionSource(), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: configuration)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        let host = UIViewController()
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window: UIWindow
        if let scene = previousWindow?.windowScene {
            window = InteractionFixtureWindow(windowScene: scene)
        } else {
            window = InteractionFixtureWindow(frame: web.frame)
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.addSubview(web)
        defer {
            web.navigationDelegate = nil
            web.stopLoading()
            window.isHidden = true
            previousWindow?.makeKey()
        }
        let loaded = expectation(description: "nested checkout form loaded")
        let navigation = InteractionNavigation { loaded.fulfill() }
        web.navigationDelegate = navigation
        web.loadHTMLString("""
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;overflow:hidden}
        header{height:40px}main{position:absolute;inset:40px 0 0;overflow:auto}
        input{box-sizing:border-box;display:block;height:34px;font-size:16px;width:90%}</style></head>
        <body><header>Checkout</header><main id="scroller"><div style="height:320px"></div>
        <input id="field" value="SDK Native Test"><div style="height:400px"></div></main></body></html>
        """, baseURL: URL(string: "https://checkout.invalid"))
        await fulfillment(of: [loaded], timeout: 15)
        let baseline = try await web.evaluateJavaScript("""
        (() => { const field = document.querySelector('#field');
        field.focus({preventScroll:true}); field.setSelectionRange(4,10);
        return {height:innerHeight,bottom:field.getBoundingClientRect().bottom,
        focused:document.activeElement===field}; })()
        """) as? [String: Any]
        XCTAssertEqual(baseline?["focused"] as? Bool, true)
        XCTAssertEqual(baseline?["height"] as? Double, 600)
        XCTAssertLessThan(try XCTUnwrap(baseline?["bottom"] as? Double), 600)

        web.frame.size.height = 180
        web.setNeedsLayout()
        web.layoutIfNeeded()
        let value: Any? = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript("""
            const field = document.querySelector('#field'), scroller = document.querySelector('#scroller');
            let rect;
            for (let attempt = 0; attempt < 100; attempt++) {
                await new Promise(resolve => setTimeout(resolve, 20));
                rect = field.getBoundingClientRect();
                if (innerHeight === 180 && rect.top >= 40 && rect.bottom <= innerHeight) break;
            }
            return {height:innerHeight,top:rect.top,bottom:rect.bottom,scrollTop:scroller.scrollTop,
                value:field.value,start:field.selectionStart,end:field.selectionEnd,
                focused:document.activeElement===field};
            """, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        let result = try XCTUnwrap(value as? [String: Any])
        XCTAssertEqual(result["height"] as? Double, 180)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result["top"] as? Double), 40)
        XCTAssertLessThanOrEqual(try XCTUnwrap(result["bottom"] as? Double), 180)
        XCTAssertGreaterThan(try XCTUnwrap(result["scrollTop"] as? Double), 0)
        XCTAssertEqual(result["value"] as? String, "SDK Native Test")
        XCTAssertEqual(result["start"] as? Int, 4)
        XCTAssertEqual(result["end"] as? Int, 10)
        XCTAssertEqual(result["focused"] as? Bool, true)

        let repaired: Any? = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript("""
            const field = document.querySelector('#field'), scroller = document.querySelector('#scroller');
            scroller.scrollTop += field.getBoundingClientRect().bottom - innerHeight;
            const clippedBottom = field.getBoundingClientRect().bottom;
            window.__stashRevealFocusedElement();
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            const rect = field.getBoundingClientRect();
            return {before:clippedBottom,top:rect.top,bottom:rect.bottom,value:field.value,
                start:field.selectionStart,end:field.selectionEnd};
            """, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        let repairedResult = try XCTUnwrap(repaired as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(repairedResult["before"] as? Double), 180, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(repairedResult["top"] as? Double), 40)
        XCTAssertLessThanOrEqual(try XCTUnwrap(repairedResult["bottom"] as? Double), 172)
        XCTAssertEqual(repairedResult["value"] as? String, "SDK Native Test")
        XCTAssertEqual(repairedResult["start"] as? Int, 4)
        XCTAssertEqual(repairedResult["end"] as? Int, 10)

        let settled: Any? = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript("""
            const field = document.querySelector('#field'), scroller = document.querySelector('#scroller');
            const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
            window.__stashRevealFocusedElement();
            await wait(80);
            scroller.scrollTop = 0;
            const lateBottom = field.getBoundingClientRect().bottom;
            await wait(150);
            const repairedBottom = field.getBoundingClientRect().bottom;
            document.dispatchEvent(new Event('pointerdown', {bubbles:true}));
            scroller.scrollTop = 0;
            await wait(150);
            const userBottom = field.getBoundingClientRect().bottom;
            window.__stashRevealFocusedElement();
            await wait(1150);
            scroller.scrollTop = 0;
            await wait(150);
            return {lateBottom,repairedBottom,userBottom,expiredBottom:field.getBoundingClientRect().bottom,
                height:innerHeight,value:field.value,start:field.selectionStart,end:field.selectionEnd};
            """, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        let settledResult = try XCTUnwrap(settled as? [String: Any])
        XCTAssertGreaterThan(try XCTUnwrap(settledResult["lateBottom"] as? Double), 180)
        XCTAssertLessThanOrEqual(try XCTUnwrap(settledResult["repairedBottom"] as? Double), 172)
        XCTAssertGreaterThan(try XCTUnwrap(settledResult["userBottom"] as? Double), 180)
        XCTAssertGreaterThan(try XCTUnwrap(settledResult["expiredBottom"] as? Double), 180)
        XCTAssertEqual(settledResult["height"] as? Double, 180)
        XCTAssertEqual(settledResult["value"] as? String, "SDK Native Test")
        XCTAssertEqual(settledResult["start"] as? Int, 4)
        XCTAssertEqual(settledResult["end"] as? Int, 10)

        let ancestor: Any? = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript("""
            const field = document.querySelector('#field'), scroller = document.querySelector('#scroller');
            const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
            scroller.style.position = 'fixed';
            scroller.style.bottom = 'auto';
            scroller.style.height = '335px';
            scroller.scrollTop = 0;
            window.__stashRevealFocusedElement();
            await wait(80);
            const before = field.getBoundingClientRect().bottom;
            scroller.style.height = '140px';
            await wait(150);
            const result = {before,after:field.getBoundingClientRect().bottom,top:field.getBoundingClientRect().top,
                height:innerHeight,ancestorHeight:scroller.clientHeight,value:field.value,
                start:field.selectionStart,end:field.selectionEnd};
            document.dispatchEvent(new Event('pointerdown', {bubbles:true}));
            scroller.style.height = '120px'; scroller.scrollTop = 0;
            await wait(80);
            result.cancelledLayoutScroll = scroller.scrollTop;
            window.__stashRevealFocusedElement();
            await wait(1150);
            scroller.style.height = '130px'; scroller.scrollTop = 0;
            await wait(80);
            result.expiredLayoutScroll = scroller.scrollTop;
            return result;
            """, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        let ancestorResult = try XCTUnwrap(ancestor as? [String: Any])
        XCTAssertGreaterThan(try XCTUnwrap(ancestorResult["before"] as? Double), 180)
        XCTAssertLessThanOrEqual(try XCTUnwrap(ancestorResult["after"] as? Double), 172)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(ancestorResult["top"] as? Double), 40)
        XCTAssertEqual(ancestorResult["height"] as? Double, 180)
        XCTAssertEqual(ancestorResult["ancestorHeight"] as? Double, 140)
        XCTAssertEqual(ancestorResult["value"] as? String, "SDK Native Test")
        XCTAssertEqual(ancestorResult["start"] as? Int, 4)
        XCTAssertEqual(ancestorResult["end"] as? Int, 10)
        XCTAssertEqual(ancestorResult["cancelledLayoutScroll"] as? Double, 0)
        XCTAssertEqual(ancestorResult["expiredLayoutScroll"] as? Double, 0)
    }

    @MainActor func testLateViewportChangesCannotEnablePageZoomAndFieldsRemainEditable() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.ignoresViewportScaleLimits = false
        configuration.userContentController.addUserScript(WKUserScript(
            source: StashNativeInteractionSource(), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: configuration)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        let loaded = expectation(description: "checkout document loaded")
        let navigation = InteractionNavigation { loaded.fulfill() }
        web.navigationDelegate = navigation
        web.loadHTMLString("""
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body><p id="label">Checkout</p><input id="field"><textarea id="notes"></textarea>
        <div id="editable" contenteditable="true">Name</div></body></html>
        """, baseURL: URL(string: "https://checkout.invalid"))
        await fulfillment(of: [loaded], timeout: 15)
        let script = """
        const errors = [];
        window.addEventListener('error', event => errors.push(event.message));
        document.querySelector('meta[name=viewport]').content = 'width=980,maximum-scale=5,user-scalable=yes';
        const duplicate = document.createElement('meta');
        duplicate.name = 'viewport'; duplicate.content = 'width=980,maximum-scale=5';
        document.head.appendChild(duplicate);
        await new Promise(resolve => setTimeout(resolve, 0));
        const viewports = Array.from(document.querySelectorAll('meta[name=viewport]'), element => element.content);
        const replacement = document.createElement('head');
        replacement.innerHTML = '<meta name="viewport" content="width=980,maximum-scale=8,user-scalable=yes">';
        document.querySelector('meta[name=viewport]').content = 'width=980';
        document.head.remove();
        await new Promise(resolve => setTimeout(resolve, 0));
        document.documentElement.prepend(replacement);
        await new Promise(resolve => setTimeout(resolve, 0));
        document.querySelector('#__stash_native_interactions').firstChild.data = 'body{user-select:text}';
        await new Promise(resolve => setTimeout(resolve, 0));
        return {
            errors,
            viewports,
            replacement: document.querySelector('meta[name=viewport]').content,
            label: getComputedStyle(document.querySelector('#label')).webkitUserSelect,
            field: getComputedStyle(document.querySelector('#field')).webkitUserSelect,
            notes: getComputedStyle(document.querySelector('#notes')).webkitUserSelect,
            editable: getComputedStyle(document.querySelector('#editable')).webkitUserSelect
        };
        """
        let value: Any? = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        let result = try XCTUnwrap(value as? [String: Any])
        let viewports = try XCTUnwrap(result["viewports"] as? [String])
        XCTAssertEqual(result["errors"] as? [String], [])
        XCTAssertEqual(viewports.count, 2)
        for viewport in viewports {
            XCTAssertTrue(viewport.contains("width=device-width"))
            XCTAssertTrue(viewport.contains("maximum-scale=1"))
            XCTAssertTrue(viewport.contains("user-scalable=no"))
        }
        XCTAssertEqual(result["replacement"] as? String, viewports.first)
        XCTAssertEqual(result["label"] as? String, "none")
        for field in ["field", "notes", "editable"] {
            XCTAssertEqual(result[field] as? String, "text", field)
        }
        web.navigationDelegate = nil
        web.stopLoading()
    }
}

private final class InteractionNavigation: NSObject, WKNavigationDelegate {
    private let didLoad: () -> Void
    init(didLoad: @escaping () -> Void) { self.didLoad = didLoad }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { didLoad() }
}
