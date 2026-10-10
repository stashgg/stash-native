#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativeCardPrivate.h"

@interface StashReadinessWebView : WKWebView
@property (nonatomic, strong) NSMutableArray *readinessReplies;
@property (nonatomic) NSUInteger requests;
@end
@implementation StashReadinessWebView
- (instancetype)init {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 390, 560)])) self.readinessReplies = [NSMutableArray array];
    return self;
}
- (void)callAsyncJavaScript:(NSString *)functionBody arguments:(NSDictionary<NSString *, id> *)arguments
    inFrame:(WKFrameInfo *)frame inContentWorld:(WKContentWorld *)contentWorld
    completionHandler:(void (^)(id, NSError *))completionHandler {
    [self.readinessReplies addObject:[completionHandler copy]];
}
- (WKNavigation *)loadRequest:(NSURLRequest *)request { self.requests++; return nil; }
@end

@interface StashReadinessSession : StashCheckoutSession
@property (nonatomic) BOOL foreground;
@end
@implementation StashReadinessSession
- (BOOL)isInitialContentForeground { return self.foreground; }
@end

static StashCheckoutSession *StashLoadingSession(StashNativeCard *owner) {
    StashReadinessSession *session = [StashReadinessSession new];
    session.foreground = YES;
    owner.session = session; session.owner = owner;
    session.config = [StashNativeCardConfig new];
    session.url = @"https://checkout.invalid";
    session.webView = [StashReadinessWebView new];
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    controller.session = session; session.controller = controller;
    [controller loadViewIfNeeded];
    [session webView:session.webView didStartProvisionalNavigation:nil];
    [session webView:session.webView didCommitNavigation:nil];
    return session;
}

static void StashReply(StashReadinessWebView *web, NSUInteger index, BOOL ready) {
    void (^reply)(id, NSError *) = web.readinessReplies[index];
    reply(@(ready), nil);
}

NSString *StashInitialContentReadinessSource(void) { return StashInitialContentReadinessScript(); }

NSDictionary *StashLoadingPresentationProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = StashLoadingSession(owner);
    StashReadinessWebView *web = (id)session.webView;
    BOOL initiallyCovered = session.controller.loadingCover && !web.userInteractionEnabled && web.accessibilityElementsHidden;
    NSTimer *initialWatchdog = session.contentRevealTimer;
    session.contentWaitElapsed = 3;
    [session webView:web didStartProvisionalNavigation:nil];
    BOOL retryKeepsDeadline = session.contentRevealTimer == initialWatchdog && session.contentWaitElapsed >= 3;
    [session webView:web didCommitNavigation:nil];
    StashReply(web, 0, YES);
    BOOL retryRejectsOldReply = session.controller.loadingCover && !session.initialContentRevealed;
    StashReply(web, 1, YES);
    BOOL revealed = session.initialContentRevealed && !session.controller.loadingCover &&
        web.userInteractionEnabled && !web.accessibilityElementsHidden && !session.controller.spinner.isAnimating;
    [session webView:web didStartProvisionalNavigation:nil];
    [session webView:web didCommitNavigation:nil];
    [session webView:web didFinishNavigation:nil];
    BOOL navigationStaysVisible = !session.controller.loadingCover && web.readinessReplies.count == 2;
    [session webViewWebContentProcessDidTerminate:web];
    [session webView:web didStartProvisionalNavigation:nil];
    [session webView:web didCommitNavigation:nil];
    [session webView:web didFinishNavigation:nil];
    BOOL recoveryStaysVisible = web.requests == 1 && !session.controller.loadingCover && web.readinessReplies.count == 2;
    [session finishWithUserDismiss:NO completion:nil];

    StashCheckoutSession *capped = StashLoadingSession(owner);
    capped.receivedResponse = YES;
    capped.contentWaitElapsed = 16;
    ((StashReadinessSession *)capped).foreground = NO;
    [capped updateInitialContentWait];
    BOOL backgroundKeepsCover = capped.controller.loadingCover && !capped.initialContentRevealed;
    StashReply((id)capped.webView, 0, YES);
    BOOL backgroundReplyKeepsCover = capped.controller.loadingCover && !capped.initialContentRevealed;
    ((StashReadinessSession *)capped).foreground = YES;
    [capped updateInitialContentWait];
    BOOL deadlineRevealsWithoutError = owner.session == capped && capped.initialContentRevealed &&
        !capped.controller.loadingCover && !capped.controller.spinner.isAnimating && !capped.loaded;
    [capped finishWithUserDismiss:NO completion:nil];

    StashCheckoutSession *stalled = StashLoadingSession(owner);
    stalled.receivedResponse = YES;
    [stalled webView:stalled.webView didStartProvisionalNavigation:nil];
    stalled.contentWaitElapsed = 16;
    [stalled updateInitialContentWait];
    BOOL provisionalStallReleasesCover = stalled.initialContentRevealed && !stalled.controller.loadingCover;
    [stalled finishWithUserDismiss:NO completion:nil];

    StashCheckoutSession *closed = StashLoadingSession(owner);
    StashCheckoutViewController *closedController = closed.controller;
    StashReadinessWebView *closedWeb = (id)closed.webView;
    [closed finishWithUserDismiss:NO completion:nil];
    StashReply(closedWeb, 0, YES);
    BOOL closeDiscardsReply = owner.session == nil && !closedController.loadingCover && !closedController.spinner.isAnimating;

    StashCheckoutSession *failed = StashLoadingSession(owner);
    StashCheckoutViewController *failedController = failed.controller;
    [failed networkFailed];
    BOOL errorStopsLoading = owner.session == nil && !failedController.loadingCover && !failedController.spinner.isAnimating;
    return @{@"initiallyCovered":@(initiallyCovered), @"retryRejectsOldReply":@(retryRejectsOldReply),
        @"retryKeepsDeadline":@(retryKeepsDeadline), @"provisionalStallReleasesCover":@(provisionalStallReleasesCover),
        @"revealed":@(revealed), @"navigationStaysVisible":@(navigationStaysVisible),
        @"recoveryStaysVisible":@(recoveryStaysVisible), @"deadlineRevealsWithoutError":@(deadlineRevealsWithoutError),
        @"backgroundKeepsCover":@(backgroundKeepsCover),
        @"backgroundReplyKeepsCover":@(backgroundReplyKeepsCover),
        @"closeDiscardsReply":@(closeDiscardsReply), @"errorStopsLoading":@(errorStopsLoading)};
}


@interface StashChromeProbeWebView : WKWebView
@property (nonatomic, strong) NSMutableArray *activationReplies;
@property (nonatomic) NSUInteger samples;
@property (nonatomic) NSUInteger requests;
@end
@implementation StashChromeProbeWebView
- (instancetype)init {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 390, 560)])) self.activationReplies = [NSMutableArray array];
    return self;
}
- (void)evaluateJavaScript:(NSString *)script inFrame:(WKFrameInfo *)frame inContentWorld:(WKContentWorld *)world
    completionHandler:(void (^)(id, NSError *))completion {
    if ([script containsString:@".activate("]) [self.activationReplies addObject:[completion copy]];
    if ([script containsString:@".sample()"] ) self.samples++;
}
- (void)evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion {}
- (WKNavigation *)loadRequest:(NSURLRequest *)request { self.requests++; return nil; }
@end
@interface StashChromeProbeFrame : NSObject
@property (nonatomic) BOOL top;
@end
@implementation StashChromeProbeFrame
- (BOOL)isMainFrame { return self.top; }
@end
@interface StashChromeProbeMessage : NSObject
@property (nonatomic, strong) WKWebView *source;
@property (nonatomic, strong) WKFrameInfo *sourceFrame;
@property (nonatomic, strong) WKContentWorld *sourceWorld;
@property (nonatomic, strong) NSDictionary *payload;
@end
@implementation StashChromeProbeMessage
- (WKWebView *)webView { return self.source; }
- (WKFrameInfo *)frameInfo { return self.sourceFrame; }
- (WKContentWorld *)world { return self.sourceWorld; }
- (id)body { return self.payload; }
- (NSString *)name { return StashTopChromeHandlerName; }
@end
NSString *StashTopChromeProbeSource(void) { return StashTopChromeScript(); }
NSDictionary *StashTopChromeLifecycleProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new];
    StashChromeProbeWebView *web = [StashChromeProbeWebView new];
    session.owner = owner; owner.session = session; session.webView = web;
    session.config = [StashNativeCardConfig new]; session.loaded = YES; session.initialContentRevealed = YES;
    session.url = @"https://checkout.invalid";
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    controller.session = session; session.controller = controller;
    UIColor *fallback = [UIColor colorWithRed:0.2 green:0.3 blue:0.4 alpha:1];
    web.underPageBackgroundColor = fallback;
    StashChromeProbeFrame *frame = [StashChromeProbeFrame new]; frame.top = YES;
    StashChromeProbeMessage *message = [StashChromeProbeMessage new];
    message.source = web; message.sourceFrame = (id)frame; message.sourceWorld = StashTopChromeWorld();
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [session invalidateTopChrome]; [session activateTopChrome];
    NSString *oldToken = session.topChromeToken;
    void (^oldReply)(id, NSError *) = web.activationReplies.lastObject;
    [session invalidateTopChrome]; [session activateTopChrome];
    oldReply(@"old-document", nil);
    result[@"staleReply"] = @(!session.topChromeDocumentID && ![session.topChromeToken isEqual:oldToken]);
    void (^reply)(id, NSError *) = web.activationReplies.lastObject;
    reply(@"current-document", nil);
    result[@"forcedSampleAfterBinding"] = @([session.topChromeDocumentID isEqual:@"current-document"] && web.samples == 1);
    NSDictionary *(^payload)(id) = ^NSDictionary *(id color) {
        return @{@"generation":@(session.topChromeGeneration), @"token":session.topChromeToken ?: @"",
            @"documentId":session.topChromeDocumentID ?: @"", @"color":color};
    };
    message.payload = payload(@[@247,@249,@244]);
    [session acceptTopChromeMessage:(id)message];
    UIColor *panel = [UIColor colorWithRed:247/255.0 green:249/255.0 blue:244/255.0 alpha:1];
    result[@"acceptsPanel"] = @([controller.topChromeColor isEqual:panel] && [controller.view.backgroundColor isEqual:panel]);
    BOOL malformedIgnored = YES;
    for (id bad in @[@[@YES,@0,@0], @[@1,@2], @[@1,@2,@256], @[@1,@2,@(NAN)], @[@"1",@2,@3]]) {
        message.payload = payload(bad); [session acceptTopChromeMessage:(id)message];
        malformedIgnored &= [controller.topChromeColor isEqual:panel];
    }
    result[@"malformedIgnored"] = @(malformedIgnored);
    message.payload = payload(@[@0,@0,@0]);
    frame.top = NO; [session acceptTopChromeMessage:(id)message]; frame.top = YES;
    message.sourceWorld = WKContentWorld.pageWorld; [session acceptTopChromeMessage:(id)message]; message.sourceWorld = StashTopChromeWorld();
    message.source = [WKWebView new]; [session acceptTopChromeMessage:(id)message]; message.source = web;
    NSMutableDictionary *stale = [message.payload mutableCopy]; stale[@"documentId"] = @"old-document";
    message.payload = stale; [session acceptTopChromeMessage:(id)message];
    result[@"foreignMessagesIgnored"] = @([controller.topChromeColor isEqual:panel]);
    message.payload = payload(NSNull.null); [session acceptTopChromeMessage:(id)message];
    result[@"unknownResetsFallback"] = @(!controller.topChromeColor && [controller.view.backgroundColor isEqual:web.underPageBackgroundColor]);
    WKNavigation *navigationA = (id)[NSObject new], *navigationB = (id)[NSObject new];
    [session webView:web didStartProvisionalNavigation:navigationA];
    NSUInteger activations = web.activationReplies.count;
    [session webView:web didStartProvisionalNavigation:navigationB];
    NSError *cancel = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
    [session webView:web didFailProvisionalNavigation:navigationA withError:cancel];
    result[@"obsoleteCancellationIgnored"] = @(web.activationReplies.count == activations);
    [session webView:web didFailProvisionalNavigation:navigationB withError:cancel];
    result[@"currentCancellationReactivates"] = @(web.activationReplies.count == activations + 1);
    reply = web.activationReplies.lastObject; reply(@"returned-document", nil);
    result[@"sameDocumentReturnBinds"] = @([session.topChromeDocumentID isEqual:@"returned-document"]);
    [session webViewWebContentProcessDidTerminate:web];
    result[@"rendererInvalidates"] = @(!session.topChromeDocumentID && !controller.topChromeColor && web.requests == 1);
    [session activateTopChrome]; reply = web.activationReplies.lastObject;
    [session cleanup]; reply(@"late-document", nil);
    result[@"cleanupRejectsReply"] = @(!session.webView && !session.topChromeDocumentID && !session.topChromeToken);
    [web.activationReplies removeAllObjects]; owner.session = nil;
    return result;
}

NSDictionary *StashChromeLoadingCoverProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.owner = owner; owner.session = session;
    session.config = [StashNativeCardConfig new];
    session.webView = [WKWebView new];
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session; [controller configurePresentation];
    controller.view.frame = CGRectMake(0, 0, 390, 576);
    [controller viewDidLayoutSubviews];
    CGRect expected = session.webView.frame;
    BOOL covers = CGRectEqualToRect(controller.loadingCover.frame, expected) &&
        CGRectContainsRect(controller.loadingCover.frame, session.webView.frame);
    covers &= CGRectEqualToRect(session.webView.frame, controller.view.bounds);
    controller.topChromeColor = UIColor.redColor; [controller updateTopChromeBackgroundColor];
    result[@"native"] = @(covers && controller.loadingCover.alpha == 1);
    [session cleanup]; owner.session = nil;
    return result;
}


@interface StashBackingProbeWebView : StashChromeProbeWebView
@property (nonatomic) NSUInteger backingWrites;
@property (nonatomic) NSUInteger backingResets;
@property (nonatomic) NSUInteger setterDepth;
@property (nonatomic) NSUInteger maximumSetterDepth;
@end
@implementation StashBackingProbeWebView
- (void)setUnderPageBackgroundColor:(UIColor *)color {
    self.backingWrites++;
    if (!color) self.backingResets++;
    self.setterDepth++;
    self.maximumSetterDepth = MAX(self.maximumSetterDepth, self.setterDepth);
    [super setUnderPageBackgroundColor:color];
    self.setterDepth--;
}
@end
@interface StashBackingReentryObserver : NSObject
@property (nonatomic, weak) StashCheckoutSession *session;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic) NSUInteger callbacks;
@property (nonatomic) NSUInteger callbackDepth;
@end
@implementation StashBackingReentryObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    self.callbacks++;
    self.callbackDepth++;
    SEL selector = NSSelectorFromString(@"applyInferredPageBackingColor:");
    if (self.callbackDepth < 3 && [self.session respondsToSelector:selector])
        ((void (*)(id, SEL, UIColor *))[self.session methodForSelector:selector])(self.session, selector, self.color);
    self.callbackDepth--;
}
@end
static BOOL StashLoadingSamePaint(UIColor *left, UIColor *right);

NSDictionary *StashPageBackingLifecycleProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new];
    StashBackingProbeWebView *web = [StashBackingProbeWebView new];
    owner.session = session; session.owner = owner; session.webView = web;
    session.config = [StashNativeCardConfig new]; session.loaded = YES; session.initialContentRevealed = YES;
    session.url = @"https://checkout.invalid";
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session;
    UIColor *coverColor = UIColor.magentaColor;
    controller.loadingCover = [UIView new]; controller.loadingCover.backgroundColor = coverColor;
    web.backgroundColor = stash_sheetBackgroundUIColor();
    UIColor *fallback = web.underPageBackgroundColor;
    UIColor *panel = [UIColor colorWithRed:247/255.0 green:249/255.0 blue:244/255.0 alpha:1];
    StashChromeProbeFrame *frame = [StashChromeProbeFrame new]; frame.top = YES;
    StashChromeProbeMessage *message = [StashChromeProbeMessage new];
    message.source = web; message.sourceFrame = (id)frame; message.sourceWorld = StashTopChromeWorld();
    void (^bind)(void) = ^{
        session.topChromeToken = @"backing-token";
        session.topChromeDocumentID = @"backing-document";
    };
    NSDictionary *(^payload)(id,id) = ^NSDictionary *(id edge,id backing) {
        NSMutableDictionary *value = [@{@"generation":@(session.topChromeGeneration), @"token":session.topChromeToken ?: @"",
            @"documentId":session.topChromeDocumentID ?: @"", @"color":edge} mutableCopy];
        if (backing) value[@"backingColor"] = backing;
        return value;
    };
    void (^send)(id,id) = ^(id edge,id backing) {
        message.payload = payload(edge, backing); [session acceptTopChromeMessage:(id)message];
    };
    bind();
    NSUInteger writes = web.backingWrites;
    send(@[@247,@249,@244], @[@247,@249,@244]);
    BOOL applied = StashLoadingSamePaint(web.underPageBackgroundColor, panel) && StashLoadingSamePaint(web.scrollView.backgroundColor, panel) && StashLoadingSamePaint(web.backgroundColor, panel);
    send(@[@247,@249,@244], @[@247,@249,@244]);
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"appliesOnce"] = @(applied && web.backingWrites == writes + 1);
    BOOL ignored = YES;
    for (id bad in @[@[@YES,@0,@0], @[@1,@2], @[@1,@2,@256], @[@1,@2,@(NAN)], @[@"1",@2,@3]]) {
        send(@[@0,@0,@0], bad); ignored &= StashLoadingSamePaint(web.underPageBackgroundColor, panel);
    }
    message.payload = payload(@[@0,@0,@0], @[@0,@0,@0]);
    frame.top = NO; [session acceptTopChromeMessage:(id)message]; frame.top = YES;
    message.sourceWorld = WKContentWorld.pageWorld; [session acceptTopChromeMessage:(id)message]; message.sourceWorld = StashTopChromeWorld();
    message.source = [WKWebView new]; [session acceptTopChromeMessage:(id)message]; message.source = web;
    for (NSString *key in @[@"token", @"documentId", @"generation"]) {
        NSMutableDictionary *stale = [payload(@[@0,@0,@0], @[@0,@0,@0]) mutableCopy];
        stale[key] = [key isEqual:@"generation"] ? @9999 : @"stale";
        message.payload = stale; [session acceptTopChromeMessage:(id)message];
    }
    result[@"messageIsolation"] = @(ignored && StashLoadingSamePaint(web.underPageBackgroundColor, panel));
    send(@[@247,@249,@244], NSNull.null);
    result[@"backingNullResets"] = @(web.backingResets == 1 && StashLoadingSamePaint(web.underPageBackgroundColor, fallback) &&
        [controller.topChromeColor isEqual:panel] && StashLoadingSamePaint(web.scrollView.backgroundColor, fallback) && StashLoadingSamePaint(web.backgroundColor, fallback));
    send(@[@247,@249,@244], @[@247,@249,@244]); send(NSNull.null, @[@247,@249,@244]);
    result[@"edgeNullResets"] = @(web.backingResets == 2 && !controller.topChromeColor && StashLoadingSamePaint(web.underPageBackgroundColor, fallback));
    send(@[@247,@249,@244], @[@247,@249,@244]); send(@[@247,@249,@244], nil);
    result[@"missingBackingResets"] = @(web.backingResets == 3 && StashLoadingSamePaint(web.underPageBackgroundColor, fallback));
    send(@[@247,@249,@244], @[@247,@249,@244]);
    WKNavigation *navigation = (id)[NSObject new]; [session webView:web didStartProvisionalNavigation:navigation];
    result[@"navigationResets"] = @(web.backingResets == 4 && StashLoadingSamePaint(web.underPageBackgroundColor, fallback));
    [session webView:web didFailProvisionalNavigation:navigation withError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
    void (^reply)(id,NSError *) = web.activationReplies.lastObject;
    if (reply) reply(@"returned", nil);
    send(@[@247,@249,@244], @[@247,@249,@244]);
    result[@"canceledNavigationReacquires"] = @([session.topChromeDocumentID isEqual:@"returned"] && StashLoadingSamePaint(web.underPageBackgroundColor, panel));
    [session webViewWebContentProcessDidTerminate:web];
    result[@"rendererResets"] = @(web.backingResets == 5 && StashLoadingSamePaint(web.underPageBackgroundColor, fallback));
    bind();
    web.underPageBackgroundColor = nil;
    StashBackingReentryObserver *observer = [StashBackingReentryObserver new]; observer.session = session; observer.color = panel;
    [web addObserver:observer forKeyPath:@"underPageBackgroundColor" options:NSKeyValueObservingOptionNew context:NULL];
    writes = web.backingWrites; web.maximumSetterDepth = 0;
    send(@[@247,@249,@244], @[@247,@249,@244]); send(@[@247,@249,@244], NSNull.null);
    [web removeObserver:observer forKeyPath:@"underPageBackgroundColor"];
    result[@"synchronousKVOReentry"] = @(observer.callbacks >= 2 && web.backingWrites == writes + 2 &&
        web.maximumSetterDepth == 1 && StashLoadingSamePaint(web.underPageBackgroundColor, fallback));
    result[@"coverUnchangedAndWebBackgroundReset"] = @([controller.loadingCover.backgroundColor isEqual:coverColor] &&
        StashLoadingSamePaint(web.backgroundColor, fallback));
    send(@[@247,@249,@244], @[@247,@249,@244]);
    NSUInteger resets = web.backingResets;
    [session cleanup];
    result[@"cleanupResets"] = @(web.backingResets == resets + 1 && StashLoadingSamePaint(web.underPageBackgroundColor, fallback) && StashLoadingSamePaint(web.backgroundColor, fallback));
    [web.activationReplies removeAllObjects]; owner.session = nil;
    return result;
}

@interface StashLoadingBackgroundHost : UIViewController
@end
@implementation StashLoadingBackgroundHost
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    [self addChildViewController:controller];
    controller.view.frame = self.view.bounds;
    [self.view addSubview:controller.view];
    [controller didMoveToParentViewController:self];
    if (completion) completion();
}
@end

NSDictionary *StashObservedChromeContentFixture(UIViewController *presenter, CGFloat measured) {
    StashLoadingBackgroundHost *host = [StashLoadingBackgroundHost new];
    [presenter addChildViewController:host]; host.view.frame = presenter.view.bounds;
    [presenter.view addSubview:host.view]; [host didMoveToParentViewController:presenter];
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new];
    owner.session = session; session.owner = owner; session.presenter = host;
    session.url = @"about:blank"; session.config = [StashNativeCardConfig new];
    session.measuredContentHeight = measured;
    [session presentCheckout]; [session.webView stopLoading];
    session.loaded = YES; session.initialContentRevealed = YES;
    StashCheckoutViewController *controller = session.controller;
    [controller revealInitialContentAnimated:NO];
    controller.view.frame = CGRectMake(30, 50, 390, [controller contentHeightForMaximum:800 expanded:NO]);
    [controller viewDidLayoutSubviews]; controller.previousWidth = session.webView.bounds.size.width;
    return @{@"owner":owner, @"session":session, @"controller":controller, @"web":session.webView};
}

static BOOL StashLoadingSamePaint(UIColor *left, UIColor *right) {
    CGFloat lr, lg, lb, la, rr, rg, rb, ra;
    return [left getRed:&lr green:&lg blue:&lb alpha:&la] && [right getRed:&rr green:&rg blue:&rb alpha:&ra] &&
        fabs(lr - rr) < 0.00001 && fabs(lg - rg) < 0.00001 && fabs(lb - rb) < 0.00001 && fabs(la - ra) < 0.00001;
}

NSDictionary *StashLoadingCoverBackgroundProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    BOOL glass = NO;
    if (@available(iOS 26.0, *)) glass = YES;
    UIWindow *previous = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) previous = window;
    UIWindow *window = previous.windowScene ? [[UIWindow alloc] initWithWindowScene:previous.windowScene] :
        [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 700)];
    for (NSUInteger dark = 0; dark < 2; dark++) {
        StashLoadingBackgroundHost *host = [StashLoadingBackgroundHost new];
        window.rootViewController = host; [window makeKeyAndVisible];
        StashNativeCard *owner = [StashNativeCard new];
        StashCheckoutSession *session = [StashCheckoutSession new];
        owner.session = session; session.owner = owner; session.presenter = host;

        session.url = @"about:blank";
        session.config = [StashNativeCardConfig new];
        [session presentCheckout]; [session.webView stopLoading];
        UIView *cover = session.controller.loadingCover;
        UIColor *initial = dark ? UIColor.blackColor : UIColor.whiteColor;
        UIColor *page = dark ? UIColor.whiteColor : UIColor.blackColor;
        session.webView.underPageBackgroundColor = initial;
        UIColor *loading = cover.backgroundColor;
        session.webView.underPageBackgroundColor = page;
        BOOL stable = cover && cover == session.controller.loadingCover && cover.alpha == 1 &&
            [cover.backgroundColor isEqual:loading] && !session.initialContentRevealed;
        BOOL follows = StashLoadingSamePaint(session.controller.view.backgroundColor, glass ? UIColor.clearColor : page) &&
            StashLoadingSamePaint(session.webView.scrollView.backgroundColor, page);
        BOOL concealed = session.webView.alpha == (glass ? 0 : 1) && !session.webView.userInteractionEnabled &&
            session.webView.accessibilityElementsHidden;
        [session.controller revealInitialContentAnimated:NO];
        BOOL revealed = session.webView.alpha == 1 && !session.controller.loadingCover &&
            !session.controller.glassLoading && StashLoadingSamePaint(session.controller.view.backgroundColor, page) &&
            session.webView.userInteractionEnabled && !session.webView.accessibilityElementsHidden;
        result[[NSString stringWithFormat:@"%@-%@", @"native", dark ? @"dark" : @"light"]] = @(stable && follows && concealed && revealed);
        [session cleanup]; owner.session = nil;
    }
    StashNativeCard *shared = [StashNativeCard sharedInstance];
    StashCheckoutSession *savedSession = shared.session;
    for (NSUInteger dark = 0; dark < 2; dark++) {
        UIViewController *host = [UIViewController new];
        host.overrideUserInterfaceStyle = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
        window.rootViewController = host; [window makeKeyAndVisible];
        StashCheckoutSession *session = [StashCheckoutSession new];
        shared.session = session; session.owner = shared; session.presenter = host;

        session.config = [StashNativeCardConfig new];
        session.webView = [[WKWebView alloc] initWithFrame:CGRectZero];
        UIColor *page = UIColor.magentaColor;
        UIColor *edge = UIColor.greenColor;
        session.webView.underPageBackgroundColor = page;
        StashCheckoutViewController *controller = [StashCheckoutViewController new];
        session.controller = controller; controller.session = session;
        controller.topChromeColor = edge;
        [controller configurePresentation];
        UIColor *initial = stash_sheetBackgroundUIColor();
        BOOL notLoaded = !controller.isViewLoaded;
        [controller loadViewIfNeeded];
        UIView *cover = controller.loadingCover;
        BOOL nativeMaterial = YES;
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 260100
        if (@available(iOS 26.1, *)) {
            for (UISheetPresentationControllerDetent *detent in controller.sheetPresentationController.detents)
                nativeMaterial &= [controller usesFloatingNativeSizing]
                    ? [detent.backgroundEffect isKindOfClass:UIBlurEffect.class] : detent.backgroundEffect == nil;
        }
#endif
        BOOL covered = notLoaded && cover && cover.alpha == 1 && !session.initialContentRevealed &&
            stash_effectiveThemeIsDark() == (dark != 0) &&
            StashLoadingSamePaint(cover.backgroundColor, glass ? UIColor.clearColor : initial) &&
            session.webView.alpha == (glass ? 0 : 1) && !StashLoadingSamePaint(initial, page);
        BOOL contentPaint = StashLoadingSamePaint(controller.view.backgroundColor, glass ? UIColor.clearColor : edge);
        [controller revealInitialContentAnimated:NO];
        contentPaint &= StashLoadingSamePaint(controller.view.backgroundColor, edge) && session.webView.alpha == 1;
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 260100
        if (@available(iOS 26.1, *)) {
            for (UISheetPresentationControllerDetent *detent in controller.sheetPresentationController.detents)
                nativeMaterial &= detent.backgroundEffect == nil;
        }
#endif
        result[[NSString stringWithFormat:@"construction-%@-%@", @"native", dark ? @"dark" : @"light"]] = @(covered && contentPaint && nativeMaterial);
        [session cleanup]; shared.session = nil;
    }
    shared.session = savedSession;
    window.hidden = YES; [previous makeKeyWindow];
    return result;
}
