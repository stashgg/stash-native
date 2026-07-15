//
//  StashNativeCardInternal.m
//  StashNative
//
//  Card interaction engine: gestures, expand/collapse animation, keyboard handling,
//  WKScriptMessage dispatch, dismiss/cleanup, and iPhone card window relayout
//  (incl. force-portrait settle machinery). Shared state is defined in
//  StashNativeCard.m; extern'd via StashNativeCardPrivate.h.
//

#import "StashNativeCard.h"
#import "StashNativeCardPrivate.h"
#import <SafariServices/SafariServices.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

// Non-ARC compatibility: These warnings are suppressed when compiling without ARC
// (e.g., in game engines like Unreal Engine that manage memory manually).
// ARC builds do not need these suppressions.
#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

#ifdef DEBUG
#define STASH_DEBUG_LOG(...) NSLog(__VA_ARGS__)
#else
#define STASH_DEBUG_LOG(...)
#endif

#pragma mark - Animation / Gesture Constants

static const CGFloat kSpringDampingTight = 0.82f;
static const CGFloat kAnimationDurationFast = 0.5f;
static const CGFloat kCornerRadiusExpanded = 24.0f;
static const CGFloat kHandleBarCornerRadius = 3.0f;
static const CGFloat kDismissCardAlpha = 0.0f;
static const CGFloat kDismissCardScale = 0.9f;
static const CGFloat kIPhoneLandscapeExpandedHeightRatio = 0.9f;  /* Expand = 90% screen height in landscape */
static const CGFloat kSpringDampingSnapBack = 0.82f;
static const NSTimeInterval kSnapBackAnimationDuration = 0.45;
/// Ease-out-back constant for display-link expand/collapse.
static const CGFloat kEaseOutBackOvershoot = 1.70158f;
/// Stronger overshoot for snap-back when dismiss gesture does not hit threshold (smooth spring back).
static const CGFloat kEaseOutBackSnapBackOvershoot = 2.4f;

static inline CGFloat easeOutBackWithOvershoot(CGFloat t, CGFloat overshoot) {
    if (t <= 0.0f) return 0.0f;
    if (t >= 1.0f) return 1.0f;
    CGFloat k = overshoot;
    CGFloat u = t - 1.0f;
    return 1.0f + (k + 1.0f) * u * u * u + k * u * u;
}
/// Poll interval while waiting for scene portrait geometry after opening force-portrait card from landscape.
static const NSTimeInterval kPortraitSettlePollInterval = 0.016;
/// Max time to wait for portrait before laying out the card (then fall back to in-landscape portrait strip).
static const NSTimeInterval kPortraitSettleTimeout = 1.0;
/// Elapsed time from settle start at which we retry `requestGeometryUpdate` (iOS 16+), if still landscape.
static const NSTimeInterval kPortraitSettleGeometryRetryFirst = 0.40;
static const NSTimeInterval kPortraitSettleGeometryRetrySecond = 0.70;
static const CGFloat kSpringVelocityCollapse = 0.3f;
static const CGFloat kProgressFullyExpanded = 1.0f;
static const CGFloat kProgressFullyCollapsed = 0.0f;
static const CGFloat kProgressCornerRadiusExpandThreshold = 0.9f;
static const CGFloat kProgressCornerRadiusMidThreshold = 0.5f;
static const CGFloat kExpandDragThresholdRatio = 0.15f;
static const CGFloat kCollapseDragThresholdRatio = 0.25f;
static const CGFloat kDismissDragThresholdRatio = 0.4f;
static const CGFloat kExpandVelocityThreshold = -300.0f;
static const CGFloat kCollapseVelocityThreshold = 300.0f;
static const CGFloat kDragDismissTravelRatioForProgress = 0.1f;
static const CGFloat kDismissDistanceFromBottomThreshold = 10.0f;
static const CGFloat kDismissTravelRatioThresholdIPad = 0.325f;
static const CGFloat kDismissVelocityThresholdIPad = 1040.0f;
static const NSTimeInterval kExpandAnimationDuration = 0.45;
static const NSTimeInterval kCollapseAnimationDurationDefault = 0.45;
static const NSTimeInterval kCollapseAnimationDurationFast = 0.45;
static const NSTimeInterval kDismissAnimationDurationFast = 0.35;
static const NSTimeInterval kDismissAnimationDurationNormal = 0.45;
static const CGFloat kVelocityDivisorForSpring = 1000.0f;
static const CGFloat kVelocityThresholdForFastCollapse = 600.0f;
static const CGFloat kVelocityThresholdForFastDismiss = 1000.0f;

NSUInteger StashNativeCurrentPresentationSessionToken(void) {
    return [StashNativeCardInternal sharedInstance].presentationSessionToken;
}

@implementation StashNativeCardInternal

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(stashApplicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)stashApplicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    WebViewLoadDelegate *del = self.activeWebViewLoadDelegate;
    if (del) {
        [del recoverStaleLoadAfterApplicationForegroundIfNeeded];
    }
}

+ (instancetype)sharedInstance {
    static StashNativeCardInternal *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[StashNativeCardInternal alloc] init];
    });
    return sharedInstance;
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer.view isEqual:self.dragTrayView] || [otherGestureRecognizer.view isEqual:self.dragTrayView]) {
        return NO;
    }
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    // iPad: only allow drag-down (dismiss). Block upward drags.
    if (isRunningOniPad() && [gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        UIPanGestureRecognizer *panGesture = (UIPanGestureRecognizer *)gestureRecognizer;
        if ([panGesture.view isEqual:self.dragTrayView]) {
            UIView *referenceView = self.portraitWindow ? self.portraitWindow : panGesture.view.superview;
            CGPoint translation = [panGesture translationInView:referenceView];
            CGPoint velocity = [panGesture velocityInView:referenceView];
            if (translation.y < 0 || velocity.y < 0) {
                return NO;
            }
        }
    }
    return YES;
}

- (void)callDelegateCallbackOnce {
    if (!_callbackWasCalled) {
        _callbackWasCalled = YES;
        _isCardCurrentlyPresented = NO;
        
        id<StashNativeCardDelegate> delegate = [StashNativeCard sharedInstance].delegate;
        if (delegate && [delegate respondsToSelector:@selector(stashNativeCardDidDismiss)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate stashNativeCardDidDismiss];
            });
        }
    }
}

- (UIView *)cardViewForCurrentPresentation {
    if (!self.currentPresentedVC) return nil;
    if (isRunningOniPad()) {
        return [self.currentPresentedVC.view viewWithTag:kCardViewTag];
    }
    UIView *cardView = self.portraitWindow ? [self.portraitWindow viewWithTag:kCardViewTag] : [self.currentPresentedVC.view viewWithTag:kCardViewTag];
    return cardView ?: self.currentPresentedVC.view;
}

- (void)updateDragTrayVisibilityForPurchaseProcessing:(BOOL)isProcessing {
    void (^apply)(void) = ^{
        UIView *cardView = [self cardViewForCurrentPresentation];
        if (!cardView) {
            return;
        }
        UIView *tray = self.dragTrayView;
        if (!tray) {
            tray = [cardView viewWithTag:kDragTrayViewTag];
        }
        if (!tray) {
            return;
        }
        CGFloat targetAlpha = isProcessing ? 0.0 : 1.0;
        [UIView animateWithDuration:kOverlayFadeInDuration
                              delay:0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            tray.alpha = targetAlpha;
        } completion:nil];
        tray.userInteractionEnabled = !isProcessing;
    };
    if ([NSThread isMainThread]) {
        apply();
    } else {
        dispatch_async(dispatch_get_main_queue(), apply);
    }
}

- (BOOL)isIPhoneLandscapeCurrentOrientation {
    if (!self.currentPresentedVC) return NO;
    if (![self.currentPresentedVC isKindOfClass:[IPhoneCardCurrentOrientationViewController class]]) return NO;
    CGRect b = [self referenceScreenBoundsForIPhoneCardLayout];
    return b.size.width > b.size.height;
}

- (void)setSkipLayoutDuringInitialSetup:(BOOL)skip forViewController:(UIViewController *)vc {
    if (vc && [vc respondsToSelector:@selector(setSkipLayoutDuringInitialSetup:)]) {
        [(id)vc setSkipLayoutDuringInitialSetup:skip];
    }
}

- (void)updateCustomFrameIfSupported:(CGRect)frame forViewController:(UIViewController *)vc {
    UIViewController *target = vc ?: self.currentPresentedVC;
    if (target && [target respondsToSelector:@selector(setCustomFrame:)]) {
        [(id)target setCustomFrame:frame];
    }
}

- (void)beginDismissStoppingLoadAndTimers {
    STASH_DEBUG_LOG(@"StashNativeRetryTrace teardown begin tokenBefore=%lu", (unsigned long)self.presentationSessionToken);
    self.presentationSessionToken++;
    self.isDismissingCard = YES;
    if (!self.currentPresentedVC) {
        return;
    }
    WebViewLoadDelegate *activeDelegate = objc_getAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyWebViewDelegate);
    [activeDelegate invalidateAllTimers];
    WKWebView *webView = findWebViewInView(self.currentPresentedVC.view);
    if (!webView && self.portraitWindow) {
        webView = findWebViewInView(self.portraitWindow);
    }
    if (webView) {
        [webView stopLoading];
    }
}

- (void)cleanupCardInstance {
    stashInvalidateRotationResizeArtifacts(self.currentPresentedVC);
    [self unregisterIPhoneCardWindowGeometryObservers];
    [self stopKeyboardObserving];
    
    if (self.collapseDisplayLink) {
        [self.collapseDisplayLink invalidate];
        self.collapseDisplayLink = nil;
        self.collapseCompletion = nil;
    }
    if (self.expandDisplayLink) {
        [self.expandDisplayLink invalidate];
        self.expandDisplayLink = nil;
        self.expandCompletion = nil;
    }
    
    if (self.dragTrayView) {
        [self.dragTrayView removeFromSuperview];
        self.dragTrayView = nil;
    }

    if (self.currentPresentedVC) {
        // If dismiss animation did not run (e.g. network error path), stop timers/load now.
        if (!self.isDismissingCard) {
            [self beginDismissStoppingLoadAndTimers];
        }
        // Cancel all delegate timers before releasing — NSTimer retains its target, so a stale
        // _networkTimeoutTimer would keep the delegate alive and fire handleNetworkError on a
        // future card presentation if the user opens/closes rapidly.
        WebViewLoadDelegate *activeDelegate = objc_getAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyWebViewDelegate);
        [activeDelegate invalidateAllTimers];

        // Clear all associated objects to break retain cycles and allow deallocation
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyWebViewDelegate, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyWebViewUIDelegate, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)StashNativeAssociatedKeyOverlayView, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyLoadingView, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyCardView, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyInitialCardHeight, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // Search the full view hierarchy: covers popup (webView in containerVC.view),
        // iPhone card (webView → cardView → cardWindow), and modal/iPad (webView → cardView → containerVC.view).
        WKWebView *webView = findWebViewInView(self.currentPresentedVC.view);
        if (!webView && self.portraitWindow) {
            webView = findWebViewInView(self.portraitWindow);
        }
        if (webView) {
            [webView stopLoading];
            webView.navigationDelegate = nil;
            webView.UIDelegate = nil;

            [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerPaymentSuccess];
            [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerPaymentFailure];
            [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerPurchaseProcessing];
            [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerProcessingCompleted];
            [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerOptin];
            [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerExpand];
            [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerCollapse];
            [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerWindowClose];
            [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerExternalPayment];
            [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerOpenLink];
            [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerPageReady];
            [webView.configuration.userContentController removeAllUserScripts];

            // Remove immediately — loadHTMLString:@"" would restart the WebContent
            // process and keep the (now-private) process pool alive longer than needed.
            [webView removeFromSuperview];
        }
        
        UIView *overlayView = objc_getAssociatedObject(self.currentPresentedVC, (__bridge const void *)StashNativeAssociatedKeyOverlayView);
        if (overlayView) {
            for (UIView *subview in [overlayView.subviews copy]) {
                [subview removeFromSuperview];
            }
            [overlayView removeFromSuperview];
        }
    }
    
    if (self.portraitWindow) {
        if (self.isHandingOffPortraitWindowToSafari) {
            // External-payment path: Safari is about to be presented from this portrait window.
            // Keep the window and scene in portrait — no rotation animations.
            // Give the window a solid background so nothing shows through during the
            // brief gap between card teardown and Safari sliding up.
            self.portraitWindow.backgroundColor = stash_sheetBackgroundUIColor();
        } else if ([self.portraitWindow.rootViewController
                       isKindOfClass:[SafariPortraitContainerViewController class]]) {
            // Root already swapped to Safari's container: an openBrowser handoff superseded
            // this cleanup (e.g. its dismiss animation was still in flight). The Safari
            // session owns the window now; tearDownSafariPresentationState dismantles it.
        } else {
            if (self.portraitWindow.rootViewController) {
                [self.portraitWindow.rootViewController dismissViewControllerAnimated:NO completion:nil];
            }
            
            self.portraitWindow.hidden = YES;
            self.portraitWindow.rootViewController = nil;
            
            if (self.previousKeyWindow) {
                // Restore scene orientation whenever it was locked during this card session.
                // restorePrePortraitOrientation is a no-op if previousSceneOrientationMask == 0.
                [self restorePrePortraitOrientation];
                [self.previousKeyWindow makeKeyAndVisible];
                self.previousKeyWindow = nil;
            }
            
            self.portraitWindow = nil;
        }
    }
    
    self.currentPresentedVC = nil;
    self.activeWebViewLoadDelegate = nil;
    self.activeWebViewUIDelegate = nil;
    self.isDismissingCard = NO;
    self.isPurchaseProcessing = NO;
    _isCardExpanded = NO;
    _isCardCurrentlyPresented = NO;
    _usePopupPresentation = NO;
    _useModalPresentation = NO;
    _useCustomPopupSize = NO;
    // _callbackWasCalled intentionally NOT reset here; openInCardUI resets it per session
    // so overlapping dismiss completions cannot double-fire didDismiss.
    _paymentSuccessHandled = NO;
    _autoCloseOnPaymentEvent = YES;
    _presentationBackgroundColorHex = nil;
    _cardIsInLandscape = NO;
    _cardSafeAreaTop = 0.0f;
}

- (void)restorePrePortraitOrientation {
    if (self.previousSceneOrientationMask == 0) return;
    UIInterfaceOrientationMask mask = self.previousSceneOrientationMask;
    self.previousSceneOrientationMask = 0;

    // MaskAll means "opened from portrait/neutral -- no forced rotation needed on restore."
    // Requesting MaskAll would unlock all orientations and potentially cause an unwanted rotation
    // from the accelerometer. Instead, just let the window teardown return control to the app.
    if (mask == UIInterfaceOrientationMaskAll) {
        return;
    }

    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene = nil;
        if (self.previousKeyWindow) {
            scene = self.previousKeyWindow.windowScene;
        }
        if (!scene) {
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]] &&
                    s.activationState == UISceneActivationStateForegroundActive) {
                    scene = (UIWindowScene *)s;
                    break;
                }
            }
        }
        if (scene) {
            UIWindowSceneGeometryPreferencesIOS *prefs =
                [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
            [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *e) {
                STASH_DEBUG_LOG(@"StashNative orientation restore failed: %@", e);
            }];
        }
    } else {
        // UIDevice hack only needed for landscape restore; portrait/neutral returns naturally.
        if (mask == UIInterfaceOrientationMaskLandscapeLeft ||
            mask == UIInterfaceOrientationMaskLandscapeRight) {
            UIInterfaceOrientation target =
                (mask == UIInterfaceOrientationMaskLandscapeLeft)
                    ? UIInterfaceOrientationLandscapeLeft
                    : UIInterfaceOrientationLandscapeRight;
            [[UIDevice currentDevice] setValue:@(target) forKey:@"orientation"];
            [UIViewController attemptRotationToDeviceOrientation];
        }
    }
}

- (void)dismissWithAnimation:(void (^)(void))completion {
    if (!self.currentPresentedVC) {
        if (completion) completion();
        return;
    }

    [self beginDismissStoppingLoadAndTimers];

    UIViewController *containerVC = self.currentPresentedVC;
    UIView *overlayView = objc_getAssociatedObject(containerVC, (__bridge const void *)StashNativeAssociatedKeyOverlayView);
    
    [self setSkipLayoutDuringInitialSetup:YES forViewController:containerVC];
    
    CGFloat animationDuration = (_usePopupPresentation || _useModalPresentation) ? kDismissAnimationDurationPopup : kDismissAnimationDurationNormal;
    
    [UIView animateWithDuration:animationDuration delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        if (_useModalPresentation) {
            // Modal: fade out only (no scale to avoid webview shift)
            UIView *cardView = objc_getAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyCardView);
            if (!cardView) cardView = [containerVC.view viewWithTag:kCardViewTag];
            UIView *targetView = cardView ? cardView : containerVC.view;
            targetView.alpha = 0.0;
        } else if (_usePopupPresentation || isRunningOniPad()) {
            // iPad/Popup: fade out and scale the cardView
            UIView *cardView = objc_getAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyCardView);
            if (!cardView) cardView = [containerVC.view viewWithTag:kCardViewTag];
            UIView *targetView = cardView ? cardView : containerVC.view;
            targetView.alpha = kDismissCardAlpha;
            targetView.transform = CGAffineTransformMakeScale(kDismissCardScale, kDismissCardScale);
        } else {
            // iPhone: slide down the cardView
            UIView *cardView = [self cardViewForCurrentPresentation];
            if (cardView) {
                CGRect screenBounds = self.portraitWindow ? self.portraitWindow.bounds : [UIScreen mainScreen].bounds;
                CGFloat dismissY = screenBounds.size.height + cardView.frame.size.height;
                
                CGRect frame = cardView.frame;
                frame.origin.y = dismissY;
                cardView.frame = frame;
                
                [self updateCustomFrameIfSupported:frame forViewController:containerVC];
            }
        }
        
        setOverlayToDismissAppearance(overlayView);
    } completion:^(BOOL finished) {
        [self setSkipLayoutDuringInitialSetup:NO forViewController:containerVC];
        if (completion) completion();
    }];
}

// Resets Safari/portrait presentation state and tears down any dedicated Safari/portrait window,
// restoring the host key window and orientation. Called by both safariViewControllerDidFinish:
// (user "Done") and the programmatic dismiss paths (closeBrowser / dismissSafariViewControllerWithResult:);
// Apple does not invoke the delegate on a programmatic dismiss. Fires no callbacks. Idempotent.
- (void)tearDownSafariPresentationState {
    // Unlock portrait before any window teardown so the scene can freely rotate
    // back to landscape as we restore the game window.
    self.isSafariPortraitLocked = NO;

    // If we created a dedicated Safari portrait window (standalone browser path), tear it down.
    if (self.safariPresentationWindow) {
        self.safariPresentationWindow.hidden = YES;
        self.safariPresentationWindow.rootViewController = nil;
        if (self.previousKeyWindow) {
            [self restorePrePortraitOrientation];
            [self.previousKeyWindow makeKeyAndVisible];
            self.previousKeyWindow = nil;
        }
        self.safariPresentationWindow = nil;
    }

    _safariOpenedViaOpenBrowser = NO;
    _isCardCurrentlyPresented = NO;
    self.currentSafariViewController = nil;

    // External-payment handoff OR forcePortrait browser -- the portrait window was kept/created so
    // Safari ran in portrait. Tear it down and restore landscape.
    if (self.portraitWindow) {
        self.portraitWindow.hidden = YES;
        self.portraitWindow.rootViewController = nil;
        if (self.previousKeyWindow) {
            [self restorePrePortraitOrientation];
            [self.previousKeyWindow makeKeyAndVisible];
            self.previousKeyWindow = nil;
        }
        self.portraitWindow = nil;
    }
}

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
    BOOL openedViaOpenBrowser = _safariOpenedViaOpenBrowser;

    [self tearDownSafariPresentationState];

    if (openedViaOpenBrowser) {
        if (_safariBrowserCloseDelegatePending) {
            _safariBrowserCloseDelegatePending = NO;
            id<StashNativeCardDelegate> delegate = [StashNativeCard sharedInstance].delegate;
            if (delegate != nil
                && [delegate respondsToSelector:@selector(stashNativeCardDidCloseBrowser)]) {
                [delegate stashNativeCardDidCloseBrowser];
            }
        }
    } else {
        // Unreachable today: openInSafariViewController is only called from openBrowserWithURL:,
        // which sets _safariOpenedViaOpenBrowser=YES. Kept for a non-openBrowser Safari path.
        [self callDelegateCallbackOnce];
        [self cleanupCardInstance];
    }
}

- (UIView *)createDragTrayViewWithWidth:(CGFloat)cardWidth {
    // Shared: build drag tray + handle bar (no gesture). Used by createDragTray.
    DragTrayView *dragTrayView = [[DragTrayView alloc] init];
    dragTrayView.frame = CGRectMake(0, 0, cardWidth, kDragTrayHeight);
    dragTrayView.tag = kDragTrayViewTag;
    dragTrayView.backgroundColor = [UIColor clearColor];
    
    UIView *handleView = [[UIView alloc] init];
    UIColor *chromeBg = stash_sheetBackgroundUIColor();
    BOOL darkChrome = stash_colorIsDarkBackground(chromeBg);
    handleView.backgroundColor = darkChrome ? [UIColor colorWithWhite:0.82 alpha:1.0]
                                           : [UIColor colorWithWhite:0.39 alpha:1.0];
    handleView.layer.cornerRadius = kHandleBarCornerRadius;
    handleView.tag = kDragHandleViewTag;
    handleView.frame = CGRectMake(cardWidth/2 - kHandleBarHalfWidth, kHandleBarTopInset, kHandleBarWidth, kHandleBarHeight);
    handleView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [dragTrayView addSubview:handleView];
    
    return dragTrayView;
}

- (UIView *)createDragTray:(CGFloat)cardWidth {
    DragTrayView *dragTrayView = (DragTrayView *)[self createDragTrayViewWithWidth:cardWidth];
    UIPanGestureRecognizer *dragTrayPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDragTrayPanGesture:)];
    dragTrayPanGesture.delegate = self;
    [dragTrayView addGestureRecognizer:dragTrayPanGesture];
    return dragTrayView;
}

- (void)expandCardToFullScreen {
    UIView *cardView = [self cardViewForCurrentPresentation];
    if (!cardView) return;

    _isCardExpanded = YES;

    CGRect screenBounds = self.portraitWindow ? [self referenceScreenBoundsForIPhoneCardLayout] : [UIScreen mainScreen].bounds;
    CGFloat safeTop = getSafeAreaTopForView(cardView);
    CGRect fullScreenFrame;
    if ([self isIPhoneLandscapeCurrentOrientation]) {
        // Height-only expand in landscape: use same canonical collapsed frame (includes min clamp)
        CGRect collapsedFrame = computePhoneCardFrameForBoundsAndOrientation(screenBounds, YES);
        CGFloat expW = collapsedFrame.size.width;
        CGFloat expH = screenBounds.size.height * kIPhoneLandscapeExpandedHeightRatio;
        CGFloat expX = (screenBounds.size.width - expW) / 2.0f;
        CGFloat expY = screenBounds.size.height - expH;
        if (expY < safeTop) expY = safeTop;
        fullScreenFrame = CGRectMake(expX, expY, expW, expH);
    } else {
        fullScreenFrame = CGRectMake(0, safeTop, screenBounds.size.width, screenBounds.size.height - safeTop);
    }

    WKWebView *webView = switchWebViewToFrameLayoutInCardView(cardView);

    [self setSkipLayoutDuringInitialSetup:YES forViewController:self.currentPresentedVC];

    [UIView animateWithDuration:kAnimationDurationDefault
                          delay:0
         usingSpringWithDamping:kSpringDampingDefault
          initialSpringVelocity:kSpringVelocityExpand
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionLayoutSubviews
                     animations:^{
        cardView.frame = fullScreenFrame;

        // Update webview frame inside animation block for synchronized resize
        if (webView) {
            webView.frame = CGRectMake(0, 0, fullScreenFrame.size.width, fullScreenFrame.size.height);
        }

        updateDragTrayAndHandleInCardView(cardView, fullScreenFrame.size.width);
        
        [self updateCustomFrameIfSupported:fullScreenFrame forViewController:nil];
        
        cardView.backgroundColor = stash_sheetBackgroundUIColor();
        
        [cardView layoutIfNeeded];
    } completion:^(BOOL finished) {
        CGFloat radius = isRunningOniPad() ? kCornerRadiusExpanded : kCornerRadiusDefault;
        CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, radius);
        cardView.layer.mask = maskLayer;
        
        [self setSkipLayoutDuringInitialSetup:NO forViewController:self.currentPresentedVC];
    }];
}

- (void)collapseCardToOriginal {
    UIView *cardView = [self cardViewForCurrentPresentation];
    if (!cardView) return;

    _isCardExpanded = NO;

    CGRect screenBounds = self.portraitWindow ? [self referenceScreenBoundsForIPhoneCardLayout] : [UIScreen mainScreen].bounds;
    CGFloat width, height;

    CGRect collapsedFrame;
    if (isRunningOniPad()) {
        CGSize cardSize = calculateiPadCardSize(screenBounds);
        width = cardSize.width;
        height = cardSize.height;
        CGFloat x = (screenBounds.size.width - width) / 2;
        CGFloat finalY = (screenBounds.size.height - height) / 2;
        collapsedFrame = CGRectMake(x, finalY, width, height);
    } else {
        collapsedFrame = computePhoneCardFrameForBoundsAndOrientation(screenBounds, [self isIPhoneLandscapeCurrentOrientation]);
        width = collapsedFrame.size.width;
        height = collapsedFrame.size.height;
    }

    WKWebView *webView = switchWebViewToFrameLayoutInCardView(cardView);

    [self setSkipLayoutDuringInitialSetup:YES forViewController:self.currentPresentedVC];

    [UIView animateWithDuration:kAnimationDurationDefault
                          delay:0
         usingSpringWithDamping:kSpringDampingDefault
          initialSpringVelocity:kSpringVelocityCollapse
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionLayoutSubviews
                     animations:^{
        cardView.frame = collapsedFrame;

        if (webView) {
            webView.frame = CGRectMake(0, 0, width, height);
        }

        updateDragTrayAndHandleInCardView(cardView, width);

        [self updateCustomFrameIfSupported:collapsedFrame forViewController:nil];
        
        [cardView layoutIfNeeded];
    } completion:^(BOOL finished) {
        UIRectCorner corners = getCornersToRoundForPosition(kProgressFullyExpanded, isRunningOniPad());
        CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, corners, kCornerRadiusDefault);
        cardView.layer.mask = maskLayer;

        [self setSkipLayoutDuringInitialSetup:NO forViewController:self.currentPresentedVC];
    }];
}

- (void)collapseDisplayLinkTick:(CADisplayLink *)link {
    CFTimeInterval elapsed = CACurrentMediaTime() - self.collapseStartTime;
    NSTimeInterval duration = self.collapseDuration;
    CGFloat t = (duration > 0 && elapsed < duration) ? (CGFloat)(elapsed / duration) : 1.0f;
    CGFloat overshoot = self.expandCollapseEaseOvershoot > 0.0f ? self.expandCollapseEaseOvershoot : kEaseOutBackOvershoot;
    CGFloat ease = easeOutBackWithOvershoot(t, overshoot);
    CGFloat progress = self.collapseInitialProgress * (1.0f - ease);
    if (progress < 0.0f) progress = 0.0f;

    UIView *cardView = [self cardViewForCurrentPresentation];
    if (cardView) {
        [self updateCardExpansionProgress:progress cardView:cardView];
    }

    if (t >= 1.0f || progress <= 0.0f) {
        self.expandCollapseEaseOvershoot = 0.0f;
        [self.collapseDisplayLink invalidate];
        self.collapseDisplayLink = nil;
        _isCardExpanded = NO;
        if (cardView) {
            UIRectCorner corners = getCornersToRoundForPosition(kProgressFullyExpanded, isRunningOniPad());
            CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, corners, kCornerRadiusDefault);
            cardView.layer.mask = maskLayer;
        }
        [self setSkipLayoutDuringInitialSetup:NO forViewController:self.currentPresentedVC];
        void (^completion)(void) = self.collapseCompletion;
        self.collapseCompletion = nil;
        if (completion) completion();
    }
}

- (void)animateCollapseWithDuration:(NSTimeInterval)duration completion:(void (^)(void))completion {
    if (self.collapseDisplayLink) {
        [self.collapseDisplayLink invalidate];
        self.collapseDisplayLink = nil;
        self.collapseCompletion = nil;
    }
    UIView *cardView = [self cardViewForCurrentPresentation];
    if (!cardView) {
        _isCardExpanded = NO;
        if (completion) completion();
        return;
    }
    self.collapseInitialProgress = [self currentExpansionProgressForCardView:cardView];
    [self setSkipLayoutDuringInitialSetup:YES forViewController:self.currentPresentedVC];
    self.collapseStartTime = CACurrentMediaTime();
    self.collapseDuration = duration;
    self.collapseCompletion = completion;
    self.collapseDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(collapseDisplayLinkTick:)];
    [self.collapseDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)expandDisplayLinkTick:(CADisplayLink *)link {
    CFTimeInterval elapsed = CACurrentMediaTime() - self.expandStartTime;
    NSTimeInterval duration = self.expandDuration;
    CGFloat t = (duration > 0 && elapsed < duration) ? (CGFloat)(elapsed / duration) : 1.0f;
    CGFloat overshoot = self.expandCollapseEaseOvershoot > 0.0f ? self.expandCollapseEaseOvershoot : kEaseOutBackOvershoot;
    CGFloat ease = easeOutBackWithOvershoot(t, overshoot);
    CGFloat progress = self.expandInitialProgress + (1.0f - self.expandInitialProgress) * ease;
    if (progress > 1.0f) progress = 1.0f;

    UIView *cardView = [self cardViewForCurrentPresentation];
    if (cardView) {
        [self updateCardExpansionProgress:progress cardView:cardView];
    }

    if (t >= 1.0f || progress >= 1.0f) {
        self.expandCollapseEaseOvershoot = 0.0f;
        [self.expandDisplayLink invalidate];
        self.expandDisplayLink = nil;
        _isCardExpanded = YES;
        if (cardView) {
            if (isRunningOniPad()) {
                CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, UIRectCornerAllCorners, kCornerRadiusDefault);
                cardView.layer.mask = maskLayer;
            } else {
                CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
                cardView.layer.mask = maskLayer;
            }
        }
        [self setSkipLayoutDuringInitialSetup:NO forViewController:self.currentPresentedVC];
        void (^completion)(void) = self.expandCompletion;
        self.expandCompletion = nil;
        if (completion) completion();
    }
}

- (void)animateExpandWithDuration:(NSTimeInterval)duration completion:(void (^)(void))completion {
    if (self.expandDisplayLink) {
        [self.expandDisplayLink invalidate];
        self.expandDisplayLink = nil;
        self.expandCompletion = nil;
    }
    UIView *cardView = [self cardViewForCurrentPresentation];
    if (!cardView) {
        _isCardExpanded = YES;
        if (completion) completion();
        return;
    }
    self.expandInitialProgress = [self currentExpansionProgressForCardView:cardView];
    [self setSkipLayoutDuringInitialSetup:YES forViewController:self.currentPresentedVC];
    self.expandStartTime = CACurrentMediaTime();
    self.expandDuration = duration;
    self.expandCompletion = completion;
    self.expandDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(expandDisplayLinkTick:)];
    [self.expandDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)updateCardExpansionProgress:(CGFloat)progress cardView:(UIView *)cardView {
    if (!cardView) return;

    progress = MAX(0.0, MIN(1.0, progress));

    CGRect screenBounds = self.portraitWindow ? [self referenceScreenBoundsForIPhoneCardLayout] : [UIScreen mainScreen].bounds;
    CGFloat safeTop = getSafeAreaTopForView(cardView);

    CGFloat collapsedWidth, collapsedHeight, collapsedX, collapsedY;
    CGFloat expandedWidth, expandedHeight, expandedX, expandedY;

    if (isRunningOniPad()) {
        CGSize cardSize = calculateiPadCardSize(screenBounds);
        CGFloat baseW = cardSize.width;
        CGFloat baseH = cardSize.height;
        CGFloat expandedH = stashTabletSdkExpandedHeightFromBase(baseH, screenBounds, cardView);
        collapsedWidth = expandedWidth = baseW;
        collapsedHeight = baseH;
        expandedHeight = expandedH;
        collapsedX = expandedX = (screenBounds.size.width - baseW) / 2.0;
        collapsedY = (screenBounds.size.height - collapsedHeight) / 2.0;
        expandedY = (screenBounds.size.height - expandedHeight) / 2.0;
    } else {
        // iPhone: use same canonical collapsed frame as initial present (includes min clamp)
        CGRect collapsedFrame;
        if (self.portraitWindow && _forcePortraitOnCheckout) {
            collapsedFrame = [self collapsedPhoneCardFrameForReferenceBounds:screenBounds];
        } else {
            collapsedFrame = computePhoneCardFrameForBoundsAndOrientation(screenBounds, [self isIPhoneLandscapeCurrentOrientation]);
        }
        collapsedWidth = collapsedFrame.size.width;
        collapsedHeight = collapsedFrame.size.height;
        collapsedX = collapsedFrame.origin.x;
        collapsedY = collapsedFrame.origin.y;

        if ([self isIPhoneLandscapeCurrentOrientation]) {
            // Height-only expand in landscape: same width, expand = 90% screen height
            expandedWidth = collapsedWidth;
            expandedHeight = screenBounds.size.height * kIPhoneLandscapeExpandedHeightRatio;
            expandedX = collapsedX;
            expandedY = screenBounds.size.height - expandedHeight;
            if (expandedY < safeTop) expandedY = safeTop;
        } else {
            expandedWidth = screenBounds.size.width;
            expandedHeight = screenBounds.size.height - safeTop;
            expandedX = 0;
            expandedY = safeTop;
        }
    }

    CGFloat currentWidth = collapsedWidth + (expandedWidth - collapsedWidth) * progress;
    CGFloat currentHeight = collapsedHeight + (expandedHeight - collapsedHeight) * progress;
    CGFloat currentX = collapsedX + (expandedX - collapsedX) * progress;
    CGFloat currentY;
    if (isRunningOniPad()) {
        currentY = collapsedY + (expandedY - collapsedY) * progress;
    } else {
        // iPhone: keep bottom of card anchored to bottom of screen every frame (no gap)
        currentY = screenBounds.size.height - currentHeight;
    }

    cardView.frame = CGRectMake(currentX, currentY, currentWidth, currentHeight);

    for (UIView *subview in cardView.subviews) {
        if ([subview isKindOfClass:[WKWebView class]]) {
            WKWebView *webView = (WKWebView *)subview;
            if (!webView.translatesAutoresizingMaskIntoConstraints) {
                webView.translatesAutoresizingMaskIntoConstraints = YES;
            }
            webView.frame = cardView.bounds;
            break;
        }
    }

    if ([self.currentPresentedVC isKindOfClass:[OrientationLockedViewController class]]) {
        OrientationLockedViewController *containerVC = (OrientationLockedViewController *)self.currentPresentedVC;
        containerVC.customFrame = cardView.frame;
    }
    [self updateCustomFrameIfSupported:cardView.frame forViewController:nil];

    updateDragTrayAndHandleInCardView(cardView, currentWidth);

    if (isRunningOniPad()) {
        CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, UIRectCornerAllCorners, kCornerRadiusDefault);
        cardView.layer.mask = maskLayer;
    } else {
        if (progress > kProgressCornerRadiusExpandThreshold) {
            CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
            cardView.layer.mask = maskLayer;
        } else if (progress > kProgressCornerRadiusMidThreshold) {
            UIRectCorner corners = getCornersToRoundForPosition(kProgressFullyExpanded, NO);
            corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
            CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, corners, kCornerRadiusDefault);
            cardView.layer.mask = maskLayer;
        } else {
            UIRectCorner corners = getCornersToRoundForPosition(kProgressFullyExpanded, NO);
            CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, corners, kCornerRadiusDefault);
            cardView.layer.mask = maskLayer;
        }
    }
}

- (CGFloat)currentExpansionProgressForCardView:(UIView *)cardView {
    if (!cardView) return 0.0f;
    CGRect screenBounds = self.portraitWindow ? [self referenceScreenBoundsForIPhoneCardLayout] : [UIScreen mainScreen].bounds;
    CGFloat safeTop = getSafeAreaTopForView(cardView);
    CGFloat collapsedHeight, expandedHeight;
    if (isRunningOniPad()) {
        CGSize cardSize = calculateiPadCardSize(screenBounds);
        collapsedHeight = cardSize.height;
        expandedHeight = stashTabletSdkExpandedHeightFromBase(collapsedHeight, screenBounds, cardView);
    } else {
        CGRect collapsedFrame;
        if (self.portraitWindow && _forcePortraitOnCheckout) {
            collapsedFrame = [self collapsedPhoneCardFrameForReferenceBounds:screenBounds];
        } else {
            collapsedFrame = computePhoneCardFrameForBoundsAndOrientation(screenBounds, [self isIPhoneLandscapeCurrentOrientation]);
        }
        collapsedHeight = collapsedFrame.size.height;
        if ([self isIPhoneLandscapeCurrentOrientation]) {
            expandedHeight = screenBounds.size.height * kIPhoneLandscapeExpandedHeightRatio;
        } else {
            expandedHeight = screenBounds.size.height - safeTop;
        }
    }
    CGFloat currentHeight = cardView.frame.size.height;
    CGFloat heightRange = expandedHeight - collapsedHeight;
    if (heightRange <= 0.0f) return 0.0f;
    CGFloat progress = (currentHeight - collapsedHeight) / heightRange;
    return (CGFloat)MAX(0.0, MIN(1.0, (double)progress));
}

- (CGRect)frameForExpansionProgress:(CGFloat)progress cardView:(UIView *)cardView {
    if (!cardView) return CGRectZero;
    progress = (CGFloat)MAX(0.0, MIN(1.0, (double)progress));
    CGRect screenBounds = self.portraitWindow ? [self referenceScreenBoundsForIPhoneCardLayout] : [UIScreen mainScreen].bounds;
    CGFloat safeTop = getSafeAreaTopForView(cardView);
    CGFloat collapsedWidth, collapsedHeight, collapsedX, collapsedY;
    CGFloat expandedWidth, expandedHeight, expandedX, expandedY;
    if (isRunningOniPad()) {
        CGSize cardSize = calculateiPadCardSize(screenBounds);
        CGFloat baseW = cardSize.width;
        CGFloat baseH = cardSize.height;
        CGFloat expandedH = stashTabletSdkExpandedHeightFromBase(baseH, screenBounds, cardView);
        collapsedWidth = expandedWidth = baseW;
        collapsedHeight = baseH;
        expandedHeight = expandedH;
        collapsedX = expandedX = (screenBounds.size.width - baseW) / 2.0;
        collapsedY = (screenBounds.size.height - collapsedHeight) / 2.0;
        expandedY = (screenBounds.size.height - expandedHeight) / 2.0;
    } else {
        CGRect collapsedFrame;
        if (self.portraitWindow && _forcePortraitOnCheckout) {
            collapsedFrame = [self collapsedPhoneCardFrameForReferenceBounds:screenBounds];
        } else {
            collapsedFrame = computePhoneCardFrameForBoundsAndOrientation(screenBounds, [self isIPhoneLandscapeCurrentOrientation]);
        }
        collapsedWidth = collapsedFrame.size.width;
        collapsedHeight = collapsedFrame.size.height;
        collapsedX = collapsedFrame.origin.x;
        collapsedY = collapsedFrame.origin.y;
        if ([self isIPhoneLandscapeCurrentOrientation]) {
            expandedWidth = collapsedWidth;
            expandedHeight = screenBounds.size.height * kIPhoneLandscapeExpandedHeightRatio;
            expandedX = collapsedX;
            expandedY = screenBounds.size.height - expandedHeight;
            if (expandedY < safeTop) expandedY = safeTop;
        } else {
            expandedWidth = screenBounds.size.width;
            expandedHeight = screenBounds.size.height - safeTop;
            expandedX = 0;
            expandedY = safeTop;
        }
    }
    CGFloat w = collapsedWidth + (expandedWidth - collapsedWidth) * progress;
    CGFloat h = collapsedHeight + (expandedHeight - collapsedHeight) * progress;
    CGFloat x = collapsedX + (expandedX - collapsedX) * progress;
    CGFloat y;
    if (isRunningOniPad()) {
        y = collapsedY + (expandedY - collapsedY) * progress;
    } else {
        y = screenBounds.size.height - h;
    }
    return CGRectMake(x, y, w, h);
}

- (void)startKeyboardObserving {
    if (self.isObservingKeyboard) return;
    self.isObservingKeyboard = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)stopKeyboardObserving {
    if (!self.isObservingKeyboard) return;
    self.isObservingKeyboard = NO;
    self.isIPhoneCardKeyboardVisible = NO;
    self.stashLastValidDeviceOrientationForKeyboard = 0;
    self.stashLastSceneSizeForKeyboardDismiss = CGSizeZero;

    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    (void)notification;
    [self stashApplyKeyboardOrientationLockIfNeeded];

    if (_usePopupPresentation || _useModalPresentation || isRunningOniPad()) return;
    if (_isCardExpanded) return;
    
    if (!self.currentPresentedVC) return;
    
    if ([self.currentPresentedVC isKindOfClass:[OrientationLockedViewController class]]) {
        OrientationLockedViewController *containerVC = (OrientationLockedViewController *)self.currentPresentedVC;
        containerVC.skipLayoutDuringInitialSetup = YES;
    }
    
    if (self.portraitWindow) {
        CGRect b = stashSceneCoordinateBoundsForIPhoneCardWindow(self.portraitWindow);
        [self relayoutIPhoneCardWindowWithTargetBounds:b forcedCardExpansionProgress:-1.0];
    }
    
    [self expandCardToFullScreen];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    (void)notification;
    [self stashClearKeyboardOrientationLockIfNeeded];
}

- (void)handleDragTrayPanGesture:(UIPanGestureRecognizer *)gesture {
    if (!self.currentPresentedVC) return;
    if (self.isPurchaseProcessing) return;
    
    UIView *cardView = [self cardViewForCurrentPresentation];
    if (!cardView) return;
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            [self handleDragGestureBegan:gesture cardView:cardView];
            break;
            
        case UIGestureRecognizerStateChanged:
            [self handleDragGestureChanged:gesture cardView:cardView];
            break;
            
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            [self handleDragGestureEnded:gesture cardView:cardView];
            break;
            
        default:
            break;
    }
}

#pragma mark - Gesture Handling Methods (Matching Unity)

- (void)handleDragGestureBegan:(UIPanGestureRecognizer *)gesture cardView:(UIView *)cardView {
    // A new drag owns the frame; stop any running expand/collapse link so they do not fight.
    if (self.expandDisplayLink) {
        [self.expandDisplayLink invalidate];
        self.expandDisplayLink = nil;
        self.expandCompletion = nil;
    }
    if (self.collapseDisplayLink) {
        [self.collapseDisplayLink invalidate];
        self.collapseDisplayLink = nil;
        self.collapseCompletion = nil;
    }
    self.initialY = cardView.frame.origin.y;
    
    if (!isRunningOniPad()) {
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyInitialCardHeight, @(cardView.frame.size.height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        switchWebViewToFrameLayoutInCardView(cardView);
    }
    
    [self setSkipLayoutDuringInitialSetup:YES forViewController:self.currentPresentedVC];
}
    
- (void)handleDragGestureChanged:(UIPanGestureRecognizer *)gesture cardView:(UIView *)cardView {
    CGPoint translation = [gesture translationInView:self.portraitWindow ? self.portraitWindow : cardView.superview];
    CGFloat currentTravel = translation.y;
    CGFloat screenHeight = self.portraitWindow ? self.portraitWindow.bounds.size.height : cardView.superview.bounds.size.height;
    CGFloat height = cardView.frame.size.height;
    
    if (isRunningOniPad()) {
        // iPad: drag-down only (toward dismiss). No expand/collapse.
        if (currentTravel <= 0) return;
            CGFloat newY = MIN(screenHeight, self.initialY + currentTravel);
            runWithoutImplicitAnimations(^{
                cardView.frame = CGRectMake(cardView.frame.origin.x, newY, cardView.frame.size.width, height);
            });
        [self updateCustomFrameIfSupported:cardView.frame forViewController:nil];
        return;
    }
    
        CGRect screenBounds = self.portraitWindow ? [self referenceScreenBoundsForIPhoneCardLayout] : [UIScreen mainScreen].bounds;
        CGFloat safeTop = getSafeAreaTopForView(cardView);
        BOOL landscapeHeightOnly = [self isIPhoneLandscapeCurrentOrientation];
        CGRect collapsedFrame;
        if (self.portraitWindow && _forcePortraitOnCheckout) {
            collapsedFrame = [self collapsedPhoneCardFrameForReferenceBounds:screenBounds];
        } else {
            collapsedFrame = computePhoneCardFrameForBoundsAndOrientation(screenBounds, landscapeHeightOnly);
        }
        CGFloat collapsedWidth = collapsedFrame.size.width;
        CGFloat collapsedHeight = collapsedFrame.size.height;
        CGFloat collapsedX = collapsedFrame.origin.x;
        CGFloat expandedHeight = landscapeHeightOnly ? (screenBounds.size.height * kIPhoneLandscapeExpandedHeightRatio) : (screenBounds.size.height - safeTop);
        CGFloat currentProgress = 0.0;
        
        if (currentTravel < 0) {
            if (_isCardExpanded) {
                currentProgress = 1.0;
            } else if (_cardIsInLandscape) {
                // Landscape card stays at its configured size; don't show expand visual feedback.
                currentProgress = 0.0;
            } else {
                CGFloat dragAmount = fabs(currentTravel);
                CGFloat heightRange = expandedHeight - collapsedHeight;
                // Degenerate ratios can make the range 0; 0/0 is NaN and poisons the frame.
                currentProgress = (heightRange > 0.0f) ? MIN(1.0, dragAmount / heightRange) : 0.0;
            }
        } else if (currentTravel > 0) {
            if (_isCardExpanded) {
                CGFloat dragAmount = currentTravel;
                CGFloat heightRange = expandedHeight - collapsedHeight;
                currentProgress = MAX(0.0, 1.0 - (dragAmount / heightRange));
                
                if (currentProgress <= 0.0 && currentTravel > height * kDragDismissTravelRatioForProgress) {
                    CGFloat newY = MIN(screenHeight, screenBounds.size.height - collapsedHeight + (currentTravel - heightRange));
                    runWithoutImplicitAnimations(^{
                        cardView.frame = CGRectMake(collapsedX, newY, collapsedWidth, collapsedHeight);
                    });
                [self updateCustomFrameIfSupported:cardView.frame forViewController:nil];
                    runWithoutImplicitAnimations(^{
                        [self updateCardExpansionProgress:kProgressFullyCollapsed cardView:cardView];
                    });
                    return;
                }
            } else {
                CGFloat newY = MIN(screenHeight, self.initialY + currentTravel);
                runWithoutImplicitAnimations(^{
                    cardView.frame = CGRectMake(cardView.frame.origin.x, newY, cardView.frame.size.width, cardView.frame.size.height);
                });
            [self updateCustomFrameIfSupported:cardView.frame forViewController:nil];
                return;
            }
        }
        runWithoutImplicitAnimations(^{
            [self updateCardExpansionProgress:currentProgress cardView:cardView];
            [cardView layoutIfNeeded];
        });
}
    
- (void)handleDragGestureEnded:(UIPanGestureRecognizer *)gesture cardView:(UIView *)cardView {
    if (!isRunningOniPad()) {
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyInitialCardHeight, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    UIView *referenceView = self.portraitWindow ? self.portraitWindow : cardView.superview;
    CGPoint translation = [gesture translationInView:referenceView];
    CGPoint velocity = [gesture velocityInView:referenceView];
    CGFloat currentTravel = translation.y;
    CGFloat height = cardView.frame.size.height;
    UIView *overlayView = self.portraitWindow ? objc_getAssociatedObject(self.currentPresentedVC, (__bridge const void *)StashNativeAssociatedKeyOverlayView) : nil;
    
    BOOL shouldExpand = NO;
    BOOL shouldCollapse = NO;
    BOOL shouldDismiss = NO;
    
    if (isRunningOniPad()) {
        // iPad: dismiss only. No expand/collapse.
        if (currentTravel > 0) {
            CGFloat currentY = cardView.frame.origin.y;
            CGFloat screenHeight = referenceView.bounds.size.height;
            CGFloat cardBottom = currentY + height;
            CGFloat distanceToBottom = screenHeight - cardBottom;
            if (distanceToBottom < kDismissDistanceFromBottomThreshold || (velocity.y > kDismissVelocityThresholdIPad && currentTravel > height * kDismissTravelRatioThresholdIPad)) {
                shouldDismiss = YES;
            }
        }
    } else {
// iPhone: expand, collapse, or dismiss
        CGFloat expandThreshold = height * kExpandDragThresholdRatio;
        CGFloat collapseThreshold = height * kCollapseDragThresholdRatio;
        CGFloat dismissThreshold = height * kDismissDragThresholdRatio;

        if (currentTravel < -expandThreshold || velocity.y < kExpandVelocityThreshold) {
            // Landscape cards stay at their configured size; drag-up expand has no effect.
            if (!_isCardExpanded && !_cardIsInLandscape) shouldExpand = YES;
        } else if (currentTravel > 0) {
            if (_isCardExpanded) {
                if (currentTravel > dismissThreshold && velocity.y > kDismissVelocityThreshold) {
                    shouldDismiss = YES;
                } else if (currentTravel > collapseThreshold || velocity.y > kCollapseVelocityThreshold) {
                    shouldCollapse = YES;
                }
            } else {
                if (currentTravel > dismissThreshold || velocity.y > kDismissVelocityThreshold) {
                    shouldDismiss = YES;
                }
            }
        }
    }
    
    if (shouldExpand) {
        [self animateExpandWithDuration:kExpandAnimationDuration completion:nil];
    } else if (shouldCollapse) {
        NSTimeInterval animationDuration = kCollapseAnimationDurationDefault;
        if (velocity.y > kVelocityThresholdForFastCollapse) {
            animationDuration = kCollapseAnimationDurationFast;
        }
        [self animateCollapseWithDuration:animationDuration completion:nil];
    } else if (shouldDismiss) {
        [self setSkipLayoutDuringInitialSetup:YES forViewController:self.currentPresentedVC];
        
        CGFloat animationDuration = (velocity.y > kVelocityThresholdForFastDismiss) ? kDismissAnimationDurationFast : kDismissAnimationDurationNormal;
        CGFloat finalY = self.portraitWindow ? self.portraitWindow.bounds.size.height : cardView.superview.bounds.size.height;
        
        [UIView animateWithDuration:animationDuration 
                              delay:0 
             usingSpringWithDamping:kSpringDampingTight 
              initialSpringVelocity:velocity.y / kVelocityDivisorForSpring
                            options:UIViewAnimationOptionCurveEaseOut 
                         animations:^{
            cardView.frame = CGRectMake(cardView.frame.origin.x, finalY, cardView.frame.size.width, cardView.frame.size.height);
            
            [self updateCustomFrameIfSupported:cardView.frame forViewController:nil];
            setOverlayToDismissAppearance(overlayView);
        } completion:^(BOOL finished) {
            if (!self.currentPresentedVC) {
                [self callDelegateCallbackOnce];
                [self cleanupCardInstance];
                return;
            }
            
            [self setSkipLayoutDuringInitialSetup:NO forViewController:self.currentPresentedVC];
            
            UIViewController *vcToDismiss = self.currentPresentedVC;
            [vcToDismiss dismissViewControllerAnimated:NO completion:^{
                if (self.currentPresentedVC == vcToDismiss) {
                    [self callDelegateCallbackOnce];
                    [self cleanupCardInstance];
                }
            }];
        }];
    } else {
        // Snap back: iPad to center, iPhone to expanded/collapsed
        if (isRunningOniPad()) {
            CGRect screenBounds = [UIScreen mainScreen].bounds;
            CGRect targetFrame = stashFrameForIPadSdkCard(screenBounds, cardView);
            CGFloat originalWidth = targetFrame.size.width;
            CGFloat originalHeight = targetFrame.size.height;
            
            [UIView animateWithDuration:kAnimationDurationFast 
                                  delay:0 
                 usingSpringWithDamping:kSpringDampingSnapBack 
                  initialSpringVelocity:fabs(velocity.y) / kVelocityDivisorForSpring 
                                options:UIViewAnimationOptionCurveEaseOut 
                             animations:^{
                cardView.frame = targetFrame;
                
                UIView *dragTray = [cardView viewWithTag:kDragTrayViewTag];
                if (dragTray) {
                    dragTray.frame = CGRectMake(0, 0, originalWidth, kDragTrayHeight);
                    UIView *handle = [dragTray viewWithTag:kDragHandleViewTag];
                    if (handle) {
                        handle.frame = CGRectMake((originalWidth / 2.0) - kHandleBarHalfWidth, kHandleBarTopInset, kHandleBarWidth, kHandleBarHeight);
                    }
                }
                
                [self updateCustomFrameIfSupported:cardView.frame forViewController:nil];
            } completion:^(BOOL finished) {
                [self setSkipLayoutDuringInitialSetup:NO forViewController:self.currentPresentedVC];
            }];
        } else {
            // iPhone snap back: use display-link expand/collapse so every frame is bottom-anchored (no gap), with stronger spring
            if (_isCardExpanded) {
                self.expandCollapseEaseOvershoot = kEaseOutBackSnapBackOvershoot;
                [self animateExpandWithDuration:kSnapBackAnimationDuration completion:^{
                    [self setSkipLayoutDuringInitialSetup:NO forViewController:self.currentPresentedVC];
                }];
            } else {
                // Collapsed card may have been dragged down (only Y changed); progress is still 0 so display-link collapse would do nothing.
                // Spring the frame back to canonical collapsed position for a native Apple-like feel.
                CGRect targetFrame = [self frameForExpansionProgress:kProgressFullyCollapsed cardView:cardView];
                BOOL needsSpringBack = (fabs(cardView.frame.origin.y - targetFrame.origin.y) > 0.5f);
                if (needsSpringBack) {
                    // Ease-out only (no UIKit spring): spring overshoot on Y made the sheet sit above
                    // the bottom briefly — same gap as entry overshoot; display-link paths stay bottom-anchored.
                    [UIView animateWithDuration:kSnapBackAnimationDuration
                                          delay:0
                                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                                     animations:^{
                        cardView.frame = targetFrame;
                        [self updateCustomFrameIfSupported:cardView.frame forViewController:nil];
                    } completion:^(BOOL finished) {
                        [self updateCardExpansionProgress:kProgressFullyCollapsed cardView:cardView];
                        [self setSkipLayoutDuringInitialSetup:NO forViewController:self.currentPresentedVC];
                    }];
                } else {
                    self.expandCollapseEaseOvershoot = kEaseOutBackSnapBackOvershoot;
                    [self animateCollapseWithDuration:kSnapBackAnimationDuration completion:^{
                        [self setSkipLayoutDuringInitialSetup:NO forViewController:self.currentPresentedVC];
                    }];
                }
            }
        }
    }
}

#pragma mark - Payment / Close Signals (script messages and stash-pay deeplinks)

- (void)handlePaymentSuccessSignalWithOrder:(NSString *)orderString {
    // When autoClose is on, the dialog tears down after the first event, so guard against
    // duplicate callbacks. When autoClose is off, the page stays alive and may legitimately
    // emit follow-up events (e.g. failure -> retry -> success), so don't gate.
    if (_autoCloseOnPaymentEvent && _paymentSuccessHandled) return;
    if (_autoCloseOnPaymentEvent) _paymentSuccessHandled = YES;
    self.isPurchaseProcessing = NO;

    id<StashNativeCardDelegate> delegate = [StashNativeCard sharedInstance].delegate;
    if (delegate) {
        if ([delegate respondsToSelector:@selector(stashNativeCardDidCompletePaymentWithOrder:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate stashNativeCardDidCompletePaymentWithOrder:orderString];
            });
        } else if ([delegate respondsToSelector:@selector(stashNativeCardDidCompletePayment)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate stashNativeCardDidCompletePayment];
            });
        }
    }

    if (_autoCloseOnPaymentEvent) {
        [self dismissWithAnimation:^{
            [self cleanupCardInstance];
        }];
    }
}

- (void)handlePaymentFailureSignal {
    if (_autoCloseOnPaymentEvent && _paymentSuccessHandled) return;
    if (_autoCloseOnPaymentEvent) _paymentSuccessHandled = YES;
    self.isPurchaseProcessing = NO;

    id<StashNativeCardDelegate> delegate = [StashNativeCard sharedInstance].delegate;
    if (delegate && [delegate respondsToSelector:@selector(stashNativeCardDidFailPayment)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate stashNativeCardDidFailPayment];
        });
    }

    if (_autoCloseOnPaymentEvent) {
        [self dismissWithAnimation:^{
            [self cleanupCardInstance];
        }];
    }
}

- (void)handleWindowCloseSignal {
    if (self.isPurchaseProcessing) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self dismissWithAnimation:^{
            [self callDelegateCallbackOnce];
            [self cleanupCardInstance];
        }];
    });
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSString *name = message.name;
    id<StashNativeCardDelegate> delegate = [StashNativeCard sharedInstance].delegate;
    
    if ([name isEqualToString:kMessageHandlerPaymentSuccess]) {
        NSString *orderString = nil;
        id body = message.body;
        if ([body isKindOfClass:[NSString class]]) {
            NSString *s = (NSString *)body;
            if (s.length > 0) {
                orderString = s;
            }
        }
        [self handlePaymentSuccessSignalWithOrder:orderString];
    } else if ([name isEqualToString:kMessageHandlerPaymentFailure]) {
        [self handlePaymentFailureSignal];
    } else if ([name isEqualToString:kMessageHandlerPurchaseProcessing]) {
        self.isPurchaseProcessing = YES;
        [self updateDragTrayVisibilityForPurchaseProcessing:YES];
    } else if ([name isEqualToString:kMessageHandlerProcessingCompleted]) {
        self.isPurchaseProcessing = NO;
        [self updateDragTrayVisibilityForPurchaseProcessing:NO];
    } else if ([name isEqualToString:kMessageHandlerOptin]) {
        NSString *optinType = [message.body isKindOfClass:[NSString class]] ? message.body : @"";

        if (delegate && [delegate respondsToSelector:@selector(stashNativeCardDidReceiveOptIn:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate stashNativeCardDidReceiveOptIn:optinType];
            });
        }

        [self dismissWithAnimation:^{
            [self cleanupCardInstance];
        }];
    } else if ([name isEqualToString:kMessageHandlerExpand]) {
        if (_useModalPresentation || _usePopupPresentation) {
            return;
        }
        // Phones only: landscape cards stay at their configured size.
        if (_cardIsInLandscape) {
            return;
        }

        if (!_isCardExpanded && self.currentPresentedVC) {
            [self animateExpandWithDuration:kAnimationDurationDefault completion:nil];
        }
    } else if ([name isEqualToString:kMessageHandlerCollapse]) {
        if (_useModalPresentation || _usePopupPresentation) {
            return;
        }
        // Phones only: landscape cards stay at their configured size.
        if (_cardIsInLandscape) {
            return;
        }

        if (_isCardExpanded && self.currentPresentedVC) {
            [self animateCollapseWithDuration:kAnimationDurationDefault completion:nil];
        }
    } else if ([name isEqualToString:kMessageHandlerOpenLink]) {
        NSString *raw = @"";
        if ([message.body isKindOfClass:[NSString class]]) {
            raw = (NSString *)message.body;
        }
        NSString *normalized = NormalizeExternalPaymentURL(raw);
        if (!normalized) {
            return;
        }
        NSURL *linkURL = [NSURL URLWithString:normalized];
        if (!linkURL) {
            return;
        }
        // Plain external open: no theme param, no dismissal, no delegate callbacks.
        [[UIApplication sharedApplication] openURL:linkURL options:@{} completionHandler:nil];
    } else if ([name isEqualToString:kMessageHandlerExternalPayment]) {
        NSString *raw = @"";
        if ([message.body isKindOfClass:[NSString class]]) {
            raw = (NSString *)message.body;
        }
        NSString *normalized = NormalizeExternalPaymentURL(raw);
        if (!normalized) {
            return;
        }
        NSString *themed = appendThemeQueryParameter(normalized);
        dispatch_async(dispatch_get_main_queue(), ^{
            id<StashNativeCardDelegate> externalDelegate = [StashNativeCard sharedInstance].delegate;
            if (externalDelegate
                && [externalDelegate respondsToSelector:@selector(stashNativeCardDidRequestExternalPaymentWithURL:)]) {
                [externalDelegate stashNativeCardDidRequestExternalPaymentWithURL:themed];
            }
            StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
            // Signal cleanupCardInstance to keep the portrait window alive so Safari can be
            // presented from it immediately — no scene-rotation animation between card and Safari.
            if (_forcePortraitOnCheckout) {
                internal.isHandingOffPortraitWindowToSafari = YES;
            }
            [internal dismissWithAnimation:^{
                [internal cleanupCardInstance];
                [[StashNativeCard sharedInstance] openBrowserWithURL:normalized];
            }];
        });
    } else if ([name isEqualToString:kMessageHandlerWindowClose]) {
        [self handleWindowCloseSignal];
    } else if ([name isEqualToString:kMessageHandlerPageReady]) {
        WebViewLoadDelegate *loadDelegate = self.activeWebViewLoadDelegate;
        if (loadDelegate) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [loadDelegate notifyPageReadyFromInjectedScript];
            });
        }
    }
}

#pragma mark - iPhone card window bounds / relayout

- (CGRect)referenceScreenBoundsForIPhoneCardLayout {
    if (self.portraitWindow) {
        return self.portraitWindow.bounds;
    }
    return [UIScreen mainScreen].bounds;
}

- (CGRect)collapsedPhoneCardFrameForReferenceBounds:(CGRect)actualBounds {
    if (_forcePortraitOnCheckout) {
        CGFloat apw = MIN(actualBounds.size.width, actualBounds.size.height);
        CGFloat aph = MAX(actualBounds.size.width, actualBounds.size.height);
        BOOL rotationSucceeded = actualBounds.size.width < actualBounds.size.height;
        CGRect r;
        if (rotationSucceeded) {
            r = computePhoneCardFrameForBoundsAndOrientation(actualBounds, NO);
        } else {
            CGFloat cardWidth = apw;
            CGFloat cardHeight = aph * _cardHeightRatioPortrait;
            CGFloat cardX = (actualBounds.size.width - cardWidth) / 2.0;
            CGFloat cardFinalY = actualBounds.size.height - cardHeight;
            r = CGRectMake(cardX, cardFinalY, cardWidth, cardHeight);
        }
        if (r.origin.y < _cardSafeAreaTop) {
            CGFloat cardH = actualBounds.size.height - _cardSafeAreaTop;
            r = CGRectMake(r.origin.x, _cardSafeAreaTop, r.size.width, cardH);
        }
        if (r.origin.y < 0) {
            r = CGRectMake(r.origin.x, 0, r.size.width, r.size.height);
        }
        return r;
    }
    BOOL isLandscape = actualBounds.size.width > actualBounds.size.height;
    return computePhoneCardFrameForBoundsAndOrientation(actualBounds, isLandscape);
}

- (void)relayoutIPhoneCardWindowWithTargetBounds:(CGRect)targetBounds forcedCardExpansionProgress:(CGFloat)forcedProgress {
    if (!_isCardCurrentlyPresented || !self.portraitWindow) {
        return;
    }
    if (isRunningOniPad()) {
        return;
    }
    if (_usePopupPresentation || _useModalPresentation) {
        return;
    }
    UIViewController *vc = self.currentPresentedVC;
    if (!vc || self.portraitWindow.rootViewController != vc) {
        return;
    }
    if ([(id)vc skipLayoutDuringInitialSetup]) {
        return;
    }
    UIWindow *w = self.portraitWindow;
    if (!CGRectIsNull(targetBounds) && !CGRectIsInfinite(targetBounds) && targetBounds.size.width > 1.0 && targetBounds.size.height > 1.0) {
        w.frame = targetBounds;
    }
    vc.view.frame = w.bounds;
    if (@available(iOS 11.0, *)) {
        CGFloat fresh = w.safeAreaInsets.top;
        // On iOS 15, safeAreaInsets can transiently report 0 during
        // attemptRotationToDeviceOrientation (keyboard dismiss + rotation).
        // A device with a notch/Dynamic Island cannot genuinely have 0 safe
        // area while the card is presented portrait, so keep the last known value.
        if (fresh > 0 || _cardSafeAreaTop == 0) {
            _cardSafeAreaTop = fresh;
        }
    }
    UIView *overlay = objc_getAssociatedObject(vc, (__bridge const void *)StashNativeAssociatedKeyOverlayView);
    if (overlay) {
        overlay.frame = stashIPhoneCardOverscanBackdropFrameForWindowBounds(w.bounds);
    }
    UIView *cardView = [w viewWithTag:kCardViewTag];
    if (!cardView) {
        return;
    }
    switchWebViewToFrameLayoutInCardView(cardView);
    CGFloat p;
    if (forcedProgress >= 0.0 && forcedProgress <= 1.0) {
        p = (CGFloat)forcedProgress;
    } else {
        p = _isCardExpanded ? 1.0f : [self currentExpansionProgressForCardView:cardView];
    }
    [self updateCardExpansionProgress:p cardView:cardView];
    if ([vc respondsToSelector:@selector(setCardFrame:)]) {
        [(id)vc setCardFrame:cardView.frame];
    }
    [self updateCustomFrameIfSupported:cardView.frame forViewController:vc];
}

- (void)registerIPhoneCardWindowGeometryObservers {
    if (self.iPhoneCardWindowGeometryObserversRegistered) {
        return;
    }
    self.iPhoneCardWindowGeometryObserversRegistered = YES;
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(stashIPhoneCardGeometryMayHaveChanged:) name:UIDeviceOrientationDidChangeNotification object:nil];
}

- (void)unregisterIPhoneCardWindowGeometryObservers {
    if (!self.iPhoneCardWindowGeometryObserversRegistered) {
        return;
    }
    self.iPhoneCardWindowGeometryObserversRegistered = NO;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
    // Balance beginGenerating from register; UIKit refcounts the orientation machinery.
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    if (self.pendingIPhoneCardGeometryRelayoutBlock) {
        dispatch_block_cancel(self.pendingIPhoneCardGeometryRelayoutBlock);
        self.pendingIPhoneCardGeometryRelayoutBlock = nil;
    }
}

static CGRect stashCoerceBoundsToCardOrientationLock(CGRect b, UIViewController *presentedVC);

- (void)stashIPhoneCardGeometryMayHaveChanged:(NSNotification *)note {
    (void)note;
    if (!self.portraitWindow || !self.currentPresentedVC) {
        return;
    }
    if (isRunningOniPad() || _usePopupPresentation || _useModalPresentation) {
        return;
    }
    // Force-portrait checkout: the system keyboard can still follow the host when the device rotates.
    // Dismiss editing so the next tap can present the keyboard in a clean portrait state.
    if (_forcePortraitOnCheckout && self.isIPhoneCardKeyboardVisible) {
        UIDeviceOrientation d = [UIDevice currentDevice].orientation;
        if (UIDeviceOrientationIsValidInterfaceOrientation(d)) {
            NSInteger dn = (NSInteger)d;
            if (self.stashLastValidDeviceOrientationForKeyboard != 0 &&
                dn != self.stashLastValidDeviceOrientationForKeyboard) {
                [self.portraitWindow endEditing:YES];
            }
            self.stashLastValidDeviceOrientationForKeyboard = dn;
        }
    }
    if (self.pendingIPhoneCardGeometryRelayoutBlock) {
        dispatch_block_cancel(self.pendingIPhoneCardGeometryRelayoutBlock);
        self.pendingIPhoneCardGeometryRelayoutBlock = nil;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_block_t work = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.portraitWindow) {
            return;
        }
        CGRect b = stashSceneCoordinateBoundsForIPhoneCardWindow(strongSelf.portraitWindow);
        // Keyboard dismiss detection uses RAW scene bounds to detect real orientation
        // changes before we coerce them for layout. The saved reference size is also raw.
        if (_forcePortraitOnCheckout && strongSelf.isIPhoneCardKeyboardVisible) {
            CGSize sz = b.size;
            if (sz.width > 1.0 && sz.height > 1.0 && strongSelf.stashLastSceneSizeForKeyboardDismiss.width > 1.0) {
                BOOL wasLandscape =
                    strongSelf.stashLastSceneSizeForKeyboardDismiss.width > strongSelf.stashLastSceneSizeForKeyboardDismiss.height;
                BOOL nowLandscape = sz.width > sz.height;
                if (wasLandscape != nowLandscape) {
                    [strongSelf.portraitWindow endEditing:YES];
                }
            }
            if (sz.width > 1.0 && sz.height > 1.0) {
                strongSelf.stashLastSceneSizeForKeyboardDismiss = sz;
            }
        }
        // iOS 15 guard: the scene coordinate space can report bounds matching the
        // device orientation even when the card window is locked to a different one.
        // Swap width/height when bounds violate the card's orientation constraint.
        if (@available(iOS 16.0, *)) {
            // Scene geometry preferences prevent this on iOS 16+.
        } else {
            b = stashCoerceBoundsToCardOrientationLock(b, strongSelf.currentPresentedVC);
        }
        [strongSelf relayoutIPhoneCardWindowWithTargetBounds:b forcedCardExpansionProgress:-1.0];
        strongSelf.pendingIPhoneCardGeometryRelayoutBlock = nil;
    });
    self.pendingIPhoneCardGeometryRelayoutBlock = work;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), work);
}

- (UIInterfaceOrientationMask)stashKeyboardOrientationLockMaskForCardWindow {
    if (_forcePortraitOnCheckout) {
        return UIInterfaceOrientationMaskPortrait;
    }
    UIViewController *vc = self.currentPresentedVC;
    if ([vc isKindOfClass:[IPhoneCardCurrentOrientationViewController class]]) {
        IPhoneCardCurrentOrientationViewController *cvc = (IPhoneCardCurrentOrientationViewController *)vc;
        if (cvc.lockedOrientationMask != 0) {
            return cvc.lockedOrientationMask;
        }
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (void)stashApplyKeyboardOrientationLockIfNeeded {
    if (isRunningOniPad() || _usePopupPresentation || _useModalPresentation) {
        return;
    }
    if (!self.portraitWindow) {
        return;
    }
    self.isIPhoneCardKeyboardVisible = YES;
    {
        UIDeviceOrientation d = [UIDevice currentDevice].orientation;
        self.stashLastValidDeviceOrientationForKeyboard =
            UIDeviceOrientationIsValidInterfaceOrientation(d) ? (NSInteger)d : 0;
    }
    if (_forcePortraitOnCheckout && self.portraitWindow.windowScene) {
        self.stashLastSceneSizeForKeyboardDismiss = self.portraitWindow.windowScene.coordinateSpace.bounds.size;
    } else {
        self.stashLastSceneSizeForKeyboardDismiss = CGSizeZero;
    }
    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene = self.portraitWindow.windowScene;
        if (scene) {
            UIInterfaceOrientationMask mask = [self stashKeyboardOrientationLockMaskForCardWindow];
            UIWindowSceneGeometryPreferencesIOS *prefs =
                [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
            [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
                STASH_DEBUG_LOG(@"StashNative keyboard orientation lock: %@", error);
            }];
            if (_forcePortraitOnCheckout) {
                CGRect cb = scene.coordinateSpace.bounds;
                BOOL boundsLandscape = cb.size.width > cb.size.height;
                BOOL ioLandscape = UIInterfaceOrientationIsLandscape(scene.interfaceOrientation);
                if (boundsLandscape || ioLandscape) {
                    [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
                        STASH_DEBUG_LOG(@"StashNative keyboard portrait reinforce: %@", error);
                    }];
                }
            }
        }
    } else {
        // iOS 15: trigger re-query of supportedInterfaceOrientationsForWindow so the
        // swizzle sees isIPhoneCardKeyboardVisible == YES and returns the lock mask.
        [UIViewController attemptRotationToDeviceOrientation];
    }
}

- (void)stashClearKeyboardOrientationLockIfNeeded {
    if (!self.isIPhoneCardKeyboardVisible) {
        return;
    }
    self.isIPhoneCardKeyboardVisible = NO;
    self.stashLastValidDeviceOrientationForKeyboard = 0;
    self.stashLastSceneSizeForKeyboardDismiss = CGSizeZero;
    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene = self.portraitWindow.windowScene;
        if (!scene || !self.portraitWindow) {
            return;
        }
        UIInterfaceOrientationMask mask = [self stashKeyboardOrientationLockMaskForCardWindow];
        UIWindowSceneGeometryPreferencesIOS *prefs =
            [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
        [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
            STASH_DEBUG_LOG(@"StashNative keyboard orientation restore: %@", error);
        }];
    } else {
        // iOS 15: reinforce the card's orientation so the next keyboard presented
        // appears in portrait (or the locked orientation). Without this, the device
        // is still physically rotated and the next keyboard would follow that.
        if (self.portraitWindow) {
            if (_forcePortraitOnCheckout) {
                [[UIDevice currentDevice] setValue:@(UIInterfaceOrientationPortrait)
                                            forKey:@"orientation"];
            }
            [UIViewController attemptRotationToDeviceOrientation];
        }
    }
}

@end

CGRect stashSceneCoordinateBoundsForIPhoneCardWindow(UIWindow *window) {
    if (!window) {
        return [UIScreen mainScreen].bounds;
    }
    if (@available(iOS 13.0, *)) {
        UIWindowScene *ws = window.windowScene;
        if (ws != nil) {
            return ws.coordinateSpace.bounds;
        }
    }
    return window.screen.bounds;
}

/// iOS 15 helper: if the scene reports bounds that violate the card's orientation lock,
/// swap width/height to get correct portrait/landscape dimensions.
static CGRect stashCoerceBoundsToCardOrientationLock(CGRect b, UIViewController *presentedVC) {
    if (_forcePortraitOnCheckout) {
        if (b.size.width > b.size.height) {
            return CGRectMake(0, 0, b.size.height, b.size.width);
        }
        return b;
    }
    if ([presentedVC isKindOfClass:[IPhoneCardCurrentOrientationViewController class]]) {
        IPhoneCardCurrentOrientationViewController *cvc =
            (IPhoneCardCurrentOrientationViewController *)presentedVC;
        UIInterfaceOrientationMask mask = cvc.lockedOrientationMask;
        if (mask == 0) return b;
        BOOL boundsLandscape = b.size.width > b.size.height;
        BOOL maskPortrait = (mask == UIInterfaceOrientationMaskPortrait);
        BOOL maskLandscape = (mask & UIInterfaceOrientationMaskLandscape) &&
                             !(mask & UIInterfaceOrientationMaskPortrait);
        if ((maskPortrait && boundsLandscape) || (maskLandscape && !boundsLandscape)) {
            return CGRectMake(0, 0, b.size.height, b.size.width);
        }
    }
    return b;
}

/// YES when the window scene looks portrait (short side = width) or reports a portrait interface orientation.
static BOOL stashForcePortraitCardSceneLooksPortrait(UIWindow *window) {
    if (!window) {
        return NO;
    }
    CGRect b = stashSceneCoordinateBoundsForIPhoneCardWindow(window);
    if (b.size.width > 1.0 && b.size.height > 1.0 && b.size.width < b.size.height) {
        return YES;
    }
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = window.windowScene;
        if (scene) {
            UIInterfaceOrientation io = scene.interfaceOrientation;
            if (UIInterfaceOrientationIsPortrait(io) || io == UIInterfaceOrientationPortraitUpsideDown) {
                return YES;
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIInterfaceOrientation io = [UIApplication sharedApplication].statusBarOrientation;
#pragma clang diagnostic pop
    return UIInterfaceOrientationIsPortrait(io);
}

static void stashRequestPortraitGeometryForIPhoneCardWindow(UIWindow *window) {
    if (!window) {
        return;
    }
    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene = window.windowScene;
        if (!scene) {
            return;
        }
        UIWindowSceneGeometryPreferencesIOS *prefs =
            [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
        [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
            STASH_DEBUG_LOG(@"StashNative portrait settle geometry retry: %@", error);
        }];
    }
}

/// After opening from landscape, poll until the scene is portrait or timeout, optionally retrying geometry updates (iOS 16+).
void stashScheduleForcePortraitCardLayoutAfterPortraitSettle(UIWindow *cardWindow,
                                                              BOOL openedFromLandscape,
                                                              NSUInteger sessionToken,
                                                              StashNativeCardInternal *internal,
                                                              void (^onStaleSession)(void),
                                                              void (^onContinueLayout)(void)) {
    if (!openedFromLandscape) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (onContinueLayout) {
                onContinueLayout();
            }
        });
        return;
    }

    __block CFAbsoluteTime t0 = 0;
    __block unsigned geometryRetryPhase = 0;
    __block void (^poll)(void);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
    poll = ^{
        if (internal.presentationSessionToken != sessionToken) {
            if (onStaleSession) {
                onStaleSession();
            }
            return;
        }
        if (t0 == 0) {
            t0 = CFAbsoluteTimeGetCurrent();
        }
        if (stashForcePortraitCardSceneLooksPortrait(cardWindow)) {
            CGRect b = stashSceneCoordinateBoundsForIPhoneCardWindow(cardWindow);
            STASH_DEBUG_LOG(@"StashNative portrait settle ok bounds=%@ session=%lu",
                            NSStringFromCGRect(b), (unsigned long)sessionToken);
            if (onContinueLayout) {
                onContinueLayout();
            }
            return;
        }

        CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - t0;
        if (@available(iOS 16.0, *)) {
            if (elapsed >= kPortraitSettleGeometryRetryFirst && geometryRetryPhase == 0) {
                geometryRetryPhase = 1;
                stashRequestPortraitGeometryForIPhoneCardWindow(cardWindow);
            } else if (elapsed >= kPortraitSettleGeometryRetrySecond && geometryRetryPhase == 1) {
                geometryRetryPhase = 2;
                stashRequestPortraitGeometryForIPhoneCardWindow(cardWindow);
            }
        } else {
            // iOS 15: retry the UIDevice orientation hack at the same intervals.
            if (elapsed >= kPortraitSettleGeometryRetryFirst && geometryRetryPhase == 0) {
                geometryRetryPhase = 1;
                [[UIDevice currentDevice] setValue:@(UIInterfaceOrientationPortrait)
                                            forKey:@"orientation"];
                [UIViewController attemptRotationToDeviceOrientation];
            } else if (elapsed >= kPortraitSettleGeometryRetrySecond && geometryRetryPhase == 1) {
                geometryRetryPhase = 2;
                [[UIDevice currentDevice] setValue:@(UIInterfaceOrientationPortrait)
                                            forKey:@"orientation"];
                [UIViewController attemptRotationToDeviceOrientation];
            }
        }

        if (elapsed >= kPortraitSettleTimeout) {
            CGRect b = stashSceneCoordinateBoundsForIPhoneCardWindow(cardWindow);
            STASH_DEBUG_LOG(@"StashNative portrait settle timeout bounds=%@ session=%lu",
                            NSStringFromCGRect(b), (unsigned long)sessionToken);
            if (onContinueLayout) {
                onContinueLayout();
            }
            return;
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPortraitSettlePollInterval * NSEC_PER_SEC)),
                       dispatch_get_main_queue(),
                       poll);
    };
#pragma clang diagnostic pop

    dispatch_async(dispatch_get_main_queue(), poll);
}

void stashRelayoutIPhoneCardWindowWithTargetBoundsAndProgress(CGRect targetBounds, CGFloat forcedCardExpansionProgress) {
    [[StashNativeCardInternal sharedInstance] relayoutIPhoneCardWindowWithTargetBounds:targetBounds
                                                            forcedCardExpansionProgress:forcedCardExpansionProgress];
}

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
