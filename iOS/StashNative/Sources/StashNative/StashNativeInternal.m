#import "StashNativePrivate.h"
#import <CoreHaptics/CoreHaptics.h>
#import <math.h>

static void *StashPageBackgroundContext = &StashPageBackgroundContext;
static void *StashRootScrollContext = &StashRootScrollContext;

static BOOL StashTopChromeColor(id channels, UIColor **color) {
    *color = nil;
    if (channels == NSNull.null) return YES;
    if (![channels isKindOfClass:NSArray.class] || [channels count] != 3) return NO;
    for (id channel in channels) {
        if (![channel isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)channel) == CFBooleanGetTypeID() ||
            !isfinite([channel doubleValue]) || [channel doubleValue] < 0 || [channel doubleValue] > 255) return NO;
    }
    *color = [UIColor colorWithRed:[channels[0] doubleValue]/255.0 green:[channels[1] doubleValue]/255.0
        blue:[channels[2] doubleValue]/255.0 alpha:1];
    return YES;
}

static BOOL StashSamePageBackingPaint(UIColor *left, UIColor *right) {
    CGFloat lr, lg, lb, la, rr, rg, rb, ra;
    return [left getRed:&lr green:&lg blue:&lb alpha:&la] &&
        [right getRed:&rr green:&rg blue:&rb alpha:&ra] &&
        fabs(lr - rr) <= 0.000001 && fabs(lg - rg) <= 0.000001 &&
        fabs(lb - rb) <= 0.000001 && fabs(la - ra) <= 0.000001;
}

StashCardSession *StashSessionLeavingSurface(UIViewController *surface) {
    id session = nil;
    if ([surface isKindOfClass:StashCardViewController.class]) session = ((StashCardViewController *)surface).session;
    else if ([surface isKindOfClass:SFSafariViewController.class]) session = ((SFSafariViewController *)surface).delegate;
    return [session isKindOfClass:StashCardSession.class] && [session dismissingSurface] ? session : nil;
}

// Dismisses keepOpen Safari from its card once any transition it is part of has ended.
static void StashDismissOverlay(UIViewController *overlay) {
    id<UIViewControllerTransitionCoordinator> transition = overlay.transitionCoordinator;
    if ((overlay.isBeingPresented || overlay.isBeingDismissed) && transition &&
        [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            dispatch_async(dispatch_get_main_queue(), ^{ StashDismissOverlay(overlay); });
        }]) return;
    UIViewController *card = overlay.presentingViewController;
    if (card.presentedViewController == overlay && !overlay.isBeingDismissed && !card.isBeingDismissed)
        [card dismissViewControllerAnimated:YES completion:nil];
}

@implementation StashCardSession
- (BOOL)isActive { return self.owner.session == self && !self.closing; }
- (BOOL)canUserDismiss { return [self isActive] && self.config.allowDismiss && !self.processing && !self.scanCompleted; }
- (UIViewController *)presentationPresenter { return self.portraitPresentation.presenter ?: self.presenter; }

- (void)presentCheckout {
    if (![self isActive] || self.controller) return;
    if ([self waitForLeavingSurfaceOn:self.presenter then:^{ [self presentCheckout]; }]) return;
    if (!self.presenter.view.window || self.presenter.isBeingDismissed || self.presenter.presentedViewController) {
        [self finishWithUserDismiss:self.openDeferred completion:nil];
        return;
    }
    [self preparePortraitWithCompletion:^{ [self presentCheckoutContent]; }];
}
- (void)preparePortraitWithCompletion:(void (^)(void))completion {
    if (self.portraitPresentation.presenter) { completion(); return; }
    if (self.config.orientationPreference == StashNativeOrientationPreferencePortrait &&
        self.presenter.view.window.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        if (self.portraitPresentation) return;
        StashPortraitPresentation *presentation = [[StashPortraitPresentation alloc] initWithPresenter:self.presenter];
        self.portraitPresentation = presentation;
        // Let an immediate close/reset cancel before creating a window or requesting rotation.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self isActive] || self.portraitPresentation != presentation) return;
            [presentation prepareWithCompletion:^(BOOL ready) {
                if (![self isActive]) return;
                if (!ready) self.portraitPresentation = nil;
                completion();
            }];
        });
#if !__has_feature(objc_arc)
        [presentation release];
#endif
    } else completion();
}
- (void)presentCheckoutContent {
    if (![self isActive] || self.controller) return;
    UIViewController *presenter = self.presentationPresenter;
    // presentCheckout rejected these states synchronously; reaching them here means they changed after the open
    // was accepted, so the presentation still ends with its dismissal.
    if (!presenter.view.window || presenter.isBeingDismissed || presenter.presentedViewController ||
        !self.presenter.viewIfLoaded.window || self.presenter.isBeingDismissed) {
        [self finishWithUserDismiss:YES completion:nil];
        return;
    }
    if (self.scanner) {
        Class contentClass = StashScannerContentClass();
        if (!contentClass) {
            // Same contract as Android's late module check: the unavailable error, without a dismissal.
            StashNative *owner = self.owner;
            [self finishWithUserDismiss:NO completion:^{ [owner deliverScannerUnavailable]; }];
            return;
        }
        UIViewController<StashNativeScannerContent> *scanner = [[contentClass alloc] init];
        scanner.scannerHost = self;
        self.scannerController = scanner;
        self.initialContentRevealed = YES;
        [self presentCardFrom:presenter];
#if !__has_feature(objc_arc)
        [scanner release];
#endif
        return;
    }
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *content = configuration.userContentController;
    for (NSString *name in StashScriptHandlerNames()) [content addScriptMessageHandler:self name:name];
    [content addScriptMessageHandlerWithReply:self contentWorld:WKContentWorld.pageWorld name:@"stashTelemetry"];
    WKUserScript *bridge = [[WKUserScript alloc] initWithSource:StashBridgeScript()
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
    [content addUserScript:bridge];
    WKUserScript *interactionScript = [[WKUserScript alloc] initWithSource:StashNativeInteractionScript()
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
    [content addUserScript:interactionScript];
    [self installTopChromeProbe:content];
    configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;
    configuration.defaultWebpagePreferences.preferredContentMode = WKContentModeMobile;
    configuration.ignoresViewportScaleLimits = NO;
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = YES;
    WKWebView *web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.webView = web;
    web.navigationDelegate = self;
    web.UIDelegate = self;
    web.allowsLinkPreview = NO;
    web.allowsBackForwardNavigationGestures = NO;
    web.backgroundColor = StashSheetBackgroundUIColor(self.presenter.traitCollection);
    web.scrollView.backgroundColor = web.backgroundColor;
    web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    web.scrollView.bounces = NO;
    web.scrollView.bouncesZoom = NO;
    web.scrollView.alwaysBounceHorizontal = NO;
    web.scrollView.directionalLockEnabled = YES;
    web.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    web.scrollView.pinchGestureRecognizer.enabled = NO;
    web.scrollView.showsHorizontalScrollIndicator = NO;
    StashRemoveFormInputAccessoryView(web);
    if (@available(iOS 16.4, *)) web.inspectable = [StashNative isInspectableWebViewsEnabled];
    [self observeRootScroll];
    self.observingPageBackground = YES;
    [web addObserver:self forKeyPath:@"underPageBackgroundColor" options:NSKeyValueObservingOptionNew
        context:StashPageBackgroundContext];
    [self presentCardFrom:presenter];
    self.loadStart = CFAbsoluteTimeGetCurrent();
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(loadActivityChanged:)
        name:UISceneDidActivateNotification object:self.presenter.view.window.windowScene];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(loadActivityChanged:)
        name:UISceneWillDeactivateNotification object:self.presenter.view.window.windowScene];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(loadActivityChanged:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(loadActivityChanged:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [self beginLoadBudget];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:self.url]
        cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:60];
    [web loadRequest:request];
#if !__has_feature(objc_arc)
    [configuration release]; [bridge release]; [interactionScript release]; [web release];
#endif
}
- (void)presentCardFrom:(UIViewController *)presenter {
    StashCardViewController *controller = [[StashCardViewController alloc] init];
    self.controller = controller;
    controller.session = self;
    [controller configurePresentation];
    [presenter.view endEditing:YES];
    [presenter presentViewController:controller animated:YES completion:^{
        if ([self isActive]) [self.controller updatePresentationAnimated:NO];
    }];
#if !__has_feature(objc_arc)
    [controller release];
#endif
}
- (BOOL)scannerSessionIsActive { return [self isActive]; }
- (void)scannerRequestedDismissal {
    if ([self canUserDismiss]) [self finishWithUserDismiss:YES completion:nil];
}
- (void)scannerDidFailWithError:(NSError *)error {
    if (![self isActive]) return;
    [self.owner deliverToDelegate:^(id<StashNativeDelegate> delegate) {
        if ([delegate respondsToSelector:@selector(stashNativeScannerDidEncounterError:)])
            [delegate stashNativeScannerDidEncounterError:error];
    }];
}
- (void)completeScan:(NSString *)content {
    if (![self isActive] || !self.scanner || self.scanCompleted || !content.length) return;
    self.scanCompleted = YES;
    [self.controller updateDismissalPolicy];
    NSString *payload = [content copy];
    StashNative *owner = self.owner;
    void (^finish)(void) = ^{
        [self finishWithUserDismiss:NO completion:^{
            [owner deliverToDelegate:^(id<StashNativeDelegate> delegate) {
                if ([delegate respondsToSelector:@selector(stashNativeDidScanQRCode:)])
                    [delegate stashNativeDidScanQRCode:payload];
            }];
        }];
    };
    if (self.scannerController) [self.scannerController showConnectedWithCompletion:finish];
    else finish();
#if !__has_feature(objc_arc)
    [payload release];
#endif
}
- (void)observeRootScroll {
    UIScrollView *scroll = self.webView.scrollView;
    if (self.observedRootScroll == scroll) return;
    [self stopObservingRootScroll];
    self.observedRootScroll = scroll;
    for (NSString *key in @[@"contentOffset", @"contentSize"])
        [scroll addObserver:self forKeyPath:key options:0 context:StashRootScrollContext];
    [scroll.panGestureRecognizer addTarget:self action:@selector(rootScrollPanChanged:)];
}
- (void)stopObservingRootScroll {
    UIScrollView *scroll = self.observedRootScroll;
    if (!scroll) return;
    for (NSString *key in @[@"contentOffset", @"contentSize"])
        [scroll removeObserver:self forKeyPath:key context:StashRootScrollContext];
    [scroll.panGestureRecognizer removeTarget:self action:@selector(rootScrollPanChanged:)];
    self.observedRootScroll = nil;
    self.rootOffsetRepairPending = NO;
}
- (void)rootScrollPanChanged:(UIPanGestureRecognizer *)gesture {
    [self.controller nativePanChanged:gesture];
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) [self retryRootOffsetRepair];
}
- (void)scheduleRootOffsetRepair {
    if (![self isActive] || self.observedRootScroll != self.webView.scrollView) return;
    self.rootOffsetRepairPending = YES;
    [self retryRootOffsetRepair];
}
- (void)retryRootOffsetRepair {
    if (!self.rootOffsetRepairPending || self.rootOffsetRepairQueued || ![self isActive]) return;
    self.rootOffsetRepairQueued = YES;
    WKWebView *web = self.webView;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self isActive] && self.webView == web && self.observedRootScroll == web.scrollView &&
            [self.controller canNormalizeIdleRootScrollOffset]) {
            // WebKit may apply its native focus scroll after the page's reveal callback.
            [self.controller normalizeIdleRootScrollOffset];
            self.rootOffsetRepairPending = NO;
        }
        self.rootOffsetRepairQueued = NO;
    });
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == StashRootScrollContext) {
        if (object == self.observedRootScroll) [self scheduleRootOffsetRepair];
        return;
    }
    if (context == StashPageBackgroundContext) {
        if (object == self.webView && [self isActive]) {
            if (self.applyingPageBacking) return;
            UIColor *background = self.webView.underPageBackgroundColor;
            self.webView.scrollView.backgroundColor = background;
            self.webView.backgroundColor = background ?: StashSheetBackgroundUIColor(self.presenter.traitCollection);
            if (self.controller.isViewLoaded) {
                [self.controller updateTopChromeBackgroundColor];
            }
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
- (void)beginInitialContentNavigation {
    if (self.initialContentRevealed) return;
    self.contentRevealGeneration++;
    self.contentReadinessProbePending = NO;
    self.initialContentFinished = NO;
    self.initialContentHasCommitted = NO;
    [self startInitialContentWait];
}
- (void)initialContentCommitted {
    if (self.initialContentRevealed || ![self isActive]) return;
    self.initialContentHasCommitted = YES;
    [self startInitialContentWait];
}
- (void)startInitialContentWait {
    if (!self.contentRevealTimer) {
        self.contentRevealTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self
            selector:@selector(initialContentTimerFired:) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:self.contentRevealTimer forMode:NSRunLoopCommonModes];
    }
    [self updateInitialContentWait];
}
- (void)initialContentTimerFired:(NSTimer *)timer { [self updateInitialContentWait]; }
- (void)initialContentDidFinish {
    if (self.initialContentRevealed) { [self.controller.spinner stopAnimating]; return; }
    self.initialContentFinished = YES;
    [self initialContentCommitted];
}
- (BOOL)isInitialContentForeground {
    UIWindowScene *scene = self.presenter.view.window.windowScene;
    return scene ? scene.activationState == UISceneActivationStateForegroundActive :
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}
- (void)updateInitialContentWait {
    if (![self isActive] || self.initialContentRevealed || !self.contentRevealTimer) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (![self isInitialContentForeground]) {
        if (self.contentWaitStart > 0) self.contentWaitElapsed += now - self.contentWaitStart;
        self.contentWaitStart = 0;
        return;
    }
    if (self.contentWaitStart == 0) self.contentWaitStart = now;
    if (self.contentWaitElapsed + now - self.contentWaitStart >= 15) {
        [self revealInitialContent];
        return;
    }
    if (!self.initialContentHasCommitted) return;
    if (self.contentReadinessProbePending) return;
    self.contentReadinessProbePending = YES;
    NSUInteger generation = self.contentRevealGeneration;
    WKWebView *web = self.webView;
    BOOL finished = self.initialContentFinished;
    [web callAsyncJavaScript:StashInitialContentReadinessScript() arguments:@{@"finished":@(finished)}
        inFrame:nil inContentWorld:WKContentWorld.defaultClientWorld completionHandler:^(id value, NSError *error) {
            if (![self isActive] || self.webView != web || generation != self.contentRevealGeneration) return;
            self.contentReadinessProbePending = NO;
            if (![self isInitialContentForeground]) return;
            if ([value isKindOfClass:NSNumber.class] && [value boolValue]) [self revealInitialContent];
            else if (error && finished) [self revealInitialContent];
        }];
}
- (void)revealInitialContent {
    if (![self isActive] || self.initialContentRevealed) return;
    self.initialContentRevealed = YES;
    [self cancelInitialContentReveal];
    [self sampleTopChrome];
    [self.controller revealInitialContentAnimated:!self.keyboardVisible];
}
- (void)cancelInitialContentReveal {
    self.contentRevealGeneration++;
    self.contentReadinessProbePending = NO;
    [self.contentRevealTimer invalidate];
    self.contentRevealTimer = nil;
}
- (void)loadTimedOut:(NSTimer *)timer { [self updateLoadBudget]; }
- (void)beginLoadBudget {
    [self.loadTimer invalidate];
    self.foregroundLoadStart = 0;
    self.foregroundLoadElapsed = 0;
    self.retriedLoad = NO;
    self.receivedResponse = NO;
    self.loadTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(loadTimedOut:)
        userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.loadTimer forMode:NSRunLoopCommonModes];
    [self updateLoadBudget];
}
- (void)loadActivityChanged:(NSNotification *)note {
    if ([note.name isEqualToString:UISceneWillDeactivateNotification] ||
        [note.name isEqualToString:UIApplicationWillResignActiveNotification]) {
        if (self.foregroundLoadStart > 0) self.foregroundLoadElapsed += CFAbsoluteTimeGetCurrent() - self.foregroundLoadStart;
        self.foregroundLoadStart = 0;
        if (self.contentWaitStart > 0) self.contentWaitElapsed += CFAbsoluteTimeGetCurrent() - self.contentWaitStart;
        self.contentWaitStart = 0;
    } else {
        [self updateLoadBudget];
        [self updateInitialContentWait];
    }
}
- (void)updateLoadBudget {
    if (![self isActive] || self.loaded || self.receivedResponse) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    UIWindowScene *scene = self.presenter.view.window.windowScene;
    BOOL active = scene ? scene.activationState == UISceneActivationStateForegroundActive :
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    if (!active) {
        if (self.foregroundLoadStart > 0) self.foregroundLoadElapsed += now - self.foregroundLoadStart;
        self.foregroundLoadStart = 0;
        return;
    }
    if (self.foregroundLoadStart == 0) self.foregroundLoadStart = now;
    NSTimeInterval elapsed = self.foregroundLoadElapsed + now - self.foregroundLoadStart;
    if (elapsed >= 15) { [self networkFailed]; return; }
    if (elapsed >= 10 && !self.retriedLoad) {
        self.retriedLoad = YES;
        [self.webView stopLoading];
        NSURL *url = [NSURL URLWithString:self.url];
        if (url) [self.webView loadRequest:[NSURLRequest requestWithURL:url
            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60]];
    }
}
- (void)presentBrowser {
    [self presentBrowserAfterHandoff:NO];
}
// An open rejected synchronously is ignored. After a handoff, a deferred open, or once preparation has gone
// asynchronous, the host was told a browser is coming, so a failure ends with the browser-closed event.
- (void)presentBrowserAfterHandoff:(BOOL)handoff {
    if (![self isActive] || self.browser) return;
    if (!handoff && [self waitForLeavingSurfaceOn:self.presenter then:^{ [self presentBrowserAfterHandoff:NO]; }]) return;
    UIViewController *presenter = self.presentationPresenter;
    if (!presenter.viewIfLoaded.window || presenter.isBeingDismissed || presenter.presentedViewController) {
        if (handoff || self.openDeferred) [self browserClosed];
        else [self finishWithUserDismiss:NO completion:nil];
        return;
    }
    StashSafariViewController *browser = [[StashSafariViewController alloc] initWithURL:[NSURL URLWithString:self.url]];
    self.browser = browser;
    browser.delegate = self;
    [self preparePortraitWithCompletion:^{
        if (![self isActive] || self.browser != browser) return;
        UIViewController *readyPresenter = self.presentationPresenter;
        if (!readyPresenter.viewIfLoaded.window || readyPresenter.isBeingDismissed ||
            readyPresenter.presentedViewController || !self.presenter.viewIfLoaded.window || self.presenter.isBeingDismissed) {
            [self browserClosed];
            return;
        }
        browser.prefersPortrait = self.portraitPresentation.presenter != nil;
        [readyPresenter presentViewController:browser animated:YES completion:^{
            if ([self isActive] && self.browser == browser && self.portraitPresentation)
                browser.presentationController.delegate = self;
        }];
    }];
#if !__has_feature(objc_arc)
    [browser release];
#endif
}
// A reset or released card can still be in its entrance animation. An open from the same presenter waits for
// it to leave instead of presenting from the card that is about to be dismissed.
- (BOOL)waitForLeavingSurfaceOn:(UIViewController *)presenter then:(void (^)(void))open {
    StashCardSession *leaving = StashSessionLeavingSurface(presenter.presentedViewController);
    if (!leaving || leaving == self) return NO;
    if (!leaving.surfaceDismissalWaiters) leaving.surfaceDismissalWaiters = [NSMutableArray array];
    void (^waiter)(void) = [open copy];
    [leaving.surfaceDismissalWaiters addObject:waiter];
#if !__has_feature(objc_arc)
    [waiter release];
#endif
    self.openDeferred = YES;
    return YES;
}
- (void)dismissPresentedSurfaceAnimated:(BOOL)animated completion:(void (^)(void))completion {
    UIViewController *surface = self.browser ?: self.controller;
    // keepOpen Safari leaves with its card.
    if (surface && surface == self.controller) [self detachOverlayBrowser];
    // UIKit ignores a dismissal while the surface, or anything it presents, is mid-transition.
    for (UIViewController *top = surface; top; top = top.presentedViewController) {
        id<UIViewControllerTransitionCoordinator> transition = top.transitionCoordinator;
        if (!(top.isBeingPresented || top.isBeingDismissed) || !transition) continue;
        self.dismissingSurface = YES;
        BOOL waiting = [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self dismissPresentedSurfaceAnimated:animated completion:completion];
            });
        }];
        if (waiting) return;
    }
    UIViewController *presenting = surface.presentingViewController;
    if (!presenting) { [self surfaceDismissed:completion]; return; }
    self.dismissingSurface = YES;
    void (^dismissed)(void) = ^{ [self surfaceDismissed:completion]; };
    // Sent to a surface that presents keepOpen Safari or a page dialog, UIKit dismisses only that child and
    // leaves the surface on screen; its presenter removes the whole stack.
    if (surface.presentedViewController && presenting.presentedViewController == surface)
        [presenting dismissViewControllerAnimated:animated completion:dismissed];
    else [surface dismissViewControllerAnimated:animated completion:dismissed];
}
- (void)surfaceDismissed:(void (^)(void))completion {
    self.dismissingSurface = NO;
    NSArray *waiters = self.surfaceDismissalWaiters;
#if !__has_feature(objc_arc)
    [[waiters retain] autorelease];
#endif
    self.surfaceDismissalWaiters = nil;
    if (completion) completion();
    for (void (^waiter)(void) in waiters) waiter();
}
- (void)finishWithUserDismiss:(BOOL)userDismiss completion:(void (^)(void))completion {
    if (![self isActive]) return;
#if !__has_feature(objc_arc)
    [self retain];
#endif
    self.closing = YES;
    BOOL scan = self.scanner;
    [self.scannerController stopScanning];
    [self cancelInitialContentReveal];
    [self.controller.spinner stopAnimating];
    [self completeDialog:nil];
    [self.loadTimer invalidate];
    self.loadTimer = nil;
    [self.webView stopLoading];
    void (^finished)(void) = ^{
        StashNative *owner = self.owner;
        BOOL owned = owner.session == self;
        [self cleanup];
        if (owned) owner.session = nil;
        if (owned && userDismiss) {
            [owner deliverToDelegate:^(id<StashNativeDelegate> delegate) {
                if (scan) {
                    if ([delegate respondsToSelector:@selector(stashNativeDidDismissScanner)])
                        [delegate stashNativeDidDismissScanner];
                } else if ([delegate respondsToSelector:@selector(stashNativeDidDismissCard)]) {
                    [delegate stashNativeDidDismissCard];
                }
            }];
        }
        if (owned && completion) completion();
#if !__has_feature(objc_arc)
        [self release];
#endif
    };
    [self dismissPresentedSurfaceAnimated:YES completion:^{
        if (self.portraitPresentation) [self.portraitPresentation restoreWithCompletion:finished];
        else finished();
    }];
}
- (void)cleanupCheckout {
    [self.scannerController dispose];
    self.scannerController.scannerHost = nil;
    self.scannerController = nil;
    [self stopObservingRootScroll];
    [self invalidateTopChrome];
    [self.webView evaluateJavaScript:@"window.__stashTopEdgeProbe&&window.__stashTopEdgeProbe.stop()"
        inFrame:nil inContentWorld:StashTopChromeWorld() completionHandler:nil];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:StashTopChromeHandlerName
        contentWorld:StashTopChromeWorld()];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self completeDialog:nil];
    [self.loadTimer invalidate];
    self.loadTimer = nil;
    [self cancelInitialContentReveal];
    [self.controller revealInitialContentAnimated:NO];
    if (self.observingPageBackground) {
        [self.webView removeObserver:self forKeyPath:@"underPageBackgroundColor" context:StashPageBackgroundContext];
        self.observingPageBackground = NO;
    }
    self.webView.navigationDelegate = nil;
    self.webView.UIDelegate = nil;
    [self.webView stopLoading];
    for (NSString *name in StashScriptHandlerNames()) {
        [self.webView.configuration.userContentController removeScriptMessageHandlerForName:name];
    }
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"stashTelemetry"
        contentWorld:WKContentWorld.pageWorld];
    self.telemetryNavigation = nil;
    self.telemetryFirstCallAt = nil;
    self.telemetryPageLoadStartedAt = nil;
    self.telemetryPageLoadedAt = nil;
    self.telemetryPageLoadTimeMs = nil;
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
    if (@available(iOS 18.0, *)) ((UIUpdateLink *)self.controller.geometryUpdateLink).enabled = NO;
#endif
    self.controller.geometryUpdateLink = nil;
    [self.controller stopNativeEntrance];
    self.controller.session = nil;
    self.controller = nil;
    self.webView = nil;
    self.processing = NO;
}
- (void)cleanup {
    [self cleanupCheckout];
    [self detachOverlayBrowser];
    [self.hapticEngine stopWithCompletionHandler:nil];
    self.hapticEngine = nil;
    self.browser.delegate = nil;
    self.browser = nil;
    self.browserHandoff = NO;
    [self.portraitPresentation restoreWithCompletion:nil];
    self.portraitPresentation = nil;
}
- (void)retire {
    self.owner = nil;
    if (self.closing) return;
    self.closing = YES;
    [self dismissPresentedSurfaceAnimated:NO completion:^{
        [self cleanup];
    }];
}
- (void)handoffToBrowserWithURL:(NSString *)url {
    if (![self isActive] || self.browserHandoff) return;
#if !__has_feature(objc_arc)
    [[self retain] autorelease];
#endif
    StashNative *owner = self.owner;
    [owner deliverToDelegate:^(id<StashNativeDelegate> delegate) {
        if ([delegate respondsToSelector:@selector(stashNativeDidRequestExternalPaymentWithURL:)])
            [delegate stashNativeDidRequestExternalPaymentWithURL:url];
    }];
    if (![self isActive]) return;
    self.browserHandoff = YES;
    self.webView.navigationDelegate = nil;
    self.webView.UIDelegate = nil;
    [self.webView stopLoading];
    [self cancelInitialContentReveal];
    [self.loadTimer invalidate]; self.loadTimer = nil;
    [self completeDialog:nil];
    [self dismissPresentedSurfaceAnimated:YES completion:^{
        if (![self isActive] || !self.browserHandoff) return;
        [self cleanupCheckout];
        self.config = StashNormalizedConfig(nil);
        self.url = url;
        self.browserHandoff = NO;
        [self presentBrowserAfterHandoff:YES];
    }];
}
- (void)openBrowserOverCardWithURL:(NSString *)url {
    if (![self isActive] || self.overlayBrowser) return;
#if !__has_feature(objc_arc)
    [[self retain] autorelease];
#endif
    StashNative *owner = self.owner;
    [owner deliverToDelegate:^(id<StashNativeDelegate> delegate) {
        if ([delegate respondsToSelector:@selector(stashNativeDidRequestExternalPaymentWithURL:)])
            [delegate stashNativeDidRequestExternalPaymentWithURL:url];
    }];
    UIViewController *card = self.controller;
    NSURL *target = [NSURL URLWithString:url];
    if (![self isActive] || !target || !card.viewIfLoaded.window || card.isBeingDismissed ||
        card.presentedViewController) return;
    StashSafariViewController *browser = [[StashSafariViewController alloc] initWithURL:target];
    browser.delegate = self;
    browser.prefersPortrait = self.portraitPresentation.presenter != nil;
    self.overlayBrowser = browser;
    [card presentViewController:browser animated:YES completion:nil];
#if !__has_feature(objc_arc)
    [browser release];
#endif
}
- (void)detachOverlayBrowser {
    self.overlayBrowser.delegate = nil;
    self.overlayBrowser = nil;
}
- (void)closeOverlayBrowser {
    SFSafariViewController *overlay = self.overlayBrowser;
    if (!overlay) return;
#if !__has_feature(objc_arc)
    [[overlay retain] autorelease];
#endif
    [self detachOverlayBrowser];
    StashDismissOverlay(overlay);
}
- (void)playLongHaptic {
    if (![self playContinuousHaptic]) {
        // Without Core Haptics, the error notification is the longest system pattern.
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeError];
#if !__has_feature(objc_arc)
        [feedback release];
#endif
    }
}
- (BOOL)playContinuousHaptic {
    if (!CHHapticEngine.capabilitiesForHardware.supportsHaptics) return NO;
    NSError *error = nil;
    CHHapticEngine *engine = self.hapticEngine;
    if (!engine) {
        engine = [[CHHapticEngine alloc] initAndReturnError:&error];
        if (!engine) return NO;
        self.hapticEngine = engine;
#if !__has_feature(objc_arc)
        [engine release];
#endif
    }
    NSDictionary *definition = @{CHHapticPatternKeyPattern:@[@{CHHapticPatternKeyEvent:@{
        CHHapticPatternKeyEventType:CHHapticEventTypeHapticContinuous, CHHapticPatternKeyTime:@0,
        CHHapticPatternKeyEventDuration:@0.4, CHHapticPatternKeyEventParameters:@[
            @{CHHapticPatternKeyParameterID:CHHapticEventParameterIDHapticIntensity, CHHapticPatternKeyParameterValue:@0.8},
            @{CHHapticPatternKeyParameterID:CHHapticEventParameterIDHapticSharpness, CHHapticPatternKeyParameterValue:@0.4}]}}]};
    CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithDictionary:definition error:&error];
    id<CHHapticPatternPlayer> player = pattern ? [engine createPlayerWithPattern:pattern error:&error] : nil;
#if !__has_feature(objc_arc)
    [pattern release];
#endif
    if (!player || ![engine startAndReturnError:&error] || ![player startAtTime:CHHapticTimeImmediate error:&error]) return NO;
    [engine notifyWhenPlayersFinished:^CHHapticEngineFinishedAction(NSError *finishError) {
        return CHHapticEngineFinishedActionStopEngine;
    }];
    return YES;
}
- (void)paymentSucceeded:(BOOL)success order:(NSString *)order {
    if (![self isActive] || (self.config.autoClose && self.paymentHandled)) return;
#if !__has_feature(objc_arc)
    [[self retain] autorelease];
#endif
    if (self.config.autoClose) self.paymentHandled = YES;
    self.processing = NO;
    [self.controller updateDismissalPolicy];
    StashNative *owner = self.owner;
    NSString *payload = order.length ? [order copy] : nil;
    void (^deliver)(void) = ^{
        [owner deliverToDelegate:^(id<StashNativeDelegate> delegate) {
            if (success && [delegate respondsToSelector:@selector(stashNativeDidCompletePaymentWithOrder:)])
                [delegate stashNativeDidCompletePaymentWithOrder:payload];
            else if (!success && [delegate respondsToSelector:@selector(stashNativeDidFailPayment)])
                [delegate stashNativeDidFailPayment];
        }];
    };
    // A result that closes the card is final: deliver it after teardown so the game can open again.
    if (self.config.autoClose) [self finishWithUserDismiss:NO completion:deliver];
    else deliver();
#if !__has_feature(objc_arc)
    [payload release];
#endif
}
- (void)networkFailed {
    if (![self isActive]) return;
    StashNative *owner = self.owner;
    [self finishWithUserDismiss:NO completion:^{
        [owner deliverToDelegate:^(id<StashNativeDelegate> delegate) {
            if ([delegate respondsToSelector:@selector(stashNativeDidEncounterNetworkError)])
                [delegate stashNativeDidEncounterNetworkError];
        }];
    }];
}
- (void)browserClosed {
    if (![self isActive] || self.browserCloseDelivered) return;
    self.browserCloseDelivered = YES;
    StashNative *owner = self.owner;
    [self finishWithUserDismiss:NO completion:^{
        [owner deliverToDelegate:^(id<StashNativeDelegate> delegate) {
            if ([delegate respondsToSelector:@selector(stashNativeDidDismissBrowser)]) {
                [delegate stashNativeDidDismissBrowser];
            }
        }];
    }];
}
- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
    // Safari over an open card returns to the card without ending the session.
    if (controller == self.overlayBrowser) { [self detachOverlayBrowser]; return; }
    if (controller == self.browser) [self browserClosed];
}
- (void)presentedSurfaceDidDisappear:(UIViewController *)surface {
    if (![self isActive] || self.browserHandoff) return;
    if (surface == self.overlayBrowser) {
        // The host can dismiss keepOpen Safari without Safari's Done callback; the card must be able to open it again.
        BOOL dismissed = surface.isBeingDismissed;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (surface == self.overlayBrowser && (dismissed || !surface.presentingViewController)) [self detachOverlayBrowser];
        });
        return;
    }
    if (surface != self.controller && surface != self.browser) return;
    // Dismissing the host's presenter chain removes the card or Safari without a UIKit delegate callback.
    BOOL dismissed = surface.isBeingDismissed;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self isActive] || self.browserHandoff || (!dismissed && surface.presentingViewController)) return;
        if (surface == self.browser) [self browserClosed];
        else if (surface == self.controller) [self finishWithUserDismiss:YES completion:nil];
    });
}
- (BOOL)presentationControllerShouldDismiss:(UIPresentationController *)presentationController {
    if (presentationController.presentedViewController == self.controller && self.controller.touchBeganInWebContent) return NO;
    return [self canUserDismiss];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    if (![self isActive]) return;
    if (self.browser && presentationController.presentedViewController == self.browser) [self browserClosed];
    else if (!self.browserHandoff && presentationController.presentedViewController == self.controller)
        [self finishWithUserDismiss:YES completion:nil];
}
- (void)sheetPresentationControllerDidChangeSelectedDetentIdentifier:(UISheetPresentationController *)sheet {
    if (!self.keyboardVisible && !self.controller.updatingLayout && !self.controller.singleDetent) {
        self.expanded = [self.controller nativeSelectionIsExpanded];
        self.controller.hasRequestedNativeSelection = YES;
        self.controller.requestedNativeExpanded = self.expanded;
        [self.controller.viewIfLoaded setNeedsLayout];
    }
}
- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    if (![self isActive]) return;
    [self.controller cancelContentExpansion];
    _expanded = expanded;
    self.controller.hasRequestedNativeSelection = NO;
    [self.controller updatePresentationAnimated:animated];
}
- (void)handleMessage:(NSString *)name body:(id)body {
    if (![self isActive] || self.browserHandoff) return;
#if !__has_feature(objc_arc)
    [[self retain] autorelease];
#endif
    if ([name isEqualToString:@"stashNativementSuccess"]) {
        [self paymentSucceeded:YES order:[body isKindOfClass:NSString.class] ? body : nil];
    } else if ([name isEqualToString:@"stashNativementFailure"]) {
        [self paymentSucceeded:NO order:nil];
    } else if ([name isEqualToString:@"stashPurchaseProcessing"] || [name isEqualToString:@"stashProcessingCompleted"]) {
        self.processing = [name isEqualToString:@"stashPurchaseProcessing"];
        if (self.processing) [self.controller cancelContentExpansion];
        [self.controller updateDismissalPolicy];
    } else if ([name isEqualToString:@"stashWindowClose"]) {
        WKWebView *web = self.webView;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self isActive] && !self.processing && !self.scanCompleted &&
                !self.browserHandoff && self.webView == web)
                [self finishWithUserDismiss:YES completion:nil];
        });
    } else if ([name isEqualToString:@"stashExpand"]) {
        [self setExpanded:YES animated:YES];
    } else if ([name isEqualToString:@"stashCollapse"]) {
        [self setExpanded:NO animated:YES];
    } else if ([name isEqualToString:@"stashTriggerHaptic"]) {
        UIWindow *window = self.webView.window;
        BOOL foreground = window.windowScene ? window.windowScene.activationState == UISceneActivationStateForegroundActive :
            UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
        if (!window || window.hidden || self.webView.hidden || !foreground) return;
        if ([body isKindOfClass:NSDictionary.class] && [body[@"type"] isEqual:@"long"]) {
            [self playLongHaptic];
            return;
        }
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
#if !__has_feature(objc_arc)
        [feedback release];
#endif
    } else if ([name isEqualToString:@"stashOpenLink"] || [name isEqualToString:@"stashExternalPayment"]) {
        // externalBrowser sends {url, keepOpen}; older scripts send the URL string.
        id raw = body;
        BOOL keepOpen = NO;
        if ([body isKindOfClass:NSDictionary.class]) {
            raw = body[@"url"];
            id flag = body[@"keepOpen"];
            keepOpen = [flag isKindOfClass:NSNumber.class] && [flag boolValue];
        }
        NSString *url = StashNormalizeExternalPaymentURL(raw);
        if (!url) return;
        if ([name isEqualToString:@"stashOpenLink"]) {
            StashOpenExternalURL([NSURL URLWithString:url], nil, nil);
        } else if (keepOpen) {
            [self openBrowserOverCardWithURL:StashAppendThemeQueryParameter(url, self.presenter.traitCollection)];
        } else {
            [self handoffToBrowserWithURL:StashAppendThemeQueryParameter(url, self.presenter.traitCollection)];
        }
    }
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (message.webView != self.webView || !message.frameInfo.isMainFrame) return;
    if ([message.name isEqualToString:StashTopChromeHandlerName]) { [self acceptTopChromeMessage:message]; return; }
    [self handleMessage:message.name body:message.body];
}
- (void)installTopChromeProbe:(WKUserContentController *)content {
    [content addScriptMessageHandler:self contentWorld:StashTopChromeWorld() name:StashTopChromeHandlerName];
    WKUserScript *paintScript = [[WKUserScript alloc] initWithSource:StashTopChromeScript()
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES inContentWorld:StashTopChromeWorld()];
    [content addUserScript:paintScript];
#if !__has_feature(objc_arc)
    [paintScript release];
#endif
}
- (void)invalidateTopChrome {
    self.topChromeGeneration++;
    self.topChromeToken = nil;
    self.topChromeDocumentID = nil;
    self.topChromeNavigation = nil;
    self.controller.topChromeColor = nil;
    [self applyInferredPageBackingColor:nil];
    [self.controller updateTopChromeBackgroundColor];
}
- (void)activateTopChrome {
    if (![self isActive] || !self.webView) return;
    WKWebView *web = self.webView;
    NSUInteger generation = self.topChromeGeneration;
    NSString *token = NSUUID.UUID.UUIDString;
    self.topChromeToken = token;
    self.topChromeDocumentID = nil;
    NSString *script = [NSString stringWithFormat:@"window.__stashTopEdgeProbe&&window.__stashTopEdgeProbe.activate(%lu,'%@')",
        (unsigned long)generation, token];
    [web evaluateJavaScript:script inFrame:nil inContentWorld:StashTopChromeWorld()
        completionHandler:^(id document, NSError *error) {
            if (![self isActive] || self.webView != web || self.topChromeGeneration != generation ||
                ![self.topChromeToken isEqualToString:token] || error || ![document isKindOfClass:NSString.class] || ![document length]) return;
            self.topChromeDocumentID = document;
            // Activation can post before this reply. Force a sample after binding its document.
            [self sampleTopChrome];
        }];
}
- (void)sampleTopChrome {
    if (![self isActive] || !self.topChromeDocumentID.length) return;
    [self.webView evaluateJavaScript:@"window.__stashTopEdgeProbe&&window.__stashTopEdgeProbe.sample()"
        inFrame:nil inContentWorld:StashTopChromeWorld() completionHandler:nil];
}
- (void)acceptTopChromeMessage:(WKScriptMessage *)message {
    if (![self isActive] || message.webView != self.webView || !message.frameInfo.isMainFrame ||
        ![message.world isEqual:StashTopChromeWorld()] || ![message.body isKindOfClass:NSDictionary.class]) return;
    NSDictionary *body = message.body;
    id generation = body[@"generation"];
    if (![generation isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)generation) == CFBooleanGetTypeID() ||
        !isfinite([generation doubleValue]) || [generation doubleValue] != (double)self.topChromeGeneration ||
        !self.topChromeToken.length || ![body[@"token"] isEqual:self.topChromeToken] ||
        !self.topChromeDocumentID.length || ![body[@"documentId"] isEqual:self.topChromeDocumentID]) return;
    UIColor *color = nil, *backing = nil;
    if (!StashTopChromeColor(body[@"color"], &color) ||
        !StashTopChromeColor(body[@"backingColor"] ?: NSNull.null, &backing)) return;
    self.controller.topChromeColor = color;
    [self applyInferredPageBackingColor:color ? backing : nil];
    [self.controller updateTopChromeBackgroundColor];
}
- (void)applyInferredPageBackingColor:(UIColor *)color {
    if (!self.webView || self.applyingPageBacking) return;
    WKWebView *web = self.webView;
    self.applyingPageBacking = YES;
    if (color) {
        BOOL needsWrite = !self.inferredPageBackingApplied || !StashSamePageBackingPaint(web.underPageBackgroundColor, color);
        self.inferredPageBackingApplied = YES;
        if (needsWrite) web.underPageBackgroundColor = color;
    } else if (self.inferredPageBackingApplied) {
        self.inferredPageBackingApplied = NO;
        // Transparent pages fall back to WK's view background after clearing the override.
        web.backgroundColor = StashSheetBackgroundUIColor(self.presenter.traitCollection);
        web.underPageBackgroundColor = nil;
    }
    UIColor *background = web.underPageBackgroundColor ?: StashSheetBackgroundUIColor(self.presenter.traitCollection);
    web.backgroundColor = background;
    web.scrollView.backgroundColor = background;
    self.applyingPageBacking = NO;
}
- (void)completeDialog:(id)result {
    void (^completion)(id) = self.dialogCompletion;
#if !__has_feature(objc_arc)
    completion = [completion copy];
#endif
    self.dialogCompletion = nil;
    if (completion) completion(result);
#if !__has_feature(objc_arc)
    [completion release];
#endif
}
- (void)dealloc {
    [self cleanup];
#if !__has_feature(objc_arc)
    [_config release]; [_scannerConfig release]; [_url release]; [_surfaceDismissalWaiters release];
    [super dealloc];
#endif
}
@end
