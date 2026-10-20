#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativePrivate.h"
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

@interface StashInstanceSurface : StashCardViewController
@end
@implementation StashInstanceSurface
- (void)viewDidLoad {}
@end

static UIColor *StashInstanceFallbackPaint(UIViewController *presenter) {
    // Exercise the native fallback without a page color or temporary glass loading paint.
    StashCardSession *session = [StashCardSession new];
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

@interface StashInstanceObservation : NSObject <StashNativeDelegate>
@property (nonatomic, weak) StashNative *owner;
@property (nonatomic, weak) StashCardSession *session;
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, weak) StashPortraitPresentation *portrait;
@property (nonatomic, strong) NSTimer *loadTimer;
@property (nonatomic) NSUInteger callbacks;
@property (nonatomic) BOOL sessionReleasedOnMain;
@property (nonatomic) BOOL admitted;
@property (nonatomic) BOOL pendingPortrait;
@end
@implementation StashInstanceObservation
- (void)stashNativeDidDismissCard { self.callbacks++; }
- (void)stashNativeDidDismissScanner { self.callbacks++; }
- (void)stashNativeDidDismissBrowser { self.callbacks++; }
- (void)stashNativeDidEncounterNetworkError { self.callbacks++; }
- (void)stashNativeDidLoadPage:(double)loadTimeMs { self.callbacks++; }
- (void)stashNativeDidCompletePaymentWithOrder:(NSString *)order { self.callbacks++; }
- (void)stashNativeDidFailPayment { self.callbacks++; }
- (void)stashNativeDidRequestExternalPaymentWithURL:(NSString *)url { self.callbacks++; }
- (void)stashNativeDidScanQRCode:(NSString *)content { self.callbacks++; }
@end

static char StashInstanceDeallocationKey;

@interface StashInstancePendingDismissal : StashCardSession
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
        StashNative *owner = [StashNative new];
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
        __block StashNative *owner = [StashNative new];
        owner.delegate = observation;
        StashNativeCardConfig *config = [StashNativeCardConfig new];
        if (portrait) config.orientationPreference = StashNativeOrientationPreferencePortrait;
        [owner openCardWithURL:@"https://example.invalid" fromViewController:presenter config:config];
        StashCardSession *session = owner.session;
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
        // Loaded CI runners can delay the background release; a leak never completes, so the deadline only bounds the wait.
        StashAwaitInstanceRelease(observation, CFAbsoluteTimeGetCurrent() + 4, ^(NSDictionary *result) {
            completion(result);
            window.rootViewController = nil;
        });
    });
}

NSDictionary *StashInstanceThemeProbe(void) {
    [StashNative.sharedInstance resetPresentationState];
    UIWindow *singletonWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    UIWindow *darkWindow = [[UIWindow alloc] initWithFrame:singletonWindow.frame];
    UIWindow *lightWindow = [[UIWindow alloc] initWithFrame:singletonWindow.frame];
    StashInstancePresenter *singletonHost = StashInstanceHost(singletonWindow, UIUserInterfaceStyleLight);
    StashInstancePresenter *darkHost = StashInstanceHost(darkWindow, UIUserInterfaceStyleDark);
    StashInstancePresenter *lightHost = StashInstanceHost(lightWindow, UIUserInterfaceStyleLight);
    StashNative *dark = [StashNative new], *light = [StashNative new];
    [StashNative.sharedInstance openCardWithURL:@"https://example.invalid" fromViewController:singletonHost config:nil];
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
    [StashNative.sharedInstance resetPresentationState];
    return @{@"darkURL":darkURL, @"lightURL":lightURL, @"darkWeb":@(darkWeb), @"darkSurface":@(darkSurface),
        @"lightSurface":@(lightSurface), @"darkHandoff":@(darkHandoff), @"lightHandoff":@(lightHandoff),
        @"lightBrowser":@(lightBrowser)};
}

@interface StashCallbackReceiver : NSObject <StashNativeDelegate>
@property (nonatomic, strong) NSMutableArray<NSString *> *events;
@property (nonatomic, copy) void (^onSelector)(SEL selector);
@property (nonatomic, copy) void (^onEvent)(NSString *event);
@property (nonatomic, copy) void (^onRelease)(void);
@end
@implementation StashCallbackReceiver
- (instancetype)init {
    if ((self = [super init])) _events = [NSMutableArray new];
    return self;
}
- (BOOL)respondsToSelector:(SEL)selector {
    if (self.onSelector) self.onSelector(selector);
    return [super respondsToSelector:selector];
}
- (void)record:(NSString *)event {
    [self.events addObject:event];
    if (self.onEvent) self.onEvent(event);
}
- (void)stashNativeDidDismissCard { [self record:@"card-dismissed"]; }
- (void)stashNativeDidDismissScanner { [self record:@"scan-dismissed"]; }
- (void)stashNativeDidDismissBrowser { [self record:@"browser-dismissed"]; }
- (void)stashNativeDidCompletePaymentWithOrder:(NSString *)order { [self record:order ?: @"nil-order"]; }
- (void)stashNativeDidFailPayment { [self record:@"failure"]; }
- (void)stashNativeDidScanQRCode:(NSString *)content { [self record:content]; }
- (void)stashNativeDidRequestExternalPaymentWithURL:(NSString *)url { [self record:@"handoff"]; }
- (void)dealloc { if (_onRelease) _onRelease(); }
@end

static StashCardSession *StashCallbackSession(StashNative *owner) {
    StashCardSession *session = [StashCardSession new];
    session.owner = owner;
    session.config = [StashNativeCardConfig new];
    owner.session = session;
    return session;
}

NSDictionary *StashCallbackDismissalProbe(void) {
    StashNative *owner = [StashNative new];
    StashCallbackReceiver *receiver = [StashCallbackReceiver new];
    owner.delegate = receiver;
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    StashInstancePresenter *host = StashInstanceHost(window, UIUserInterfaceStyleLight);
    [owner openCardWithURL:@"https://example.invalid" fromViewController:host config:nil];
    BOOL cardAdmitted = owner.session != nil && !owner.session.scanner;
    [owner dismiss];
    [owner openScannerFromViewController:host];
    BOOL scannerAdmitted = owner.session != nil && owner.session.scanner;
    [owner dismiss];
    for (NSInteger mode = 0; mode < 3; mode++) {
        [owner openBrowserWithURL:@"https://example.invalid" fromViewController:host];
        StashCardSession *browser = owner.session;
        if (mode == 0) [owner closeBrowser];
        else if (mode == 1) [owner dismiss];
        else [browser safariViewControllerDidFinish:browser.browser];
        [browser browserClosed];
    }
    [owner openCardWithURL:@"https://example.invalid" fromViewController:host config:nil];
    StashCardSession *card = owner.session;
    [card handleMessage:@"stashExternalPayment" body:@"https://example.invalid/pay"];
    BOOL sameSession = owner.session == card && card.browser != nil;
    [owner closeBrowser];
    [owner openCardWithURL:@"https://example.invalid" fromViewController:host config:nil];
    [owner.session handleMessage:@"stashExternalPayment" body:@"https://example.invalid/pay"];
    StashCallbackReceiver *replacement = [StashCallbackReceiver new];
    owner.delegate = replacement;
    [owner closeBrowser];
    BOOL handoffUsesReplacement = [replacement.events isEqualToArray:@[@"browser-dismissed"]];
    NSArray *expected = @[@"card-dismissed", @"scan-dismissed", @"browser-dismissed", @"browser-dismissed", @"browser-dismissed",
        @"handoff", @"browser-dismissed", @"handoff"];
    return @{@"cardAdmitted":@(cardAdmitted), @"scannerAdmitted":@(scannerAdmitted),
        @"handoffKeepsSession":@(sameSession), @"events":receiver.events, @"expected":expected,
        @"handoffUsesReplacement":@(handoffUsesReplacement), @"closed":@(!owner.isCurrentlyPresented)};
}

// Each accepted open whose presentation fails later still ends with its final event; reset stays silent.
void StashLatePresentationFailureProbe(void (^completion)(NSDictionary *)) {
    StashNative *handoffOwner = [StashNative new];
    StashCallbackReceiver *handoffEvents = [StashCallbackReceiver new];
    handoffOwner.delegate = handoffEvents;
    UIWindow *handoffWindow = [[StashInstanceWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    StashInstancePresenter *handoffHost = StashInstanceHost(handoffWindow, UIUserInterfaceStyleLight);
    [handoffOwner openCardWithURL:@"https://example.invalid" fromViewController:handoffHost config:nil];
    // The host leaves the window while the card closes for the handoff, so Safari cannot be presented.
    handoffEvents.onEvent = ^(NSString *event) {
        if ([event isEqualToString:@"handoff"]) [handoffHost.view removeFromSuperview];
    };
    [handoffOwner.session handleMessage:@"stashExternalPayment" body:@"https://example.invalid/pay"];
    NSArray *handoff = [handoffEvents.events copy];
    BOOL handoffClosed = !handoffOwner.isCurrentlyPresented;

    StashNativeCardConfig *portrait = [StashNativeCardConfig new];
    portrait.orientationPreference = StashNativeOrientationPreferencePortrait;
    NSMutableArray *owners = [NSMutableArray array], *receivers = [NSMutableArray array], *windows = [NSMutableArray array];
    for (NSInteger reset = 0; reset < 2; reset++) {
        StashNative *owner = [StashNative new];
        StashCallbackReceiver *receiver = [StashCallbackReceiver new];
        owner.delegate = receiver;
        UIWindow *window = [[StashInstanceWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
        StashInstancePresenter *host = StashInstanceHost(window, UIUserInterfaceStyleLight);
        // Portrait preparation defers the card; the presenter leaves its window before it resumes.
        [owner openCardWithURL:@"https://example.invalid" fromViewController:host config:portrait];
        [host.view removeFromSuperview];
        if (reset) [owner resetPresentationState];
        [owners addObject:owner]; [receivers addObject:receiver]; [windows addObject:window];
    }
    BOOL admitted = [owners[0] isCurrentlyPresented];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        StashCallbackReceiver *card = receivers[0], *reset = receivers[1];
        completion(@{@"handoffEvents":handoff, @"handoffClosed":@(handoffClosed), @"cardAdmitted":@(admitted),
            @"cardEvents":[card.events copy], @"cardClosed":@(![owners[0] isCurrentlyPresented]),
            @"resetEvents":[reset.events copy], @"resetClosed":@(![owners[1] isCurrentlyPresented])});
        (void)windows;
    });
}

NSDictionary *StashCallbackLiveReceiverProbe(BOOL clear) {
    StashNative *owner = [StashNative new];
    StashCallbackReceiver *second = [StashCallbackReceiver new];
    __block StashCallbackReceiver *first = [StashCallbackReceiver new];
    NSMutableArray *firstEvents = first.events;
    __block BOOL released = NO, aliveDuringCallback = NO;
    first.onRelease = ^{ released = YES; };
    first.onEvent = ^(NSString *event) { aliveDuringCallback = !released; };
    first.onSelector = ^(SEL selector) {
        if (selector != @selector(stashNativeDidCompletePaymentWithOrder:)) return;
        owner.delegate = clear ? nil : second;
        first = nil;
    };
    owner.delegate = first;
    StashCardSession *session = StashCallbackSession(owner);
    session.config.autoClose = NO;
    @autoreleasepool { [session paymentSucceeded:YES order:@"first"]; }
    [session paymentSucceeded:YES order:@"second"];
    BOOL nextDelivery = clear ? second.events.count == 0 : [second.events isEqualToArray:@[@"second"]];
    [owner resetPresentationState];
    BOOL resetKeepsRegistration = owner.delegate == (clear ? nil : second);
    owner.delegate = second;
    BOOL noReplay = clear ? second.events.count == 0 : second.events.count == 1;
    return @{@"snapshottedOnce":@([firstEvents isEqualToArray:@[@"first"]]),
        @"aliveDuringCallback":@(aliveDuringCallback), @"releasedAfterCallback":@(released),
        @"nextDelivery":@(nextDelivery), @"resetKeepsRegistration":@(resetKeepsRegistration),
        @"noReplay":@(noReplay)};
}

NSDictionary *StashCallbackReentrantProbe(void) {
    StashNative *owner = [StashNative new];
    StashCallbackReceiver *first = [StashCallbackReceiver new], *second = [StashCallbackReceiver new];
    owner.delegate = first;
    StashCardSession *session = StashCallbackSession(owner);
    session.browser = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString:@"https://example.invalid"]];
    __block BOOL paymentBeforeTeardown = NO, closeAfterTeardown = NO;
    first.onEvent = ^(NSString *event) {
        paymentBeforeTeardown = owner.isCurrentlyPresented;
        owner.delegate = second;
    };
    second.onEvent = ^(NSString *event) {
        closeAfterTeardown = !owner.isCurrentlyPresented;
        owner.delegate = nil;
        StashCallbackSession(owner).scanner = YES;
    };
    [session paymentSucceeded:YES order:nil];
    [session browserClosed];
    BOOL replacementSurvived = owner.session.scanner && owner.isCurrentlyPresented;
    [owner dismiss];
    BOOL clearSuppressesNext = second.events.count == 1;
    return @{@"paymentBeforeTeardown":@(paymentBeforeTeardown), @"closeAfterTeardown":@(closeAfterTeardown),
        @"eventUsesNewReceiver":@([first.events isEqualToArray:@[@"nil-order"]] &&
            [second.events isEqualToArray:@[@"browser-dismissed"]]), @"replacementSurvived":@(replacementSurvived),
        @"clearSuppressesNext":@(clearSuppressesNext)};
}

NSDictionary *StashCallbackReopenProbe(void) {
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    StashInstancePresenter *host = StashInstanceHost(window, UIUserInterfaceStyleLight);
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSNumber *success in @[@YES, @NO]) {
        StashNative *owner = [StashNative new];
        StashCallbackReceiver *receiver = [StashCallbackReceiver new];
        owner.delegate = receiver;
        StashCardSession *session = StashCallbackSession(owner);
        __block BOOL closedFirst = NO;
        __block StashCardSession *reopened = nil;
        receiver.onEvent = ^(NSString *event) {
            closedFirst = !owner.isCurrentlyPresented && session.closing;
            [owner openCardWithURL:@"https://example.invalid" fromViewController:host config:nil];
            reopened = owner.session;
        };
        [session paymentSucceeded:success.boolValue order:@"order"];
        NSString *name = success.boolValue ? @"success" : @"failure";
        result[[name stringByAppendingString:@"ClosedBeforeEvent"]] = @(closedFirst);
        result[[name stringByAppendingString:@"Reopened"]] = @(reopened && reopened != session && owner.session == reopened);
        result[[name stringByAppendingString:@"Once"]] = @(receiver.events.count == 1);
        [owner resetPresentationState];
    }
    // With autoClose off the card stays open, so the event arrives while it is presented.
    StashNative *owner = [StashNative new];
    StashCallbackReceiver *receiver = [StashCallbackReceiver new];
    owner.delegate = receiver;
    StashCardSession *open = StashCallbackSession(owner);
    open.config.autoClose = NO;
    __block BOOL presentedDuringEvent = NO;
    receiver.onEvent = ^(NSString *event) { presentedDuringEvent = owner.isCurrentlyPresented; };
    [open paymentSucceeded:YES order:nil];
    result[@"repeatableEventWhilePresented"] = @(presentedDuringEvent && owner.session == open);
    [owner resetPresentationState];
    return result;
}

NSDictionary *StashCallbackDelayedProbe(void) {
    StashNative *owner = [StashNative new];
    StashCallbackReceiver *first = [StashCallbackReceiver new], *second = [StashCallbackReceiver new];
    owner.delegate = first;
    StashInstancePendingDismissal *scanner = [StashInstancePendingDismissal new];
    scanner.owner = owner; scanner.config = [StashNativeCardConfig new]; scanner.scanner = YES; owner.session = scanner;
    [scanner completeScan:@"raw-qr-payload"];
    BOOL noEarlyScan = first.events.count == 0 && scanner.closing;
    owner.delegate = second;
    __block BOOL scannerClosed = NO;
    second.onEvent = ^(NSString *event) { scannerClosed = !owner.isCurrentlyPresented; };
    [scanner completeDismissal];
    BOOL scanUsesLiveReceiver = first.events.count == 0 && [second.events isEqualToArray:@[@"raw-qr-payload"]];
    second.onEvent = nil;
    StashInstancePendingDismissal *cancelled = [StashInstancePendingDismissal new];
    cancelled.scanner = YES; cancelled.owner = owner; cancelled.config = [StashNativeCardConfig new]; owner.session = cancelled;
    [owner dismiss];
    owner.delegate = first;
    [cancelled completeDismissal];
    BOOL attributedAfterCleanup = [first.events isEqualToArray:@[@"scan-dismissed"]];
    StashInstancePendingDismissal *stale = [StashInstancePendingDismissal new];
    stale.owner = owner; stale.config = [StashNativeCardConfig new]; owner.session = stale;
    [stale browserClosed];
    [owner resetPresentationState];
    StashCardSession *replacement = StashCallbackSession(owner);
    [stale completeDismissal];
    BOOL staleSilent = owner.session == replacement && first.events.count == 1;
    [owner resetPresentationState];
    return @{@"noEarlyScan":@(noEarlyScan), @"scannerClosed":@(scannerClosed),
        @"scanUsesLiveReceiver":@(scanUsesLiveReceiver), @"attributedAfterCleanup":@(attributedAfterCleanup),
        @"staleSilent":@(staleSilent)};
}

NSDictionary *StashCallbackIsolationProbe(void) {
    StashNative *left = [StashNative new], *right = [StashNative new];
    StashCallbackReceiver *first = [StashCallbackReceiver new], *second = [StashCallbackReceiver new];
    left.delegate = first; right.delegate = second;
    StashCardSession *leftSession = StashCallbackSession(left);
    StashCardSession *rightSession = StashCallbackSession(right);
    rightSession.scanner = YES;
    leftSession.config.autoClose = NO;
    [leftSession paymentSucceeded:YES order:@""];
    [leftSession paymentSucceeded:YES order:@"order"];
    [leftSession paymentSucceeded:NO order:nil];
    [right dismiss];
    BOOL rightClosed = rightSession.closing && left.session == leftSession;
    left.delegate = nil;
    [left dismiss];
    return @{@"isolated":@([first.events isEqualToArray:@[@"nil-order", @"order", @"failure"]] &&
        [second.events isEqualToArray:@[@"scan-dismissed"]]), @"rightClosedOnly":@(rightClosed)};
}
