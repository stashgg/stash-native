#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativeCardPrivate.h"
#import <objc/runtime.h>

@interface StashInstancePresenter : UIViewController
@property (nonatomic) UIUserInterfaceStyle style;
@end
@implementation StashInstancePresenter
- (UITraitCollection *)traitCollection { return [UITraitCollection traitCollectionWithUserInterfaceStyle:self.style]; }
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    if (completion) completion();
}
@end

@interface StashInstanceWindow : UIWindow
@end
@implementation StashInstanceWindow
- (UITraitCollection *)traitCollection { return [UITraitCollection traitCollectionWithUserInterfaceIdiom:UIUserInterfaceIdiomPhone]; }
@end

static StashInstancePresenter *StashInstanceHost(UIWindow *window, UIUserInterfaceStyle style) {
    StashInstancePresenter *host = [StashInstancePresenter new];
    host.style = style;
    window.rootViewController = host;
    [window addSubview:host.view];
    return host;
}

@interface StashInstanceSurface : StashCheckoutViewController
@end
@implementation StashInstanceSurface
- (void)viewDidLoad {}
@end

static UIColor *StashInstanceFallbackPaint(UIViewController *presenter) {
    // Exercise the native fallback without a page color or temporary glass loading paint.
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.presenter = presenter;
    StashInstanceSurface *surface = [StashInstanceSurface new];
    surface.session = session;
    [surface updateTopChromeBackgroundColor];
    return surface.view.backgroundColor;
}

@interface StashInstanceDeallocation : NSObject
@property (nonatomic, copy) void (^completion)(void);
@end
@implementation StashInstanceDeallocation
- (void)dealloc { if (_completion) _completion(); }
@end

@interface StashInstanceObservation : NSObject <StashNativeCardDelegate>
@property (nonatomic, weak) StashNativeCard *owner;
@property (nonatomic, weak) StashCheckoutSession *session;
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, weak) StashPortraitPresentation *portrait;
@property (nonatomic, strong) NSTimer *loadTimer;
@property (nonatomic) NSUInteger callbacks;
@property (nonatomic) BOOL sessionReleasedOnMain;
@property (nonatomic) BOOL admitted;
@property (nonatomic) BOOL pendingPortrait;
@end
@implementation StashInstanceObservation
- (void)stashNativeCardDidDismiss { self.callbacks++; }
- (void)stashNativeCardDidCloseBrowser { self.callbacks++; }
- (void)stashNativeCardDidEncounterNetworkError { self.callbacks++; }
- (void)stashNativeCardDidLoadPage:(double)loadTimeMs { self.callbacks++; }
- (void)stashNativeCardDidCompletePaymentWithOrder:(NSString *)order { self.callbacks++; }
- (void)stashNativeCardDidCompletePayment { self.callbacks++; }
- (void)stashNativeCardDidFailPayment { self.callbacks++; }
- (void)stashNativeCardDidRequestExternalPaymentWithURL:(NSString *)url { self.callbacks++; }
- (void)stashNativeCardDidScanQRCode:(NSString *)content { self.callbacks++; }
@end

static char StashInstanceDeallocationKey;

@interface StashInstancePendingDismissal : StashCheckoutSession
@property (nonatomic, copy) void (^dismissal)(void);
@end
@implementation StashInstancePendingDismissal
- (void)dismissPresentedSurfaceAnimated:(BOOL)animated completion:(void (^)(void))completion {
    self.dismissal = completion;
}
- (void)completeDismissal {
    void (^completion)(void) = self.dismissal;
    self.dismissal = nil;
    if (completion) completion();
}
@end

NSDictionary *StashInstanceClosingOwnerReleaseProbe(void) {
    StashInstanceObservation *observation = [StashInstanceObservation new];
    BOOL pending, detached;
    @autoreleasepool {
        StashNativeCard *owner = [StashNativeCard new];
        owner.delegate = observation;
        StashInstancePendingDismissal *session = [StashInstancePendingDismissal new];
        session.config = [StashNativeCardConfig new];
        session.owner = owner;
        owner.session = session;
        observation.owner = owner;
        observation.session = session;
        [owner dismiss];
        pending = session.closing && session.dismissal != nil;
        [owner resetPresentationState];
        detached = session.owner == nil && !owner.isCurrentlyPresented;
        owner = nil;
        // Observe the missing detach without dereferencing a stale MRC owner on failure.
        if (!detached) session.owner = nil;
        [session completeDismissal];
    }
    return @{@"pending":@(pending), @"detached":@(detached), @"ownerReleased":@(observation.owner == nil),
        @"sessionReleased":@(observation.session == nil), @"silent":@(observation.callbacks == 0)};
}

static void StashAwaitInstanceRelease(StashInstanceObservation *observation, CFAbsoluteTime deadline,
                                     void (^completion)(NSDictionary *)) {
    if ((observation.session || observation.webView || observation.portrait) && CFAbsoluteTimeGetCurrent() < deadline) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            StashAwaitInstanceRelease(observation, deadline, completion);
        });
        return;
    }
    completion(@{@"admitted":@(observation.admitted), @"pendingPortrait":@(observation.pendingPortrait),
        @"ownerReleased":@(observation.owner == nil), @"sessionReleased":@(observation.session == nil),
        @"webReleased":@(observation.webView == nil), @"portraitReleased":@(observation.portrait == nil),
        @"timerInvalidated":@(!observation.loadTimer.isValid),
        @"sessionReleasedOnMain":@(observation.sessionReleasedOnMain), @"callbacks":@(observation.callbacks)});
    // A failing implementation must not leave the fixture's timers running.
    [observation.session cleanup];
}

void StashInstanceOwnerReleaseProbe(BOOL background, BOOL portrait, void (^completion)(NSDictionary *)) {
    StashInstanceObservation *observation = [StashInstanceObservation new];
    UIWindow *window = [[StashInstanceWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    StashInstancePresenter *presenter = StashInstanceHost(window, UIUserInterfaceStyleLight);
    @autoreleasepool {
        __block StashNativeCard *owner = [StashNativeCard new];
        owner.delegate = observation;
        StashNativeCardConfig *config = [StashNativeCardConfig new];
        if (portrait) config.orientationPreference = StashNativeOrientationPreferencePortrait;
        [owner openCardWithURL:@"https://example.invalid" fromViewController:presenter config:config];
        StashCheckoutSession *session = owner.session;
        observation.owner = owner;
        observation.session = session;
        observation.webView = session.webView;
        observation.portrait = session.portraitPresentation;
        observation.loadTimer = session.loadTimer;
        observation.admitted = session != nil;
        observation.pendingPortrait = session.portraitPresentation != nil && session.webView == nil;
        StashInstanceDeallocation *deallocation = [StashInstanceDeallocation new];
        deallocation.completion = ^{ observation.sessionReleasedOnMain = NSThread.isMainThread; };
        objc_setAssociatedObject(session, &StashInstanceDeallocationKey, deallocation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (background) dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ owner = nil; });
        else owner = nil;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        StashAwaitInstanceRelease(observation, CFAbsoluteTimeGetCurrent() + 2, ^(NSDictionary *result) {
            completion(result);
            window.rootViewController = nil;
        });
    });
}

NSDictionary *StashInstanceThemeProbe(void) {
    [StashNativeCard.sharedInstance resetPresentationState];
    UIWindow *singletonWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    UIWindow *darkWindow = [[UIWindow alloc] initWithFrame:singletonWindow.frame];
    UIWindow *lightWindow = [[UIWindow alloc] initWithFrame:singletonWindow.frame];
    StashInstancePresenter *singletonHost = StashInstanceHost(singletonWindow, UIUserInterfaceStyleLight);
    StashInstancePresenter *darkHost = StashInstanceHost(darkWindow, UIUserInterfaceStyleDark);
    StashInstancePresenter *lightHost = StashInstanceHost(lightWindow, UIUserInterfaceStyleLight);
    StashNativeCard *dark = [StashNativeCard new], *light = [StashNativeCard new];
    [StashNativeCard.sharedInstance openCardWithURL:@"https://example.invalid" fromViewController:singletonHost config:nil];
    [dark openCardWithURL:@"https://example.invalid?token=a%2Bb%26c&theme=light#section" fromViewController:darkHost config:nil];
    [light openCardWithURL:@"https://example.invalid" fromViewController:lightHost config:nil];
    NSString *darkURL = dark.session.url, *lightURL = light.session.url;
    UIColor *darkBackground = [UIColor colorWithRed:0x1e/255.0 green:0x1e/255.0 blue:0x1e/255.0 alpha:1];
    BOOL darkWeb = [dark.session.webView.backgroundColor isEqual:darkBackground];
    BOOL darkSurface = [StashInstanceFallbackPaint(darkHost) isEqual:darkBackground];
    BOOL lightSurface = [StashInstanceFallbackPaint(lightHost) isEqual:
        [UIColor.systemBackgroundColor resolvedColorWithTraitCollection:lightHost.traitCollection]];
    [dark.session handleMessage:@"stashExternalPayment" body:@"https://example.invalid/pay"];
    BOOL darkHandoff = dark.session.browser && [dark.session.url hasSuffix:@"theme=dark"];
    singletonHost.style = UIUserInterfaceStyleDark;
    [light.session handleMessage:@"stashExternalPayment" body:@"https://example.invalid/pay"];
    BOOL lightHandoff = light.session.browser && [light.session.url hasSuffix:@"theme=light"];
    [light resetPresentationState];
    [light openBrowserWithURL:@"https://example.invalid" fromViewController:lightHost];
    BOOL lightBrowser = light.session.browser && [light.session.url hasSuffix:@"theme=light"];
    [dark resetPresentationState];
    [light resetPresentationState];
    [StashNativeCard.sharedInstance resetPresentationState];
    return @{@"darkURL":darkURL, @"lightURL":lightURL, @"darkWeb":@(darkWeb), @"darkSurface":@(darkSurface),
        @"lightSurface":@(lightSurface), @"darkHandoff":@(darkHandoff), @"lightHandoff":@(lightHandoff),
        @"lightBrowser":@(lightBrowser)};
}
