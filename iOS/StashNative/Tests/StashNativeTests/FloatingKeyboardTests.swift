import XCTest
import WebKit
import RegressionSupport

final class FloatingKeyboardTests: XCTestCase {
    @MainActor func testSharedKeyboardRectangleRejectsScaledNotificationAndLaggingGuide() {
        let result = StashKeyboardRectangleResolutionProbe() as! [String: Any]
        XCTAssertEqual(result["ipadBeforeFocus"] as? [Double], [0, 314, 580, 408, 580, 722])
        let expected: [String: Double] = ["ipadHeight": 330, "ipadAvailableBottom": 330,
            "bookHeight": 278.3333333333333, "earlierGuideHeight": 260,
            "insetGuideHeight": 405, "insetGuideAvailableBottom": 405,
            "outsideSafeTailHeight": 630, "unanchoredGuideHeight": 661,
            "staleBoundsHeight": 397, "staleOrientationHeight": 397,
            "earlyNotificationHeight": 278.3333333333333, "floatingHeight": 661]
        for (key, value) in expected {
            XCTAssertEqual((result[key] as? NSNumber)?.doubleValue ?? -1, value, accuracy: 0.01, key)
        }
        let book = result["bookBeforeFocus"] as! [Double]
        XCTAssertEqual(book[1], 262.3333333333333, accuracy: 0.01)
        let inset = result["insetGuideBeforeFocus"] as! [Double]
        XCTAssertEqual(inset[1], 389, accuracy: 0.01)
        let unanchored = result["unanchoredGuideFocus"] as! [Double]
        XCTAssertEqual(unanchored[1], 393, accuracy: 0.01)
        XCTAssertEqual(result["floatingOcclusion"] as? [Double], [20, 200, 334, 300, 447.5, 661])
        for key in ["capturedDockedHeight", "capturedSplitHeight", "capturedRedockedHeight"] {
            XCTAssertEqual((result[key] as? NSNumber)?.doubleValue ?? -1, 740, accuracy: 0.01, key)
        }
        XCTAssertEqual(result["capturedSplitOcclusion"] as? [Double], [0, 589.5, 400, 150.5, 400, 740])
        for key in ["capturedDockedClassified", "capturedSplitUndocked", "capturedSplitNoDockedCrop", "capturedRedockedOwned"] {
            XCTAssertEqual(result[key] as? Bool, true, key)
        }
        for key in ["ipadFocusClearedAfterClipping", "bookFocusClearedAfterClipping",
                    "insetGuideFocusClearedAfterClipping", "nativeContainerNotDoubleClipped", "floatingHideStillVisible", "hiddenGuideEndsEpisode",
                    "unownedExcluded", "foreignWindowExcluded", "hiddenExcluded"] {
            XCTAssertEqual(result[key] as? Bool, true, key)
        }
    }

    @MainActor func testFloatingSheetHiddenGuideEndsOwnershipWithoutDiscardingDockedOrFloatingKeyboard() {
        let result = StashFloatingSheetKeyboardBaselineProbe() as! [String: NSNumber]
        for key in ["positiveDockedPreserved", "hiddenBaselineEndsEpisode", "unchangedBaselineStaysHidden",
                    "nextDockedEpisode", "floatingAfterZeroHide", "undockedBelowContentPreserved"] {
            XCTAssertEqual(result[key]?.boolValue, true, key)
        }
    }

    @MainActor func testKeyboardVisibilityRequiresAnOwnedNotificationAndReconcilesUnchangedGuide() {
        let result = StashKeyboardVisibilityOwnershipProbe() as! [String: NSNumber]
        for key in ["guideAloneStaysHidden", "hiddenCollapseRestoresResting", "floatingAfterZeroHide",
                    "unchangedGuideRestoresVisibility", "hiddenGuideEndsEpisode", "safeBottomIsHidden",
                    "endedEpisodeCannotRestartFromGuide", "visibleHidePreservesFloating", "staleVisibleHideEndsAtHiddenGuide"] {
            XCTAssertEqual(result[key]?.boolValue, true, key)
        }
    }

    @MainActor func testKeyboardOcclusionUsesCurrentWebCoordinatesAndExcludesClippedKeyboard() {
        let result = StashFloatingKeyboardCoordinateProbe() as! [String: Any]
        let values = result["floating"] as! [Double]
        XCTAssertEqual(values, [30, 220, 334, 333.5, 480, 600])
        for key in ["clippedDockedExcluded", "hiddenExcluded", "detachedExcluded"] {
            XCTAssertEqual(result[key] as? Bool, true, key)
        }
    }

    @MainActor func testVisibleFloatingHideNotificationDoesNotEndKeyboardSession() {
        let result = StashFloatingKeyboardNotificationProbe() as! [String: NSNumber]
        for key in ["floatingRemainsVisible", "resignedFocusHides", "offscreenHides", "semanticPreserved"] {
            XCTAssertEqual(result[key]?.boolValue, true, key)
        }
    }

    @MainActor func testUndockedGuideRestoresFullCardWithoutUsingClampedDockedGuideTop() {
        let result = StashUndockedKeyboardLayoutProbe() as! [String: NSNumber]
        XCTAssertEqual(result["cardDockedHeight"]?.doubleValue, 573)
        XCTAssertEqual(result["cardUndockedHeight"]?.doubleValue, 900)
        XCTAssertEqual(result["cardClassification"]?.boolValue, true)
    }

    @MainActor func testCurrentGuideOverridesStaleNotificationCoordinates() {
        let result = StashFloatingKeyboardGuideProbe() as! [String: Any]
        XCTAssertEqual(result["current"] as? [Double], [40, 40, 334, 280, 480, 600])
        XCTAssertEqual(result["moved"] as? [Double], [70, 200, 334, 300, 480, 600])
        XCTAssertEqual(result["restoredVisible"] as? Bool, true)
        XCTAssertEqual(result["hiddenGuideClearsOcclusion"] as? Bool, true)
    }

    @MainActor func testFloatingKeyboardRevealsNestedFieldWithoutResizing() async throws {
        let configuration = WKWebViewConfiguration()
        let interaction = StashNativeInteractionSource()!
        let labelProbe = interaction.replacingOccurrences(of: "function associatedFocusRange(", with:
            "window.__stashTestLabelRange=function(e,t,b){return associatedFocusRange(e,t,b);};function associatedFocusRange(")
        XCTAssertNotEqual(interaction, labelProbe)
        configuration.userContentController.addUserScript(WKUserScript(
            source: labelProbe, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: configuration)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        let host = UIViewController()
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window: UIWindow
        if let scene = previous?.windowScene { window = UIWindow(windowScene: scene) }
        else { window = UIWindow(frame: web.frame) }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.addSubview(web)
        defer {
            web.navigationDelegate = nil
            web.stopLoading()
            window.isHidden = true
            previous?.makeKey()
        }
        let loaded = expectation(description: "floating keyboard fixture loaded")
        let navigation = FloatingNavigation { loaded.fulfill() }
        web.navigationDelegate = navigation
        web.loadHTMLString("""
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;overflow:hidden}main{position:fixed;inset:0;overflow:auto}
        input{display:block;height:34px;box-sizing:border-box;font-size:16px;width:90%}
        </style></head>
        <body><header>Underlying Checkout</header><main id="scroller">
        <article id="canvas" style="min-height:100%;display:flex;flex-direction:column;background:#f7f9f4">
        <section data-stash-content style="flex:0 0 auto"><div id="lead" style="height:320px"></div>
        <input id="field" value="Native value"><div id="tail" style="height:500px"></div></section></article></main>
        </body></html>
        """, baseURL: URL(string: "https://checkout.invalid"))
        await fulfillment(of: [loaded], timeout: 15)
        let direct = try await evaluate("""
        const field=document.querySelector('#field'),scroller=document.querySelector('#scroller');
        const initialFocus={documentFocused:document.hasFocus(),active:document.activeElement?.id||document.activeElement?.tagName};
        field.focus({preventScroll:true});field.setSelectionRange(1,5);
        const afterFocus={documentFocused:document.hasFocus(),active:document.activeElement?.id||document.activeElement?.tagName};
        window.__stashSetKeyboardOcclusion([0,240,390,200,390,600]);
        window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));
        const rect=field.getBoundingClientRect();
        const result={top:rect.top,bottom:rect.bottom,height:innerHeight,value:field.value,
        start:field.selectionStart,end:field.selectionEnd,style:field.getAttribute('style'),
        initialFocus,afterFocus,firstRevealFocus:{documentFocused:document.hasFocus(),active:document.activeElement?.id||document.activeElement?.tagName},firstScroll:scroller.scrollTop};
        window.__stashSetKeyboardOcclusion([0,240,390,200,1000,600]);
        scroller.scrollTop=0;window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,80));
        result.staleWidthTop=field.getBoundingClientRect().top;
        window.__stashSetKeyboardOcclusion(null);
        scroller.scrollTop=0;window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,80));
        result.clearedTop=field.getBoundingClientRect().top;
        document.querySelector('#tail').remove();scroller.scrollTop=0;
        const marker=document.querySelector('[data-stash-content]');
        result.markerBefore=marker.getBoundingClientRect().height;
        result.shortRangeBefore=scroller.scrollHeight-scroller.clientHeight;
        window.__stashSetKeyboardOcclusion([0,240,390,200,390,600]);window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));
        result.shortTop=field.getBoundingClientRect().top;result.shortBottom=field.getBoundingClientRect().bottom;
        result.clearanceCount=document.querySelectorAll('[data-stash-keyboard-clearance]').length;
        result.shortViewport=innerHeight;result.shortContainer=scroller.clientHeight;
        result.markerAfter=marker.getBoundingClientRect().height;
        scroller.style.paddingBottom='11px';window.__stashSetKeyboardOcclusion(null);
        await new Promise(resolve=>setTimeout(resolve,80));
        result.remainingAfterHide=document.querySelectorAll('[data-stash-keyboard-clearance]').length;
        result.authoredPadding=scroller.style.paddingBottom;
        scroller.scrollTop=0;window.__stashSetKeyboardOcclusion([0,240,390,200,390,600]);
        window.__stashRevealFocusedElement();await new Promise(resolve=>setTimeout(resolve,80));
        field.blur();await new Promise(resolve=>setTimeout(resolve,80));
        result.remainingAfterBlur=document.querySelectorAll('[data-stash-keyboard-clearance]').length;
        scroller.style.paddingBottom='';
        const tail=document.createElement('div');tail.style.height='500px';marker.appendChild(tail);
        field.focus({preventScroll:true});scroller.scrollTop=220;
        window.__stashSetKeyboardOcclusion([0,20,390,280,390,600]);window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));
        result.belowTop=field.getBoundingClientRect().top;result.belowBottom=field.getBoundingClientRect().bottom;
        result.belowClearanceCount=document.querySelectorAll('[data-stash-keyboard-clearance]').length;
        result.belowMarkerHeight=marker.getBoundingClientRect().height;
        window.__stashSetKeyboardOcclusion(null);tail.remove();scroller.scrollTop=0;
        document.querySelector('#lead').style.height='100px';
        const canvas=document.querySelector('#canvas'),canvasBefore=canvas.getBoundingClientRect();
        const canvasStyle=canvas.getAttribute('style'),markerStyle=marker.getAttribute('style');
        window.__stashSetKeyboardOcclusion([0,20,390,280,390,600]);window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));
        result.shortBelowTop=field.getBoundingClientRect().top;result.shortBelowBottom=field.getBoundingClientRect().bottom;
        const canvasAfter=canvas.getBoundingClientRect();
        result.canvasAnchored=canvasBefore.top===canvasAfter.top&&canvasBefore.left===canvasAfter.left&&canvasBefore.width===canvasAfter.width;
        result.canvasCoversTop=!!document.elementFromPoint(10,10).closest('#canvas');
        result.shortBelowScroll=scroller.scrollTop;result.shortBelowMarkerHeight=marker.getBoundingClientRect().height;
        result.shortBelowClearance=document.querySelectorAll('[data-stash-keyboard-clearance]').length;
        result.authoredCanvasUnchanged=canvas.getAttribute('style')===canvasStyle&&marker.getAttribute('style')===markerStyle;
        window.__stashSetKeyboardOcclusion(null);scroller.scrollTop=0;
        result.shortBelowRestored=field.getBoundingClientRect().top;
        const wrapper=document.createElement('div');wrapper.style.cssText='height:100%;display:flex;flex-direction:column';
        canvas.before(wrapper);wrapper.appendChild(canvas);field.focus({preventScroll:true});
        const wrapperStyle=wrapper.getAttribute('style');
        window.__stashSetKeyboardOcclusion([0,20,390,280,390,600]);window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));
        result.wrappedBelowTop=field.getBoundingClientRect().top;
        result.wrappedCanvasTop=canvas.getBoundingClientRect().top;
        result.wrappedCanvasCoversTop=!!document.elementFromPoint(10,10).closest('#canvas');
        result.wrappedMarkerHeight=marker.getBoundingClientRect().height;
        result.wrappedStylePreserved=wrapper.getAttribute('style')===wrapperStyle&&canvas.getAttribute('style')===canvasStyle;
        result.wrappedClearance=document.querySelectorAll('[data-stash-keyboard-clearance]').length;
        window.__stashSetKeyboardOcclusion(null);scroller.scrollTop=0;
        result.wrappedRestoredTop=field.getBoundingClientRect().top;
        wrapper.before(canvas);wrapper.remove();field.focus({preventScroll:true});
        const painted=document.createElement('div');painted.id='painted';
        painted.style.cssText='background:#ddeeff;position:relative;flex:1 0 auto;margin-top:-16px;min-height:616px';
        canvas.appendChild(painted);painted.appendChild(marker);field.focus({preventScroll:true});
        document.querySelector('#lead').style.height='336px';const paintBefore=painted.getBoundingClientRect();
        const paintStyle=painted.getAttribute('style');
        window.__stashSetKeyboardOcclusion([0,240,390,200,390,600]);window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));
        result.deepBottom=field.getBoundingClientRect().bottom;
        result.deepClearanceOwner=document.querySelector('[data-stash-keyboard-clearance]')?.parentElement.id;
        result.deepPaintOwnsBottom=!!document.elementFromPoint(10,590).closest('#painted');
        result.deepPaintOrigin=painted.getBoundingClientRect().top+scroller.scrollTop;
        result.deepPaintOriginal=paintBefore.top;result.deepPaintStyle=painted.getAttribute('style')===paintStyle;
        result.deepMarkerHeight=marker.getBoundingClientRect().height;
        window.__stashSetKeyboardOcclusion(null);scroller.scrollTop=0;
        canvas.appendChild(marker);painted.remove();field.focus({preventScroll:true});
        const label=document.createElement('label');label.htmlFor='field';label.textContent='Name on card';
        label.style.cssText='display:block;height:24px';field.before(label);
        const labelTail=document.createElement('div');labelTail.style.height='500px';marker.appendChild(labelTail);
        document.querySelector('#lead').style.height='290px';scroller.scrollTop=0;
        window.__stashSetKeyboardOcclusion([0,20,390,280,390,600]);window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));
        result.labelBelowTop=label.getBoundingClientRect().top;result.labelBelowFieldBottom=field.getBoundingClientRect().bottom;
        window.__stashSetKeyboardOcclusion(null);scroller.scrollTop=300;window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));
        result.labelDockedTop=label.getBoundingClientRect().top;result.labelDockedFieldBottom=field.getBoundingClientRect().bottom;
        label.id='field-caption';label.removeAttribute('for');field.setAttribute('aria-labelledby','field-caption');
        scroller.scrollTop=0;window.__stashSetKeyboardOcclusion([0,20,390,280,390,600]);window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));result.ariaLabelTop=label.getBoundingClientRect().top;
        window.__stashSetKeyboardOcclusion(null);field.removeAttribute('aria-labelledby');label.remove();labelTail.remove();
        scroller.scrollTop=0;
        const framePort=document.createElement('div');framePort.style.cssText='position:fixed;inset:0;overflow:auto;background:white';
        framePort.innerHTML='<div style="height:290px"></div><div id="frameField"><div id="frameLabel" aria-hidden="true" style="height:24px">Card number</div><div><iframe title="Card number" tabindex="0" style="display:block;border:0;width:90%;height:34px"></iframe></div></div><div style="height:500px"></div>';
        document.body.appendChild(framePort);const frame=framePort.querySelector('iframe'),frameLabel=framePort.querySelector('#frameLabel');
        window.__stashSetKeyboardOcclusion([0,20,390,280,390,600]);
        result.iframeLabelOffset=window.__stashTestLabelRange(frame,0,34).top;
        const duplicate=frameLabel.cloneNode(true);frameLabel.after(duplicate);
        result.duplicateLabelOffset=window.__stashTestLabelRange(frame,0,34).top;
        duplicate.remove();const other=document.createElement('input');other.style.height='34px';frameLabel.after(other);
        result.multipleControlLabelOffset=window.__stashTestLabelRange(frame,0,34).top;
        window.__stashSetKeyboardOcclusion(null);framePort.remove();field.focus({preventScroll:true});
        document.querySelector('#lead').style.height='320px';
        window.__stashSetKeyboardOcclusion([0,240,390,200,390,600]);window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));
        result.clearanceBeforePageHide=document.querySelectorAll('[data-stash-keyboard-clearance]').length;
        dispatchEvent(new PageTransitionEvent('pagehide'));
        result.remainingAfterPageHide=document.querySelectorAll('[data-stash-keyboard-clearance]').length;
        return result;
        """, in: web)
        if let data = try? JSONSerialization.data(withJSONObject: direct, options: .sortedKeys),
           let text = String(data: data, encoding: .utf8) { print("FLOATING_FIXTURE_FOCUS " + text) }
        XCTAssertLessThanOrEqual(try XCTUnwrap(direct["bottom"] as? Double), 232)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(direct["top"] as? Double), 8)
        XCTAssertEqual(direct["height"] as? Double, 600)
        XCTAssertEqual(direct["staleWidthTop"] as? Double, 320)
        XCTAssertEqual(direct["clearedTop"] as? Double, 320)
        XCTAssertTrue(direct["style"] is NSNull)
        XCTAssertEqual(direct["value"] as? String, "Native value")
        XCTAssertEqual(direct["start"] as? Int, 1)
        XCTAssertEqual(direct["end"] as? Int, 5)
        XCTAssertEqual(direct["shortRangeBefore"] as? Double, 0)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(direct["shortTop"] as? Double), 8)
        XCTAssertLessThanOrEqual(try XCTUnwrap(direct["shortBottom"] as? Double), 232)
        XCTAssertEqual(direct["clearanceCount"] as? Int, 1)
        XCTAssertEqual(direct["shortViewport"] as? Double, 600)
        XCTAssertEqual(direct["shortContainer"] as? Double, 600)
        XCTAssertEqual(direct["markerBefore"] as? Double, 354)
        XCTAssertEqual(direct["markerAfter"] as? Double, 354)
        XCTAssertEqual(direct["remainingAfterHide"] as? Int, 0)
        XCTAssertEqual(direct["remainingAfterBlur"] as? Int, 0)
        XCTAssertEqual(direct["authoredPadding"] as? String, "11px")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(direct["belowTop"] as? Double), 308)
        XCTAssertLessThanOrEqual(try XCTUnwrap(direct["belowBottom"] as? Double), 592)
        XCTAssertEqual(direct["belowClearanceCount"] as? Int, 1)
        XCTAssertEqual(direct["belowMarkerHeight"] as? Double, 854)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(direct["shortBelowTop"] as? Double), 308)
        XCTAssertLessThanOrEqual(try XCTUnwrap(direct["shortBelowBottom"] as? Double), 592)
        XCTAssertEqual(direct["canvasAnchored"] as? Bool, true)
        XCTAssertEqual(direct["canvasCoversTop"] as? Bool, true)
        XCTAssertEqual(direct["authoredCanvasUnchanged"] as? Bool, true)
        XCTAssertEqual(direct["shortBelowScroll"] as? Double, 0)
        XCTAssertEqual(direct["shortBelowMarkerHeight"] as? Double, 134)
        XCTAssertEqual(direct["shortBelowClearance"] as? Int, 1)
        XCTAssertEqual(direct["shortBelowRestored"] as? Double, 100)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(direct["wrappedBelowTop"] as? Double), 308)
        XCTAssertEqual(direct["wrappedCanvasTop"] as? Double, 0)
        XCTAssertEqual(direct["wrappedCanvasCoversTop"] as? Bool, true)
        XCTAssertEqual(direct["wrappedMarkerHeight"] as? Double, 134)
        XCTAssertEqual(direct["wrappedStylePreserved"] as? Bool, true)
        XCTAssertEqual(direct["wrappedClearance"] as? Int, 1)
        XCTAssertEqual(direct["wrappedRestoredTop"] as? Double, 100)
        XCTAssertLessThanOrEqual(try XCTUnwrap(direct["deepBottom"] as? Double), 232)
        XCTAssertEqual(direct["deepClearanceOwner"] as? String, "painted")
        XCTAssertEqual(direct["deepPaintOwnsBottom"] as? Bool, true)
        XCTAssertEqual(direct["deepPaintOrigin"] as? Double, direct["deepPaintOriginal"] as? Double)
        XCTAssertEqual(direct["deepPaintStyle"] as? Bool, true)
        XCTAssertEqual(direct["deepMarkerHeight"] as? Double, 370)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(direct["labelBelowTop"] as? Double), 308)
        XCTAssertLessThanOrEqual(try XCTUnwrap(direct["labelBelowFieldBottom"] as? Double), 592)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(direct["labelDockedTop"] as? Double), 8)
        XCTAssertLessThanOrEqual(try XCTUnwrap(direct["labelDockedFieldBottom"] as? Double), 592)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(direct["ariaLabelTop"] as? Double), 308)
        XCTAssertEqual(direct["iframeLabelOffset"] as? Double, -24)
        XCTAssertEqual(direct["duplicateLabelOffset"] as? Double, 0)
        XCTAssertEqual(direct["multipleControlLabelOffset"] as? Double, 0)
        XCTAssertEqual(direct["clearanceBeforePageHide"] as? Int, 1)
        XCTAssertEqual(direct["remainingAfterPageHide"] as? Int, 0)

        XCTAssertEqual(web.bounds.size, CGSize(width: 390, height: 600))
    }

    @MainActor func testFractionalMissingRangeExtendsInnerFlexPaintImmediately() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(
            source: StashNativeInteractionSource(), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 900), configuration: configuration)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        let host = UIViewController()
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window: UIWindow
        if let scene = previous?.windowScene { window = UIWindow(windowScene: scene) }
        else { window = UIWindow(frame: web.frame) }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.addSubview(web)
        defer {
            web.navigationDelegate = nil
            web.stopLoading()
            window.isHidden = true
            previous?.makeKey()
        }
        let loaded = expectation(description: "fractional keyboard clearance fixture loaded")
        let navigation = FloatingNavigation { loaded.fulfill() }
        web.navigationDelegate = navigation
        web.loadHTMLString("""
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;overflow:hidden}main{position:fixed;inset:0;overflow:auto}
        input{display:block;height:34px;box-sizing:border-box;font-size:16px;width:90%}</style></head><body></body></html>
        """, baseURL: URL(string: "https://checkout.invalid"))
        await fulfillment(of: [loaded], timeout: 15)
        let settling = try await evaluate("""
        await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
        document.body.innerHTML='<main id="settlingPort"><article style="min-height:100%;display:flex;flex-direction:column;background:#ebede8"><div id="innerPaint" style="background:#f7f9f4;position:relative;flex:1;margin-top:-16px"><section data-stash-content><div style="height:313px"></div><input id="settlingField" value="Preserved"><div style="height:471px"></div></section></div></article></main>';
        const port=document.querySelector('#settlingPort'),field=document.querySelector('#settlingField');
        field.focus({preventScroll:true});const before=field.getBoundingClientRect();
        window.__stashSetKeyboardOcclusion([0,267.5,390,336,390,900]);window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));
        const result={beforeTop:before.top,bottom:field.getBoundingClientRect().bottom,scroll:port.scrollTop,height:innerHeight,
        marker:document.querySelector('[data-stash-content]').getBoundingClientRect().height,
        owner:document.querySelector('[data-stash-keyboard-clearance]')?.parentElement.id,
        paintCoversBottom:!!document.elementFromPoint(10,890).closest('#innerPaint'),value:field.value};
        window.__stashSetKeyboardOcclusion(null);
        const tail=document.createElement('div');tail.style.height='500px';document.querySelector('#innerPaint').appendChild(tail);
        port.scrollTop=72;result.nearBeforeTop=field.getBoundingClientRect().top;result.nearBeforeBottom=field.getBoundingClientRect().bottom;
        window.__stashSetKeyboardOcclusion([0,267,390,336,390,900]);window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));result.nearBottom=field.getBoundingClientRect().bottom;
        window.__stashSetKeyboardOcclusion(null);tail.remove();port.scrollTop=0;
        result.smallInitialRange=port.scrollHeight-port.clientHeight;
        window.__stashSetKeyboardOcclusion([0,40,390,855,390,900]);window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));
        const rect=field.getBoundingClientRect();result.smallTop=rect.top;result.smallBottom=rect.bottom;
        window.__stashRevealFocusedElement();await new Promise(resolve=>setTimeout(resolve,150));
        result.smallStableTop=field.getBoundingClientRect().top;result.smallStableBottom=field.getBoundingClientRect().bottom;
        window.__stashSetKeyboardOcclusion(null);
        result.remaining=document.querySelectorAll('[data-stash-keyboard-clearance]').length;
        document.body.innerHTML='<main><div style="height:20px"></div><div id="nested" style="height:80px;overflow:auto"><div style="height:100px"></div><input id="nestedField"><div style="height:100px"></div></div></main>';
        const nested=document.querySelector('#nested'),nestedField=document.querySelector('#nestedField');nestedField.focus({preventScroll:true});
        result.clippedBefore=nestedField.getBoundingClientRect().top>nested.getBoundingClientRect().bottom;
        window.__stashSetKeyboardOcclusion([0,400,390,400,390,900]);window.__stashRevealFocusedElement();
        await new Promise(resolve=>setTimeout(resolve,150));
        result.nestedTop=nestedField.getBoundingClientRect().top;result.nestedBottom=nestedField.getBoundingClientRect().bottom;
        result.nestedPortTop=nested.getBoundingClientRect().top;result.nestedPortBottom=nested.getBoundingClientRect().bottom;
        window.__stashSetKeyboardOcclusion(null);return result;
        """, in: web)
        XCTAssertEqual(settling["beforeTop"] as? Double, 297)
        XCTAssertLessThanOrEqual(try XCTUnwrap(settling["bottom"] as? Double), 237)
        // The public guide temporarily reports 267.5 while the visible keyboard starts at 245.
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(settling["scroll"] as? Double), 95.5)
        XCTAssertEqual(settling["height"] as? Double, 900)
        XCTAssertEqual(settling["marker"] as? Double, 818)
        XCTAssertEqual(settling["owner"] as? String, "innerPaint")
        XCTAssertEqual(settling["paintCoversBottom"] as? Bool, true)
        XCTAssertEqual(settling["value"] as? String, "Preserved")
        XCTAssertEqual(settling["nearBeforeTop"] as? Double, 225)
        XCTAssertEqual(settling["nearBeforeBottom"] as? Double, 259)
        XCTAssertLessThanOrEqual(try XCTUnwrap(settling["nearBottom"] as? Double), 235.5)
        XCTAssertEqual(settling["smallInitialRange"] as? Double, 0)
        XCTAssertEqual(try XCTUnwrap(settling["smallTop"] as? Double), 3, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(settling["smallBottom"] as? Double), 37, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(settling["smallStableTop"] as? Double), 3, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(settling["smallStableBottom"] as? Double), 37, accuracy: 0.5)
        XCTAssertEqual(settling["remaining"] as? Int, 0)
        XCTAssertEqual(settling["clippedBefore"] as? Bool, true)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(settling["nestedTop"] as? Double), try XCTUnwrap(settling["nestedPortTop"] as? Double))
        XCTAssertLessThanOrEqual(try XCTUnwrap(settling["nestedBottom"] as? Double), try XCTUnwrap(settling["nestedPortBottom"] as? Double))
    }

    @MainActor private func evaluate(_ script: String, in web: WKWebView) async throws -> [String: Any] {
        let value: Any? = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        return try XCTUnwrap(value as? [String: Any])
    }
}

private final class FloatingNavigation: NSObject, WKNavigationDelegate {
    private let loaded: () -> Void
    init(loaded: @escaping () -> Void) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded() }
}
