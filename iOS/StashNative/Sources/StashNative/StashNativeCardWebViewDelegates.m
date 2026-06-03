//
//  StashNativeCardWebViewDelegates.m
//  StashNative
//
//  WebViewLoadDelegate: the card WebView's WKNavigationDelegate; the WKUIDelegate is the separate WebViewUIDelegate below. Holds the load-recovery
//  machinery -- the stall-retry timer chain (up to two reloads), the hard network-error deadline, and
//  the session-token gate (StashNativeCurrentPresentationSessionToken) that drops callbacks from a
//  closed card. Shared file-scope state declared as externs in StashNativeCardPrivate.h.
//

#import "StashNativeCard.h"
#import "StashNativeCardPrivate.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>



#pragma mark - Loading / Reveal Constants

static const NSTimeInterval kLoadingRevealAnimationDuration = 0.35;
/// Page-readiness predicate matching the injected `stashNativePageReady` hook; evaluated from didFinishNavigation.
static NSString * const kPageReadyEvalJS =
    @"(function(){"
    @"try{"
    @"if(document.readyState==='loading')return false;"
    @"if(!document.documentElement)return false;"
    @"if(window.getComputedStyle(document.documentElement).display==='none')return false;"
    @"if(!document.body)return false;"
    @"if(window.getComputedStyle(document.body).display==='none')return false;"
    @"}catch(e){return false;}"
    @"return true;"
    @"})()";
/// Seconds before and between stall-retry reloads while the main frame is not responding.
static const NSTimeInterval kRetryTimeoutInterval = 1.25;
/// Seconds without a main-frame HTTP success before reporting a network error.
static const NSTimeInterval kNetworkTimeoutInterval = 15.0;
/// Seconds after which the modal is revealed if no WebView load callback fires.
static const NSTimeInterval kModalFallbackRevealInterval = 2.0;
#pragma mark - WebViewLoadDelegate

@implementation WebViewLoadDelegate {
#if __has_feature(objc_arc)
    __weak WKWebView* _webView;
#else
    __unsafe_unretained WKWebView* _webView;
#endif
    UIView* _loadingView;
    NSTimer* _networkTimeoutTimer;
    NSTimer* _modalFallbackTimer;
    /// Fires the stall-retry reload after kRetryTimeoutInterval and re-arms in handleRetryTimer:, up to two reloads total.
    NSTimer* _retryTimer;
    BOOL _initialLoadComplete;
    BOOL _networkErrorHandled;
    /// URL captured from the first main-frame navigationAction; used for retries.
    NSURL* _checkoutURL;
    /// Extra seconds added before the retry timer is armed.
    NSTimeInterval _retryArmDelay;
    /// Count of stall reloads issued from handleRetryTimer, capped at 2.
    int _stallReloadCount;
    /// Token captured at init; callbacks run only when it matches StashNativeCurrentPresentationSessionToken().
    NSUInteger _expectedPresentationSessionToken;
    /// Set after the first WebContent process-termination reload; a second termination is a hard failure.
    BOOL _processTerminateRecoveryUsed;
    /// Count of foreground recovery reloads, capped at 1.
    int _foregroundRecoveryReloads;
}

static void stashRestartLoadingSpinnerInView(UIView *loadingView) {
    if (!loadingView) {
        return;
    }
    for (UIView *sub in loadingView.subviews) {
        if ([sub isKindOfClass:[UIActivityIndicatorView class]]) {
            [(UIActivityIndicatorView *)sub startAnimating];
        }
    }
}

/// Adds the timer to the main run loop in NSRunLoopCommonModes.
static void stashAddTimerToMainRunLoop(NSTimer *timer) {
    if (timer) {
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    }
}

/// True for HTTP redirect statuses only — not 304 (Not Modified) or other 3xx.
static BOOL stashHTTPStatusIsRedirect(NSInteger statusCode) {
    return statusCode == 301 || statusCode == 302 || statusCode == 303 || statusCode == 307 || statusCode == 308;
}

- (BOOL)sessionIsValidForCallbacks {
    NSUInteger current = StashNativeCurrentPresentationSessionToken();
    return current == _expectedPresentationSessionToken;
}

/// Covers the WebView with the loading layer and sets the WebView alpha to 0 before a new navigation.
- (void)prepareWebViewForReloadHidingFlash {
    if (!_webView || _networkErrorHandled) {
        return;
    }
    WKWebView *wv = _webView;
    UIColor *bg = stash_sheetBackgroundUIColor();
    stash_setWebViewBackgroundColor(wv, bg);
    wv.opaque = NO;
    wv.scrollView.backgroundColor = bg;
    wv.scrollView.opaque = YES;

    if (@available(iOS 13.0, *)) {
        if (StashNativeSheetUsesDarkWebTheme()) {
            [wv evaluateJavaScript:StashNativeDarkSheetBackgroundJavaScript() completionHandler:nil];
        }
    }

    UIView *parent = wv.superview;
    if (_loadingView && parent) {
        if (_loadingView.superview != parent) {
            [_loadingView removeFromSuperview];
            _loadingView.translatesAutoresizingMaskIntoConstraints = NO;
            [parent addSubview:_loadingView];
            [NSLayoutConstraint activateConstraints:@[
                [_loadingView.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
                [_loadingView.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor],
                [_loadingView.topAnchor constraintEqualToAnchor:parent.topAnchor],
                [_loadingView.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor],
            ]];
        }
        if (@available(iOS 13.0, *)) {
            BOOL dark = [UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark;
            _loadingView.backgroundColor = dark ? StashNativeDarkSurfaceColor() : [UIColor whiteColor];
        }
        _loadingView.alpha = 1.0;
        _loadingView.hidden = NO;
        _loadingView.userInteractionEnabled = YES;
        stashRestartLoadingSpinnerInView(_loadingView);
        [parent bringSubviewToFront:_loadingView];
        // Bring the drag tray above the loading mask.
        UIView *dragTray = [parent viewWithTag:kDragTrayViewTag];
        if (dragTray) {
            [parent bringSubviewToFront:dragTray];
        }
    }
    wv.alpha = 0.0;
}

- (instancetype)initWithWebView:(WKWebView*)webView
                    loadingView:(UIView*)loadingView
                  retryArmDelay:(NSTimeInterval)retryArmDelay
       presentationSessionToken:(NSUInteger)presentationSessionToken {
    self = [super init];
    if (self) {
        _webView = webView;
#if __has_feature(objc_arc)
        _loadingView = loadingView;
#else
        _loadingView = [loadingView retain];
#endif
        _retryArmDelay = retryArmDelay;
        _expectedPresentationSessionToken = presentationSessionToken;
        _stallReloadCount = 0;
        _processTerminateRecoveryUsed = NO;
        _foregroundRecoveryReloads = 0;
        _initialLoadComplete = NO;
        _networkErrorHandled = NO;
        
        STASH_DEBUG_LOG(@"StashNativeRetryTrace delegate init session=%lu", (unsigned long)_expectedPresentationSessionToken);
        
        // Start network timeout timer.
        _networkTimeoutTimer = [NSTimer timerWithTimeInterval:kNetworkTimeoutInterval
                                                       target:self
                                                     selector:@selector(handleNetworkTimeout:)
                                                     userInfo:nil
                                                      repeats:NO];
        stashAddTimerToMainRunLoop(_networkTimeoutTimer);
        // Modal fallback timer: reveals after kModalFallbackRevealInterval if didCommit/didFinish never fire.
        if (stash_useModalPresentation) {
            _modalFallbackTimer = [NSTimer timerWithTimeInterval:kModalFallbackRevealInterval
                                                          target:self
                                                        selector:@selector(handleModalFallbackReveal:)
                                                        userInfo:nil
                                                         repeats:NO];
            stashAddTimerToMainRunLoop(_modalFallbackTimer);
        } else {
            _modalFallbackTimer = nil;
        }
    }
    return self;
}

- (void)scheduleNetworkTimeoutTimerFromCurrentLoadAttempt {
    if (![self sessionIsValidForCallbacks]) {
        return;
    }
    if (_networkErrorHandled || _initialLoadComplete) {
        return;
    }
    [_networkTimeoutTimer invalidate];
    _networkTimeoutTimer = [NSTimer timerWithTimeInterval:kNetworkTimeoutInterval
                                                   target:self
                                                 selector:@selector(handleNetworkTimeout:)
                                                 userInfo:nil
                                                  repeats:NO];
    stashAddTimerToMainRunLoop(_networkTimeoutTimer);
}

/// Arms the next stall-retry fire (or initial arm). Does not increment `_stallReloadCount`; `handleRetryTimer:` does.
- (void)scheduleStallRetryTimerWithDelay:(NSTimeInterval)delay reason:(NSString *)reason {
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace stall timer SKIP reason=%@ (stale session expected=%lu current=%lu)",
              reason ?: @"",
              (unsigned long)_expectedPresentationSessionToken,
              (unsigned long)StashNativeCurrentPresentationSessionToken());
        return;
    }
    if (_initialLoadComplete || _networkErrorHandled || !_checkoutURL || !_webView) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace stall timer SKIP reason=%@ (load complete=%d errorHandled=%d noURL=%d)",
              reason ?: @"", _initialLoadComplete, _networkErrorHandled, !_checkoutURL);
        return;
    }
    if (_stallReloadCount >= 2) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace stall timer SKIP reason=%@ (stall reload cap)", reason ?: @"");
        return;
    }
    [_retryTimer invalidate];
    _retryTimer = [NSTimer timerWithTimeInterval:delay
                                        target:self
                                      selector:@selector(handleRetryTimer:)
                                      userInfo:nil
                                       repeats:NO];
    stashAddTimerToMainRunLoop(_retryTimer);
    STASH_DEBUG_LOG(@"StashNativeRetryTrace stall timer ARM delay=%.2fs reason=%@ stallReloadCount=%d session=%lu",
          delay, reason ?: @"", _stallReloadCount, (unsigned long)_expectedPresentationSessionToken);
}

- (void)handleRetryTimer:(NSTimer *)timer {
    _retryTimer = nil;
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace stall timer FIRED ignored (stale session)");
        return;
    }
    if (_initialLoadComplete || _networkErrorHandled || !_checkoutURL || !_webView) return;

    // Caps at 2 stall reloads (3 total load attempts). Stall timers clear on main-frame
    // non-redirect HTTP success in decidePolicyForNavigationResponse, not on each didCommit.
    if (_stallReloadCount >= 2) {
        return;
    }
    _stallReloadCount += 1;
    STASH_DEBUG_LOG(@"StashNativeRetryTrace stall timer FIRE reload %d/2 url=%@ session=%lu",
          _stallReloadCount, _checkoutURL.absoluteString, (unsigned long)_expectedPresentationSessionToken);
    STASH_DEBUG_LOG(@"StashNative: stall retry %d/2 — reloading %@", _stallReloadCount, _checkoutURL.absoluteString);

    // Loads the request directly without stopLoading(), with NSURLRequestReloadIgnoringLocalCacheData.
    [self prepareWebViewForReloadHidingFlash];
    NSURLRequest *retryRequest = [NSURLRequest requestWithURL:_checkoutURL
                                                  cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                              timeoutInterval:kNetworkTimeoutInterval];
    [_webView loadRequest:retryRequest];

    // Restarts the full network deadline from this reload.
    [self scheduleNetworkTimeoutTimerFromCurrentLoadAttempt];

    if (_stallReloadCount < 2) {
        _retryTimer = [NSTimer timerWithTimeInterval:kRetryTimeoutInterval
                                              target:self
                                            selector:@selector(handleRetryTimer:)
                                            userInfo:nil
                                             repeats:NO];
        stashAddTimerToMainRunLoop(_retryTimer);
        STASH_DEBUG_LOG(@"StashNativeRetryTrace stall timer CHAIN re-arm in %.1fs (next fire)", kRetryTimeoutInterval);
    }
}

- (void)armRetryTimerIfNeededForMainFrameURL:(NSURL *)url {
    if (!url || _checkoutURL || _initialLoadComplete || _networkErrorHandled) {
        return;
    }
#if __has_feature(objc_arc)
    _checkoutURL = url;
#else
    _checkoutURL = [url retain];
#endif
    NSTimeInterval retryDelay = kRetryTimeoutInterval + MAX(0.0, _retryArmDelay);
    [self scheduleStallRetryTimerWithDelay:retryDelay reason:@"initial-main-frame-arm"];
}

- (void)handleNetworkTimeout:(NSTimer*)timer {
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace network timeout ignored (stale session)");
        return;
    }
    if (!_initialLoadComplete && !_networkErrorHandled) {
        STASH_DEBUG_LOG(@"StashNative: TIMEOUT %.0fs — no main-frame HTTP success (initial + %d stall reload(s))",
              kNetworkTimeoutInterval, _stallReloadCount);
        STASH_DEBUG_LOG(@"StashNativeRetryTrace network timeout %.0fs stallReloads=%d session=%lu",
              kNetworkTimeoutInterval, _stallReloadCount, (unsigned long)_expectedPresentationSessionToken);
        [self handleNetworkError];
    }
}

- (void)handleNetworkError {
    if (_networkErrorHandled) return;
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace handleNetworkError skipped (stale session)");
        return;
    }
    _networkErrorHandled = YES;
    STASH_DEBUG_LOG(@"StashNativeRetryTrace handleNetworkError session=%lu", (unsigned long)_expectedPresentationSessionToken);
    
    // Cancel timers
    [_retryTimer invalidate];
    _retryTimer = nil;
    [_networkTimeoutTimer invalidate];
    _networkTimeoutTimer = nil;
    [_modalFallbackTimer invalidate];
    _modalFallbackTimer = nil;
    
    // Call the network error callback
    id<StashNativeCardDelegate> delegate = [StashNativeCard sharedInstance].delegate;
    if (delegate && [delegate respondsToSelector:@selector(stashNativeCardDidEncounterNetworkError)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate stashNativeCardDidEncounterNetworkError];
        });
    }
    
    // Dismiss the dialog without calling onDismiss
    dispatch_async(dispatch_get_main_queue(), ^{
        [[StashNativeCard sharedInstance] resetPresentationState];
    });
}

- (void)cancelNetworkTimeout {
    if (_networkTimeoutTimer) {
        [_networkTimeoutTimer invalidate];
        _networkTimeoutTimer = nil;
    }
}

- (void)recoverStaleLoadAfterApplicationForegroundIfNeeded {
    if (![self sessionIsValidForCallbacks]) {
        return;
    }
    if (_initialLoadComplete || _networkErrorHandled || !_checkoutURL || !_webView) {
        return;
    }
    WKWebView *wv = _webView;
    STASH_DEBUG_LOG(@"StashNativeRetryTrace foreground recover begin stallReloads=%d isLoading=%d progress=%.3f url=%@ session=%lu",
          _stallReloadCount, wv.isLoading, wv.estimatedProgress, wv.URL.absoluteString ?: @"(nil)",
          (unsigned long)_expectedPresentationSessionToken);

    // Restarts the network deadline from now.
    [self scheduleNetworkTimeoutTimerFromCurrentLoadAttempt];

    // Re-arms the stall chain when no retry timer is scheduled.
    if (!_retryTimer) {
        [self scheduleStallRetryTimerWithDelay:kRetryTimeoutInterval + MAX(0.0, _retryArmDelay)
                                        reason:@"foreground-rearm-stall"];
    }

    // Reloads once when the WebView is idle with progress below 0.05.
    BOOL looksStuck = !wv.isLoading && wv.estimatedProgress < 0.05;
    if (looksStuck && _foregroundRecoveryReloads < 1) {
        _foregroundRecoveryReloads += 1;
        STASH_DEBUG_LOG(@"StashNativeRetryTrace foreground recover issuing reload (stuck idle before first progress)");
        [self prepareWebViewForReloadHidingFlash];
        NSURLRequest *req = [NSURLRequest requestWithURL:_checkoutURL
                                               cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                           timeoutInterval:kNetworkTimeoutInterval];
        [wv loadRequest:req];
        [self scheduleNetworkTimeoutTimerFromCurrentLoadAttempt];
        [self scheduleStallRetryTimerWithDelay:kRetryTimeoutInterval + MAX(0.0, _retryArmDelay)
                                        reason:@"foreground-reload"];
    }
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    (void)webView;
    STASH_DEBUG_LOG(@"StashNativeRetryTrace webContentProcessTerminate session=%lu stallReloads=%d recoveryUsed=%d",
          (unsigned long)_expectedPresentationSessionToken, _stallReloadCount, _processTerminateRecoveryUsed);
    STASH_DEBUG_LOG(@"StashNative: WebContent process terminated — reloading");
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace processTerminate ignored (stale session)");
        return;
    }
    if (_networkErrorHandled || !_checkoutURL || !_webView) {
        [self handleNetworkError];
        return;
    }
    // One reload after process death; second termination surfaces as network error (independent of stall count).
    if (_processTerminateRecoveryUsed) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace processTerminate — second termination, failing");
        [self handleNetworkError];
        return;
    }
    _processTerminateRecoveryUsed = YES;
    _initialLoadComplete = NO;
    [_retryTimer invalidate];
    _retryTimer = nil;
    [_networkTimeoutTimer invalidate];
    _networkTimeoutTimer = nil;

    [self prepareWebViewForReloadHidingFlash];
    NSURLRequest *fresh = [NSURLRequest requestWithURL:_checkoutURL
                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                       timeoutInterval:kNetworkTimeoutInterval];
    [_webView loadRequest:fresh];

    [self scheduleNetworkTimeoutTimerFromCurrentLoadAttempt];
    NSTimeInterval delay = kRetryTimeoutInterval + MAX(0.0, _retryArmDelay);
    [self scheduleStallRetryTimerWithDelay:delay reason:@"process-terminate-reload"];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace navigationAction CANCEL stale session");
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    NSURL *url = navigationAction.request.URL;
    NSString *urlString = url.absoluteString;
    STASH_DEBUG_LOG(@"StashNative: navigationAction type=%ld url=%@", (long)navigationAction.navigationType, urlString);
    STASH_DEBUG_LOG(@"StashNativeRetryTrace navigationAction type=%ld url=%@ session=%lu",
          (long)navigationAction.navigationType, urlString, (unsigned long)_expectedPresentationSessionToken);

    // Retry arming is driven by the explicit presenter URL via armRetryTimerIfNeededForMainFrameURL:.

    if ([url.scheme isEqualToString:@"tel"] ||
        [url.scheme isEqualToString:@"mailto"] ||
        [url.scheme isEqualToString:@"sms"]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    
    NSString *host = url.host.lowercaseString;
    if ([host isEqualToString:@"apps.apple.com"] ||
        [host isEqualToString:@"itunes.apple.com"]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)markInitialLoadProgressFromMainFrameHTTPResponse:(NSHTTPURLResponse *)httpResponse {
    (void)httpResponse;
    if (![self sessionIsValidForCallbacks]) {
        return;
    }
    if (_initialLoadComplete || _networkErrorHandled) {
        return;
    }
    [_retryTimer invalidate];
    _retryTimer = nil;
    _initialLoadComplete = YES;
    STASH_DEBUG_LOG(@"StashNativeRetryTrace main-frame HTTP progress — clear stall timers session=%lu stallReloads=%d",
          (unsigned long)_expectedPresentationSessionToken, _stallReloadCount);
    [self cancelNetworkTimeout];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace navigationResponse CANCEL stale session");
        decisionHandler(WKNavigationResponsePolicyCancel);
        return;
    }

    // Main-frame HTTP: 4xx/5xx report a network error; 301/302/303/307/308 are redirect hops that
    // leave the stall timers running; non-redirect success (2xx, 304, etc.) marks initial progress
    // and clears the stall timers.
    if (!_initialLoadComplete && navigationResponse.isForMainFrame) {
        if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)navigationResponse.response;
            NSInteger statusCode = httpResponse.statusCode;
            STASH_DEBUG_LOG(@"StashNative: navigationResponse mainFrame=%d status=%ld url=%@",
                  navigationResponse.isForMainFrame, (long)statusCode, httpResponse.URL.absoluteString);
            STASH_DEBUG_LOG(@"StashNativeRetryTrace navigationResponse mainFrame=%d status=%ld url=%@ session=%lu",
                  navigationResponse.isForMainFrame, (long)statusCode, httpResponse.URL.absoluteString,
                  (unsigned long)_expectedPresentationSessionToken);

            if (statusCode >= 400) {
                STASH_DEBUG_LOG(@"StashNative: HTTP error on main frame during initial load: %ld", (long)statusCode);
                decisionHandler(WKNavigationResponsePolicyCancel);
                [self handleNetworkError];
                return;
            }
            if (stashHTTPStatusIsRedirect(statusCode)) {
                decisionHandler(WKNavigationResponsePolicyAllow);
                return;
            }
            [self markInitialLoadProgressFromMainFrameHTTPResponse:httpResponse];
        }
        // Non-NSHTTPURLResponse: leave stall timers until timeout, data:/file: fallback in didCommit, or later HTTP response.
    }

    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)handleModalFallbackReveal:(NSTimer*)timer {
    _modalFallbackTimer = nil;
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace modal fallback ignored (stale session)");
        return;
    }
    if (!_initialLoadComplete && !_networkErrorHandled) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace modal fallback reveal session=%lu", (unsigned long)_expectedPresentationSessionToken);
        [self showWebViewAndRemoveLoading];
    }
}

- (void)showWebViewAndRemoveLoading {
    if (![self sessionIsValidForCallbacks]) {
        return;
    }
    if (_webView) {
        stash_configureScrollViewForWebView(_webView.scrollView);
    }
    if (_modalFallbackTimer) {
        [_modalFallbackTimer invalidate];
        _modalFallbackTimer = nil;
    }
    
    if (_webView.alpha < 0.01) {
        UIColor *backgroundColor = stash_sheetBackgroundUIColor();
        _webView.backgroundColor = backgroundColor;
        _webView.scrollView.backgroundColor = backgroundColor;
        _webView.scrollView.opaque = YES;
        // Marks the WebView non-opaque so it composites against backgroundColor during the crossfade.
        _webView.opaque = NO;

        if (@available(iOS 13.0, *)) {
            if (StashNativeSheetUsesDarkWebTheme()) {
                [_webView evaluateJavaScript:StashNativeDarkSheetBackgroundJavaScript() completionHandler:nil];
            }
        }
        
        // Modal: backdrop and card are shown on presentation; only crossfade loading → WebView here.
        [UIView animateWithDuration:kLoadingRevealAnimationDuration delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self->_loadingView.alpha = 0.0;
            self->_webView.alpha = 1.0;
        } completion:^(BOOL finished) {
            // Leaves the loading view in the hierarchy and disables its interaction.
            self->_loadingView.userInteractionEnabled = NO;
            self->_webView.opaque = YES;
        }];
    }
}

- (void)notifyPageReadyFromInjectedScript {
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace pageReady script ignored (stale session)");
        return;
    }
    STASH_DEBUG_LOG(@"StashNativeRetryTrace pageReady from injected hook session=%lu",
          (unsigned long)_expectedPresentationSessionToken);
    [self showWebViewAndRemoveLoading];
}

/// Evaluates kPageReadyEvalJS once after navigation finishes; reveals the WebView when it returns true.
- (void)evaluatePageReadyOnceAfterNavigationFinished {
    if (!_webView || _networkErrorHandled) {
        return;
    }
    if (![self sessionIsValidForCallbacks]) {
        return;
    }
    if (_webView.alpha >= 0.01) {
        return;
    }
#if __has_feature(objc_arc)
    __weak WebViewLoadDelegate *weakSelf = self;
#else
    __unsafe_unretained WebViewLoadDelegate *weakSelf = self;
#endif
    [_webView evaluateJavaScript:kPageReadyEvalJS completionHandler:^(id result, NSError *error) {
        WebViewLoadDelegate *strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_networkErrorHandled) {
            return;
        }
        if (![strongSelf sessionIsValidForCallbacks]) {
            STASH_DEBUG_LOG(@"StashNativeRetryTrace pageReady fallback eval aborted (stale session)");
            return;
        }
        if (strongSelf->_webView.alpha >= 0.01) {
            return;
        }
        if ([result boolValue]) {
            [strongSelf showWebViewAndRemoveLoading];
        }
    }];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace didFinishNavigation ignored (stale session)");
        return;
    }
    STASH_DEBUG_LOG(@"StashNativeRetryTrace didFinishNavigation session=%lu", (unsigned long)_expectedPresentationSessionToken);
    if (webView) {
        stash_configureScrollViewForWebView(webView.scrollView);
    }
    // Initial load completion for stall timers is driven by main-frame non-redirect HTTP
    // response (or data:/file: fallback in didCommit), not didFinish alone.
    if (self.pageLoadStartTime > 0) {
        CFAbsoluteTime loadEndTime = CFAbsoluteTimeGetCurrent();
        double loadTimeSeconds = loadEndTime - self.pageLoadStartTime;
        double loadTimeMs = loadTimeSeconds * 1000.0;

        id<StashNativeCardDelegate> delegate = [StashNativeCard sharedInstance].delegate;
        if (delegate && [delegate respondsToSelector:@selector(stashNativeCardDidLoadPage:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate stashNativeCardDidLoadPage:loadTimeMs];
            });
        }

        self.pageLoadStartTime = 0;
    }
    // Fallback for when the injected `stashNativePageReady` message does not fire.
    [self evaluatePageReadyOnceAfterNavigationFinished];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace didCommitNavigation ignored (stale session)");
        return;
    }
    if (webView) {
        stash_configureScrollViewForWebView(webView.scrollView);
    }
    STASH_DEBUG_LOG(@"StashNative: didCommitNavigation url=%@", webView.URL.absoluteString);
    STASH_DEBUG_LOG(@"StashNativeRetryTrace didCommit url=%@ session=%lu", webView.URL.absoluteString, (unsigned long)_expectedPresentationSessionToken);
    // Does not clear stall timers; decidePolicyForNavigationResponse marks progress on non-redirect HTTP.
    // Fallback for non-HTTP main-frame loads (data:, file:) that have no HTTP status.
    if (!_initialLoadComplete && !_networkErrorHandled) {
        NSURL *u = webView.URL;
        NSString *scheme = u.scheme.lowercaseString;
        if ([scheme isEqualToString:@"data"] || [scheme isEqualToString:@"file"]) {
            [self markInitialLoadProgressFromMainFrameHTTPResponse:nil];
        }
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    STASH_DEBUG_LOG(@"StashNative: didFailNavigation domain=%@ code=%ld msg=%@ url=%@",
          error.domain, (long)error.code, error.localizedDescription, webView.URL.absoluteString);
    STASH_DEBUG_LOG(@"StashNativeRetryTrace didFailNavigation code=%ld session=%lu",
          (long)error.code, (unsigned long)_expectedPresentationSessionToken);
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace didFailNavigation ignored (stale session)");
        return;
    }
    if (error.code == NSURLErrorCancelled) {
        return;
    }
    
    if (!_initialLoadComplete) {
        [self handleNetworkError];
    } else {
        [[StashNativeCard sharedInstance] dismiss];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    STASH_DEBUG_LOG(@"StashNative: didFailProvisionalNavigation domain=%@ code=%ld msg=%@ url=%@",
          error.domain, (long)error.code, error.localizedDescription,
          [error.userInfo[NSURLErrorFailingURLStringErrorKey] description] ?: webView.URL.absoluteString);
    STASH_DEBUG_LOG(@"StashNativeRetryTrace didFailProvisional code=%ld session=%lu",
          (long)error.code, (unsigned long)_expectedPresentationSessionToken);
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace didFailProvisional ignored (stale session)");
        return;
    }
    if (error.code == NSURLErrorCancelled) {
        return;
    }
    
    if (!_initialLoadComplete) {
        [self handleNetworkError];
    } else {
        [[StashNativeCard sharedInstance] dismiss];
    }
}

- (void)invalidateAllTimers {
    STASH_DEBUG_LOG(@"StashNativeRetryTrace invalidateAllTimers session=%lu", (unsigned long)_expectedPresentationSessionToken);
    _networkErrorHandled = YES;
    if (_retryTimer) {
        [_retryTimer invalidate];
        _retryTimer = nil;
    }
    if (_networkTimeoutTimer) {
        [_networkTimeoutTimer invalidate];
        _networkTimeoutTimer = nil;
    }
    if (_modalFallbackTimer) {
        [_modalFallbackTimer invalidate];
        _modalFallbackTimer = nil;
    }
}

- (void)dealloc {
    [self invalidateAllTimers];
#if !__has_feature(objc_arc)
    [_loadingView release];
    [_checkoutURL release];
    [super dealloc];
#endif
}

@end

#pragma mark - WebViewUIDelegate

@implementation WebViewUIDelegate

- (void)webView:(WKWebView *)webView contextMenuConfigurationForElement:(WKContextMenuElementInfo *)elementInfo completionHandler:(void (^)(UIContextMenuConfiguration *))completionHandler API_AVAILABLE(ios(13.0)) {
    completionHandler(nil);
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    UIViewController *presenter = stash_getTopPresentedViewController();
    if (!presenter) {
        completionHandler();
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler();
    }];
    [alert addAction:okAction];
    
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    UIViewController *presenter = stash_getTopPresentedViewController();
    if (!presenter) {
        completionHandler(NO);
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        completionHandler(NO);
    }];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler(YES);
    }];
    [alert addAction:cancelAction];
    [alert addAction:okAction];
    
    [presenter presentViewController:alert animated:YES completion:nil];
}

@end
