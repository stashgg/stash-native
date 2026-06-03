//
//  StashNativeCard.m
//  StashNative
//
//  Core implementation: the StashNativeCard public facade plus the StashNativeCardInternal
//  presentation/lifecycle singleton. Cohesive responsibilities live in sibling translation units --
//  Support (pure helpers), Layout (view-utils), WebBridge (JS message dispatch), Orientation
//  (forced-portrait swizzle + keyboard lock), Safari (external browser), Configs (public value
//  types) -- which read this file's stash_/k-prefixed externs. Declarations are split across
//  StashNativeCardPrivate.h, StashNativeCardInternal.h, the per-cluster *.h, and StashNativeCardLogging.h.
//

#import "StashNativeCard.h"
#import "StashNativeCardPrivate.h"
#import "StashNativeCardInternal.h"
#import "StashNativeCardWebBridge.h"
#import "StashNativeCardScripts.h"
#import "StashNativeCardOrientation.h"
#import <SafariServices/SafariServices.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdlib.h>

// Non-ARC compatibility: These warnings are suppressed when compiling without ARC
// (e.g., in game engines like Unreal Engine that manage memory manually).
// ARC builds do not need these suppressions.
#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

#pragma mark - Default Popup Size Multipliers
// Defined early so StashNativePopupSizeConfig (now in StashNativeCardConfigs.m) can use them; non-static
// so StashNativeCardConfigs.m and StashNativeCardViewControllers.m reference them via extern
const CGFloat kPopupPortraitWidthMultiplier = 1.0285;
const CGFloat kPopupPortraitHeightMultiplier = 1.485;
const CGFloat kPopupLandscapeWidthMultiplier = 1.2275445;
const CGFloat kPopupLandscapeHeightMultiplier = 1.1385;

#pragma mark - Private State
// Note: These statics are reset in [StashNativeCardInternal cleanupCardInstance].
// They are file-scope to this translation unit and effectively private to the SDK.

// --- Transient presentation state (reset on each dismiss) ---
static BOOL _callbackWasCalled = NO;              // Ensures dismiss callback fires only once
BOOL stash_isCardCurrentlyPresented = NO;       // Guards against double-presentation
BOOL stash_paymentSuccessHandled = NO;          // Ensures payment result callback fires only once

// --- User-configurable sizing (persists across presentations) ---
BOOL stash_forcePortraitOnCheckout = NO;
// Phone card: portrait = full width + height ratio; landscape = width/height ratios when not forcing portrait
CGFloat stash_cardHeightRatioPortrait = 0.68;
CGFloat stash_cardWidthRatioLandscape = 0.7f;
CGFloat stash_cardHeightRatioLandscape = 0.9f;

// Orientation-specific tablet (iPad) card configuration
CGFloat stash_tabletWidthRatioPortrait = 0.4;
CGFloat stash_tabletHeightRatioPortrait = 0.5;
CGFloat stash_tabletWidthRatioLandscape = 0.3;
CGFloat stash_tabletHeightRatioLandscape = 0.6;

// --- Popup size configuration (reset on cleanup) ---
// File-local: read only inside stash_computePopupFrameForScreenBounds (defined in this TU).
BOOL stash_useCustomPopupSize = NO;
CGFloat stash_customPortraitWidthMultiplier = kPopupPortraitWidthMultiplier;
CGFloat stash_customPortraitHeightMultiplier = kPopupPortraitHeightMultiplier;
CGFloat stash_customLandscapeWidthMultiplier = 1.753635;  // Default custom landscape is wider
CGFloat stash_customLandscapeHeightMultiplier = kPopupLandscapeHeightMultiplier;

// --- Presentation mode flags (reset on cleanup) ---

BOOL stash_usePopupPresentation = NO;
BOOL stash_isCardExpanded = NO;

// --- Landscape / force-portrait orientation flags (phones only; reset on cleanup) ---
/// YES when the card was opened in the current (landscape) orientation without forcing portrait.
/// Card stays at its configured size; expand/collapse have no effect.
BOOL stash_cardIsInLandscape = NO;
/// Safe-area top inset (notch / Dynamic Island) of the active card window, in points.
/// Used to clamp card height so the card never overlaps the notch. Reset to 0 on cleanup.
CGFloat stash_cardSafeAreaTop = 0.0f;

// --- Modal configuration (reset on cleanup) ---
// stash_useModalPresentation is non-static (read by StashNativeCardWebViewDelegates.m); the ratios and
// allowDismiss are file-local (read only by this TU's modal builder + stash_computeModalFrameForScreenBounds).
BOOL stash_useModalPresentation = NO;
static BOOL _modalAllowDismiss = YES;
/** When NO, dialog stays open after onPaymentSuccess/onPaymentFailure. Reset to YES on cleanup. */
BOOL stash_autoCloseOnPaymentEvent = YES;
CGFloat stash_modalPhoneWidthRatioPortrait = 0.9f;
CGFloat stash_modalPhoneHeightRatioPortrait = 0.7f;
CGFloat stash_modalPhoneWidthRatioLandscape = 0.7f;
CGFloat stash_modalPhoneHeightRatioLandscape = 0.85f;
CGFloat stash_modalTabletWidthRatioPortrait = 0.40f;
CGFloat stash_modalTabletHeightRatioPortrait = 0.30f;
CGFloat stash_modalTabletWidthRatioLandscape = 0.30f;
CGFloat stash_modalTabletHeightRatioLandscape = 0.40f;

/** Optional #hex for card/modal chrome; cleared on cleanup. */
NSString *stash_presentationBackgroundColorHex = nil;

#pragma mark - Animation Constants (Apple Pay–style: single duration + spring for consistent feel)

static const CGFloat kSpringDampingDefault = 0.82f;
static const CGFloat kSpringDampingTight = 0.82f;
const CGFloat kAnimationDurationDefault = 0.5f;
static const CGFloat kAnimationDurationFast = 0.5f;
// Non-static for StashNativeCardViewControllers.m
const CGFloat kCornerRadiusDefault = 20.0f;
static const CGFloat kCornerRadiusExpanded = 24.0f;
const CGFloat kDragTrayHeight = 44.0f;

#pragma mark - View Tag Constants
// Non-static for StashNativeCardViewControllers.m
const NSInteger kCardViewTag = 9999;
const NSInteger kDragTrayViewTag = 8888;
const NSInteger kDragHandleViewTag = 8889;

#pragma mark - Handle Bar (Drag Tray) Constants
// Non-static so StashNativeCardViewControllers.m can reference them via extern
const CGFloat kHandleBarWidth = 36.0f;
const CGFloat kHandleBarHeight = 5.0f;
const CGFloat kHandleBarTopInset = 8.0f;
const CGFloat kHandleBarHalfWidth = 18.0f;
static const CGFloat kHandleBarCornerRadius = 3.0f;
const CGFloat kHandleHitAreaInset = 15.0f;

#pragma mark - Overlay / Dismiss Appearance

static const CGFloat kOverlayDismissAlpha = 0.0f;
static const CGFloat kDismissCardAlpha = 0.0f;
static const CGFloat kDismissCardScale = 0.9f;
static const CGFloat kOverlayOpacity = 0.4f;  /* Unified overlay dim (40%) - same on all modes and as Android */
/// Backdrop is this many times larger than the card window (centered) so dimming edges stay off-screen during rotation.
static const CGFloat kIPhoneCardBackdropOverscanFactor = 5.0f;
static const CGFloat kIPhoneLandscapeExpandedHeightRatio = 0.9f;  /* Expand = 90% screen height in landscape */
static const NSTimeInterval kOverlayFadeInDuration = 0.25;

/// Centered frame larger than `windowBounds` so the dimming layer does not show rotating edges during scene orientation changes.
static inline CGRect stashIPhoneCardOverscanBackdropFrameForWindowBounds(CGRect windowBounds) {
    CGFloat w = windowBounds.size.width;
    CGFloat h = windowBounds.size.height;
    if (w <= 0 || h <= 0) {
        return windowBounds;
    }
    CGFloat ow = w * kIPhoneCardBackdropOverscanFactor;
    CGFloat oh = h * kIPhoneCardBackdropOverscanFactor;
    CGFloat cx = CGRectGetMidX(windowBounds);
    CGFloat cy = CGRectGetMidY(windowBounds);
    return CGRectMake(cx - ow * 0.5f, cy - oh * 0.5f, ow, oh);
}

#pragma mark - Snap-Back / Entry Animation (same timing as card animations)

static const CGFloat kSpringDampingSnapBack = 0.82f;
static const NSTimeInterval kSnapBackAnimationDuration = 0.45;
/// Slide-up presentation: duration tuned for sheet feel. Damping 1 + zero velocity avoids spring overshoot
/// past the rest Y (undershoot in UIKit spring briefly lifts the card → visible gap above screen bottom).
static const NSTimeInterval kCardEntrySpringDuration = 0.55;
static const CGFloat kCardEntrySpringDamping = 1.0f;
static const CGFloat kCardEntrySpringVelocity = 0.0f;
/// After overlay fade finishes, brief hold before sheet slide so off-screen WebView can advance load.
static const NSTimeInterval kCardEntryHoldAfterOverlayFadeIn = 0.2;
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

#pragma mark - Shadow (iPhone card vs iPad/popup)

static const CGFloat kShadowOpacityPhone = 0.2f;
static const CGFloat kShadowRadiusPhone = 10.0f;
static const CGFloat kShadowOffsetYPhone = -3.0f;
static const CGFloat kShadowOpacityPopup = 0.15f;
static const CGFloat kShadowRadiusPopup = 12.0f;
static const CGFloat kShadowOffsetYPopup = 4.0f;

#pragma mark - Request (timeout, Accept-Encoding)

static const NSTimeInterval kRequestTimeoutSeconds = 15.0;
static NSString * const kAcceptEncodingHeader = @"gzip, deflate, br";

#pragma mark - Theme (query parameter)

static NSString * const kThemeQueryParamName = @"theme";
static NSString * const kThemeLight = @"light";
static NSString * const kThemeDark = @"dark";

#pragma mark - Ratio Clamp (sizing setters)

static const CGFloat kVerticalPositionThresholdBottom = 0.1f;
static const CGFloat kVerticalPositionThresholdTop = 0.9f;

/// Recursively find the first WKWebView in a view subtree.
static WKWebView *findWebViewInView(UIView *view) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[WKWebView class]]) return (WKWebView *)sub;
        WKWebView *found = findWebViewInView(sub);
        if (found) return found;
    }
    return nil;
}

static NSMutableURLRequest *requestForURL(NSURL *url) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                       timeoutInterval:kRequestTimeoutSeconds];
    [request setValue:kAcceptEncodingHeader forHTTPHeaderField:@"Accept-Encoding"];
    return request;
}

#pragma mark - Timing

static const NSTimeInterval kDismissAnimationDurationPopup = 0.35;

#pragma mark - Spring Velocities (expand/collapse)

static const CGFloat kSpringVelocityExpand = 0.5f;
static const CGFloat kSpringVelocityCollapse = 0.3f;

#pragma mark - iPad SDK expand/collapse (height only, clamped)

/** Base height × this value when expanded via JS (50% growth); clamped by max card height. */
const CGFloat kTabletSdkExpandHeightMultiplier = 1.5f;
/** Matches Android CardConstants.EXPANDED_CARD_HEIGHT_RATIO — max card height when expanding via SDK. */
const CGFloat kExpandedCardHeightScreenRatio = 0.95f;

#pragma mark - Progress Thresholds (corner radius)

static const CGFloat kProgressFullyExpanded = 1.0f;
static const CGFloat kProgressFullyCollapsed = 0.0f;
static const CGFloat kProgressCornerRadiusExpandThreshold = 0.9f;
static const CGFloat kProgressCornerRadiusMidThreshold = 0.5f;

#pragma mark - Gesture Thresholds (iPhone)

static const CGFloat kExpandDragThresholdRatio = 0.15f;
static const CGFloat kCollapseDragThresholdRatio = 0.25f;
static const CGFloat kDismissDragThresholdRatio = 0.4f;
static const CGFloat kExpandVelocityThreshold = -300.0f;
static const CGFloat kCollapseVelocityThreshold = 300.0f;
static const CGFloat kDismissVelocityThreshold = 500.0f;
static const CGFloat kDragDismissTravelRatioForProgress = 0.1f;

#pragma mark - Gesture Thresholds (iPad dismiss)

static const CGFloat kDismissDistanceFromBottomThreshold = 10.0f;
static const CGFloat kDismissTravelRatioThresholdIPad = 0.325f;
static const CGFloat kDismissVelocityThresholdIPad = 1040.0f;

#pragma mark - Gesture-Driven Animation (same duration as card animations)

static const NSTimeInterval kExpandAnimationDuration = 0.45;
static const NSTimeInterval kCollapseAnimationDurationDefault = 0.45;
static const NSTimeInterval kCollapseAnimationDurationFast = 0.45;
static const NSTimeInterval kDismissAnimationDurationFast = 0.35;
static const NSTimeInterval kDismissAnimationDurationNormal = 0.45;
static const CGFloat kVelocityDivisorForSpring = 1000.0f;
static const CGFloat kVelocityThresholdForFastCollapse = 600.0f;
static const CGFloat kVelocityThresholdForFastDismiss = 1000.0f;

#pragma mark - Popup Frame (OrientationLockedViewController)
// Non-static so StashNativeCardViewControllers.m can reference them via extern
const CGFloat kPopupBaseSizePercentageIPad = 0.5f;
const CGFloat kPopupBaseSizePercentagePhone = 0.75f;
const CGFloat kPopupBaseSizeMinIPad = 400.0f;
const CGFloat kPopupBaseSizeMinPhone = 300.0f;
const CGFloat kPopupBaseSizeMax = 500.0f;
const CGFloat kFallbackTabletCardWidth = 600.0f;
const CGFloat kFallbackTabletCardHeight = 700.0f;
const CGFloat kTabletMinHeight = 500.0f;
const NSTimeInterval kPopupFrameAnimationDuration = 0.5;

#pragma mark - Message Handler Registration (name string values are defined in StashNativeCardWebBridge.m)

// All script-message handler names, registered and torn down together (order does not matter).
// Single source so adding a handler cannot drift between the add and remove sites.
static NSArray<NSString *> *stashAllMessageHandlerNames(void) {
    return @[kMessageHandlerPaymentSuccess, kMessageHandlerPaymentFailure, kMessageHandlerPurchaseProcessing,
             kMessageHandlerOptin, kMessageHandlerExpand, kMessageHandlerCollapse, kMessageHandlerExternalPayment,
             kMessageHandlerWindowClose, kMessageHandlerPageReady];
}

#pragma mark - Associated Object Keys

static NSString * const kAssociatedKeyWebViewDelegate = @"webViewDelegate";
static NSString * const kAssociatedKeyWebViewUIDelegate = @"webViewUIDelegate";
NSString * const StashNativeAssociatedKeyOverlayView = @"overlayView";  // extern for StashNativeCardViewControllers.m
static NSString * const kAssociatedKeyLoadingView = @"loadingView";
static NSString * const kAssociatedKeyCardView = @"cardView";
static NSString * const kAssociatedKeyInitialCardHeight = @"initialCardHeight";

#pragma mark - Helper Function Prototypes

static UIRectCorner getCornersToRoundForPosition(CGFloat verticalPosition, BOOL isiPad);
static NSString* appendThemeQueryParameter(NSString* url);
static void runWithoutImplicitAnimations(void (^block)(void));
static UIView* createOverlayViewWithFrame(CGRect frame, UIView *parentView, NSInteger index, UIViewController *vc);
static void applyCardShadowToLayer(CALayer *layer, BOOL phoneStyle);
static void setOverlayToDismissAppearance(UIView *overlayView);

#pragma mark - StashNativeCardInternal

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
    if (stash_isRunningOniPad() && [gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
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
        stash_isCardCurrentlyPresented = NO;
        
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
    if (stash_isRunningOniPad()) {
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

            for (NSString *handlerName in stashAllMessageHandlerNames()) {
                [webView.configuration.userContentController removeScriptMessageHandlerForName:handlerName];
            }
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
        } else {
            if (self.portraitWindow.rootViewController) {
                [self.portraitWindow.rootViewController dismissViewControllerAnimated:NO completion:nil];
            }
            [self teardownPresentationWindow:self.portraitWindow];
            self.portraitWindow = nil;
        }
    }
    
    self.currentPresentedVC = nil;
    self.activeWebViewLoadDelegate = nil;
    self.activeWebViewUIDelegate = nil;
    self.isDismissingCard = NO;
    self.isPurchaseProcessing = NO;
    stash_isCardExpanded = NO;
    stash_isCardCurrentlyPresented = NO;
    stash_usePopupPresentation = NO;
    stash_useModalPresentation = NO;
    stash_useCustomPopupSize = NO;
    _callbackWasCalled = NO;
    stash_paymentSuccessHandled = NO;
    stash_autoCloseOnPaymentEvent = YES;
    stash_presentationBackgroundColorHex = nil;
    stash_cardIsInLandscape = NO;
    stash_cardSafeAreaTop = 0.0f;
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
    
    CGFloat animationDuration = (stash_usePopupPresentation || stash_useModalPresentation) ? kDismissAnimationDurationPopup : kDismissAnimationDurationNormal;
    
    [UIView animateWithDuration:animationDuration delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        if (stash_useModalPresentation) {
            // Modal: fade out only (no scale to avoid webview shift)
            UIView *cardView = objc_getAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyCardView);
            if (!cardView) cardView = [containerVC.view viewWithTag:kCardViewTag];
            UIView *targetView = cardView ? cardView : containerVC.view;
            targetView.alpha = 0.0;
        } else if (stash_usePopupPresentation || stash_isRunningOniPad()) {
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
    handleView.isAccessibilityElement = NO;  // purely visual drag affordance
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

    stash_isCardExpanded = YES;

    CGRect screenBounds = self.portraitWindow ? [self referenceScreenBoundsForIPhoneCardLayout] : [UIScreen mainScreen].bounds;
    CGFloat safeTop = stash_getSafeAreaTopForView(cardView);
    CGRect fullScreenFrame;
    if ([self isIPhoneLandscapeCurrentOrientation]) {
        // Height-only expand in landscape: use same canonical collapsed frame (includes min clamp)
        CGRect collapsedFrame = stash_computePhoneCardFrameForBoundsAndOrientation(screenBounds, YES);
        CGFloat expW = collapsedFrame.size.width;
        CGFloat expH = screenBounds.size.height * kIPhoneLandscapeExpandedHeightRatio;
        CGFloat expX = (screenBounds.size.width - expW) / 2.0f;
        CGFloat expY = screenBounds.size.height - expH;
        if (expY < safeTop) expY = safeTop;
        fullScreenFrame = CGRectMake(expX, expY, expW, expH);
    } else {
        fullScreenFrame = CGRectMake(0, safeTop, screenBounds.size.width, screenBounds.size.height - safeTop);
    }

    WKWebView *webView = stash_switchWebViewToFrameLayoutInCardView(cardView);

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

        stash_updateDragTrayAndHandleInCardView(cardView, fullScreenFrame.size.width);
        
        [self updateCustomFrameIfSupported:fullScreenFrame forViewController:nil];
        
        cardView.backgroundColor = stash_sheetBackgroundUIColor();
        
        [cardView layoutIfNeeded];
    } completion:^(BOOL finished) {
        CGFloat radius = stash_isRunningOniPad() ? kCornerRadiusExpanded : kCornerRadiusDefault;
        CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, radius);
        cardView.layer.mask = maskLayer;
        
        [self setSkipLayoutDuringInitialSetup:NO forViewController:self.currentPresentedVC];
    }];
}

- (void)collapseCardToOriginal {
    UIView *cardView = [self cardViewForCurrentPresentation];
    if (!cardView) return;

    stash_isCardExpanded = NO;

    CGRect screenBounds = self.portraitWindow ? [self referenceScreenBoundsForIPhoneCardLayout] : [UIScreen mainScreen].bounds;
    CGFloat width, height;

    CGRect collapsedFrame;
    if (stash_isRunningOniPad()) {
        CGSize cardSize = stash_calculateiPadCardSize(screenBounds);
        width = cardSize.width;
        height = cardSize.height;
        CGFloat x = (screenBounds.size.width - width) / 2;
        CGFloat finalY = (screenBounds.size.height - height) / 2;
        collapsedFrame = CGRectMake(x, finalY, width, height);
    } else {
        collapsedFrame = stash_computePhoneCardFrameForBoundsAndOrientation(screenBounds, [self isIPhoneLandscapeCurrentOrientation]);
        width = collapsedFrame.size.width;
        height = collapsedFrame.size.height;
    }

    WKWebView *webView = stash_switchWebViewToFrameLayoutInCardView(cardView);

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

        stash_updateDragTrayAndHandleInCardView(cardView, width);

        [self updateCustomFrameIfSupported:collapsedFrame forViewController:nil];
        
        [cardView layoutIfNeeded];
    } completion:^(BOOL finished) {
        UIRectCorner corners = getCornersToRoundForPosition(kProgressFullyExpanded, stash_isRunningOniPad());
        CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, corners, kCornerRadiusDefault);
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
        stash_isCardExpanded = NO;
        if (cardView) {
            UIRectCorner corners = getCornersToRoundForPosition(kProgressFullyExpanded, stash_isRunningOniPad());
            CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, corners, kCornerRadiusDefault);
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
        stash_isCardExpanded = NO;
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
        stash_isCardExpanded = YES;
        if (cardView) {
            if (stash_isRunningOniPad()) {
                CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, UIRectCornerAllCorners, kCornerRadiusDefault);
                cardView.layer.mask = maskLayer;
            } else {
                CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
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
        stash_isCardExpanded = YES;
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

// Collapsed and expanded card frames for the current device/orientation. The expand/collapse
// interpolation, current-progress read, and per-frame relayout all derive from these two rects.
- (void)collapsedRect:(CGRect *)outCollapsed expandedRect:(CGRect *)outExpanded forCardView:(UIView *)cardView {
    CGRect screenBounds = self.portraitWindow ? [self referenceScreenBoundsForIPhoneCardLayout] : [UIScreen mainScreen].bounds;
    CGFloat safeTop = stash_getSafeAreaTopForView(cardView);

    CGFloat collapsedWidth, collapsedHeight, collapsedX, collapsedY;
    CGFloat expandedWidth, expandedHeight, expandedX, expandedY;

    if (stash_isRunningOniPad()) {
        CGSize cardSize = stash_calculateiPadCardSize(screenBounds);
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
        if (self.portraitWindow && stash_forcePortraitOnCheckout) {
            collapsedFrame = [self collapsedPhoneCardFrameForReferenceBounds:screenBounds];
        } else {
            collapsedFrame = stash_computePhoneCardFrameForBoundsAndOrientation(screenBounds, [self isIPhoneLandscapeCurrentOrientation]);
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

    if (outCollapsed) *outCollapsed = CGRectMake(collapsedX, collapsedY, collapsedWidth, collapsedHeight);
    if (outExpanded) *outExpanded = CGRectMake(expandedX, expandedY, expandedWidth, expandedHeight);
}

- (void)updateCardExpansionProgress:(CGFloat)progress cardView:(UIView *)cardView {
    if (!cardView) return;

    progress = MAX(0.0, MIN(1.0, progress));

    CGRect frame = [self frameForExpansionProgress:progress cardView:cardView];
    CGFloat currentWidth = frame.size.width;
    cardView.frame = frame;

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

    stash_updateDragTrayAndHandleInCardView(cardView, currentWidth);

    if (stash_isRunningOniPad()) {
        CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, UIRectCornerAllCorners, kCornerRadiusDefault);
        cardView.layer.mask = maskLayer;
    } else {
        if (progress > kProgressCornerRadiusExpandThreshold) {
            CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
            cardView.layer.mask = maskLayer;
        } else if (progress > kProgressCornerRadiusMidThreshold) {
            UIRectCorner corners = getCornersToRoundForPosition(kProgressFullyExpanded, NO);
            corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
            CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, corners, kCornerRadiusDefault);
            cardView.layer.mask = maskLayer;
        } else {
            UIRectCorner corners = getCornersToRoundForPosition(kProgressFullyExpanded, NO);
            CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, corners, kCornerRadiusDefault);
            cardView.layer.mask = maskLayer;
        }
    }
}

- (CGFloat)currentExpansionProgressForCardView:(UIView *)cardView {
    if (!cardView) return 0.0f;
    CGRect collapsed, expanded;
    [self collapsedRect:&collapsed expandedRect:&expanded forCardView:cardView];
    CGFloat collapsedHeight = collapsed.size.height;
    CGFloat expandedHeight = expanded.size.height;
    CGFloat currentHeight = cardView.frame.size.height;
    CGFloat heightRange = expandedHeight - collapsedHeight;
    if (heightRange <= 0.0f) return 0.0f;
    CGFloat progress = (currentHeight - collapsedHeight) / heightRange;
    return (CGFloat)MAX(0.0, MIN(1.0, (double)progress));
}

- (CGRect)frameForExpansionProgress:(CGFloat)progress cardView:(UIView *)cardView {
    if (!cardView) return CGRectZero;
    progress = (CGFloat)MAX(0.0, MIN(1.0, (double)progress));
    CGRect collapsed, expanded;
    [self collapsedRect:&collapsed expandedRect:&expanded forCardView:cardView];
    CGFloat w = collapsed.size.width + (expanded.size.width - collapsed.size.width) * progress;
    CGFloat h = collapsed.size.height + (expanded.size.height - collapsed.size.height) * progress;
    CGFloat x = collapsed.origin.x + (expanded.origin.x - collapsed.origin.x) * progress;
    CGFloat y;
    if (stash_isRunningOniPad()) {
        y = collapsed.origin.y + (expanded.origin.y - collapsed.origin.y) * progress;
    } else {
        // iPhone: keep bottom of card anchored to bottom of screen every frame (no gap)
        CGRect screenBounds = self.portraitWindow ? [self referenceScreenBoundsForIPhoneCardLayout] : [UIScreen mainScreen].bounds;
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

    if (stash_usePopupPresentation || stash_useModalPresentation || stash_isRunningOniPad()) return;
    if (stash_isCardExpanded) return;
    
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
    self.initialY = cardView.frame.origin.y;
    
    if (!stash_isRunningOniPad()) {
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyInitialCardHeight, @(cardView.frame.size.height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        stash_switchWebViewToFrameLayoutInCardView(cardView);
    }
    
    [self setSkipLayoutDuringInitialSetup:YES forViewController:self.currentPresentedVC];
}
    
- (void)handleDragGestureChanged:(UIPanGestureRecognizer *)gesture cardView:(UIView *)cardView {
    CGPoint translation = [gesture translationInView:self.portraitWindow ? self.portraitWindow : cardView.superview];
    CGFloat currentTravel = translation.y;
    CGFloat screenHeight = self.portraitWindow ? self.portraitWindow.bounds.size.height : cardView.superview.bounds.size.height;
    CGFloat height = cardView.frame.size.height;
    
    if (stash_isRunningOniPad()) {
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
        CGFloat safeTop = stash_getSafeAreaTopForView(cardView);
        BOOL landscapeHeightOnly = [self isIPhoneLandscapeCurrentOrientation];
        CGRect collapsedFrame;
        if (self.portraitWindow && stash_forcePortraitOnCheckout) {
            collapsedFrame = [self collapsedPhoneCardFrameForReferenceBounds:screenBounds];
        } else {
            collapsedFrame = stash_computePhoneCardFrameForBoundsAndOrientation(screenBounds, landscapeHeightOnly);
        }
        CGFloat collapsedWidth = collapsedFrame.size.width;
        CGFloat collapsedHeight = collapsedFrame.size.height;
        CGFloat collapsedX = collapsedFrame.origin.x;
        CGFloat expandedHeight = landscapeHeightOnly ? (screenBounds.size.height * kIPhoneLandscapeExpandedHeightRatio) : (screenBounds.size.height - safeTop);
        CGFloat currentProgress = 0.0;
        
        if (currentTravel < 0) {
            if (stash_isCardExpanded) {
                currentProgress = 1.0;
            } else if (stash_cardIsInLandscape) {
                // Landscape card stays at its configured size; don't show expand visual feedback.
                currentProgress = 0.0;
            } else {
                CGFloat dragAmount = fabs(currentTravel);
                CGFloat heightRange = expandedHeight - collapsedHeight;
                currentProgress = MIN(1.0, dragAmount / heightRange);
            }
        } else if (currentTravel > 0) {
            if (stash_isCardExpanded) {
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
    if (!stash_isRunningOniPad()) {
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
    
    if (stash_isRunningOniPad()) {
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
            if (!stash_isCardExpanded && !stash_cardIsInLandscape) shouldExpand = YES;
        } else if (currentTravel > 0) {
            if (stash_isCardExpanded) {
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
                [self cleanupCardInstance];
                [self callDelegateCallbackOnce];
                return;
            }
            
            [self setSkipLayoutDuringInitialSetup:NO forViewController:self.currentPresentedVC];
            
            UIViewController *vcToDismiss = self.currentPresentedVC;
            [vcToDismiss dismissViewControllerAnimated:NO completion:^{
                if (self.currentPresentedVC == vcToDismiss) {
                    [self cleanupCardInstance];
                    [self callDelegateCallbackOnce];
                }
            }];
        }];
    } else {
        // Snap back: iPad to center, iPhone to expanded/collapsed
        if (stash_isRunningOniPad()) {
            CGRect screenBounds = [UIScreen mainScreen].bounds;
            CGRect targetFrame = stashFrameForIPadSdkCard(screenBounds, cardView);
            CGFloat originalWidth = targetFrame.size.width;

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
            if (stash_isCardExpanded) {
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

#pragma mark - WKScriptMessageHandler

// The WKScriptMessageHandler bridge below dispatches one message to one of these per-message
// handlers. Each handler is the verbatim body of its former else-if branch; the dispatcher keeps
// the main-frame gate and the mutually-exclusive routing, so exactly one runs per message.

#pragma mark - iPhone card window bounds / relayout

- (CGRect)referenceScreenBoundsForIPhoneCardLayout {
    if (self.portraitWindow) {
        return self.portraitWindow.bounds;
    }
    return [UIScreen mainScreen].bounds;
}

- (CGRect)collapsedPhoneCardFrameForReferenceBounds:(CGRect)actualBounds {
    if (stash_forcePortraitOnCheckout) {
        CGFloat apw = MIN(actualBounds.size.width, actualBounds.size.height);
        CGFloat aph = MAX(actualBounds.size.width, actualBounds.size.height);
        BOOL rotationSucceeded = actualBounds.size.width < actualBounds.size.height;
        CGRect r;
        if (rotationSucceeded) {
            r = stash_computePhoneCardFrameForBoundsAndOrientation(actualBounds, NO);
        } else {
            CGFloat cardWidth = apw;
            CGFloat cardHeight = aph * stash_cardHeightRatioPortrait;
            CGFloat cardX = (actualBounds.size.width - cardWidth) / 2.0;
            CGFloat cardFinalY = actualBounds.size.height - cardHeight;
            r = CGRectMake(cardX, cardFinalY, cardWidth, cardHeight);
        }
        if (r.origin.y < stash_cardSafeAreaTop) {
            CGFloat cardH = actualBounds.size.height - stash_cardSafeAreaTop;
            r = CGRectMake(r.origin.x, stash_cardSafeAreaTop, r.size.width, cardH);
        }
        if (r.origin.y < 0) {
            r = CGRectMake(r.origin.x, 0, r.size.width, r.size.height);
        }
        return r;
    }
    BOOL isLandscape = actualBounds.size.width > actualBounds.size.height;
    return stash_computePhoneCardFrameForBoundsAndOrientation(actualBounds, isLandscape);
}

- (void)relayoutIPhoneCardWindowWithTargetBounds:(CGRect)targetBounds forcedCardExpansionProgress:(CGFloat)forcedProgress {
    if (!stash_isCardCurrentlyPresented || !self.portraitWindow) {
        return;
    }
    if (stash_isRunningOniPad()) {
        return;
    }
    if (stash_usePopupPresentation || stash_useModalPresentation) {
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
        if (fresh > 0 || stash_cardSafeAreaTop == 0) {
            stash_cardSafeAreaTop = fresh;
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
    stash_switchWebViewToFrameLayoutInCardView(cardView);
    CGFloat p;
    if (forcedProgress >= 0.0 && forcedProgress <= 1.0) {
        p = (CGFloat)forcedProgress;
    } else {
        p = stash_isCardExpanded ? 1.0f : [self currentExpansionProgressForCardView:cardView];
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
    if (stash_isRunningOniPad() || stash_usePopupPresentation || stash_useModalPresentation) {
        return;
    }
    // Force-portrait checkout: the system keyboard can still follow the host when the device rotates.
    // Dismiss editing so the next tap can present the keyboard in a clean portrait state.
    if (stash_forcePortraitOnCheckout && self.isIPhoneCardKeyboardVisible) {
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
        if (stash_forcePortraitOnCheckout && strongSelf.isIPhoneCardKeyboardVisible) {
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

@end

// Creates and wires the load + UI delegates for a checkout WKWebView (the setup that is identical
// across all present* builders) and tracks them on the internal singleton. Returns the load delegate
// so the caller can drive the initial load. Per-builder associated objects (cardView / loadingView)
// stay in each builder.
static WebViewLoadDelegate *stashAttachCheckoutDelegates(WKWebView *webView,
                                                         UIView *loadingView,
                                                         UIViewController *containerVC,
                                                         StashNativeCardInternal *internal) {
    WebViewLoadDelegate *delegate = [[WebViewLoadDelegate alloc] initWithWebView:webView
                                                                     loadingView:loadingView
                                                                   retryArmDelay:0.0
                                                        presentationSessionToken:internal.presentationSessionToken];
    webView.navigationDelegate = delegate;
    WebViewUIDelegate *uiDelegate = [[WebViewUIDelegate alloc] init];
    webView.UIDelegate = uiDelegate;
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewDelegate, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewUIDelegate, uiDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    internal.activeWebViewLoadDelegate = delegate;
    internal.activeWebViewUIDelegate = uiDelegate;
    return delegate;
}

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
    if (stash_forcePortraitOnCheckout) {
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
static void stashScheduleForcePortraitCardLayoutAfterPortraitSettle(UIWindow *cardWindow,
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

#pragma mark - Helper Functions

static UIRectCorner getCornersToRoundForPosition(CGFloat verticalPosition, BOOL isiPad) {
    if (isiPad) {
        return UIRectCornerAllCorners;
    }
    if (verticalPosition < kVerticalPositionThresholdBottom) {
        return UIRectCornerBottomLeft | UIRectCornerBottomRight;
    } else if (verticalPosition > kVerticalPositionThresholdTop) {
        return UIRectCornerTopLeft | UIRectCornerTopRight;
    }
    return UIRectCornerAllCorners;
}

static void runWithoutImplicitAnimations(void (^block)(void)) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (block) block();
    [CATransaction commit];
}

static UIView* createOverlayViewWithFrame(CGRect frame, UIView *parentView, NSInteger index, UIViewController *vc) {
    UIView *overlayView = [[UIView alloc] initWithFrame:frame];
    overlayView.backgroundColor = [UIColor clearColor];
    overlayView.userInteractionEnabled = YES;
    overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parentView insertSubview:overlayView atIndex:index];
    if (vc) {
        objc_setAssociatedObject(vc, (__bridge const void *)StashNativeAssociatedKeyOverlayView, overlayView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return overlayView;
}

static void applyCardShadowToLayer(CALayer *layer, BOOL phoneStyle) {
    if (!layer) return;
    layer.shadowColor = [UIColor blackColor].CGColor;
    if (phoneStyle) {
        layer.shadowOffset = CGSizeMake(0, kShadowOffsetYPhone);
        layer.shadowOpacity = kShadowOpacityPhone;
        layer.shadowRadius = kShadowRadiusPhone;
    } else {
        layer.shadowOffset = CGSizeMake(0, kShadowOffsetYPopup);
        layer.shadowOpacity = kShadowOpacityPopup;
        layer.shadowRadius = kShadowRadiusPopup;
    }
}

static void setOverlayToDismissAppearance(UIView *overlayView) {
    if (overlayView) {
        overlayView.backgroundColor = [UIColor colorWithWhite:kOverlayDismissAlpha alpha:kOverlayDismissAlpha];
    }
}

static NSString* appendThemeQueryParameter(NSString* url) {
    if (url == nil || url.length == 0) {
        return url;
    }

    NSString *theme = stash_effectiveThemeIsDark() ? kThemeDark : kThemeLight;

    NSURLComponents *components = [NSURLComponents componentsWithString:url];
    if (components == nil) {
        NSString *separator = [url containsString:@"?"] ? @"&" : @"?";
        return [NSString stringWithFormat:@"%@%@%@=%@", url, separator, kThemeQueryParamName, theme];
    }
    
    NSMutableArray *queryItems = [NSMutableArray arrayWithArray:components.queryItems ?: @[]];
    
    NSMutableArray *filteredItems = [NSMutableArray array];
    for (NSURLQueryItem *item in queryItems) {
        if (![item.name isEqualToString:kThemeQueryParamName]) {
            [filteredItems addObject:item];
        }
    }
    
    [filteredItems addObject:[NSURLQueryItem queryItemWithName:kThemeQueryParamName value:theme]];
    components.queryItems = filteredItems;
    
    return components.URL.absoluteString;
}

#pragma mark - StashNativeCard Implementation

@interface StashNativeCard ()
@property (nonatomic, assign) BOOL isCardExpanded;
@end

// ============================================================================

@implementation StashNativeCard

+ (instancetype)sharedInstance {
    static StashNativeCard *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[StashNativeCard alloc] init];
    });
    return sharedInstance;
}

+ (NSString *)sdkVersion {
    return @"2.3.0";
}

- (instancetype)init {
    self = [super init];
    if (self) {
    }
    return self;
}

// These getters reflect presentation state that the SDK mutates on the main thread.
// Read them from the main thread for a coherent value; an off-main read may see a
// stale value during a presentation/teardown transition.
- (BOOL)isCurrentlyPresented {
    return stash_isCardCurrentlyPresented;
}

- (BOOL)isPurchaseProcessing {
    return [StashNativeCardInternal sharedInstance].isPurchaseProcessing;
}

// ============================================================================
// openCardWithURL:config: (applies config to static sizing, then opens)
// ============================================================================

// Clamps a caller-supplied size ratio to the documented [0.1, 1.0] range (matches Android).
static inline CGFloat stashClampRatio(CGFloat r) {
    return MAX((CGFloat)0.1, MIN((CGFloat)1.0, r));
}

// Popup multipliers may exceed 1.0; only reject degenerate (<=0 or NaN) values, falling back to the default.
static inline CGFloat stashSanitizePopupMultiplier(CGFloat v, CGFloat fallback) {
    return (isnan(v) || v <= 0.0) ? fallback : v;
}

- (void)openCardWithURL:(NSString *)url config:(StashNativeCardConfig *)config {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openCardWithURL:url config:config]; });
        return;
    }
    if (url == nil || url.length == 0) {
        return;
    }
    // Reject a second open before mutating config statics, so a rejected open
    // cannot corrupt the live card (openURLInternal: also guards after the main hop).
    if (stash_isCardCurrentlyPresented) {
        return;
    }

    stash_autoCloseOnPaymentEvent = config ? config.autoClose : YES;

    if (config) {
        stash_forcePortraitOnCheckout = config.forcePortrait;
        stash_cardHeightRatioPortrait = stashClampRatio(config.cardHeightRatioPortrait);
        stash_cardWidthRatioLandscape = stashClampRatio(config.cardWidthRatioLandscape);
        stash_cardHeightRatioLandscape = stashClampRatio(config.cardHeightRatioLandscape);
        stash_tabletWidthRatioPortrait = stashClampRatio(config.tabletWidthRatioPortrait);
        stash_tabletHeightRatioPortrait = stashClampRatio(config.tabletHeightRatioPortrait);
        stash_tabletWidthRatioLandscape = stashClampRatio(config.tabletWidthRatioLandscape);
        stash_tabletHeightRatioLandscape = stashClampRatio(config.tabletHeightRatioLandscape);
        NSString *ch = config.backgroundColor;
        ch = ch ? [ch stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
        stash_presentationBackgroundColorHex = (ch.length > 0) ? [ch copy] : nil;
    } else {
        stash_presentationBackgroundColorHex = nil;
    }

    stash_usePopupPresentation = NO;
    stash_useModalPresentation = NO;
    [self openURLInternal:url];
}

- (void)openPopupWithURL:(NSString *)url {
    [self openPopupWithURL:url sizeConfig:nil];
}

- (void)openPopupWithURL:(NSString *)url sizeConfig:(StashNativePopupSizeConfig *)sizeConfig {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openPopupWithURL:url sizeConfig:sizeConfig]; });
        return;
    }
    if (url == nil || url.length == 0) {
        return;
    }
    if (stash_isCardCurrentlyPresented) {
        return;
    }

    stash_presentationBackgroundColorHex = nil;

    stash_usePopupPresentation = YES;
    
    if (sizeConfig) {
        stash_useCustomPopupSize = YES;
        stash_customPortraitWidthMultiplier = stashSanitizePopupMultiplier(sizeConfig.portraitWidthMultiplier, kPopupPortraitWidthMultiplier);
        stash_customPortraitHeightMultiplier = stashSanitizePopupMultiplier(sizeConfig.portraitHeightMultiplier, kPopupPortraitHeightMultiplier);
        stash_customLandscapeWidthMultiplier = stashSanitizePopupMultiplier(sizeConfig.landscapeWidthMultiplier, kPopupLandscapeWidthMultiplier);
        stash_customLandscapeHeightMultiplier = stashSanitizePopupMultiplier(sizeConfig.landscapeHeightMultiplier, kPopupLandscapeHeightMultiplier);
    } else {
        stash_useCustomPopupSize = NO;
    }
    
    [self openURLInternal:url];
}

- (void)openModalWithURL:(NSString *)url {
    [self openModalWithURL:url config:nil];
}

- (void)openModalWithURL:(NSString *)url config:(StashNativeModalConfig *)config {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openModalWithURL:url config:config]; });
        return;
    }
    if (url == nil || url.length == 0) {
        return;
    }
    if (stash_isCardCurrentlyPresented) {
        return;
    }

    stash_autoCloseOnPaymentEvent = config ? config.autoClose : YES;

    stash_usePopupPresentation = NO;
    stash_useModalPresentation = YES;

    if (config) {
        _modalAllowDismiss = config.allowDismiss;
        stash_modalPhoneWidthRatioPortrait = stashClampRatio(config.phoneWidthRatioPortrait);
        stash_modalPhoneHeightRatioPortrait = stashClampRatio(config.phoneHeightRatioPortrait);
        stash_modalPhoneWidthRatioLandscape = stashClampRatio(config.phoneWidthRatioLandscape);
        stash_modalPhoneHeightRatioLandscape = stashClampRatio(config.phoneHeightRatioLandscape);
        stash_modalTabletWidthRatioPortrait = stashClampRatio(config.tabletWidthRatioPortrait);
        stash_modalTabletHeightRatioPortrait = stashClampRatio(config.tabletHeightRatioPortrait);
        stash_modalTabletWidthRatioLandscape = stashClampRatio(config.tabletWidthRatioLandscape);
        stash_modalTabletHeightRatioLandscape = stashClampRatio(config.tabletHeightRatioLandscape);
        NSString *ch = config.backgroundColor;
        ch = ch ? [ch stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
        stash_presentationBackgroundColorHex = (ch.length > 0) ? [ch copy] : nil;
    } else {
        // Match StashNativeModalConfig -init defaults exactly.
        _modalAllowDismiss = YES;
        stash_modalPhoneWidthRatioPortrait = 0.80f;
        stash_modalPhoneHeightRatioPortrait = 0.50f;
        stash_modalPhoneWidthRatioLandscape = 0.50f;
        stash_modalPhoneHeightRatioLandscape = 0.80f;
        stash_modalTabletWidthRatioPortrait = 0.40f;
        stash_modalTabletHeightRatioPortrait = 0.30f;
        stash_modalTabletWidthRatioLandscape = 0.30f;
        stash_modalTabletHeightRatioLandscape = 0.40f;
        stash_presentationBackgroundColorHex = nil;
    }

    [self openURLInternal:url];
}

- (void)openURLInternal:(NSString *)url {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self openURLInternal:url];
        });
        return;
    }
    if (stash_isCardCurrentlyPresented) {
        return;
    }
    
    NSString *urlWithTheme = appendThemeQueryParameter(url);
    [self openInCardUI:urlWithTheme];
}

- (void)openInCardUI:(NSString *)url {
    StashNativeCardInternal *sessionInternal = [StashNativeCardInternal sharedInstance];
    sessionInternal.presentationSessionToken++;
    sessionInternal.isDismissingCard = NO;
    STASH_DEBUG_LOG(@"StashNativeRetryTrace open card session=%lu", (unsigned long)sessionInternal.presentationSessionToken);

    // Reset state
    stash_isCardCurrentlyPresented = YES;
    _callbackWasCalled = NO;
    stash_paymentSuccessHandled = NO;
    stash_isCardExpanded = NO;

    // Determine phone-only orientation flags (tablets always use normal expand/collapse logic).
    if (!stash_isRunningOniPad() && !stash_useModalPresentation && !stash_usePopupPresentation) {
        CGRect sb = [UIScreen mainScreen].bounds;
        BOOL isLandscape = sb.size.width > sb.size.height;
        stash_cardIsInLandscape = !stash_forcePortraitOnCheckout && isLandscape;
    } else {
        stash_cardIsInLandscape = NO;
    }
    
    // Dispatch to appropriate presentation method based on device type
    if (stash_useModalPresentation) {
        [self presentModalWithURL:url];
    } else if (stash_usePopupPresentation) {
        [self presentPopupWithURL:url];
    } else if (stash_isRunningOniPad()) {
        [self presentiPadModalWithURL:url];
    } else if (stash_forcePortraitOnCheckout) {
        [self presentIPhoneCardWithURL:url];
    } else {
        [self presentIPhoneCardInCurrentOrientationWithURL:url];
    }
}

#pragma mark - iPhone Card Presentation (Apple Pay Style)

- (void)presentIPhoneCardWithURL:(NSString *)url {
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];

    // Unlock portrait in the AppDelegate delegate method so iOS 13–15 and landscape-locked
    // game engines (Unity, Unreal) allow the portrait rotation, unless the integrator has
    // opted out to handle orientation unlocking themselves.
    if (!self.disableAutoOrientationUnlock) {
        stashInstallOrientationSwizzleIfNeeded();
    }

    // Store previous key window
    internal.previousKeyWindow = stash_getKeyWindow();
    
    // Get current screen bounds and determine orientation
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    BOOL isLandscape = screenBounds.size.width > screenBounds.size.height;
    
    // Calculate portrait dimensions
    CGFloat portraitWidth = isLandscape ? screenBounds.size.height : screenBounds.size.width;
    CGFloat portraitHeight = isLandscape ? screenBounds.size.width : screenBounds.size.height;
    CGRect portraitBounds = CGRectMake(0, 0, portraitWidth, portraitHeight);
    
    // Create the window - use portrait bounds directly
    // When the window becomes key with a portrait-only VC, iOS should rotate
    UIWindow *cardWindow = [[UIWindow alloc] initWithFrame:portraitBounds];
    stash_attachWindowToKeyWindowScene(cardWindow, internal.previousKeyWindow);
    cardWindow.windowLevel = UIWindowLevelAlert;
    cardWindow.backgroundColor = [UIColor clearColor];
    cardWindow.hidden = YES;
    internal.portraitWindow = cardWindow;
    
    // Create container view controller (forces portrait)
    IPhoneCardViewController *containerVC = [[IPhoneCardViewController alloc] init];
    containerVC.modalPresentationStyle = UIModalPresentationFullScreen;
    containerVC.view.backgroundColor = [UIColor clearColor];
    containerVC.view.frame = portraitBounds;
    containerVC.skipLayoutDuringInitialSetup = YES;
    
    // Set as root VC BEFORE making visible - this helps iOS recognize orientation preference
    cardWindow.rootViewController = containerVC;
    internal.currentPresentedVC = containerVC;
    
    // Capture current orientation for restoration on dismiss, then request portrait.
    // If already portrait, store MaskAll so dismiss unlocks normally without forcing a rotation.
    // If landscape, store the specific landscape mask so dismiss rotates back.
    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene = cardWindow.windowScene;
        if (scene) {
            UIInterfaceOrientation cur = scene.interfaceOrientation;
            if (UIInterfaceOrientationIsLandscape(cur)) {
                internal.previousSceneOrientationMask = stashOrientationMaskForOrientation(cur);
            } else {
                // Already portrait -- restore should unlock all, not lock to portrait.
                internal.previousSceneOrientationMask = UIInterfaceOrientationMaskAll;
            }
            UIWindowSceneGeometryPreferencesIOS *prefs = [[UIWindowSceneGeometryPreferencesIOS alloc]
                initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
            [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
                STASH_DEBUG_LOG(@"StashNative portrait request failed: %@", error);
            }];
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIInterfaceOrientation cur = [[UIApplication sharedApplication] statusBarOrientation];
#pragma clang diagnostic pop
        if (UIInterfaceOrientationIsLandscape(cur)) {
            internal.previousSceneOrientationMask = stashOrientationMaskForOrientation(cur);
        } else {
            internal.previousSceneOrientationMask = UIInterfaceOrientationMaskAll;
        }
        [[UIDevice currentDevice] setValue:@(UIInterfaceOrientationPortrait) forKey:@"orientation"];
        [UIViewController attemptRotationToDeviceOrientation];
    }
    
    // Make window visible after rotation request.
    cardWindow.hidden = NO;
    [cardWindow makeKeyAndVisible];
    [containerVC.view setNeedsLayout];
    [containerVC.view layoutIfNeeded];

    // Create WebView early so networking starts during the rotation delay.
    WKWebView *webView = [self createConfiguredWebViewWithInternal:internal];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.alpha = 0.0;
    
    UIView *loadingView = [self createLoadingViewWithFrame:CGRectZero];
    loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    loadingView.alpha = 1.0;

    WebViewLoadDelegate *delegate = stashAttachCheckoutDelegates(webView, loadingView, containerVC, internal);
    
    // Preload: attach WebView off-screen so networking begins before the card slides in.
    CGFloat preloadH = portraitBounds.size.height * stash_cardHeightRatioPortrait;
    CGFloat preloadW = portraitBounds.size.width;
    UIView *preloadHost = [[UIView alloc] initWithFrame:CGRectMake(0, -10000, preloadW, preloadH)];
    preloadHost.userInteractionEnabled = NO;
    preloadHost.accessibilityElementsHidden = YES;
    [containerVC.view addSubview:preloadHost];
    [preloadHost addSubview:webView];
    [preloadHost addSubview:loadingView];
    [NSLayoutConstraint activateConstraints:@[
        [webView.leadingAnchor constraintEqualToAnchor:preloadHost.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:preloadHost.trailingAnchor],
        [webView.topAnchor constraintEqualToAnchor:preloadHost.topAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:preloadHost.bottomAnchor],
        [loadingView.leadingAnchor constraintEqualToAnchor:preloadHost.leadingAnchor],
        [loadingView.trailingAnchor constraintEqualToAnchor:preloadHost.trailingAnchor],
        [loadingView.topAnchor constraintEqualToAnchor:preloadHost.topAnchor],
        [loadingView.bottomAnchor constraintEqualToAnchor:preloadHost.bottomAnchor]
    ]];
    [containerVC.view layoutIfNeeded];
    NSURL *preloadURL = [NSURL URLWithString:url];
    if (preloadURL) {
        NSMutableURLRequest *preloadRequest = requestForURL(preloadURL);
        [delegate armRetryTimerIfNeededForMainFrameURL:preloadURL];
        delegate.pageLoadStartTime = CFAbsoluteTimeGetCurrent();
        [webView loadRequest:preloadRequest];
    }
    
    // Wait for portrait scene geometry (when opening from landscape) before setting up the visual hierarchy.
    NSUInteger sessionWhenRotationBlockScheduled = internal.presentationSessionToken;
    stashScheduleForcePortraitCardLayoutAfterPortraitSettle(cardWindow,
                                                            isLandscape,
                                                            sessionWhenRotationBlockScheduled,
                                                            internal,
                                                            ^{
        STASH_DEBUG_LOG(@"StashNativeRetryTrace rotation block aborted stale session scheduled=%lu current=%lu",
              (unsigned long)sessionWhenRotationBlockScheduled, (unsigned long)internal.presentationSessionToken);
        [delegate invalidateAllTimers];
        [preloadHost removeFromSuperview];
    },
                                                            ^{
        if (internal.presentationSessionToken != sessionWhenRotationBlockScheduled) {
            STASH_DEBUG_LOG(@"StashNativeRetryTrace rotation block aborted stale session scheduled=%lu current=%lu",
                  (unsigned long)sessionWhenRotationBlockScheduled, (unsigned long)internal.presentationSessionToken);
            [delegate invalidateAllTimers];
            [preloadHost removeFromSuperview];
            return;
        }
        // Prefer scene coordinate space — UIScreen.main.bounds can lag during rotation.
        CGRect actualBounds = stashSceneCoordinateBoundsForIPhoneCardWindow(cardWindow);

        CGFloat actualPortraitWidth = fmin(actualBounds.size.width, actualBounds.size.height);
        CGFloat actualPortraitHeight = fmax(actualBounds.size.width, actualBounds.size.height);
        BOOL rotationSucceeded = (actualBounds.size.width < actualBounds.size.height);

        // On iOS 15, the scene's coordinateSpace.bounds can still report landscape
        // even after the interfaceOrientation has settled to portrait (race between
        // the orientation property and the coordinate space). Since this is a
        // force-portrait card, always use portrait dimensions for the window frame
        // and card layout. On iOS 16+ scene geometry preferences keep them in sync.
        if (!rotationSucceeded) {
            if (@available(iOS 16.0, *)) {
                // iOS 16+: scene geometry preferences handle this.
            } else {
                actualBounds = CGRectMake(0, 0, actualPortraitWidth, actualPortraitHeight);
                rotationSucceeded = YES;
            }
        }

        // Update window frame to actual screen bounds
        cardWindow.frame = actualBounds;
        containerVC.view.frame = actualBounds;

        if (@available(iOS 16.0, *)) {
            [containerVC setNeedsUpdateOfSupportedInterfaceOrientations];
        }

        // Calculate card dimensions using portrait dimensions
        CGFloat cardWidth, cardHeight, cardX, cardFinalY, startY;

        if (rotationSucceeded) {
            // Portrait bounds - use directly (phone card is always full width)
            cardWidth = actualBounds.size.width;
            cardHeight = actualBounds.size.height * stash_cardHeightRatioPortrait;
            cardX = (actualBounds.size.width - cardWidth) / 2.0;
            cardFinalY = actualBounds.size.height - cardHeight;
            startY = actualBounds.size.height + cardHeight;
        } else {
            // Rotation failed (iOS 16+ only path now) - present in portrait within landscape
            cardWidth = actualPortraitWidth;
            cardHeight = actualPortraitHeight * stash_cardHeightRatioPortrait;
            cardX = (actualBounds.size.width - cardWidth) / 2.0;
            cardFinalY = actualBounds.size.height - cardHeight;
            startY = actualBounds.size.height + cardHeight;
        }
        
        // Compute safe-area top for clamping the card so it never overlaps the notch.
        CGFloat safeTop = 0;
        if (@available(iOS 11.0, *)) {
            safeTop = cardWindow.safeAreaInsets.top;
        }
        stash_cardSafeAreaTop = safeTop;

        // Cap the card so its top edge never overlaps the notch / Dynamic Island.
        if (cardFinalY < safeTop) {
            cardFinalY = safeTop;
            cardHeight = actualBounds.size.height - safeTop;
            startY = actualBounds.size.height + cardHeight;
        }
        if (cardFinalY < 0) cardFinalY = 0;

        // Create cardView
        UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(cardX, startY, cardWidth, cardHeight)];
        cardView.backgroundColor = stash_sheetBackgroundUIColor();
        cardView.clipsToBounds = YES;
        cardView.tag = kCardViewTag;
        [cardWindow addSubview:cardView];
        
        // Store the target frame
        containerVC.cardFrame = CGRectMake(cardX, cardFinalY, cardWidth, cardHeight);
        containerVC.customFrame = CGRectMake(cardX, startY, cardWidth, cardHeight);
        
        // Apply corner radius (top corners only)
        CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
        cardView.layer.mask = maskLayer;
        
        // Add shadow (iPhone card style)
        cardView.layer.shadowColor = [UIColor blackColor].CGColor;
        cardView.layer.shadowOffset = CGSizeMake(0, kShadowOffsetYPhone);
        cardView.layer.shadowOpacity = kShadowOpacityPhone;
        cardView.layer.shadowRadius = kShadowRadiusPhone;
        
        [webView removeFromSuperview];
        [loadingView removeFromSuperview];
        [preloadHost removeFromSuperview];
        
        [cardView addSubview:webView];
        [cardView addSubview:loadingView];
        
        [NSLayoutConstraint activateConstraints:@[
            [webView.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor],
            [webView.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor],
            [webView.topAnchor constraintEqualToAnchor:cardView.topAnchor],
            [webView.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor],
            [loadingView.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor],
            [loadingView.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor],
            [loadingView.topAnchor constraintEqualToAnchor:cardView.topAnchor],
            [loadingView.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor]
        ]];
        [cardWindow layoutIfNeeded];
        
        // Dimming backdrop after load has started; short hold after fade before slide gives WebKit time off-screen.
        UIView *overlayView = createOverlayViewWithFrame(stashIPhoneCardOverscanBackdropFrameForWindowBounds(actualBounds),
                                                         cardWindow,
                                                         0,
                                                         containerVC);
        overlayView.autoresizingMask = UIViewAutoresizingNone;

        // Add drag tray so it is part of the card from the start (visible during slide-up)
        UIView *dragTray = [internal createDragTray:cardWidth];
        [cardView addSubview:dragTray];
        internal.dragTrayView = dragTray;
        
        // Animate overlay fade in
        [UIView animateWithDuration:kOverlayFadeInDuration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:kOverlayOpacity];
        } completion:nil];
        
        // Animate card sliding UP from BOTTOM (after overlay fade + hold)
        NSTimeInterval cardSlideDelay = kOverlayFadeInDuration + kCardEntryHoldAfterOverlayFadeIn;
        [UIView animateWithDuration:kCardEntrySpringDuration
                              delay:cardSlideDelay
             usingSpringWithDamping:kCardEntrySpringDamping
              initialSpringVelocity:kCardEntrySpringVelocity
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            cardView.frame = CGRectMake(cardX, cardFinalY, cardWidth, cardHeight);
            containerVC.customFrame = CGRectMake(cardX, cardFinalY, cardWidth, cardHeight);
            
            // Update corner radius mask for new frame
            CAShapeLayer *newMaskLayer = stash_createCornerRadiusMask(CGRectMake(0, 0, cardWidth, cardHeight), UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
            cardView.layer.mask = newMaskLayer;
        } completion:^(BOOL finished) {
            // Add tap-to-dismiss on overlay
            UIButton *dismissButton = [UIButton buttonWithType:UIButtonTypeCustom];
            dismissButton.frame = overlayView.bounds;
            dismissButton.backgroundColor = [UIColor clearColor];
            dismissButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [overlayView addSubview:dismissButton];
            [dismissButton addTarget:self action:@selector(handleOverlayTap) forControlEvents:UIControlEventTouchUpInside];
            dismissButton.accessibilityLabel = @"Close checkout";
            dismissButton.accessibilityTraits = UIAccessibilityTraitButton;
            
            [internal startKeyboardObserving];
            [internal registerIPhoneCardWindowGeometryObservers];
            
            containerVC.skipLayoutDuringInitialSetup = NO;
        }];
    });
}

#pragma mark - iPhone Card Presentation (Current Orientation, No Rotation)

- (void)presentIPhoneCardInCurrentOrientationWithURL:(NSString *)url {
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    
    internal.previousKeyWindow = stash_getKeyWindow();
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    BOOL isLandscape = screenBounds.size.width > screenBounds.size.height;
    
    UIWindow *cardWindow = [[UIWindow alloc] initWithFrame:screenBounds];
    stash_attachWindowToKeyWindowScene(cardWindow, internal.previousKeyWindow);
    cardWindow.windowLevel = UIWindowLevelAlert;
    cardWindow.backgroundColor = [UIColor clearColor];
    cardWindow.hidden = YES;
    internal.portraitWindow = cardWindow;
    
    IPhoneCardCurrentOrientationViewController *containerVC = [[IPhoneCardCurrentOrientationViewController alloc] init];
    containerVC.modalPresentationStyle = UIModalPresentationFullScreen;
    containerVC.view.backgroundColor = [UIColor clearColor];
    containerVC.view.frame = screenBounds;
    containerVC.skipLayoutDuringInitialSetup = YES;

    // Lock to the orientation the card was opened in so the user cannot rotate while the card is visible.
    UIInterfaceOrientationMask lockMask = isLandscape ? UIInterfaceOrientationMaskLandscape
                                                      : UIInterfaceOrientationMaskPortrait;
    containerVC.lockedOrientationMask = lockMask;
    // Store "allow all" so cleanupCardInstance/restorePrePortraitOrientation releases the lock on iOS 16+.
    internal.previousSceneOrientationMask = UIInterfaceOrientationMaskAll;

    cardWindow.rootViewController = containerVC;
    internal.currentPresentedVC = containerVC;

    // iOS 16+: lock the scene geometry before making the window visible.
    // iOS 15: trigger rotation re-evaluation so the swizzle (which returns lockMask
    // via rootVC) locks this window to the opening orientation.
    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene = cardWindow.windowScene;
        if (scene) {
            UIWindowSceneGeometryPreferencesIOS *prefs = [[UIWindowSceneGeometryPreferencesIOS alloc]
                initWithInterfaceOrientations:lockMask];
            [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
                STASH_DEBUG_LOG(@"StashNative orientation lock failed: %@", error);
            }];
        }
    } else {
        [UIViewController attemptRotationToDeviceOrientation];
    }

    cardWindow.hidden = NO;
    [cardWindow makeKeyAndVisible];
    [containerVC.view setNeedsLayout];
    [containerVC.view layoutIfNeeded];

    // Cache safe-area top so stash_computePhoneCardFrameForBoundsAndOrientation uses the same clamp.
    stash_cardSafeAreaTop = 0;
    if (@available(iOS 11.0, *)) {
        stash_cardSafeAreaTop = cardWindow.safeAreaInsets.top;
    }

    CGRect actualBounds = stashSceneCoordinateBoundsForIPhoneCardWindow(cardWindow);
    cardWindow.frame = actualBounds;
    containerVC.view.frame = actualBounds;
    BOOL isLandscapeLayout = actualBounds.size.width > actualBounds.size.height;
    CGFloat cardWidth, cardHeight, cardX, cardFinalY, startY;
    
    if (isLandscapeLayout) {
        cardWidth = actualBounds.size.width * stash_cardWidthRatioLandscape;
        cardHeight = actualBounds.size.height * stash_cardHeightRatioLandscape;
        CGFloat minPhone = 300.0f;
        if (cardWidth < minPhone) cardWidth = minPhone;
        if (cardHeight < minPhone) cardHeight = minPhone;
        cardX = (actualBounds.size.width - cardWidth) / 2.0f;
        cardFinalY = actualBounds.size.height - cardHeight;
        startY = actualBounds.size.height + cardHeight;
    } else {
        cardWidth = actualBounds.size.width;
        cardHeight = actualBounds.size.height * stash_cardHeightRatioPortrait;
        cardX = 0;
        cardFinalY = actualBounds.size.height - cardHeight;
        startY = actualBounds.size.height + cardHeight;
    }

    // Cap so the card top never overlaps the notch / Dynamic Island.
    // In landscape, safeAreaInsets.top can be 0 (notch is on the side). Enforce a minimum
    // buffer so the card does not collide with the notification/control center pull-down gesture.
    CGFloat effectiveSafeTop = stash_cardSafeAreaTop;
    if (isLandscapeLayout && effectiveSafeTop < 8.0f) {
        effectiveSafeTop = 8.0f;
    }
    if (cardFinalY < effectiveSafeTop) {
        cardFinalY = effectiveSafeTop;
        cardHeight = actualBounds.size.height - effectiveSafeTop;
        startY = actualBounds.size.height + cardHeight;
    }
    if (cardFinalY < 0) cardFinalY = 0;
    
    UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(cardX, startY, cardWidth, cardHeight)];
    cardView.backgroundColor = stash_sheetBackgroundUIColor();
    cardView.clipsToBounds = YES;
    cardView.tag = kCardViewTag;
    [cardWindow addSubview:cardView];
    
    containerVC.cardFrame = CGRectMake(cardX, cardFinalY, cardWidth, cardHeight);
    containerVC.customFrame = CGRectMake(cardX, startY, cardWidth, cardHeight);
    
    CAShapeLayer *maskLayer = stash_createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
    cardView.layer.mask = maskLayer;
    
    cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    cardView.layer.shadowOffset = CGSizeMake(0, kShadowOffsetYPhone);
    cardView.layer.shadowOpacity = kShadowOpacityPhone;
    cardView.layer.shadowRadius = kShadowRadiusPhone;
    
    WKWebView *webView = [self createConfiguredWebViewWithInternal:internal];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.alpha = 0.0;
    
    UIView *loadingView = [self createLoadingViewWithFrame:CGRectZero];
    loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    loadingView.alpha = 1.0;
    
    [cardView addSubview:webView];
    [cardView addSubview:loadingView];
    
    [NSLayoutConstraint activateConstraints:@[
        [webView.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor],
        [webView.topAnchor constraintEqualToAnchor:cardView.topAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor],
        [loadingView.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor],
        [loadingView.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor],
        [loadingView.topAnchor constraintEqualToAnchor:cardView.topAnchor],
        [loadingView.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor]
    ]];
    
    UIView *dragTray = [internal createDragTray:cardWidth];
    [cardView addSubview:dragTray];
    internal.dragTrayView = dragTray;
    
    WebViewLoadDelegate *delegate = stashAttachCheckoutDelegates(webView, loadingView, containerVC, internal);
    
    [cardWindow layoutIfNeeded];
    NSURL *nsurl = [NSURL URLWithString:url];
    if (nsurl) {
        NSMutableURLRequest *request = requestForURL(nsurl);
        [delegate armRetryTimerIfNeededForMainFrameURL:nsurl];
        delegate.pageLoadStartTime = CFAbsoluteTimeGetCurrent();
        [webView loadRequest:request];
    }
    
    // Backdrop below card: insert after card is in hierarchy so stacking matches portrait-forced path.
    UIView *overlayView = createOverlayViewWithFrame(stashIPhoneCardOverscanBackdropFrameForWindowBounds(actualBounds),
                                                     cardWindow,
                                                     0,
                                                     containerVC);
    overlayView.autoresizingMask = UIViewAutoresizingNone;

    [UIView animateWithDuration:kOverlayFadeInDuration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:kOverlayOpacity];
    } completion:nil];
    
    NSTimeInterval cardSlideDelay = kOverlayFadeInDuration + kCardEntryHoldAfterOverlayFadeIn;
    [UIView animateWithDuration:kCardEntrySpringDuration
                          delay:cardSlideDelay
         usingSpringWithDamping:kCardEntrySpringDamping
          initialSpringVelocity:kCardEntrySpringVelocity
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        cardView.frame = CGRectMake(cardX, cardFinalY, cardWidth, cardHeight);
        containerVC.customFrame = CGRectMake(cardX, cardFinalY, cardWidth, cardHeight);
        CAShapeLayer *newMaskLayer = stash_createCornerRadiusMask(CGRectMake(0, 0, cardWidth, cardHeight), UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
        cardView.layer.mask = newMaskLayer;
    } completion:^(BOOL finished) {
        UIButton *dismissButton = [UIButton buttonWithType:UIButtonTypeCustom];
        dismissButton.frame = overlayView.bounds;
        dismissButton.backgroundColor = [UIColor clearColor];
        dismissButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [overlayView addSubview:dismissButton];
        [dismissButton addTarget:self action:@selector(handleOverlayTap) forControlEvents:UIControlEventTouchUpInside];
        dismissButton.accessibilityLabel = @"Close checkout";
        dismissButton.accessibilityTraits = UIAccessibilityTraitButton;
        [internal startKeyboardObserving];
        [internal registerIPhoneCardWindowGeometryObservers];
        containerVC.skipLayoutDuringInitialSetup = NO;
    }];
}

#pragma mark - iPad Modal Presentation (Centered, Rotatable)

- (void)presentiPadModalWithURL:(NSString *)url {
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGSize cardSize = stash_calculateiPadCardSize(screenBounds);
    CGFloat cardX = (screenBounds.size.width - cardSize.width) / 2.0;
    CGFloat cardY = (screenBounds.size.height - cardSize.height) / 2.0;
    
    // Create container view controller (iPad-specific, allows rotation)
    IPadModalViewController *containerVC = [[IPadModalViewController alloc] init];
    containerVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    containerVC.view.backgroundColor = [UIColor clearColor];
    containerVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // Create cardView (centered dialog)
    UIView *cardView = [[UIView alloc] init];
    cardView.backgroundColor = stash_sheetBackgroundUIColor();
    cardView.tag = kCardViewTag;
    cardView.clipsToBounds = YES;
    cardView.layer.cornerRadius = kCornerRadiusDefault;
    cardView.frame = CGRectMake(cardX, cardY, cardSize.width, cardSize.height);
    cardView.alpha = 0.0; // Start hidden for fade-in
    [containerVC.view addSubview:cardView];
    
    // Create WebView with configuration
    WKWebView *webView = [self createConfiguredWebViewWithInternal:internal];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.alpha = 0.0;
    
    // Create loading view
    UIView *loadingView = [self createLoadingViewWithFrame:CGRectZero];
    loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    loadingView.alpha = 1.0;
    
    // Add views to cardView
    [cardView addSubview:webView];
    [cardView addSubview:loadingView];
    
    // Pin views to cardView edges
    [NSLayoutConstraint activateConstraints:@[
        [webView.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor],
        [webView.topAnchor constraintEqualToAnchor:cardView.topAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor],
        [loadingView.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor],
        [loadingView.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor],
        [loadingView.topAnchor constraintEqualToAnchor:cardView.topAnchor],
        [loadingView.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor]
    ]];
    
    // Add drag tray so it is part of the card from the start (visible during fade-in)
    UIView *dragTray = [internal createDragTray:cardSize.width];
    [cardView addSubview:dragTray];
    internal.dragTrayView = dragTray;
    
    // Create delegates
    WebViewLoadDelegate *delegate = stashAttachCheckoutDelegates(webView, loadingView, containerVC, internal);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyCardView, cardView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Load URL
    NSURL *nsurl = [NSURL URLWithString:url];
    if (nsurl) {
        NSMutableURLRequest *request = requestForURL(nsurl);
        [delegate armRetryTimerIfNeededForMainFrameURL:nsurl];
        delegate.pageLoadStartTime = CFAbsoluteTimeGetCurrent();
        [webView loadRequest:request];
    }
    
    // Create window
    internal.previousKeyWindow = stash_getKeyWindow();
    UIWindow *cardWindow = [[UIWindow alloc] initWithFrame:screenBounds];
    stash_attachWindowToKeyWindowScene(cardWindow, internal.previousKeyWindow);
    cardWindow.windowLevel = UIWindowLevelAlert;
    cardWindow.backgroundColor = [UIColor clearColor];
    cardWindow.rootViewController = containerVC;
    internal.portraitWindow = cardWindow;
    internal.currentPresentedVC = containerVC;
    
    stash_isCardExpanded = NO;
    
    UIView *overlayView = createOverlayViewWithFrame(screenBounds, containerVC.view, 0, containerVC);
    
    [containerVC updateCornerRadiusMaskForCardView];
    applyCardShadowToLayer(cardView.layer, NO);
    
    // Short delay before showing (helps rendering in game engines e.g. Unreal)
    NSUInteger sessionWhenIPadModalBlockScheduled = internal.presentationSessionToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (internal.presentationSessionToken != sessionWhenIPadModalBlockScheduled) {
            STASH_DEBUG_LOG(@"StashNativeRetryTrace iPad modal delayed block aborted stale session scheduled=%lu current=%lu",
                  (unsigned long)sessionWhenIPadModalBlockScheduled, (unsigned long)internal.presentationSessionToken);
            return;
        }
        cardWindow.hidden = NO;
        [cardWindow makeKeyAndVisible];
        [containerVC.view setNeedsLayout];
        [containerVC.view layoutIfNeeded];
        
        // Animate: fade in overlay and cardView
        [UIView animateWithDuration:kAnimationDurationDefault
                              delay:0
             usingSpringWithDamping:kSpringDampingDefault
              initialSpringVelocity:kSpringVelocityExpand
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            cardView.alpha = 1.0;
            overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:kOverlayOpacity];
        } completion:^(BOOL finished) {
            UIButton *dismissButton = [UIButton buttonWithType:UIButtonTypeCustom];
            dismissButton.frame = overlayView.bounds;
            dismissButton.backgroundColor = [UIColor clearColor];
            dismissButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [overlayView addSubview:dismissButton];
            [dismissButton addTarget:self action:@selector(handleOverlayTap) forControlEvents:UIControlEventTouchUpInside];
            dismissButton.accessibilityLabel = @"Close checkout";
            dismissButton.accessibilityTraits = UIAccessibilityTraitButton;
        }];
    });
}

#pragma mark - Modal Presentation (Centered, Rotatable on all devices)

- (void)presentModalWithURL:(NSString *)url {
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGRect frame = stash_computeModalFrameForScreenBounds(screenBounds);
    
    // Window-based presentation (same pattern as iPad checkout): no portrait lock, works in game engines
    ModalViewController *containerVC = [[ModalViewController alloc] init];
    containerVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    containerVC.view.backgroundColor = [UIColor clearColor];
    containerVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    containerVC.customFrame = frame;
    
    // Create cardView (centered modal)
    UIView *cardView = [[UIView alloc] initWithFrame:frame];
    cardView.backgroundColor = stash_sheetBackgroundUIColor();
    cardView.tag = kCardViewTag;
    cardView.clipsToBounds = YES;
    cardView.layer.cornerRadius = kCornerRadiusDefault;
    cardView.alpha = 0.0; // Start hidden for fade-in
    [containerVC.view addSubview:cardView];
    
    // Create WebView
    WKWebView *webView = [self createConfiguredWebViewWithInternal:internal];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.alpha = 0.0;
    
    // Create loading view
    UIView *loadingView = [self createLoadingViewWithFrame:CGRectZero];
    loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    loadingView.alpha = 1.0;
    
    // Add views to cardView
    [cardView addSubview:webView];
    [cardView addSubview:loadingView];
    
    // Pin views to cardView edges
    [NSLayoutConstraint activateConstraints:@[
        [webView.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor],
        [webView.topAnchor constraintEqualToAnchor:cardView.topAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor],
        [loadingView.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor],
        [loadingView.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor],
        [loadingView.topAnchor constraintEqualToAnchor:cardView.topAnchor],
        [loadingView.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor]
    ]];
    
    // Create delegates
    WebViewLoadDelegate *delegate = stashAttachCheckoutDelegates(webView, loadingView, containerVC, internal);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyCardView, cardView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Load URL
    NSURL *nsurl = [NSURL URLWithString:url];
    if (nsurl) {
        NSMutableURLRequest *request = requestForURL(nsurl);
        [delegate armRetryTimerIfNeededForMainFrameURL:nsurl];
        delegate.pageLoadStartTime = CFAbsoluteTimeGetCurrent();
        [webView loadRequest:request];
    }
    
    // Create window
    internal.previousKeyWindow = stash_getKeyWindow();
    UIWindow *cardWindow = [[UIWindow alloc] initWithFrame:screenBounds];
    stash_attachWindowToKeyWindowScene(cardWindow, internal.previousKeyWindow);
    cardWindow.windowLevel = UIWindowLevelAlert;
    cardWindow.backgroundColor = [UIColor clearColor];
    cardWindow.rootViewController = containerVC;
    internal.portraitWindow = cardWindow;
    internal.currentPresentedVC = containerVC;
    
    // Modal is always considered expanded (no expand/collapse)
    stash_isCardExpanded = YES;
    
    UIView *overlayView = createOverlayViewWithFrame(screenBounds, containerVC.view, 0, containerVC);
    
    [containerVC updateCornerRadiusMaskForCardView];
    applyCardShadowToLayer(cardView.layer, NO);
    
    // Short delay before showing (helps rendering in game engines e.g. Unreal)
    NSUInteger sessionWhenModalBlockScheduled = internal.presentationSessionToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (internal.presentationSessionToken != sessionWhenModalBlockScheduled) {
            STASH_DEBUG_LOG(@"StashNativeRetryTrace modal delayed block aborted stale session scheduled=%lu current=%lu",
                  (unsigned long)sessionWhenModalBlockScheduled, (unsigned long)internal.presentationSessionToken);
            return;
        }
        cardWindow.hidden = NO;
        [cardWindow makeKeyAndVisible];
        [containerVC.view setNeedsLayout];
        [containerVC.view layoutIfNeeded];
        
        // Same pattern as iPad modal: dim + card appear immediately; WebView stays on loading until ready.
        [UIView animateWithDuration:kAnimationDurationDefault
                              delay:0
             usingSpringWithDamping:kSpringDampingDefault
              initialSpringVelocity:kSpringVelocityExpand
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            cardView.alpha = 1.0;
            overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:kOverlayOpacity];
        } completion:^(BOOL finished) {
            if (_modalAllowDismiss) {
                UIButton *dismissButton = [UIButton buttonWithType:UIButtonTypeCustom];
                dismissButton.frame = overlayView.bounds;
                dismissButton.backgroundColor = [UIColor clearColor];
                dismissButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [overlayView addSubview:dismissButton];
                [dismissButton addTarget:self action:@selector(handleOverlayTap) forControlEvents:UIControlEventTouchUpInside];
                dismissButton.accessibilityLabel = @"Close checkout";
                dismissButton.accessibilityTraits = UIAccessibilityTraitButton;
            }
        }];
    });
}

#pragma mark - Popup Presentation (Legacy)

- (void)presentPopupWithURL:(NSString *)url {
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGRect frame = stash_computePopupFrameForScreenBounds(screenBounds);
    CGFloat x = frame.origin.x;
    CGFloat finalY = frame.origin.y;
    CGFloat width = frame.size.width;
    CGFloat height = frame.size.height;

    // Create container view controller (popup mode)
    OrientationLockedViewController *containerVC = [[OrientationLockedViewController alloc] init];
    containerVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    containerVC.enforcePortrait = NO;
    containerVC.view.backgroundColor = [UIColor clearColor];
    containerVC.view.frame = CGRectMake(x, finalY, width, height);
    containerVC.customFrame = CGRectMake(x, finalY, width, height);
    
    // Create WebView
    WKWebView *webView = [self createConfiguredWebViewWithInternal:internal];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.alpha = 0.0;
    
    // Create loading view
    UIView *loadingView = [self createLoadingViewWithFrame:CGRectZero];
    loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    loadingView.alpha = 0.0;
    
    // Add views to container
    [containerVC.view addSubview:webView];
    [containerVC.view addSubview:loadingView];
    
    // Pin views to container edges
    [NSLayoutConstraint activateConstraints:@[
        [webView.leadingAnchor constraintEqualToAnchor:containerVC.view.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:containerVC.view.trailingAnchor],
        [webView.topAnchor constraintEqualToAnchor:containerVC.view.topAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:containerVC.view.bottomAnchor],
        [loadingView.leadingAnchor constraintEqualToAnchor:containerVC.view.leadingAnchor],
        [loadingView.trailingAnchor constraintEqualToAnchor:containerVC.view.trailingAnchor],
        [loadingView.topAnchor constraintEqualToAnchor:containerVC.view.topAnchor],
        [loadingView.bottomAnchor constraintEqualToAnchor:containerVC.view.bottomAnchor]
    ]];
    
    // Create delegates
    WebViewLoadDelegate *delegate = stashAttachCheckoutDelegates(webView, loadingView, containerVC, internal);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyLoadingView, loadingView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Load URL
    NSURL *nsurl = [NSURL URLWithString:url];
    if (nsurl) {
        NSMutableURLRequest *request = requestForURL(nsurl);
        [delegate armRetryTimerIfNeededForMainFrameURL:nsurl];
        delegate.pageLoadStartTime = CFAbsoluteTimeGetCurrent();
        [webView loadRequest:request];
    }
    
    // Create window
    internal.previousKeyWindow = stash_getKeyWindow();
    UIWindow *cardWindow = [[UIWindow alloc] initWithFrame:screenBounds];
    stash_attachWindowToKeyWindowScene(cardWindow, internal.previousKeyWindow);
    cardWindow.windowLevel = UIWindowLevelAlert;
    cardWindow.backgroundColor = [UIColor clearColor];
    cardWindow.rootViewController = containerVC;
    internal.portraitWindow = cardWindow;
    internal.currentPresentedVC = containerVC;
    
    UIView *overlayView = createOverlayViewWithFrame(screenBounds, cardWindow, 0, containerVC);
    
    containerVC.view.clipsToBounds = YES;
    containerVC.view.layer.cornerRadius = kCornerRadiusDefault;
    applyCardShadowToLayer(containerVC.view.layer, NO);
    
    // Short delay before showing (helps rendering in game engines e.g. Unreal)
    NSUInteger sessionWhenPopupBlockScheduled = internal.presentationSessionToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (internal.presentationSessionToken != sessionWhenPopupBlockScheduled) {
            STASH_DEBUG_LOG(@"StashNativeRetryTrace popup delayed block aborted stale session scheduled=%lu current=%lu",
                  (unsigned long)sessionWhenPopupBlockScheduled, (unsigned long)internal.presentationSessionToken);
            return;
        }
        cardWindow.hidden = NO;
        [cardWindow makeKeyAndVisible];
        [containerVC.view setNeedsLayout];
        [containerVC.view layoutIfNeeded];
        
        // Animate: fade in overlay and popup
        [UIView animateWithDuration:kDismissAnimationDurationPopup delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            containerVC.view.alpha = 1.0;
            loadingView.alpha = 1.0;
            overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:kOverlayOpacity];
        } completion:^(BOOL finished) {
            [internal startKeyboardObserving];
        }];
    });
}

#pragma mark - WebView Creation Helper

/// Removes WKWebView's built-in form input toolbar (Prev/Next/Done) by dynamically
/// subclassing the internal WKContentView and overriding inputAccessoryView → nil.
/// Uses only public UIResponder API and standard ObjC runtime functions.
static void stashRemoveFormInputAccessoryView(WKWebView *webView) {
    static const char *kSubclassName = "StashNative_WKContentView";
    for (UIView *subview in webView.scrollView.subviews) {
        if (![NSStringFromClass([subview class]) containsString:@"WKContent"]) continue;

        Class subclass = objc_getClass(kSubclassName);
        if (!subclass) {
            subclass = objc_allocateClassPair([subview class], kSubclassName, 0);
            IMP nilIMP = imp_implementationWithBlock(^UIView *(id _self) {
                return nil;
            });
            class_addMethod(subclass, @selector(inputAccessoryView), nilIMP, "@@:");
            objc_registerClassPair(subclass);
        }
        object_setClass(subview, subclass);
        break;
    }
}

- (WKWebView *)createConfiguredWebViewWithInternal:(StashNativeCardInternal *)internal {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    // Use the default WKProcessPool (do not assign config.processPool). A custom singleton
    // pool kept an idle networking process that could miss server GOAWAY/RST_STREAM frames,
    // causing the next load to hang silently until the retry timer fires.
    config.allowsInlineMediaPlayback = YES;
    config.allowsAirPlayForMediaPlayback = YES;
    config.allowsPictureInPictureMediaPlayback = YES;
    
    if (@available(iOS 14.0, *)) {
        config.limitsNavigationsToAppBoundDomains = NO;
    }
    if (@available(iOS 11.0, *)) {
        config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
        config.dataDetectorTypes = WKDataDetectorTypeNone;
    }
    
    WKPreferences *preferences = [[WKPreferences alloc] init];
    preferences.javaScriptEnabled = YES;
    preferences.javaScriptCanOpenWindowsAutomatically = YES;
    if (@available(iOS 14.0, *)) {
        preferences.fraudulentWebsiteWarningEnabled = YES;
    }
    config.preferences = preferences;
    
    if (@available(iOS 14.0, *)) {
        config.defaultWebpagePreferences.allowsContentJavaScript = YES;
    }
    if (@available(iOS 13.0, *)) {
        config.defaultWebpagePreferences.preferredContentMode = WKContentModeRecommended;
    }
    
    // User content controller with Stash SDK scripts
    WKUserContentController *userContentController = [[WKUserContentController alloc] init];
    
    NSString *viewportScript = stash_viewportUserScriptSource();
    WKUserScript *viewportInjection = [[WKUserScript alloc] initWithSource:viewportScript
                                                             injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                          forMainFrameOnly:YES];
    [userContentController addUserScript:viewportInjection];
    
    // window.stash_sdk bridge. The JS source (and its mirror/spec obligations) lives in stash_bridgeUserScriptSource.
    NSString *stashSDKScript = stash_bridgeUserScriptSource();
    WKUserScript *stashSDKInjection = [[WKUserScript alloc] initWithSource:stashSDKScript
                                                             injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                          forMainFrameOnly:YES];
    [userContentController addUserScript:stashSDKInjection];
    
    NSString *noMarginsScript = stash_noMarginsUserScriptSource();
    WKUserScript *noMarginsInjection = [[WKUserScript alloc] initWithSource:noMarginsScript
                                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                           forMainFrameOnly:YES];
    [userContentController addUserScript:noMarginsInjection];

    // Dark / custom chrome: pin HTML/body to card colour; overrideUserInterfaceStyle sets prefers-color-scheme.
    if (@available(iOS 13.0, *)) {
        if (stash_effectiveThemeIsDark()) {
            NSString *bgHex = stash_cssHexFromUIColor(stash_sheetBackgroundUIColor());
            NSString *darkBgAtStart = stash_darkBackgroundAtStartUserScriptSource(bgHex);
            WKUserScript *darkStart = [[WKUserScript alloc] initWithSource:darkBgAtStart
                                                            injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                         forMainFrameOnly:YES];
            [userContentController addUserScript:darkStart];
            NSString *darkBgAtEnd = StashNativeDarkSheetBackgroundJavaScript();
            WKUserScript *darkEnd = [[WKUserScript alloc] initWithSource:darkBgAtEnd
                                                          injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                       forMainFrameOnly:YES];
            [userContentController addUserScript:darkEnd];
        }
    }
    
    for (NSString *handlerName in stashAllMessageHandlerNames()) {
        [userContentController addScriptMessageHandler:internal name:handlerName];
    }
    {
        NSString *pageReadyHook = stash_pageReadyUserScriptSource();
        WKUserScript *pageReadyScript = [[WKUserScript alloc] initWithSource:pageReadyHook
                                                               injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                            forMainFrameOnly:YES];
        [userContentController addUserScript:pageReadyScript];
    }
    config.userContentController = userContentController;
    
    UIColor *chromeBackgroundColor = stash_sheetBackgroundUIColor();
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    webView.opaque = YES;
    webView.hidden = NO;
    stash_setWebViewBackgroundColor(webView, chromeBackgroundColor);
    webView.scrollView.opaque = YES;
    stash_configureScrollViewForWebView(webView.scrollView);
    if (@available(iOS 13.0, *)) {
        if (stash_presentationBackgroundColorHex.length > 0) {
            UIUserInterfaceStyle st = stash_effectiveThemeIsDark() ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
            webView.overrideUserInterfaceStyle = st;
            webView.scrollView.overrideUserInterfaceStyle = st;
        } else if ([UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark) {
            webView.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            webView.scrollView.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        } else {
            webView.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
            webView.scrollView.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
        }
    }
    if (@available(iOS 15.0, *)) {
        webView.underPageBackgroundColor = chromeBackgroundColor;
    }
    webView.scrollView.scrollEnabled = YES;
    webView.scrollView.showsVerticalScrollIndicator = NO;
    webView.scrollView.showsHorizontalScrollIndicator = NO;
    
    stashRemoveFormInputAccessoryView(webView);
    return webView;
}

- (UIView *)createLoadingViewWithFrame:(CGRect)frame {
    UIView *loadingView = [[UIView alloc] initWithFrame:frame];

    UIColor *chromeBg = stash_sheetBackgroundUIColor();
    BOOL darkChrome = stash_colorIsDarkBackground(chromeBg);
    loadingView.backgroundColor = chromeBg;
    loadingView.opaque = YES;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.color = darkChrome ? [UIColor whiteColor] : [UIColor darkGrayColor];
    
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.hidesWhenStopped = NO;
    [spinner startAnimating];
    [loadingView addSubview:spinner];
    
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:loadingView.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:loadingView.centerYAnchor]
    ]];
    
    return loadingView;
}

- (void)handleOverlayTap {
    if ([StashNativeCardInternal sharedInstance].isPurchaseProcessing) {
        return;
    }
    [self dismiss];
}

- (void)dismiss {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self dismiss]; });
        return;
    }
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    [internal dismissWithAnimation:^{
        [internal cleanupCardInstance];
        [internal callDelegateCallbackOnce];
    }];
}

- (void)resetPresentationState {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self resetPresentationState]; });
        return;
    }
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    [internal cleanupCardInstance];
    stash_isCardCurrentlyPresented = NO;
}

@end

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
