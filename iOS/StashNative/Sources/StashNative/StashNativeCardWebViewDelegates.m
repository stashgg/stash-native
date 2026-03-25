//
//  StashNativeCardWebViewDelegates.m
//  StashNative
//
//  WKNavigationDelegate and WKUIDelegate implementations for the card WebView.
//  Shared state via extern declarations; see StashNativeCard.m for definitions.
//

#import "StashNativeCard.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

#pragma mark - Loading / Reveal Constants (aligned with card animation timing)

static const NSTimeInterval kPageReadyCheckInterval = 0.1;
static const NSTimeInterval kLoadingRevealAnimationDuration = 0.35;
/// How long to wait for any HTTP response before retrying the load once.
static const NSTimeInterval kRetryTimeoutInterval = 3.0;
/// Hard deadline — if still no commit after the retry, report a network error.
static const NSTimeInterval kNetworkTimeoutInterval = 15.0;
/// Fallback: reveal modal after this delay if WebView callbacks never fire (e.g. in Unreal)
static const NSTimeInterval kModalFallbackRevealInterval = 2.0;
static NSString * const kForceDarkBackgroundJS =
    @"document.documentElement.style.backgroundColor = '#1e1e1e'; "
    @"if (document.body) document.body.style.backgroundColor = '#1e1e1e';";

#pragma mark - Extern declarations (defined in StashNativeCard.m)

extern BOOL _usePopupPresentation;
extern BOOL _useModalPresentation;
extern BOOL isRunningOniPad(void);
extern UIColor* getSystemBackgroundColor(void);
extern UIViewController *getTopPresentedViewController(void);
extern void configureScrollViewForWebView(UIScrollView *scrollView);

#pragma mark - WebViewLoadDelegate

@interface WebViewLoadDelegate : NSObject <WKNavigationDelegate>
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, assign) CFAbsoluteTime pageLoadStartTime;
- (instancetype)initWithWebView:(WKWebView*)webView loadingView:(UIView*)loadingView;
@end

@implementation WebViewLoadDelegate {
#if __has_feature(objc_arc)
    __weak WKWebView* _webView;
#else
    __unsafe_unretained WKWebView* _webView;
#endif
    UIView* _loadingView;
    NSTimer* _timeoutTimer;
    NSTimer* _networkTimeoutTimer;
    NSTimer* _modalFallbackTimer;
    /// Fires after kRetryTimeoutInterval if no HTTP response has arrived — triggers one retry.
    NSTimer* _retryTimer;
    BOOL _initialLoadComplete;
    BOOL _networkErrorHandled;
    /// URL captured from the first main-frame navigationAction; used when retrying.
    NSURL* _checkoutURL;
    /// Incremented on each retry attempt; prevents infinite retry loops.
    int _retryCount;
}

- (instancetype)initWithWebView:(WKWebView*)webView loadingView:(UIView*)loadingView {
    self = [super init];
    if (self) {
        _webView = webView;
        self.webView = webView;
        _loadingView = loadingView;
        _initialLoadComplete = NO;
        _networkErrorHandled = NO;
        
        _timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:kPageReadyCheckInterval
                                                        target:self
                                                      selector:@selector(handleTimeout:)
                                                      userInfo:nil
                                                       repeats:NO];
        
        // Start network timeout timer (5 seconds)
        _networkTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:kNetworkTimeoutInterval
                                                                target:self
                                                              selector:@selector(handleNetworkTimeout:)
                                                              userInfo:nil
                                                               repeats:NO];
        // Modal fallback: reveal after N seconds if didCommit/didFinish never fire (e.g. Unreal)
        if (_useModalPresentation) {
            _modalFallbackTimer = [NSTimer scheduledTimerWithTimeInterval:kModalFallbackRevealInterval
                                                                  target:self
                                                                selector:@selector(handleModalFallbackReveal:)
                                                                userInfo:nil
                                                                 repeats:NO];
        } else {
            _modalFallbackTimer = nil;
        }
    }
    return self;
}

- (void)handleRetryTimer:(NSTimer *)timer {
    _retryTimer = nil;
    if (_initialLoadComplete || _networkErrorHandled || !_checkoutURL || !_webView) return;

    _retryCount = 1;
    NSLog(@"StashNative: no HTTP response in %.0fs — retrying %@", kRetryTimeoutInterval, _checkoutURL.absoluteString);

    // Issue the new request directly — WKWebView cancels the stalled navigation internally
    // and fires didFailNavigation with NSURLErrorCancelled (which we already suppress).
    // Skipping an explicit stopLoading() avoids any intermediate visual state that could
    // cause a flash, and NSURLRequestReloadIgnoringLocalCacheData ensures WebKit opens a
    // fresh TCP connection rather than reusing the stale one.
    NSURLRequest *retryRequest = [NSURLRequest requestWithURL:_checkoutURL
                                                  cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                              timeoutInterval:kNetworkTimeoutInterval];
    [_webView loadRequest:retryRequest];
}

- (void)handleNetworkTimeout:(NSTimer*)timer {
    if (!_initialLoadComplete && !_networkErrorHandled) {
        NSLog(@"StashNative: TIMEOUT %.0fs — no didCommit after %d attempt(s)",
              kNetworkTimeoutInterval, _retryCount + 1);
        [self handleNetworkError];
    }
}

- (void)handleNetworkError {
    if (_networkErrorHandled) return;
    _networkErrorHandled = YES;
    
    // Cancel timers
    [_retryTimer invalidate];
    _retryTimer = nil;
    [_timeoutTimer invalidate];
    _timeoutTimer = nil;
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

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    (void)webView;
    NSLog(@"StashNative: WebContent process terminated — reloading");
    if (_networkErrorHandled || !_checkoutURL || !_webView) {
        [self handleNetworkError];
        return;
    }
    // One reload after process death; second termination surfaces as network error.
    if (_retryCount >= 1) {
        [self handleNetworkError];
        return;
    }
    _retryCount = 1;
    _initialLoadComplete = NO;
    [_retryTimer invalidate];
    _retryTimer = nil;
    [_networkTimeoutTimer invalidate];
    _networkTimeoutTimer = nil;

    NSURLRequest *fresh = [NSURLRequest requestWithURL:_checkoutURL
                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                       timeoutInterval:kNetworkTimeoutInterval];
    [_webView loadRequest:fresh];

    _networkTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:kNetworkTimeoutInterval
                                                            target:self
                                                          selector:@selector(handleNetworkTimeout:)
                                                          userInfo:nil
                                                           repeats:NO];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    NSURL *url = navigationAction.request.URL;
    NSString *urlString = url.absoluteString;
    NSLog(@"StashNative: navigationAction type=%ld url=%@", (long)navigationAction.navigationType, urlString);

    // Arm the retry timer the first time the main checkout URL is loaded.
    // If no HTTP response arrives within kRetryTimeoutInterval we cancel and reload once.
    if (navigationAction.targetFrame.isMainFrame && !_initialLoadComplete && _retryCount == 0 && !_networkErrorHandled) {
        _checkoutURL = url;
        [_retryTimer invalidate];
        _retryTimer = [NSTimer scheduledTimerWithTimeInterval:kRetryTimeoutInterval
                                                      target:self
                                                    selector:@selector(handleRetryTimer:)
                                                    userInfo:nil
                                                     repeats:NO];
    }

    if ([url.scheme isEqualToString:@"tel"] ||
        [url.scheme isEqualToString:@"mailto"] ||
        [url.scheme isEqualToString:@"sms"]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    
    if ([urlString containsString:@"apps.apple.com"] ||
        [urlString containsString:@"itunes.apple.com"]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {

    // HTTP response arrived — the connection is alive, no need to retry.
    if (navigationResponse.isForMainFrame) {
        [_retryTimer invalidate];
        _retryTimer = nil;
    }

    // Check for HTTP error status codes on initial load
    if (!_initialLoadComplete && navigationResponse.isForMainFrame) {
        if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)navigationResponse.response;
            NSInteger statusCode = httpResponse.statusCode;
            NSLog(@"StashNative: navigationResponse mainFrame=%d status=%ld url=%@",
                  navigationResponse.isForMainFrame, (long)statusCode, httpResponse.URL.absoluteString);
            
            // Treat 4xx and 5xx status codes as errors
            if (statusCode >= 400) {
                NSLog(@"StashNative: HTTP error on main frame during initial load: %ld", (long)statusCode);
                decisionHandler(WKNavigationResponsePolicyCancel);
                [self handleNetworkError];
                return;
            }
        }
    }
    
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)handleTimeout:(NSTimer*)timer {
    // No-op: the WebView is revealed by didCommitNavigation for all presentation types.
    // Revealing at 0.1s (before any content arrives) shows an empty black WebView.
    // The 5-second network timeout (handleNetworkTimeout) handles pages that never load.
}

- (void)handleModalFallbackReveal:(NSTimer*)timer {
    _modalFallbackTimer = nil;
    if (!_initialLoadComplete && !_networkErrorHandled) {
        [self showWebViewAndRemoveLoading];
    }
}

- (void)showWebViewAndRemoveLoading {
    if (_webView) {
        configureScrollViewForWebView(_webView.scrollView);
    }
    if (_timeoutTimer) {
        [_timeoutTimer invalidate];
        _timeoutTimer = nil;
    }
    if (_modalFallbackTimer) {
        [_modalFallbackTimer invalidate];
        _modalFallbackTimer = nil;
    }
    
    if (_webView.alpha < 0.01) {
        UIColor *backgroundColor = getSystemBackgroundColor();
        _webView.backgroundColor = backgroundColor;
        _webView.scrollView.backgroundColor = backgroundColor;
        _webView.scrollView.opaque = YES;
        // Opaque WebView + simultaneous crossfade composites against an internal white
        // background — causes a white flash. Non-opaque composites against backgroundColor.
        _webView.opaque = NO;
        
        if (@available(iOS 13.0, *)) {
            UIUserInterfaceStyle currentStyle = [UITraitCollection currentTraitCollection].userInterfaceStyle;
            if (currentStyle == UIUserInterfaceStyleDark) {
                [_webView evaluateJavaScript:kForceDarkBackgroundJS completionHandler:nil];
            }
        }
        
        // For modal: also reveal the cardView (parent) and overlay which start hidden
        UIView *cardView = _useModalPresentation ? _webView.superview : nil;
        UIView *overlayView = nil;
        if (_useModalPresentation && cardView) {
            // The overlay is the first subview of the container view (cardView's parent)
            UIView *containerView = cardView.superview;
            if (containerView && containerView.subviews.count > 0) {
                UIView *firstSubview = containerView.subviews.firstObject;
                // Overlay has tag 0 and is not the cardView
                if (firstSubview != cardView) {
                    overlayView = firstSubview;
                }
            }
        }
        
        [UIView animateWithDuration:kLoadingRevealAnimationDuration delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self->_loadingView.alpha = 0.0;
            self->_webView.alpha = 1.0;
            if (cardView) {
                cardView.alpha = 1.0;
            }
            if (overlayView) {
                overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
            }
        } completion:^(BOOL finished) {
            [self->_loadingView removeFromSuperview];
            self->_webView.opaque = YES;
        }];
    }
}

/// Poll every kPageReadyCheckInterval until the page has left the 'loading' readyState
/// (i.e. HTML parsed + CSS applied), then reveal the WebView.
/// Called from both didCommitNavigation and didFinishNavigation so the reveal happens
/// as soon as the page is visually ready — never before CSS is applied.
- (void)pollUntilPageReady {
    if (!_webView || _networkErrorHandled) return;
    // Already revealed — nothing to do.
    if (_webView.alpha >= 0.01) return;

    NSString *readyCheck =
        @"(function(){"
        @"  if(document.readyState==='loading') return false;"
        @"  if(document.documentElement.style.display==='none') return false;"
        @"  if(!document.body) return false;"
        @"  if(window.getComputedStyle(document.body).display==='none') return false;"
        @"  return true;"
        @"})()";

#if __has_feature(objc_arc)
    __weak WebViewLoadDelegate *weakSelf = self;
#else
    __unsafe_unretained WebViewLoadDelegate *weakSelf = self;
#endif
    [_webView evaluateJavaScript:readyCheck completionHandler:^(id result, NSError *error) {
        WebViewLoadDelegate *strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_networkErrorHandled) return;
        if ([result boolValue]) {
            [strongSelf showWebViewAndRemoveLoading];
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPageReadyCheckInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf pollUntilPageReady];
            });
        }
    }];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (webView) {
        configureScrollViewForWebView(webView.scrollView);
    }
    // Ensure network timeout is cancelled even if didCommit was skipped (edge case).
    if (!_initialLoadComplete) {
        _initialLoadComplete = YES;
        [self cancelNetworkTimeout];
    }
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
    // Ensure reveal happens even if didCommit polling hasn't fired yet.
    [self pollUntilPageReady];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    if (webView) {
        configureScrollViewForWebView(webView.scrollView);
    }
    NSLog(@"StashNative: didCommitNavigation url=%@", webView.URL.absoluteString);
    // Content is arriving — cancel the network error timeout.
    if (!_initialLoadComplete) {
        _initialLoadComplete = YES;
        [self cancelNetworkTimeout];
    }
    // Start polling for page readiness. The WebView stays hidden behind the loading
    // view until readyState reaches 'interactive' (HTML parsed, all CSS applied) so
    // we never reveal a white/unthemed page.
    [self pollUntilPageReady];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"StashNative: didFailNavigation domain=%@ code=%ld msg=%@ url=%@",
          error.domain, (long)error.code, error.localizedDescription, webView.URL.absoluteString);
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
    NSLog(@"StashNative: didFailProvisionalNavigation domain=%@ code=%ld msg=%@ url=%@",
          error.domain, (long)error.code, error.localizedDescription,
          [error.userInfo[NSURLErrorFailingURLStringErrorKey] description] ?: webView.URL.absoluteString);
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
    _networkErrorHandled = YES;
    if (_retryTimer) {
        [_retryTimer invalidate];
        _retryTimer = nil;
    }
    if (_timeoutTimer) {
        [_timeoutTimer invalidate];
        _timeoutTimer = nil;
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
}

@end

#pragma mark - WebViewUIDelegate

@interface WebViewUIDelegate : NSObject <WKUIDelegate>
@end

@implementation WebViewUIDelegate

- (void)webView:(WKWebView *)webView contextMenuConfigurationForElement:(WKContextMenuElementInfo *)elementInfo completionHandler:(void (^)(UIContextMenuConfiguration *))completionHandler API_AVAILABLE(ios(13.0)) {
    completionHandler(nil);
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler();
    }];
    [alert addAction:okAction];
    
    [getTopPresentedViewController() presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
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
    
    [getTopPresentedViewController() presentViewController:alert animated:YES completion:nil];
}

@end
