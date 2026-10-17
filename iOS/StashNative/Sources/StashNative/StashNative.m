#import "StashNativePrivate.h"

static BOOL stashInspectableWebViewsEnabled = NO;

NSString *const StashTopChromeHandlerName = @"stashTopChrome";
NSErrorDomain const StashNativeCodeLinkErrorDomain = @"gg.stash.native.CodeLink";

@implementation StashNative
- (void)deliverToDelegate:(void (^)(id<StashNativeDelegate> delegate))delivery {
    id<StashNativeDelegate> delegate = self.delegate;
#if !__has_feature(objc_arc)
    [delegate retain];
#endif
    @try {
        if (delegate) delivery(delegate);
    } @finally {
#if !__has_feature(objc_arc)
        [delegate release];
#endif
    }
}
+ (instancetype)sharedInstance {
    static StashNative *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}
+ (NSString *)sdkVersion { return @"3.0.0"; }
+ (void)setInspectableWebViewsEnabled:(BOOL)enabled { stashInspectableWebViewsEnabled = enabled; }
+ (BOOL)isInspectableWebViewsEnabled { return stashInspectableWebViewsEnabled; }
- (BOOL)isCurrentlyPresented { return self.session != nil; }
- (BOOL)isPurchaseProcessing { return self.session.processing; }

- (void)openCardWithURL:(NSString *)url fromViewController:(UIViewController *)presenter config:(StashNativeCardConfig *)config {
    [self openURL:url presenter:presenter config:config browser:NO];
}
- (void)openBrowserWithURL:(NSString *)url fromViewController:(UIViewController *)presenter {
    [self openBrowserWithURL:url fromViewController:presenter config:nil];
}
- (void)openBrowserWithURL:(NSString *)url fromViewController:(UIViewController *)presenter config:(StashNativeBrowserConfig *)config {
    StashNativeCardConfig *presentationConfig = [[StashNativeCardConfig alloc] init];
    presentationConfig.orientationPreference = config.orientationPreference;
    [self openURL:url presenter:presenter config:presentationConfig browser:YES];
#if !__has_feature(objc_arc)
    [presentationConfig release];
#endif
}
- (void)codeLinkFromViewController:(UIViewController *)presenter {
    [self codeLinkFromViewController:presenter config:nil];
}
- (void)codeLinkFromViewController:(UIViewController *)presenter config:(StashNativeCodeLinkConfig *)config {
    if (!NSThread.isMainThread) {
        StashNativeCodeLinkConfig *snapshot = [config copy];
        dispatch_async(dispatch_get_main_queue(), ^{ [self codeLinkFromViewController:presenter config:snapshot]; });
#if !__has_feature(objc_arc)
        [snapshot release];
#endif
        return;
    }
    if (self.session || !presenter.viewIfLoaded.window || presenter.isBeingDismissed) return;
    while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed)
        presenter = presenter.presentedViewController;
    StashCheckoutSession *session = [[StashCheckoutSession alloc] init];
    session.owner = self;
    session.presenter = presenter;
    session.config = StashNormalizedConfig(nil);
    session.config.orientationPreference = StashNativeOrientationPreferenceFollowHost;
    session.codeLink = YES;
    session.codeLinkConfig = config;
    self.session = session;
    [session presentCheckout];
#if !__has_feature(objc_arc)
    [session release];
#endif
}
- (void)openURL:(NSString *)url presenter:(UIViewController *)presenter
         config:(StashNativeCardConfig *)config browser:(BOOL)browser {
    NSString *normalized = StashNormalizeExternalPaymentURL(url);
    StashNativeCardConfig *snapshot = StashNormalizedConfig(config);
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openURL:normalized presenter:presenter config:snapshot browser:browser]; });
        return;
    }
    if (self.session || !normalized || !presenter.viewIfLoaded.window || presenter.isBeingDismissed) return;
    while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) {
        presenter = presenter.presentedViewController;
    }
    StashCheckoutSession *session = [[StashCheckoutSession alloc] init];
    session.owner = self;
    session.presenter = presenter;
    session.config = snapshot;
    self.session = session;
    session.url = StashAppendThemeQueryParameter(normalized, presenter.traitCollection);
    if (browser) [session presentBrowser]; else [session presentCheckout];
#if !__has_feature(objc_arc)
    [session release];
#endif
}
- (void)dismiss {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self dismiss]; }); return; }
    if (self.session.browser) [self closeBrowser];
    else [self.session finishWithUserDismiss:YES completion:nil];
}
- (void)resetPresentationState {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self resetPresentationState]; }); return; }
    StashCheckoutSession *session = self.session;
#if !__has_feature(objc_arc)
    [session retain];
#endif
    self.session = nil;
    [session retire];
#if !__has_feature(objc_arc)
    [session release];
#endif
}
- (void)closeBrowser {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self closeBrowser]; }); return; }
    if (self.session.browser) [self.session browserClosed];
}
- (void)dismissSafariViewControllerWithResult:(BOOL)success {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self dismissSafariViewControllerWithResult:success]; }); return;
    }
    if (!self.session.browser || self.session.closing) return;
    [self.session paymentSucceeded:success order:nil];
}
- (void)dealloc {
    StashCheckoutSession *session = _session;
    // Detach before MRC frees the assign owner; UIKit retirement stays on main.
    session.owner = nil;
    if (NSThread.isMainThread) [session retire];
    else dispatch_async(dispatch_get_main_queue(), ^{ [session retire]; });
#if !__has_feature(objc_arc)
    [_session release];
    [super dealloc];
#endif
}
@end
