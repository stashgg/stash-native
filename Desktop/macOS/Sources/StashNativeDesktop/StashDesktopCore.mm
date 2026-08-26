//
//  StashDesktopCore.mm
//  StashNativeDesktop
//
//  The core behind the facade and the C ABI: session lifetime, webview creation and prewarm,
//  presentation selection, event dispatch to the C callback and the delegate.
//

#import "StashNativeCardPrivate.h"

#include "StashDesktopTheme.h"
#include "StashDesktopUrl.h"
#include "StashSdkScript.h"

using stash::desktop::Presentation;
using stash::desktop::Session;
using stash::desktop::SessionHost;
using stash::desktop::SurfaceConfig;

static NSArray<NSString *> *StashMessageNames(void) {
    return @[
        @STASH_SDK_MSG_PAYMENT_SUCCESS, @STASH_SDK_MSG_PAYMENT_FAILURE, @STASH_SDK_MSG_PURCHASE_PROCESSING,
        @STASH_SDK_MSG_PROCESSING_COMPLETED, @STASH_SDK_MSG_OPTIN, @STASH_SDK_MSG_EXPAND, @STASH_SDK_MSG_COLLAPSE,
        @STASH_SDK_MSG_EXTERNAL_PAYMENT, @STASH_SDK_MSG_OPEN_LINK, @STASH_SDK_MSG_WINDOW_CLOSE
    ];
}

// Session -> core bridge. The core outlives every session, so the raw back-pointer is safe.
class StashCoreSessionHost : public SessionHost {
public:
    explicit StashCoreSessionHost(StashDesktopCore *core) : core_(core) {}

    void emitEvent(const std::string &type, const std::string &payload) override {
        [core_ dispatchEventType:type payload:payload];
    }

    void closeSurface() override {
        [core_ closeSurface];
    }

    void openSystemBrowser(const std::string &url) override {
        NSURL *nsurl = [NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()] ?: @""];
        if (nsurl) {
            [[NSWorkspace sharedWorkspace] openURL:nsurl];
        }
    }

    void openDeeplinkExternally(const std::string &url) override {
        NSURL *nsurl = [NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()] ?: @""];
        if (!nsurl || ![[NSWorkspace sharedWorkspace] openURL:nsurl]) {
            STASH_DESKTOP_LOG(@"StashNativeDesktop: no app installed for deeplink %s", url.c_str());
        }
    }

    void log(const std::string &message) override {
        STASH_DESKTOP_LOG(@"StashNativeDesktop: %s", message.c_str());
        (void)message;
    }

private:
    __unsafe_unretained StashDesktopCore *core_;
};

@implementation StashDesktopCore {
    std::unique_ptr<StashCoreSessionHost> _host;
    std::unique_ptr<Session> _session;
    NSUInteger _sessionId;
    StashNativeCardPresenter *_presenter;
    StashNativeCardLoadDelegate *_loadDelegate;
    StashDesktopMessageProxy *_messageProxy;
    WKWebView *_liveWebView;
    WKWebView *_prewarmedWebView;
    std::atomic<bool> _presentedMirror;
    std::atomic<bool> _processingMirror;
    StashNativeDesktopEventCallback _callback;
    void *_callbackUserData;
}

+ (instancetype)sharedInstance {
    static StashDesktopCore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[StashDesktopCore alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _host = std::make_unique<StashCoreSessionHost>(self);
        _presenter = [[StashNativeCardPresenter alloc] initWithCore:self];
        _messageProxy = [[StashDesktopMessageProxy alloc] initWithCore:self];
        _presentedMirror = false;
        _processingMirror = false;
    }
    return self;
}

+ (BOOL)systemPrefersDark {
    NSAppearance *appearance = NSApp ? NSApp.effectiveAppearance : nil;
    if (!appearance) {
        return NO;
    }
    NSAppearanceName name = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [name isEqualToString:NSAppearanceNameDarkAqua];
}

#pragma mark - State

- (NSUInteger)currentSessionId {
    return _sessionId;
}

- (WKWebView *)liveWebView {
    return _liveWebView;
}

- (StashNativeCardPresenter *)presenter {
    return _presenter;
}

- (Session *)sessionForId:(NSUInteger)sessionId {
    if (!_session || sessionId != _sessionId) {
        return nullptr;
    }
    return _session.get();
}

- (void)refreshStateMirrors {
    _presentedMirror = _session && _session->isPresented();
    _processingMirror = _session && _session->isPurchaseProcessing();
}

- (BOOL)isCurrentlyPresented {
    return _presentedMirror.load();
}

- (BOOL)isPurchaseProcessing {
    return _processingMirror.load();
}

- (void)setEventCallback:(StashNativeDesktopEventCallback)callback userData:(void *)userData {
    _callback = callback;
    _callbackUserData = userData;
}

#pragma mark - Events

// Asynchronous on the main queue, as the iOS delegate calls are: the WebKit callback that
// produced the event finishes first, and the state mirrors are already updated.
- (void)dispatchEventType:(const std::string &)type payload:(const std::string &)payload {
    [self refreshStateMirrors];
    std::string typeCopy = type;
    std::string payloadCopy = payload;
    STASH_DESKTOP_LOG(@"StashNativeDesktop: event %s %s", type.c_str(), payload.c_str());
    dispatch_async(dispatch_get_main_queue(), ^{
        StashNativeDesktopEventCallback cb = self->_callback;
        if (cb != nullptr) {
            cb(typeCopy.c_str(), payloadCopy.c_str(), self->_callbackUserData);
        }
        NSString *typeString = [NSString stringWithUTF8String:typeCopy.c_str()] ?: @"";
        NSString *payloadString = [NSString stringWithUTF8String:payloadCopy.c_str()] ?: @"";
        [[StashNativeCard sharedInstance] deliverEventType:typeString payload:payloadString];
    });
}

#pragma mark - Web views

- (WKWebView *)makeWebView {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    // PSP scripts open payment popups programmatically; they are routed to the system browser.
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = YES;
    WKUserContentController *controller = [[WKUserContentController alloc] init];
    for (NSString *name in StashMessageNames()) {
        [controller addScriptMessageHandler:_messageProxy name:name];
    }
    WKUserScript *sdkScript = [[WKUserScript alloc] initWithSource:@STASH_SDK_SCRIPT_WEBKIT
                                                     injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                  forMainFrameOnly:YES];
    [controller addUserScript:sdkScript];
    configuration.userContentController = controller;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, stash::desktop::kCardDefaultWidth,
                                                                     stash::desktop::kCardDefaultHeight)
                                            configuration:configuration];
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    return webView;
}

- (WKWebView *)takeWebView {
    WKWebView *webView = _prewarmedWebView;
    _prewarmedWebView = nil;
    if (!webView) {
        webView = [self makeWebView];
    }
    return webView;
}

- (void)applySessionScriptsToWebView:(WKWebView *)webView dark:(BOOL)dark sheetArgb:(uint32_t)sheetArgb {
    WKUserContentController *controller = webView.configuration.userContentController;
    [controller removeAllUserScripts];
    [controller addUserScript:[[WKUserScript alloc] initWithSource:@STASH_SDK_SCRIPT_WEBKIT
                                                     injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                  forMainFrameOnly:YES]];
    if (dark) {
        NSString *darkScript = [NSString stringWithUTF8String:stash::desktop::theme::darkSheetScript(sheetArgb).c_str()];
        [controller addUserScript:[[WKUserScript alloc] initWithSource:darkScript
                                                         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                      forMainFrameOnly:YES]];
        [controller addUserScript:[[WKUserScript alloc] initWithSource:darkScript
                                                         injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                      forMainFrameOnly:YES]];
    }
    if (@available(macOS 13.3, *)) {
        webView.inspectable = self.inspectableWebViews;
    }
}

- (void)prewarm {
    if (_prewarmedWebView || (_session && _session->isPresented())) {
        return;
    }
    WKWebView *webView = [self makeWebView];
    [webView loadHTMLString:@"<html></html>" baseURL:nil];
    _prewarmedWebView = webView;
    STASH_DESKTOP_LOG(@"StashNativeDesktop: prewarmed webview ready");
}

#pragma mark - Open / close

- (NSWindow *)findHostWindow {
    NSWindow *explicitWindow = self.explicitHostWindow;
    if (explicitWindow) {
        return explicitWindow;
    }
    NSWindow *window = [NSApp keyWindow];
    if (!window) {
        window = [NSApp mainWindow];
    }
    if (!window) {
        for (NSWindow *candidate in [NSApp windows]) {
            if (candidate.isVisible && candidate.contentView) {
                window = candidate;
                break;
            }
        }
    }
    return window;
}

- (void)openURL:(NSString *)url config:(const SurfaceConfig &)config {
    if (url.length == 0) {
        STASH_DESKTOP_LOG(@"StashNativeDesktop: open ignored, empty URL");
        return;
    }
    if (_session && _session->isPresented()) {
        // Block only when a presentation is live. A stale flag with nothing on screen is cleared
        // and the open proceeds (iOS self-heal), rather than returning silently.
        if (_presenter.isLive) {
            STASH_DESKTOP_LOG(@"StashNativeDesktop: open ignored, checkout already presented");
            return;
        }
        STASH_DESKTOP_LOG(@"StashNativeDesktop: clearing stale presentation guard before opening");
        _session->reset();
    }

    BOOL systemDark = [StashDesktopCore systemPrefersDark];
    _sessionId++;
    _session = std::make_unique<Session>(*_host, config, systemDark);
    uint32_t sheetArgb = stash::desktop::theme::sheetBackgroundArgb(config.backgroundColor, systemDark);
    std::string themed = _session->themedUrl(url.UTF8String ?: "");

    WKWebView *webView = [self takeWebView];
    [self applySessionScriptsToWebView:webView dark:_session->themeIsDark() sheetArgb:sheetArgb];
    _loadDelegate = [[StashNativeCardLoadDelegate alloc] initWithCore:self sessionId:_sessionId];
    webView.navigationDelegate = _loadDelegate;
    webView.UIDelegate = _loadDelegate;
    _liveWebView = webView;

    BOOL presented = NO;
    if (config.presentation == Presentation::Attached) {
        NSWindow *host = [self findHostWindow];
        if (host) {
            presented = [_presenter presentWebView:webView hostWindow:host config:config sheetColorArgb:sheetArgb];
        } else {
            STASH_DESKTOP_LOG(@"StashNativeDesktop: no host window, presenting in a standalone window");
        }
    }
    if (!presented) {
        [_presenter presentWebView:webView standaloneWithConfig:config sheetColorArgb:sheetArgb];
    }
    [self refreshStateMirrors];

    NSURL *nsurl = [NSURL URLWithString:[NSString stringWithUTF8String:themed.c_str()] ?: @""];
    if (!nsurl) {
        STASH_DESKTOP_LOG(@"StashNativeDesktop: invalid URL %@", url);
        _session->handleNetworkError();
        return;
    }
    [_presenter updateTrustHeaderForURL:nsurl];
    [_loadDelegate startLoadingURL:nsurl inWebView:webView allowFileUrls:config.allowFileUrls];
}

- (void)openBrowser:(NSString *)url {
    if (url.length == 0) {
        return;
    }
    std::string themed = stash::desktop::url::appendThemeQueryParameter(url.UTF8String ?: "",
                                                                        [StashDesktopCore systemPrefersDark]);
    NSURL *nsurl = [NSURL URLWithString:[NSString stringWithUTF8String:themed.c_str()] ?: @""];
    if (nsurl) {
        [[NSWorkspace sharedWorkspace] openURL:nsurl];
    }
}

- (void)dismiss {
    if (_session) {
        _session->dismiss();
        [self refreshStateMirrors];
    }
}

- (void)resetPresentationState {
    if (_session) {
        _session->reset();
    }
    // Reset means reset: drop the surface even if a session was never created for it.
    [self closeSurface];
    [self refreshStateMirrors];
}

- (void)requestUserDismiss {
    if (_session) {
        _session->requestUserDismiss();
        [self refreshStateMirrors];
    }
}

- (void)handleMessageNamed:(NSString *)name body:(id)body fromWebView:(WKWebView *)webView {
    if (!_session || !webView || webView != _liveWebView) {
        return;
    }
    std::string payload;
    if ([body isKindOfClass:[NSString class]]) {
        payload = ((NSString *)body).UTF8String ?: "";
    } else if ([body isKindOfClass:[NSNumber class]]) {
        payload = ((NSNumber *)body).stringValue.UTF8String ?: "";
    } else if (body && body != [NSNull null] && [NSJSONSerialization isValidJSONObject:body]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        payload = text.UTF8String ?: "";
    }
    _session->handleMessage(name.UTF8String ?: "", payload);
    [self refreshStateMirrors];
}

// The session keeps living until the next open so the caller of the closing method can finish;
// only the surface goes away here. The delegate and webview are often mid-callback when this
// runs (a refused load, a script message), so they are released on the next run-loop turn.
- (void)closeSurface {
    StashNativeCardLoadDelegate *delegate = _loadDelegate;
    WKWebView *webView = _liveWebView;
    [delegate invalidate];
    _loadDelegate = nil;
    _liveWebView = nil;
    if (webView) {
        [webView stopLoading];
        webView.navigationDelegate = nil;
        webView.UIDelegate = nil;
    }
    [_presenter teardown];
    [self refreshStateMirrors];
    dispatch_async(dispatch_get_main_queue(), ^{
        (void)delegate;
        (void)webView;
    });
}

- (void)shutdown {
    if (_session) {
        _session->reset();
        _session.reset();
    }
    [self closeSurface];
    _prewarmedWebView = nil;
    _callback = nullptr;
    _callbackUserData = nullptr;
    [self refreshStateMirrors];
}

@end
