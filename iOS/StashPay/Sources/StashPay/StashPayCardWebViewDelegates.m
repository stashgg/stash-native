//
//  StashPayCardWebViewDelegates.m
//  StashPay
//
//  WKNavigationDelegate and WKUIDelegate implementations for the card WebView.
//  Shared state via extern declarations; see StashPayCard.m for definitions.
//

#import "StashPayCard.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

#pragma mark - Loading / Reveal Constants (aligned with card animation timing)

static const NSTimeInterval kPageReadyCheckInterval = 0.1;
static const NSTimeInterval kLoadingRevealAnimationDuration = 0.35;
static const NSTimeInterval kNetworkTimeoutInterval = 5.0;
/// Fallback: reveal modal after this delay if WebView callbacks never fire (e.g. in Unreal)
static const NSTimeInterval kModalFallbackRevealInterval = 2.0;
static NSString * const kForceDarkBackgroundJS =
    @"document.documentElement.style.backgroundColor = 'black'; "
    @"document.body.style.backgroundColor = 'black'; "
    @"var style = document.createElement('style'); "
    @"style.innerHTML = 'body, html { background-color: black !important; }'; "
    @"document.head.appendChild(style);";

#pragma mark - Extern declarations (defined in StashPayCard.m)

extern BOOL _usePopupPresentation;
extern BOOL _useModalPresentation;
extern BOOL isRunningOniPad(void);
extern UIColor* getSystemBackgroundColor(void);
extern UIViewController *getTopPresentedViewController(void);

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
    BOOL _initialLoadComplete;
    BOOL _networkErrorHandled;
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

- (void)handleNetworkTimeout:(NSTimer*)timer {
    if (!_initialLoadComplete && !_networkErrorHandled) {
        NSLog(@"StashPay: Network timeout - page did not load within %.0f seconds", kNetworkTimeoutInterval);
        [self handleNetworkError];
    }
}

- (void)handleNetworkError {
    if (_networkErrorHandled) return;
    _networkErrorHandled = YES;
    
    // Cancel timers
    [_timeoutTimer invalidate];
    _timeoutTimer = nil;
    [_networkTimeoutTimer invalidate];
    _networkTimeoutTimer = nil;
    [_modalFallbackTimer invalidate];
    _modalFallbackTimer = nil;
    
    // Call the network error callback
    id<StashPayCardDelegate> delegate = [StashPayCard sharedInstance].delegate;
    if (delegate && [delegate respondsToSelector:@selector(stashPayCardDidEncounterNetworkError)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate stashPayCardDidEncounterNetworkError];
        });
    }
    
    // Dismiss the dialog without calling onDismiss
    dispatch_async(dispatch_get_main_queue(), ^{
        [[StashPayCard sharedInstance] resetPresentationState];
    });
}

- (void)cancelNetworkTimeout {
    if (_networkTimeoutTimer) {
        [_networkTimeoutTimer invalidate];
        _networkTimeoutTimer = nil;
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    NSURL *url = navigationAction.request.URL;
    NSString *urlString = url.absoluteString;
    
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
    
    // Check for HTTP error status codes on initial load
    if (!_initialLoadComplete && navigationResponse.isForMainFrame) {
        if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)navigationResponse.response;
            NSInteger statusCode = httpResponse.statusCode;
            
            // Treat 4xx and 5xx status codes as errors
            if (statusCode >= 400) {
                NSLog(@"StashPay: HTTP error on main frame during initial load: %ld", (long)statusCode);
                decisionHandler(WKNavigationResponsePolicyCancel);
                [self handleNetworkError];
                return;
            }
        }
    }
    
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)handleTimeout:(NSTimer*)timer {
    // For modal presentations, don't reveal on short (0.1s) timeout - wait for didCommit/didFinish or fallback timer
    if (_useModalPresentation) {
        return;
    }
    [self showWebViewAndRemoveLoading];
}

- (void)handleModalFallbackReveal:(NSTimer*)timer {
    _modalFallbackTimer = nil;
    if (!_initialLoadComplete && !_networkErrorHandled) {
        [self showWebViewAndRemoveLoading];
    }
}

- (void)showWebViewAndRemoveLoading {
    if (_timeoutTimer) {
        [_timeoutTimer invalidate];
        _timeoutTimer = nil;
    }
    if (_modalFallbackTimer) {
        [_modalFallbackTimer invalidate];
        _modalFallbackTimer = nil;
    }
    
    // Mark initial load as complete and cancel network timeout
    if (!_initialLoadComplete) {
        _initialLoadComplete = YES;
        [self cancelNetworkTimeout];
    }
    
    if (_webView.alpha < 0.01) {
        UIColor *backgroundColor = getSystemBackgroundColor();
        _webView.backgroundColor = backgroundColor;
        _webView.scrollView.backgroundColor = backgroundColor;
        _webView.scrollView.opaque = YES;
        _webView.opaque = YES;
        
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
        }];
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (self.pageLoadStartTime > 0) {
        CFAbsoluteTime loadEndTime = CFAbsoluteTimeGetCurrent();
        double loadTimeSeconds = loadEndTime - self.pageLoadStartTime;
        double loadTimeMs = loadTimeSeconds * 1000.0;
        
        id<StashPayCardDelegate> delegate = [StashPayCard sharedInstance].delegate;
        if (delegate && [delegate respondsToSelector:@selector(stashPayCardDidLoadPage:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate stashPayCardDidLoadPage:loadTimeMs];
            });
        }
        
        self.pageLoadStartTime = 0;
    }
    
#if __has_feature(objc_arc)
    __weak WebViewLoadDelegate *weakSelf = self;
#else
    __unsafe_unretained WebViewLoadDelegate *weakSelf = self;
#endif
    __block void (^checkPageReady)(void);
#if __has_feature(objc_arc)
    __block __weak void (^weakCheckPageReady)(void);
#endif
    checkPageReady = ^{
        NSString *readyCheck = @"(function() { \
            if (document.readyState !== 'complete') return false; \
            if (document.documentElement.style.display === 'none') return false; \
            if (document.body === null) return false; \
            if (window.getComputedStyle(document.body).display === 'none') return false; \
            return true; \
        })()";
        
        [webView evaluateJavaScript:readyCheck completionHandler:^(id result, NSError *error) {
            if ([result boolValue]) {
                WebViewLoadDelegate *strongSelf = weakSelf;
                if (strongSelf) {
                    if (@available(iOS 13.0, *)) {
                        UIUserInterfaceStyle currentStyle = [UITraitCollection currentTraitCollection].userInterfaceStyle;
                        if (currentStyle == UIUserInterfaceStyleDark) {
                            [webView evaluateJavaScript:kForceDarkBackgroundJS completionHandler:^(id result, NSError *error) {
                                [strongSelf showWebViewAndRemoveLoading];
                            }];
                        } else {
                            [strongSelf showWebViewAndRemoveLoading];
                        }
                    } else {
                        [strongSelf showWebViewAndRemoveLoading];
                    }
                }
            } else {
#if __has_feature(objc_arc)
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPageReadyCheckInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (weakCheckPageReady) {
                        weakCheckPageReady();
                    }
                });
#else
                __unsafe_unretained void (^weakCheckPageReady)(void) = checkPageReady;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPageReadyCheckInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (weakCheckPageReady) {
                        weakCheckPageReady();
                    }
                });
#endif
            }
        }];
    };
#if __has_feature(objc_arc)
    weakCheckPageReady = checkPageReady;
#endif
    checkPageReady();
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    // iPhone checkout: reveal on commit. Modal: also reveal on commit (Unreal etc. may never get didFinish)
    if ((!_usePopupPresentation && !isRunningOniPad()) || _useModalPresentation) {
        [self showWebViewAndRemoveLoading];
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled) {
        return;
    }
    
    // If initial load hasn't completed, treat as network error
    if (!_initialLoadComplete) {
        NSLog(@"StashPay: Navigation failed during initial load: %@", error.localizedDescription);
        [self handleNetworkError];
    } else {
        [[StashPayCard sharedInstance] dismiss];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled) {
        return;
    }
    
    // If initial load hasn't completed, treat as network error
    if (!_initialLoadComplete) {
        NSLog(@"StashPay: Provisional navigation failed during initial load: %@", error.localizedDescription);
        [self handleNetworkError];
    } else {
        [[StashPayCard sharedInstance] dismiss];
    }
}

- (void)dealloc {
    if (_timeoutTimer) {
        [_timeoutTimer invalidate];
        _timeoutTimer = nil;
    }
    if (_modalFallbackTimer) {
        [_modalFallbackTimer invalidate];
        _modalFallbackTimer = nil;
    }
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
