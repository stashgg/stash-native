//
//  StashNativeCardWebViewDelegates.mm
//  StashNativeDesktop
//
//  WKNavigationDelegate / WKUIDelegate for one presentation (load timers, navigation policy
//  through the session, web-content process recovery, new windows, JS panels) and the shared
//  script message proxy. Mirrors StashNativeCardWebViewDelegates.m on iOS.
//

#import "StashNativeCardPrivate.h"

#include "StashDesktopUrl.h"
#include "StashNativeDesktop.h"

using stash::desktop::NavigationDecision;
using stash::desktop::Session;

@implementation StashNativeCardLoadDelegate {
    __weak StashDesktopCore *_core;
    NSUInteger _sessionId;
    __weak WKWebView *_webView;
    NSURL *_checkoutURL;
    BOOL _allowFileUrls;
    BOOL _invalidated;
    BOOL _initialLoadComplete;
    int _stallReloadCount;
    BOOL _processTerminateRecoveryUsed;
    NSTimer *_stallTimer;
    NSTimer *_deadlineTimer;
    CFAbsoluteTime _pageLoadStartTime;
}

- (instancetype)initWithCore:(StashDesktopCore *)core sessionId:(NSUInteger)sessionId {
    self = [super init];
    if (self) {
        _core = core;
        _sessionId = sessionId;
    }
    return self;
}

- (Session *)session {
    if (_invalidated) {
        return nullptr;
    }
    return [_core sessionForId:_sessionId];
}

- (void)invalidate {
    _invalidated = YES;
    [_stallTimer invalidate];
    _stallTimer = nil;
    [_deadlineTimer invalidate];
    _deadlineTimer = nil;
}

#pragma mark - Loading and timers

static void StashAddTimerToMainRunLoop(NSTimer *timer) {
    if (timer) {
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    }
}

- (void)loadCheckoutURL {
    WKWebView *webView = _webView;
    if (!webView || !_checkoutURL) {
        return;
    }
    [[_core presenter] setLoading:YES];
    if ([_checkoutURL.scheme.lowercaseString isEqualToString:@"file"]) {
        if (!_allowFileUrls) {
            // WebKit would fail the request without a policy callback; run the policy here so
            // the refusal is reported the same way (navigationBlocked, then networkError).
            Session *session = [self session];
            if (session) {
                session->decideMainFrameNavigation(_checkoutURL.absoluteString.UTF8String ?: "");
                [_core refreshStateMirrors];
            }
            return;
        }
        // Read access to the containing directory so relative assets resolve. Do not standardize
        // the path: /private/tmp would become /tmp and fall outside the granted directory.
        [webView loadFileURL:_checkoutURL allowingReadAccessToURL:[_checkoutURL URLByDeletingLastPathComponent]];
    } else {
        NSURLRequest *request = [NSURLRequest requestWithURL:_checkoutURL
                                                 cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                             timeoutInterval:stash::desktop::kNetworkDeadlineSeconds];
        [webView loadRequest:request];
    }
}

- (void)scheduleDeadlineTimer {
    [_deadlineTimer invalidate];
    _deadlineTimer = [NSTimer timerWithTimeInterval:stash::desktop::kNetworkDeadlineSeconds
                                             target:self
                                           selector:@selector(handleDeadline:)
                                           userInfo:nil
                                            repeats:NO];
    StashAddTimerToMainRunLoop(_deadlineTimer);
}

// Stall retries are for network stalls; a local file that has not committed yet is just slow.
- (void)scheduleStallTimer {
    [_stallTimer invalidate];
    _stallTimer = nil;
    if (_initialLoadComplete || _stallReloadCount >= stash::desktop::kMaxStallReloads ||
        [_checkoutURL.scheme.lowercaseString isEqualToString:@"file"]) {
        return;
    }
    _stallTimer = [NSTimer timerWithTimeInterval:stash::desktop::kStallRetrySeconds
                                          target:self
                                        selector:@selector(handleStall:)
                                        userInfo:nil
                                         repeats:NO];
    StashAddTimerToMainRunLoop(_stallTimer);
}

- (void)startLoadingURL:(NSURL *)url inWebView:(WKWebView *)webView allowFileUrls:(BOOL)allowFileUrls {
    _webView = webView;
    _checkoutURL = url;
    _allowFileUrls = allowFileUrls;
    _pageLoadStartTime = CFAbsoluteTimeGetCurrent();
    _initialLoadComplete = NO;
    _stallReloadCount = 0;
    [self loadCheckoutURL];
    if (_invalidated) {
        // The load was refused and the session already closed.
        return;
    }
    [self scheduleDeadlineTimer];
    [self scheduleStallTimer];
}

// No main-frame HTTP response yet: reload from the network, up to kMaxStallReloads times.
- (void)handleStall:(NSTimer *)timer {
    (void)timer;
    _stallTimer = nil;
    Session *session = [self session];
    if (!session || _initialLoadComplete || _stallReloadCount >= stash::desktop::kMaxStallReloads) {
        return;
    }
    _stallReloadCount += 1;
    STASH_DESKTOP_LOG(@"StashNativeDesktop: stall retry %d/%d", _stallReloadCount, stash::desktop::kMaxStallReloads);
    [self loadCheckoutURL];
    [self scheduleDeadlineTimer];
    [self scheduleStallTimer];
}

- (void)handleDeadline:(NSTimer *)timer {
    (void)timer;
    _deadlineTimer = nil;
    Session *session = [self session];
    if (!session || _initialLoadComplete) {
        return;
    }
    STASH_DESKTOP_LOG(@"StashNativeDesktop: load deadline reached after %d stall reload(s)", _stallReloadCount);
    session->handleNetworkError();
}

- (void)markInitialLoadComplete {
    if (_initialLoadComplete) {
        return;
    }
    _initialLoadComplete = YES;
    [_stallTimer invalidate];
    _stallTimer = nil;
    [_deadlineTimer invalidate];
    _deadlineTimer = nil;
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    (void)webView;
    Session *session = [self session];
    if (!session) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    std::string url = navigationAction.request.URL.absoluteString.UTF8String ?: "";
    if (url == "about:blank") {
        // The prewarmed webview's placeholder document, never a checkout: no policy, no event.
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    BOOL isMainFrame = navigationAction.targetFrame == nil || navigationAction.targetFrame.isMainFrame;
    NavigationDecision decision = isMainFrame ? session->decideMainFrameNavigation(url)
                                             : session->decideSubFrameNavigation(url);
    [_core refreshStateMirrors];
    decisionHandler(decision == NavigationDecision::Load ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
                      decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    (void)webView;
    Session *session = [self session];
    if (!session) {
        decisionHandler(WKNavigationResponsePolicyCancel);
        return;
    }
    // Main-frame HTTP: 4xx / 5xx fail the load; redirect hops keep the stall timers armed; any
    // other status means document bytes arrived.
    if (!_initialLoadComplete && navigationResponse.isForMainFrame &&
        [navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger status = ((NSHTTPURLResponse *)navigationResponse.response).statusCode;
        if (status >= 400) {
            STASH_DESKTOP_LOG(@"StashNativeDesktop: HTTP %ld on the main frame during initial load", (long)status);
            decisionHandler(WKNavigationResponsePolicyCancel);
            session->handleNetworkError();
            return;
        }
        if (!stash::desktop::url::isRedirectStatus((int)status)) {
            [self markInitialLoadComplete];
        }
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    (void)navigation;
    if (![self session]) {
        return;
    }
    NSString *scheme = webView.URL.scheme.lowercaseString;
    if ([scheme isEqualToString:@"file"] || [scheme isEqualToString:@"data"]) {
        [self markInitialLoadComplete];
    }
    [[_core presenter] updateTrustHeaderForURL:webView.URL];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)navigation;
    Session *session = [self session];
    if (!session) {
        return;
    }
    [[_core presenter] setLoading:NO];
    [[_core presenter] updateTrustHeaderForURL:webView.URL];
    double loadTimeMs = (CFAbsoluteTimeGetCurrent() - _pageLoadStartTime) * 1000.0;
    session->handlePageFinished(loadTimeMs);
}

- (void)handleLoadFailure:(NSError *)error {
    Session *session = [self session];
    if (!session) {
        return;
    }
    if (error.code == NSURLErrorCancelled ||
        ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102)) {
        // Cancelled by our own policy or superseded; frame-load-interrupted is a download / plugin.
        return;
    }
    STASH_DESKTOP_LOG(@"StashNativeDesktop: load failed %@ (%ld)", error.domain, (long)error.code);
    if (!_initialLoadComplete) {
        session->handleNetworkError();
    } else {
        session->dismiss();
    }
    [_core refreshStateMirrors];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    [self handleLoadFailure:error];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    [self handleLoadFailure:error];
}

// One reload after a web-content process death; a second death is a network error.
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    (void)webView;
    Session *session = [self session];
    if (!session) {
        return;
    }
    if (_processTerminateRecoveryUsed) {
        // Host-visible diagnostic; delivered through the same path as every event.
        session->handleNetworkError();
        [_core refreshStateMirrors];
        return;
    }
    _processTerminateRecoveryUsed = YES;
    _initialLoadComplete = NO;
    STASH_DESKTOP_LOG(@"StashNativeDesktop: web content process terminated, reloading");
    [self loadCheckoutURL];
    [self scheduleDeadlineTimer];
    [self scheduleStallTimer];
}

#pragma mark - WKUIDelegate

- (WKWebView *)webView:(WKWebView *)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
               forNavigationAction:(WKNavigationAction *)navigationAction
                    windowFeatures:(WKWindowFeatures *)windowFeatures {
    (void)webView;
    (void)configuration;
    (void)windowFeatures;
    // target=_blank / window.open: external browser, the checkout stays presented.
    Session *session = [self session];
    if (session) {
        session->handleNewWindow(navigationAction.request.URL.absoluteString.UTF8String ?: "");
    }
    return nil;
}

- (void)webViewDidClose:(WKWebView *)webView {
    (void)webView;
    Session *session = [self session];
    if (session) {
        session->handleWindowClose();
        [_core refreshStateMirrors];
    }
}

- (NSAlert *)alertWithMessage:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message ?: @"";
    return alert;
}

- (void)webView:(WKWebView *)webView
    runJavaScriptAlertPanelWithMessage:(NSString *)message
                      initiatedByFrame:(WKFrameInfo *)frame
                     completionHandler:(void (^)(void))completionHandler {
    (void)webView;
    (void)frame;
    NSAlert *alert = [self alertWithMessage:message];
    [alert addButtonWithTitle:@"OK"];
    NSWindow *window = [_core presenter].sheetWindow;
    if (window) {
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
            (void)response;
            completionHandler();
        }];
    } else {
        completionHandler();
    }
}

- (void)webView:(WKWebView *)webView
    runJavaScriptConfirmPanelWithMessage:(NSString *)message
                        initiatedByFrame:(WKFrameInfo *)frame
                       completionHandler:(void (^)(BOOL))completionHandler {
    (void)webView;
    (void)frame;
    NSAlert *alert = [self alertWithMessage:message];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSWindow *window = [_core presenter].sheetWindow;
    if (window) {
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
            completionHandler(response == NSAlertFirstButtonReturn);
        }];
    } else {
        completionHandler(NO);
    }
}

- (void)webView:(WKWebView *)webView
    runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
                              defaultText:(NSString *)defaultText
                         initiatedByFrame:(WKFrameInfo *)frame
                        completionHandler:(void (^)(NSString *))completionHandler {
    (void)webView;
    (void)frame;
    NSWindow *window = [_core presenter].sheetWindow;
    if (!window) {
        // Nothing to present on: the page sees a cancelled prompt, as confirm() sees Cancel.
        completionHandler(nil);
        return;
    }
    NSAlert *alert = [self alertWithMessage:prompt];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    field.stringValue = defaultText ?: @"";
    alert.accessoryView = field;
    alert.window.initialFirstResponder = field;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        completionHandler(response == NSAlertFirstButtonReturn ? field.stringValue : nil);
    }];
}

@end

@implementation StashDesktopMessageProxy {
    __weak StashDesktopCore *_core;
}

- (instancetype)initWithCore:(StashDesktopCore *)core {
    self = [super init];
    if (self) {
        _core = core;
    }
    return self;
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    [_core handleMessageNamed:message.name body:message.body fromWebView:message.webView];
}

@end
