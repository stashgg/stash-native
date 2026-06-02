//
//  StashNativeCardWebViewDelegates.m
//  StashNative
//
//  WKNavigationDelegate and WKUIDelegate implementations for the card WebView.
//  Shared state via extern declarations; see StashNativeCard.m for definitions.
//

#import "StashNativeCard.h"
#import "StashNativeCardPrivate.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>


#ifdef DEBUG
#define STASH_DEBUG_LOG(...) NSLog(__VA_ARGS__)
#else
#define STASH_DEBUG_LOG(...)
#endif

#pragma mark - Loading / Reveal Constants (aligned with card animation timing)

static const NSTimeInterval kLoadingRevealAnimationDuration = 0.35;
/// Same eligibility as injected `stashNativePageReady` hook; one-shot eval from didFinishNavigation only.
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
/// Stall-retry cadence: time before / between aggressive reloads when the main frame is not responding.
static const NSTimeInterval kRetryTimeoutInterval = 1.25;
/// Hard deadline — if still no commit after the retry, report a network error.
static const NSTimeInterval kNetworkTimeoutInterval = 15.0;
/// Fallback: reveal modal after this delay if WebView callbacks never fire (e.g. in Unreal)
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
    /// Fires after kRetryTimeoutInterval if no HTTP response has arrived — triggers one retry.
    NSTimer* _retryTimer;
    BOOL _initialLoadComplete;
    BOOL _networkErrorHandled;
    /// URL captured from the first main-frame navigationAction; used when retrying.
    NSURL* _checkoutURL;
    /// Additional delay before arming retry timer (e.g. iPhone portrait rotation warm-up).
    NSTimeInterval _retryArmDelay;
    /// Stall-based reloads issued from handleRetryTimer (max 2). Independent of process-terminate recovery.
    int _stallReloadCount;
    /// Token captured at init; must match StashNativeCurrentPresentationSessionToken() for callbacks.
    NSUInteger _expectedPresentationSessionToken;
    /// Second WebContent process termination during the same presentation is a hard failure.
    BOOL _processTerminateRecoveryUsed;
    /// At most one opportunistic reload when returning active — avoids breaking redirect chains on repeated foreground.
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

/// Timers must use the main run loop so they fire when the host opens the card from a background thread.
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

/// Covers the WebView with the loading layer and hides the WebView before a new navigation.
/// WKWebView often flashes white during reload even in dark mode; this masks that until content is ready again.
- (void)prepareWebViewForReloadHidingFlash {
    if (!_webView || _networkErrorHandled) {
        return;
    }
    WKWebView *wv = _webView;
    UIColor *bg = stash_sheetBackgroundUIColor();
    setWebViewBackgroundColor(wv, bg);
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
            _loadingView.backgroundColor = dark ? [UIColor colorWithRed:0x1e/255.0 green:0x1e/255.0 blue:0x1e/255.0 alpha:1.0] : [UIColor whiteColor];
        }
        _loadingView.alpha = 1.0;
        _loadingView.hidden = NO;
        _loadingView.userInteractionEnabled = YES;
        stashRestartLoadingSpinnerInView(_loadingView);
        [parent bringSubviewToFront:_loadingView];
        // Keep drag tray above the loading mask (same order as initial setup: tray added last).
        // Otherwise bringSubviewToFront:loadingView hides the handle for every stall retry / reload.
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
        // Modal fallback: reveal after N seconds if didCommit/didFinish never fire (e.g. Unreal)
        if (_useModalPresentation) {
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

    // Up to 2 stall reloads (3 total load attempts). Stall timers clear on main-frame
    // non-redirect HTTP success in decidePolicyForNavigationResponse (not on each didCommit).
    if (_stallReloadCount >= 2) {
        return;
    }
    _stallReloadCount += 1;
    STASH_DEBUG_LOG(@"StashNativeRetryTrace stall timer FIRE reload %d/2 url=%@ session=%lu",
          _stallReloadCount, _checkoutURL.absoluteString, (unsigned long)_expectedPresentationSessionToken);
    STASH_DEBUG_LOG(@"StashNative: stall retry %d/2 — reloading %@", _stallReloadCount, _checkoutURL.absoluteString);

    // Issue the new request directly — WKWebView cancels the stalled navigation internally
    // and fires didFailNavigation with NSURLErrorCancelled (which we already suppress).
    // Skipping an explicit stopLoading() avoids any intermediate visual state that could
    // cause a flash, and NSURLRequestReloadIgnoringLocalCacheData ensures WebKit opens a
    // fresh TCP connection rather than reusing the stale one.
    [self prepareWebViewForReloadHidingFlash];
    NSURLRequest *retryRequest = [NSURLRequest requestWithURL:_checkoutURL
                                                  cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                              timeoutInterval:kNetworkTimeoutInterval];
    [_webView loadRequest:retryRequest];

    // Full deadline from this reload onward (previous 15s window may be almost exhausted).
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

    // Refresh the hard deadline from now — wall time in background does not match NSTimer semantics users expect.
    [self scheduleNetworkTimeoutTimerFromCurrentLoadAttempt];

    // Re-arm stall chain if nothing is scheduled (edge cases after suspend / process churn).
    if (!_retryTimer) {
        [self scheduleStallRetryTimerWithDelay:kRetryTimeoutInterval + MAX(0.0, _retryArmDelay)
                                        reason:@"foreground-rearm-stall"];
    }

    // WKWebView can be left idle with no navigation callbacks after backgrounding; nudge once.
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

    // Retry arming is now driven by explicit presenter URL to avoid redirect/about:blank races.

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

    // Main-frame HTTP: 4xx/5xx fail; 301/302/303/307/308 are redirect hops — do not clear stall
    // timers yet. Non-redirect success (2xx, 304, etc.) means bytes for a document response
    // arrived — safe to clear stall retry (didCommit fires per redirect leg and must not).
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
        configureScrollViewForWebView(_webView.scrollView);
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
        // Opaque WebView + simultaneous crossfade composites against an internal white
        // background — causes a white flash. Non-opaque composites against backgroundColor.
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
            // Keep loading view in hierarchy so stall/process/foreground reloads can cover the WebView
            // and avoid white flashes (do not removeFromSuperview).
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

/// If the injected document-end hook never posts (rare), one evaluation after navigation finishes.
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
        configureScrollViewForWebView(webView.scrollView);
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
    // Fallback if injected `stashNativePageReady` message did not fire (no polling).
    [self evaluatePageReadyOnceAfterNavigationFinished];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    if (![self sessionIsValidForCallbacks]) {
        STASH_DEBUG_LOG(@"StashNativeRetryTrace didCommitNavigation ignored (stale session)");
        return;
    }
    if (webView) {
        configureScrollViewForWebView(webView.scrollView);
    }
    STASH_DEBUG_LOG(@"StashNative: didCommitNavigation url=%@", webView.URL.absoluteString);
    STASH_DEBUG_LOG(@"StashNativeRetryTrace didCommit url=%@ session=%lu", webView.URL.absoluteString, (unsigned long)_expectedPresentationSessionToken);
    // Do not clear stall timers here: didCommit runs for each redirect leg; only
    // decidePolicyForNavigationResponse (non-redirect HTTP) marks progress.
    // Fallback for non-HTTP main-frame loads (data:, file:) where there is no HTTP status.
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
    UIViewController *presenter = getTopPresentedViewController();
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
    UIViewController *presenter = getTopPresentedViewController();
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
