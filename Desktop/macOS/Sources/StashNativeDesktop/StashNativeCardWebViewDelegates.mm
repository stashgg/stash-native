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
    // First didFinishNavigation of the presentation seen: failures before it are network
    // errors (nothing was ever shown), failures after it dismiss.
    BOOL _pageFinished;
    int _stallReloadCount;
    BOOL _processTerminateRecoveryUsed;
    NSTimer *_stallTimer;
    NSTimer *_deadlineTimer;
    CFAbsoluteTime _pageLoadStartTime;
    // The open JavaScript panel, if any: invalidate() ends it as cancelled.
    NSWindow *_panelWindow;
    void (^_panelCancel)(void);
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
    if (_panelCancel) {
        void (^cancel)(void) = _panelCancel;
        _panelCancel = nil;
        cancel();
    }
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
    _pageFinished = NO;
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
    if (navigationAction.targetFrame == nil) {
        // target=_blank without a window yet: the new-window rules apply (system browser or
        // deeplink), never the main-frame policy. Cancelling here means WebKit never asks the
        // UI delegate for a window, so the URL is handled exactly once.
        session->handleNewWindow(url);
        [_core refreshStateMirrors];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    NavigationDecision decision = navigationAction.targetFrame.isMainFrame ? session->decideMainFrameNavigation(url)
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
    if (navigationResponse.isForMainFrame && !navigationResponse.canShowMIMEType) {
        // A download or plugin response has no page to show. WebKit would report it as error
        // 102, which handleLoadFailure ignores, so it is decided here: before the first page
        // it is a network error, afterwards the shown page stays.
        decisionHandler(WKNavigationResponsePolicyCancel);
        if (!_pageFinished) {
            session->handleNetworkError();
            [_core refreshStateMirrors];
        }
        return;
    }
    // Main-frame HTTP before a page has finished (the first document or anything it navigates
    // to on its own): 4xx / 5xx are a network error; redirect hops keep the stall timers
    // armed; any other status means document bytes arrived. After a finished page an HTTP
    // error document is shown like any other page.
    if (navigationResponse.isForMainFrame && [navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger status = ((NSHTTPURLResponse *)navigationResponse.response).statusCode;
        if (status >= 400 && !_pageFinished) {
            STASH_DESKTOP_LOG(@"StashNativeDesktop: HTTP %ld on the main frame before the first page", (long)status);
            decisionHandler(WKNavigationResponsePolicyCancel);
            session->handleNetworkError();
            return;
        }
        if (!_initialLoadComplete && !stash::desktop::url::isRedirectStatus((int)status)) {
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
    _pageFinished = YES;
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
        // Cancelled by our own policy or superseded; frame-load-interrupted follows a response
        // the response policy already refused (download / plugin) and decided.
        return;
    }
    STASH_DESKTOP_LOG(@"StashNativeDesktop: load failed %@ (%ld)", error.domain, (long)error.code);
    // Until a page finished there is nothing on screen to keep: a body that fails while it is
    // still arriving is a network error, not a dismissal.
    if (!_pageFinished) {
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
        [_core dispatchEventType:STASH_NATIVE_DESKTOP_EVENT_WEB_PROCESS_CRASHED payload:"terminal"];
        session->handleNetworkError();
        [_core refreshStateMirrors];
        return;
    }
    _processTerminateRecoveryUsed = YES;
    _initialLoadComplete = NO;
    // The rendered page died with its process: until the reload finishes, nothing is on screen
    // to keep, so a failure of the recovery load is a network error again.
    _pageFinished = NO;
    STASH_DESKTOP_LOG(@"StashNativeDesktop: web content process terminated, reloading");
    [_core dispatchEventType:STASH_NATIVE_DESKTOP_EVENT_WEB_PROCESS_CRASHED payload:"reloading"];
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

// One JavaScript panel at a time, as a sheet on the presenting window. onResponse runs exactly
// once: from the sheet, or with Cancel when invalidate() ends the panel (dismiss, reset,
// shutdown, host window closing) or when there is nothing to present on.
- (void)presentPanel:(NSAlert *)alert onResponse:(void (^)(NSModalResponse))onResponse {
    NSWindow *window = [_core presenter].sheetWindow;
    if (_invalidated || !window || _panelWindow) {
        onResponse(NSModalResponseCancel);
        return;
    }
    NSWindow *panelWindow = alert.window;
    _panelWindow = panelWindow;
    __block BOOL resolved = NO;
    __weak StashNativeCardLoadDelegate *weakSelf = self;
    void (^resolve)(NSModalResponse) = ^(NSModalResponse response) {
        if (resolved) {
            return;
        }
        resolved = YES;
        StashNativeCardLoadDelegate *strongSelf = weakSelf;
        if (strongSelf && strongSelf->_panelWindow == panelWindow) {
            strongSelf->_panelWindow = nil;
            strongSelf->_panelCancel = nil;
        }
        onResponse(response);
    };
    _panelCancel = ^{
        [window endSheet:panelWindow returnCode:NSModalResponseCancel];
        resolve(NSModalResponseCancel);
    };
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        resolve(response);
    }];
}

- (void)webView:(WKWebView *)webView
    runJavaScriptAlertPanelWithMessage:(NSString *)message
                      initiatedByFrame:(WKFrameInfo *)frame
                     completionHandler:(void (^)(void))completionHandler {
    (void)webView;
    (void)frame;
    NSAlert *alert = [self alertWithMessage:message];
    [alert addButtonWithTitle:@"OK"];
    [self presentPanel:alert onResponse:^(NSModalResponse response) {
        (void)response;
        completionHandler();
    }];
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
    [self presentPanel:alert onResponse:^(NSModalResponse response) {
        completionHandler(response == NSAlertFirstButtonReturn);
    }];
}

- (void)webView:(WKWebView *)webView
    runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
                              defaultText:(NSString *)defaultText
                         initiatedByFrame:(WKFrameInfo *)frame
                        completionHandler:(void (^)(NSString *))completionHandler {
    (void)webView;
    (void)frame;
    NSAlert *alert = [self alertWithMessage:prompt];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    field.stringValue = defaultText ?: @"";
    alert.accessoryView = field;
    alert.window.initialFirstResponder = field;
    [self presentPanel:alert onResponse:^(NSModalResponse response) {
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
