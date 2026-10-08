#import "StashNativeCardPrivate.h"

static BOOL stashInspectableWebViewsEnabled = NO;

NSString *const StashTopChromeHandlerName = @"stashTopChrome";

@implementation StashNativeCard
+ (instancetype)sharedInstance {
    static StashNativeCard *instance;
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
    [self openURL:url presenter:presenter config:nil browser:YES];
}
- (void)openURL:(NSString *)url presenter:(UIViewController *)presenter
         config:(StashNativeCardConfig *)config browser:(BOOL)browser {
    NSString *normalized = NormalizeExternalPaymentURL(url);
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
    session.url = appendThemeQueryParameter(normalized);
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
    session.closing = YES;
    self.session = nil;
    [session dismissPresentedSurfaceAnimated:NO completion:^{
        [session cleanup];
#if !__has_feature(objc_arc)
        [session release];
#endif
    }];
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
@end
