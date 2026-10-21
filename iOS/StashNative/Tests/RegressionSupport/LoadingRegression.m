#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativePrivate.h"

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

@interface StashReadinessSession : StashCardSession
@property (nonatomic) BOOL foreground;
@end
@implementation StashReadinessSession
- (BOOL)isInitialContentForeground { return self.foreground; }
@end

static StashCardSession *StashLoadingSession(StashNative *owner) {
    StashReadinessSession *session = [StashReadinessSession new];
    session.foreground = YES;
    owner.session = session; session.owner = owner;
    session.config = [StashNativeCardConfig new];
    session.url = @"https://checkout.invalid";
    session.webView = [StashReadinessWebView new];
    StashCardViewController *controller = [StashCardViewController new];
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
    StashNative *owner = [StashNative new];
    StashCardSession *session = StashLoadingSession(owner);
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

    StashCardSession *capped = StashLoadingSession(owner);
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

    StashCardSession *stalled = StashLoadingSession(owner);
    stalled.receivedResponse = YES;
    [stalled webView:stalled.webView didStartProvisionalNavigation:nil];
    stalled.contentWaitElapsed = 16;
    [stalled updateInitialContentWait];
    BOOL provisionalStallReleasesCover = stalled.initialContentRevealed && !stalled.controller.loadingCover;
    [stalled finishWithUserDismiss:NO completion:nil];

    StashCardSession *closed = StashLoadingSession(owner);
    StashCardViewController *closedController = closed.controller;
    StashReadinessWebView *closedWeb = (id)closed.webView;
    [closed finishWithUserDismiss:NO completion:nil];
    StashReply(closedWeb, 0, YES);
    BOOL closeDiscardsReply = owner.session == nil && !closedController.loadingCover && !closedController.spinner.isAnimating;

    StashCardSession *failed = StashLoadingSession(owner);
    StashCardViewController *failedController = failed.controller;
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
    StashNative *owner = [StashNative new];
    StashCardSession *session = [StashCardSession new];
    StashChromeProbeWebView *web = [StashChromeProbeWebView new];
    session.owner = owner; owner.session = session; session.webView = web;
    session.config = [StashNativeCardConfig new]; session.loaded = YES; session.initialContentRevealed = YES;
    session.url = @"https://checkout.invalid";
    StashCardViewController *controller = [StashCardViewController new];
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
    StashNative *owner = [StashNative new];
    StashCardSession *session = [StashCardSession new];
    session.owner = owner; owner.session = session;
    session.config = [StashNativeCardConfig new];
    session.webView = [WKWebView new];
    StashCardViewController *controller = [StashCardViewController new];
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
@property (nonatomic, weak) StashCardSession *session;
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
    StashNative *owner = [StashNative new];
    StashCardSession *session = [StashCardSession new];
    StashBackingProbeWebView *web = [StashBackingProbeWebView new];
    owner.session = session; session.owner = owner; session.webView = web;
    session.config = [StashNativeCardConfig new]; session.loaded = YES; session.initialContentRevealed = YES;
    session.url = @"https://checkout.invalid";
    StashCardViewController *controller = [StashCardViewController new];
    session.controller = controller; controller.session = session;
    UIColor *coverColor = UIColor.magentaColor;
    controller.loadingCover = [UIView new]; controller.loadingCover.backgroundColor = coverColor;
    web.backgroundColor = StashSheetBackgroundUIColor(session.presenter.traitCollection);
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
    StashNative *owner = [StashNative new];
    StashCardSession *session = [StashCardSession new];
    owner.session = session; session.owner = owner; session.presenter = host;
    session.url = @"about:blank"; session.config = [StashNativeCardConfig new];
    session.measuredContentHeight = measured;
    [session presentCheckout]; [session.webView stopLoading];
    session.loaded = YES; session.initialContentRevealed = YES;
    StashCardViewController *controller = session.controller;
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

BOOL StashGlassLoadingSurfaceDefault(void) {
    NSInteger saved = StashGlassLoadingOverride;
    StashGlassLoadingOverride = -1;
    BOOL available = StashGlassLoadingAvailable();
    StashGlassLoadingOverride = saved;
    return available;
}

NSDictionary *StashLoadingCoverBackgroundProbe(BOOL glass) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSInteger savedOverride = StashGlassLoadingOverride;
    StashGlassLoadingOverride = glass ? 1 : 0;
    UIWindow *previous = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) previous = window;
    UIWindow *window = previous.windowScene ? [[UIWindow alloc] initWithWindowScene:previous.windowScene] :
        [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 700)];
    for (NSUInteger dark = 0; dark < 2; dark++) {
        StashLoadingBackgroundHost *host = [StashLoadingBackgroundHost new];
        window.rootViewController = host; [window makeKeyAndVisible];
        StashNative *owner = [StashNative new];
        StashCardSession *session = [StashCardSession new];
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
    StashNative *shared = [StashNative sharedInstance];
    StashCardSession *savedSession = shared.session;
    for (NSUInteger dark = 0; dark < 2; dark++) {
        UIViewController *host = [UIViewController new];
        host.overrideUserInterfaceStyle = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
        window.rootViewController = host; [window makeKeyAndVisible];
        StashCardSession *session = [StashCardSession new];
        shared.session = session; session.owner = shared; session.presenter = host;

        session.config = [StashNativeCardConfig new];
        session.webView = [[WKWebView alloc] initWithFrame:CGRectZero];
        UIColor *page = UIColor.magentaColor;
        UIColor *edge = UIColor.greenColor;
        session.webView.underPageBackgroundColor = page;
        StashCardViewController *controller = [StashCardViewController new];
        session.controller = controller; controller.session = session;
        controller.topChromeColor = edge;
        [controller configurePresentation];
        UIColor *initial = StashSheetBackgroundUIColor(host.traitCollection);
        BOOL notLoaded = !controller.isViewLoaded;
        [controller loadViewIfNeeded];
        UIView *cover = controller.loadingCover;
        BOOL nativeMaterial = YES;
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 260100
        if (@available(iOS 26.1, *)) {
            for (UISheetPresentationControllerDetent *detent in controller.sheetPresentationController.detents)
                nativeMaterial &= [controller usesFloatingNativeSizing] && glass
                    ? [detent.backgroundEffect isKindOfClass:UIBlurEffect.class] : detent.backgroundEffect == nil;
        }
#endif
        BOOL covered = notLoaded && cover && cover.alpha == 1 && !session.initialContentRevealed &&
            StashEffectiveThemeIsDark(host.traitCollection) == (dark != 0) &&
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
    StashGlassLoadingOverride = savedOverride;
    return result;
}

#pragma mark - Navigation policy, load budget, new windows, dialogs, post-load failure

@interface StashNavigationProbeDelegate : NSObject <StashNativeDelegate>
@property (nonatomic) NSInteger successes;
@property (nonatomic) NSInteger failures;
@property (nonatomic) NSInteger dismissals;
@property (nonatomic) NSInteger networkErrors;
@property (nonatomic) BOOL presentedAtNetworkError;
@property (nonatomic, weak) StashNative *owner;
@end
@implementation StashNavigationProbeDelegate
- (void)stashNativeDidCompletePaymentWithOrder:(NSString *)order { self.successes++; }
- (void)stashNativeDidFailPayment { self.failures++; }
- (void)stashNativeDidDismissCard { self.dismissals++; }
- (void)stashNativeDidEncounterNetworkError {
    self.networkErrors++;
    self.presentedAtNetworkError = self.owner.isCurrentlyPresented;
}
@end

@interface StashNavigationActionDouble : NSObject
@property (nonatomic, strong) NSURLRequest *request;
@property (nonatomic) WKNavigationType navigationType;
@property (nonatomic, strong) id targetFrame;
@end
@implementation StashNavigationActionDouble
@end

@interface StashNavigationResponseDouble : NSObject
@property (nonatomic, getter=isForMainFrame) BOOL forMainFrame;
@property (nonatomic, strong) NSURLResponse *response;
@end
@implementation StashNavigationResponseDouble
@end

@interface StashExternalOpenRecorder : NSObject
@property (nonatomic, strong) NSMutableArray<NSURL *> *urls;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *options;
@property (nonatomic, strong) NSMutableArray *completions;
@end
@implementation StashExternalOpenRecorder
- (instancetype)init {
    if ((self = [super init])) {
        self.urls = [NSMutableArray array]; self.options = [NSMutableArray array]; self.completions = [NSMutableArray array];
    }
    return self;
}
- (void)install {
    StashExternalOpenRecorder *recorder = self;
    StashSetExternalURLOpener(^(NSURL *url, NSDictionary *options, void (^completion)(BOOL)) {
        [recorder.urls addObject:url];
        [recorder.options addObject:options ?: @{}];
        [recorder.completions addObject:completion ? [completion copy] : NSNull.null];
    });
}
- (void)reset { [self.urls removeAllObjects]; [self.options removeAllObjects]; [self.completions removeAllObjects]; }
- (NSString *)lastURL { return self.urls.lastObject.absoluteString ?: @""; }
@end

static StashNavigationActionDouble *StashNavigationAction(NSString *url, WKNavigationType type, BOOL mainFrame) {
    StashNavigationActionDouble *action = [StashNavigationActionDouble new];
    action.request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    action.navigationType = type;
    StashChromeProbeFrame *frame = [StashChromeProbeFrame new];
    frame.top = mainFrame;
    action.targetFrame = frame;
    return action;
}

static StashNavigationResponseDouble *StashNavigationResponse(NSInteger status, BOOL mainFrame) {
    StashNavigationResponseDouble *response = [StashNavigationResponseDouble new];
    response.forMainFrame = mainFrame;
    response.response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://checkout.invalid"]
        statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:nil];
    return response;
}

static StashNavigationProbeDelegate *StashNavigationDelegate(StashNative *owner) {
    StashNavigationProbeDelegate *delegate = [StashNavigationProbeDelegate new];
    delegate.owner = owner;
    owner.delegate = delegate;
    return delegate;
}

NSDictionary *StashNavigationPolicyProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    StashExternalOpenRecorder *opens = [StashExternalOpenRecorder new];
    [opens install];
    StashNative *owner = [StashNative new];
    StashNavigationProbeDelegate *delegate = StashNavigationDelegate(owner);
    StashCardSession *session = StashLoadingSession(owner);
    session.config.autoClose = NO;
    session.loaded = YES;
    __block NSInteger calls = 0;
    __block WKNavigationActionPolicy policy = WKNavigationActionPolicyAllow;
    void (^decide)(WKNavigationActionPolicy) = ^(WKNavigationActionPolicy decision) { calls++; policy = decision; };
    void (^reset)(void) = ^{ calls = 0; policy = WKNavigationActionPolicyAllow; [opens reset]; };
    void (^navigate)(NSString *, WKNavigationType, BOOL) = ^(NSString *url, WKNavigationType type, BOOL mainFrame) {
        [session webView:session.webView decidePolicyForNavigationAction:(id)StashNavigationAction(url, type, mainFrame)
            decisionHandler:decide];
    };

    reset(); navigate(@"stashdemo://stash-pay/success", WKNavigationTypeOther, YES);
    result[@"resultSchemeCancelsAndRoutesPayment"] = @(calls == 1 && policy == WKNavigationActionPolicyCancel &&
        delegate.successes == 1 && opens.urls.count == 0 && owner.isCurrentlyPresented);

    reset(); navigate(@"stashdemo://open/settings", WKNavigationTypeOther, YES);
    result[@"customSchemeCancelsAndOpensExternally"] = @(calls == 1 && policy == WKNavigationActionPolicyCancel &&
        [opens.lastURL isEqualToString:@"stashdemo://open/settings"] && opens.urls.count == 1 &&
        opens.options.firstObject.count == 0 && delegate.successes == 1 && delegate.failures == 0);

    reset(); navigate(@"https://apps.apple.com/app/id123456", WKNavigationTypeLinkActivated, YES);
    result[@"appStoreHostCancelsAndOpensExternally"] = @(calls == 1 && policy == WKNavigationActionPolicyCancel &&
        opens.urls.count == 1 && [opens.lastURL isEqualToString:@"https://apps.apple.com/app/id123456"] &&
        opens.options.firstObject.count == 0);

    reset(); navigate(@"https://merchant.example/pay", WKNavigationTypeLinkActivated, YES);
    BOOL deferred = calls == 0 && opens.urls.count == 1 &&
        [opens.options.firstObject[UIApplicationOpenURLOptionUniversalLinksOnly] boolValue] &&
        opens.completions.firstObject != NSNull.null;
    void (^complete)(BOOL) = opens.completions.firstObject;
    if (deferred) complete(YES);
    result[@"universalLinkSuccessCancelsOnce"] = @(deferred && calls == 1 && policy == WKNavigationActionPolicyCancel);

    reset(); navigate(@"https://merchant.example/pay", WKNavigationTypeLinkActivated, YES);
    complete = opens.completions.firstObject;
    if (opens.completions.count == 1 && (id)complete != NSNull.null) complete(NO);
    result[@"universalLinkFailureAllowsOnce"] = @(calls == 1 && policy == WKNavigationActionPolicyAllow);

    reset(); navigate(@"https://merchant.example/frame", WKNavigationTypeLinkActivated, NO);
    result[@"subframeLinkAllowsInline"] = @(calls == 1 && policy == WKNavigationActionPolicyAllow && opens.urls.count == 0);

    reset(); navigate(@"https://merchant.example/3ds", WKNavigationTypeOther, YES);
    result[@"scriptNavigationAllowsInline"] = @(calls == 1 && policy == WKNavigationActionPolicyAllow && opens.urls.count == 0);

    reset(); navigate(@"about:blank", WKNavigationTypeOther, YES);
    result[@"aboutBlankAllows"] = @(calls == 1 && policy == WKNavigationActionPolicyAllow && opens.urls.count == 0);

    [session finishWithUserDismiss:NO completion:nil];
    reset(); navigate(@"https://merchant.example/late", WKNavigationTypeOther, YES);
    result[@"inactiveSessionCancels"] = @(calls == 1 && policy == WKNavigationActionPolicyCancel && opens.urls.count == 0 &&
        delegate.dismissals == 0 && delegate.networkErrors == 0);
    StashSetExternalURLOpener(nil);
    owner.session = nil;
    return result;
}

NSDictionary *StashNavigationResponseProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    StashNative *owner = [StashNative new];
    StashNavigationProbeDelegate *delegate = StashNavigationDelegate(owner);
    __block NSInteger calls = 0;
    __block WKNavigationResponsePolicy policy = WKNavigationResponsePolicyAllow;
    void (^decide)(WKNavigationResponsePolicy) = ^(WKNavigationResponsePolicy decision) { calls++; policy = decision; };

    StashCardSession *failing = StashLoadingSession(owner);
    [failing beginLoadBudget];
    [failing webView:failing.webView decidePolicyForNavigationResponse:(id)StashNavigationResponse(404, YES) decisionHandler:decide];
    result[@"errorBeforeLoadCancelsAndFails"] = @(calls == 1 && policy == WKNavigationResponsePolicyCancel &&
        delegate.networkErrors == 1 && !delegate.presentedAtNetworkError && delegate.dismissals == 0 &&
        owner.session == nil && failing.loadTimer == nil);

    StashCardSession *loaded = StashLoadingSession(owner);
    loaded.loaded = YES;
    calls = 0;
    [loaded webView:loaded.webView decidePolicyForNavigationResponse:(id)StashNavigationResponse(404, YES) decisionHandler:decide];
    result[@"errorAfterLoadAllows"] = @(calls == 1 && policy == WKNavigationResponsePolicyAllow &&
        owner.session == loaded && delegate.networkErrors == 1);

    loaded.loaded = NO;
    calls = 0;
    [loaded webView:loaded.webView decidePolicyForNavigationResponse:(id)StashNavigationResponse(404, NO) decisionHandler:decide];
    result[@"subframeErrorBeforeLoadAllows"] = @(calls == 1 && policy == WKNavigationResponsePolicyAllow &&
        owner.session == loaded && delegate.networkErrors == 1);

    [loaded beginLoadBudget];
    BOOL armed = loaded.loadTimer != nil && !loaded.receivedResponse;
    calls = 0;
    [loaded webView:loaded.webView decidePolicyForNavigationResponse:(id)StashNavigationResponse(302, YES) decisionHandler:decide];
    BOOL redirectKeepsBudget = calls == 1 && policy == WKNavigationResponsePolicyAllow && loaded.loadTimer != nil && !loaded.receivedResponse;
    calls = 0;
    [loaded webView:loaded.webView decidePolicyForNavigationResponse:(id)StashNavigationResponse(200, YES) decisionHandler:decide];
    result[@"successResponseStopsBudget"] = @(armed && redirectKeepsBudget && calls == 1 &&
        policy == WKNavigationResponsePolicyAllow && loaded.receivedResponse && loaded.loadTimer == nil);

    [loaded finishWithUserDismiss:NO completion:nil];
    calls = 0;
    [loaded webView:loaded.webView decidePolicyForNavigationResponse:(id)StashNavigationResponse(200, YES) decisionHandler:decide];
    result[@"inactiveSessionCancels"] = @(calls == 1 && policy == WKNavigationResponsePolicyCancel && delegate.dismissals == 0);
    owner.session = nil;
    return result;
}

NSDictionary *StashLoadBudgetProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    StashNative *owner = [StashNative new];
    StashNavigationProbeDelegate *delegate = StashNavigationDelegate(owner);

    StashCardSession *session = StashLoadingSession(owner);
    StashReadinessWebView *web = (id)session.webView;
    [session beginLoadBudget];
    BOOL armed = session.loadTimer != nil && web.requests == 0 && !session.retriedLoad && !session.receivedResponse;
    session.foregroundLoadElapsed = 9.5;
    [session updateLoadBudget];
    result[@"belowRetryThresholdWaits"] = @(armed && web.requests == 0 && !session.retriedLoad && owner.session == session);
    session.foregroundLoadElapsed = 10;
    [session updateLoadBudget];
    result[@"retriesAtTenSeconds"] = @(web.requests == 1 && session.retriedLoad && owner.session == session &&
        delegate.networkErrors == 0);
    session.foregroundLoadElapsed = 14.5;
    [session updateLoadBudget];
    result[@"retriesOnlyOnce"] = @(web.requests == 1 && owner.session == session && delegate.networkErrors == 0);
    session.foregroundLoadElapsed = 15;
    [session updateLoadBudget];
    result[@"failsAtFifteenSeconds"] = @(owner.session == nil && delegate.networkErrors == 1 &&
        !delegate.presentedAtNetworkError && delegate.dismissals == 0 && session.loadTimer == nil && web.requests == 1);

    StashCardSession *responded = StashLoadingSession(owner);
    StashReadinessWebView *respondedWeb = (id)responded.webView;
    [responded beginLoadBudget];
    responded.receivedResponse = YES;
    responded.foregroundLoadElapsed = 20;
    [responded updateLoadBudget];
    result[@"responseSuppressesRetryAndDeadline"] = @(respondedWeb.requests == 0 && !responded.retriedLoad &&
        owner.session == responded && delegate.networkErrors == 1);
    [responded finishWithUserDismiss:NO completion:nil];

    StashCardSession *finished = StashLoadingSession(owner);
    StashReadinessWebView *finishedWeb = (id)finished.webView;
    [finished beginLoadBudget];
    finished.loaded = YES;
    finished.foregroundLoadElapsed = 20;
    [finished updateLoadBudget];
    result[@"loadedPageSuppressesBudget"] = @(finishedWeb.requests == 0 && owner.session == finished && delegate.networkErrors == 1);
    [finished finishWithUserDismiss:NO completion:nil];
    owner.session = nil;
    return result;
}

NSDictionary *StashNewWindowProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    StashExternalOpenRecorder *opens = [StashExternalOpenRecorder new];
    [opens install];
    StashNative *owner = [StashNative new];
    StashNavigationProbeDelegate *delegate = StashNavigationDelegate(owner);
    StashCardSession *session = StashLoadingSession(owner);
    session.config.autoClose = NO;
    session.loaded = YES;
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    WKWebView *(^open)(NSString *) = ^WKWebView *(NSString *url) {
        return [session webView:session.webView createWebViewWithConfiguration:configuration
            forNavigationAction:(id)StashNavigationAction(url, WKNavigationTypeOther, YES) windowFeatures:nil];
    };
    WKWebView *blank = open(@"about:blank");
    result[@"blankWindowIgnored"] = @(blank == nil && opens.urls.count == 0 && delegate.successes == 0 && delegate.failures == 0);
    WKWebView *routed = open(@"stashdemo://stash-pay/failure");
    result[@"resultWindowRoutedToPayment"] = @(routed == nil && opens.urls.count == 0 && delegate.failures == 1 &&
        owner.isCurrentlyPresented);
    WKWebView *external = open(@"https://merchant.example/help");
    result[@"otherWindowOpensExternally"] = @(external == nil && opens.urls.count == 1 &&
        [opens.lastURL isEqualToString:@"https://merchant.example/help"] && opens.options.firstObject.count == 0 &&
        owner.isCurrentlyPresented);
    [session finishWithUserDismiss:NO completion:nil];
    WKWebView *late = open(@"https://merchant.example/late");
    result[@"inactiveWindowIgnored"] = @(late == nil && opens.urls.count == 1 && delegate.dismissals == 0);
    StashSetExternalURLOpener(nil);
    owner.session = nil;
    return result;
}

@interface StashDialogProbeController : StashCardViewController
@property (nonatomic, strong) UIViewController *occupant;
@property (nonatomic, strong) NSMutableArray<UIViewController *> *presented;
@end
@implementation StashDialogProbeController
- (UIViewController *)presentedViewController { return self.occupant ?: self.presented.lastObject; }
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    [self.presented addObject:controller];
    if (completion) completion();
}
@end

static StashCardSession *StashDialogSession(StashNative *owner, StashDialogProbeController **controllerOut) {
    StashCardSession *session = [StashCardSession new];
    owner.session = session; session.owner = owner;
    session.config = [StashNativeCardConfig new];
    session.url = @"https://checkout.invalid";
    session.loaded = YES;
    session.webView = [StashReadinessWebView new];
    StashDialogProbeController *controller = [StashDialogProbeController new];
    controller.presented = [NSMutableArray array];
    controller.session = session; session.controller = controller;
    if (controllerOut) *controllerOut = controller;
    return session;
}

NSDictionary *StashJavaScriptDialogProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    StashNative *owner = [StashNative new];
    StashNavigationProbeDelegate *delegate = StashNavigationDelegate(owner);
    __block NSInteger alerts = 0, confirms = 0, prompts = 0;
    __block BOOL confirmValue = YES;
    __block NSString *promptValue = @"unset";
    void (^alertDone)(void) = ^{ alerts++; };
    void (^confirmDone)(BOOL) = ^(BOOL value) { confirms++; confirmValue = value; };
    void (^promptDone)(NSString *) = ^(NSString *value) { prompts++; promptValue = value; };

    // A dialog already on screen: every completion runs immediately, exactly once, with the dismissive value.
    StashDialogProbeController *occupied = nil;
    StashCardSession *busy = StashDialogSession(owner, &occupied);
    occupied.occupant = [UIViewController new];
    [busy webView:busy.webView runJavaScriptAlertPanelWithMessage:@"a" initiatedByFrame:nil completionHandler:alertDone];
    [busy webView:busy.webView runJavaScriptConfirmPanelWithMessage:@"c" initiatedByFrame:nil completionHandler:confirmDone];
    [busy webView:busy.webView runJavaScriptTextInputPanelWithPrompt:@"p" defaultText:@"d" initiatedByFrame:nil completionHandler:promptDone];
    result[@"occupiedCompletesImmediately"] = @(alerts == 1 && confirms == 1 && !confirmValue && prompts == 1 &&
        promptValue == nil && occupied.presented.count == 0 && busy.dialogCompletion == nil);
    [busy completeDialog:@YES];
    result[@"occupiedHasNoPendingCompletion"] = @(alerts == 1 && confirms == 1 && prompts == 1);
    [busy cleanup]; owner.session = nil;

    // Alert presented: completion waits for the dialog, then runs once even if completed twice.
    alerts = 0;
    StashDialogProbeController *free = nil;
    StashCardSession *open = StashDialogSession(owner, &free);
    [open webView:open.webView runJavaScriptAlertPanelWithMessage:@"a" initiatedByFrame:nil completionHandler:alertDone];
    BOOL presentedAlert = free.presented.count == 1 && [free.presented.firstObject isKindOfClass:UIAlertController.class] &&
        alerts == 0 && open.dialogCompletion != nil;
    [open completeDialog:nil];
    [open completeDialog:nil];
    result[@"alertCompletesOnce"] = @(presentedAlert && alerts == 1 && open.dialogCompletion == nil);
    [open cleanup]; owner.session = nil;

    // Confirm presented, then the checkout finishes: completion runs once with NO; later taps are no-ops.
    confirms = 0; confirmValue = YES;
    StashDialogProbeController *confirming = nil;
    StashCardSession *finishing = StashDialogSession(owner, &confirming);
    [finishing webView:finishing.webView runJavaScriptConfirmPanelWithMessage:@"c" initiatedByFrame:nil completionHandler:confirmDone];
    BOOL presentedConfirm = confirming.presented.count == 1 && confirms == 0;
    [finishing finishWithUserDismiss:NO completion:nil];
    BOOL finishedOnce = confirms == 1 && !confirmValue && owner.session == nil;
    [finishing completeDialog:@YES];
    result[@"confirmCompletesOnceOnFinish"] = @(presentedConfirm && finishedOnce && confirms == 1 && !confirmValue);

    // Prompt presented, then teardown without callbacks: completion runs once with nil.
    prompts = 0; promptValue = @"unset";
    StashDialogProbeController *prompting = nil;
    StashCardSession *tearing = StashDialogSession(owner, &prompting);
    [tearing webView:tearing.webView runJavaScriptTextInputPanelWithPrompt:@"p" defaultText:@"d" initiatedByFrame:nil completionHandler:promptDone];
    BOOL presentedPrompt = prompting.presented.count == 1 && prompts == 0;
    [tearing cleanup];
    BOOL tornOnce = prompts == 1 && promptValue == nil;
    [tearing completeDialog:@"late"];
    result[@"promptCompletesOnceOnCleanup"] = @(presentedPrompt && tornOnce && prompts == 1 && promptValue == nil);
    owner.session = nil;

    // Inactive session: completions run immediately and nothing is presented.
    alerts = 0; confirms = 0; prompts = 0;
    StashDialogProbeController *retired = nil;
    StashCardSession *inactive = StashDialogSession(owner, &retired);
    owner.session = nil;
    [inactive webView:inactive.webView runJavaScriptAlertPanelWithMessage:@"a" initiatedByFrame:nil completionHandler:alertDone];
    [inactive webView:inactive.webView runJavaScriptConfirmPanelWithMessage:@"c" initiatedByFrame:nil completionHandler:confirmDone];
    [inactive webView:inactive.webView runJavaScriptTextInputPanelWithPrompt:@"p" defaultText:nil initiatedByFrame:nil completionHandler:promptDone];
    result[@"inactiveCompletesImmediately"] = @(alerts == 1 && confirms == 1 && prompts == 1 && retired.presented.count == 0 &&
        delegate.dismissals == 0);
    [inactive cleanup];
    return result;
}

NSDictionary *StashPostLoadFailureProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    UIWindow *previous = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) previous = window;
    UIWindow *window = previous.windowScene ? [[UIWindow alloc] initWithWindowScene:previous.windowScene] :
        [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 700)];
    StashLoadingBackgroundHost *host = [StashLoadingBackgroundHost new];
    window.rootViewController = host; [window makeKeyAndVisible];
    StashNative *owner = [StashNative new];
    StashNavigationProbeDelegate *delegate = StashNavigationDelegate(owner);
    StashCardSession *(^present)(void) = ^StashCardSession *{
        StashCardSession *session = [StashCardSession new];
        owner.session = session; session.owner = owner; session.presenter = host;
        session.url = @"about:blank"; session.config = [StashNativeCardConfig new];
        [session presentCheckout]; [session.webView stopLoading];
        session.loaded = YES;
        return session;
    };

    StashCardSession *session = present();
    result[@"presented"] = @(owner.isCurrentlyPresented && session.controller.viewIfLoaded.window == window && session.webView != nil);
    [session handleMessage:@"stashPurchaseProcessing" body:@{}];
    result[@"processingLocked"] = @(session.processing && owner.isPurchaseProcessing && ![session canUserDismiss]);
    [session webView:session.webView didFailNavigation:nil
        withError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
    result[@"networkErrorDelivered"] = @(delegate.networkErrors == 1);
    result[@"cardClosedBeforeCallback"] = @(!delegate.presentedAtNetworkError);
    result[@"noDismissCallback"] = @(delegate.dismissals == 0);
    result[@"notPresented"] = @(!owner.isCurrentlyPresented && session.webView == nil && session.controller == nil &&
        !owner.isPurchaseProcessing);

    StashCardSession *second = present();
    [second webView:second.webView didFailNavigation:nil
        withError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
    result[@"cancelledFailureIgnored"] = @(owner.isCurrentlyPresented && owner.session == second && delegate.networkErrors == 1);
    [second webView:second.webView didFailProvisionalNavigation:nil
        withError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];
    result[@"provisionalFailureAfterLoadFails"] = @(!owner.isCurrentlyPresented && delegate.networkErrors == 2 &&
        !delegate.presentedAtNetworkError && delegate.dismissals == 0);

    StashCardSession *third = present();
    [third handleMessage:@"stashPurchaseProcessing" body:@{}];
    [third webViewWebContentProcessDidTerminate:third.webView];
    result[@"rendererLossWhileProcessingFails"] = @(!owner.isCurrentlyPresented && delegate.networkErrors == 3 &&
        delegate.dismissals == 0);
    window.hidden = YES; [previous makeKeyWindow];
    return result;
}
