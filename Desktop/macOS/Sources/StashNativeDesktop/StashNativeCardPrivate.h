//
//  StashNativeCardPrivate.h
//  StashNativeDesktop
//
//  Internal interfaces of the macOS host. The core owns one Session (the shared C++ state
//  machine), the presenter (AppKit surface), the load delegate (WebKit callbacks and timers)
//  and the prewarmed webview. Compiled as Objective-C++ with ARC only: the bundle is built by
//  build_bundle.sh, engines load it with dlopen and never compile these sources.
//

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

#include <atomic>
#include <memory>
#include <string>

#include "StashDesktopConfig.h"
#include "StashDesktopSession.h"
#include "StashNativeDesktop.h"
#import "StashNativeCard.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG
#define STASH_DESKTOP_LOG(...) NSLog(__VA_ARGS__)
#else
#define STASH_DESKTOP_LOG(...)
#endif

@class StashDesktopCore;

/// Card / modal surface over the host window, or a standalone window (editor play mode).
/// User actions (close button, backdrop click, Esc, window close) go to the core, which asks the
/// session; the surface itself never emits events.
@interface StashNativeCardPresenter : NSObject <NSWindowDelegate>

- (instancetype)initWithCore:(StashDesktopCore *)core;

/// Attached presentation. Returns NO when the host window has no content view.
- (BOOL)presentWebView:(WKWebView *)webView
            hostWindow:(NSWindow *)hostWindow
                config:(const stash::desktop::SurfaceConfig &)config
        sheetColorArgb:(uint32_t)sheetArgb;

/// Standalone window presentation.
- (void)presentWebView:(WKWebView *)webView
   standaloneWithConfig:(const stash::desktop::SurfaceConfig &)config
        sheetColorArgb:(uint32_t)sheetArgb;

- (void)updateTrustHeaderForURL:(nullable NSURL *)url;
- (void)setLoading:(BOOL)loading;

/// Removes everything from screen. No events.
- (void)teardown;

/// Something of ours is on screen.
@property (nonatomic, readonly) BOOL isLive;

/// Window to attach JavaScript panel sheets to (the standalone window or the attached host).
@property (nonatomic, readonly, nullable) NSWindow *sheetWindow;

@end

/// Per-presentation WKNavigationDelegate / WKUIDelegate: navigation policy through the session,
/// stall retries and the network deadline, web-content process recovery, new-window handling.
@interface StashNativeCardLoadDelegate : NSObject <WKNavigationDelegate, WKUIDelegate>

- (instancetype)initWithCore:(StashDesktopCore *)core sessionId:(NSUInteger)sessionId;

- (void)startLoadingURL:(NSURL *)url inWebView:(WKWebView *)webView allowFileUrls:(BOOL)allowFileUrls;

/// The prewarm placeholder navigation of an adopted webview: its callbacks, possibly still
/// queued after stopLoading, are ignored so they cannot pass for the checkout's.
- (void)ignoreNavigation:(nullable WKNavigation *)navigation;

/// Stops timers and ends an open JavaScript panel as cancelled; every later WebKit callback is
/// ignored.
- (void)invalidate;

@end

/// The one WKScriptMessageHandler, registered on every webview the core creates (prewarmed
/// included). Routes messages from the live webview to the current session.
@interface StashDesktopMessageProxy : NSObject <WKScriptMessageHandler>

- (instancetype)initWithCore:(StashDesktopCore *)core;

@end

/// Singleton behind both the AppKit facade and the C ABI. Main thread only; the callers marshal.
@interface StashDesktopCore : NSObject

+ (instancetype)sharedInstance;

/// NSWindow from StashNativeDesktop_SetHostWindow / StashNativeCard.hostWindow.
@property (nonatomic, weak, nullable) NSWindow *explicitHostWindow;
@property (nonatomic, assign) BOOL inspectableWebViews;

/// Session generation; delegates capture it and drop callbacks from earlier presentations.
@property (nonatomic, readonly) NSUInteger currentSessionId;
/// The webview of the current presentation, nil once its surface is closed.
@property (nonatomic, readonly, nullable) WKWebView *liveWebView;
@property (nonatomic, readonly) StashNativeCardPresenter *presenter;

/// nullptr when the id is stale or no session exists.
- (nullable stash::desktop::Session *)sessionForId:(NSUInteger)sessionId;

- (void)openURL:(NSString *)url config:(const stash::desktop::SurfaceConfig &)config;
- (void)openBrowser:(NSString *)url;
- (void)dismiss;
- (void)resetPresentationState;
- (void)prewarm;
- (void)shutdown;

/// Atomic mirrors of the session state, readable from any thread.
- (BOOL)isCurrentlyPresented;
- (BOOL)isPurchaseProcessing;

- (void)setEventCallback:(nullable StashNativeDesktopEventCallback)callback userData:(nullable void *)userData;

/// From the presenter: close button, backdrop, Esc, window close. Refused while processing or
/// when a modal disallows dismissal.
- (void)requestUserDismiss;

/// From the presenter: the attached host window is closing. The presentation cannot outlive
/// it, so the session ends with dialogDismissed regardless of processing or modal rules.
- (void)hostWindowWillClose;

/// From the message proxy.
- (void)handleMessageNamed:(NSString *)name body:(nullable id)body fromWebView:(nullable WKWebView *)webView;

/// Called by the session host when the session closes its surface.
- (void)closeSurface;

/// Recomputes the atomic state mirrors from the session.
- (void)refreshStateMirrors;

/// Delivers an event to the C callback and the facade delegate (asynchronously, main queue).
- (void)dispatchEventType:(const std::string &)type payload:(const std::string &)payload;

+ (BOOL)systemPrefersDark;

@end

/// Facade side of event delivery: maps ABI event types onto the delegate protocol.
@interface StashNativeCard (Internal)
- (void)deliverEventType:(NSString *)type payload:(NSString *)payload;
@end

/// Config object -> shared SurfaceConfig (ratios clamped, nil -> defaults).
stash::desktop::SurfaceConfig StashSurfaceConfigFromCardConfig(StashNativeCardConfig *_Nullable config);
stash::desktop::SurfaceConfig StashSurfaceConfigFromModalConfig(StashNativeModalConfig *_Nullable config);

NS_ASSUME_NONNULL_END
