//
//  StashNativeCard.m
//  StashNative
//
//  Core implementation. File-scope statics and functions here are extern'd by:
//  - StashNativeCardViewControllers.m (presentation state, layout constants, helper functions)
//  - StashNativeCardWebViewDelegates.m (presentation mode flags, theme helpers, scroll config)
//  Declarations for extern'd symbols live in StashNativeCardPrivate.h.
//

#import "StashNativeCard.h"
#import "StashNativeCardPrivate.h"
#import <SafariServices/SafariServices.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdlib.h>

#ifdef DEBUG
#define STASH_DEBUG_LOG(...) NSLog(__VA_ARGS__)
#else
#define STASH_DEBUG_LOG(...)
#endif

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
// Defined early so StashNativePopupSizeConfig can use them; non-static for StashNativeCardViewControllers.m
const CGFloat kPopupPortraitWidthMultiplier = 1.0285;
const CGFloat kPopupPortraitHeightMultiplier = 1.485;
const CGFloat kPopupLandscapeWidthMultiplier = 1.2275445;
const CGFloat kPopupLandscapeHeightMultiplier = 1.1385;

#pragma mark - PopupSizeConfig Implementation

@implementation StashNativePopupSizeConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _portraitWidthMultiplier = kPopupPortraitWidthMultiplier;
        _portraitHeightMultiplier = kPopupPortraitHeightMultiplier;
        _landscapeWidthMultiplier = kPopupLandscapeWidthMultiplier;
        _landscapeHeightMultiplier = kPopupLandscapeHeightMultiplier;
    }
    return self;
}

- (instancetype)initWithPortraitWidth:(CGFloat)portraitWidth
                       portraitHeight:(CGFloat)portraitHeight
                       landscapeWidth:(CGFloat)landscapeWidth
                      landscapeHeight:(CGFloat)landscapeHeight {
    self = [super init];
    if (self) {
        _portraitWidthMultiplier = portraitWidth;
        _portraitHeightMultiplier = portraitHeight;
        _landscapeWidthMultiplier = landscapeWidth;
        _landscapeHeightMultiplier = landscapeHeight;
    }
    return self;
}

@end

#pragma mark - ModalConfig Implementation

@implementation StashNativeModalConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _phoneWidthRatioPortrait = 0.80f;
        _phoneHeightRatioPortrait = 0.50f;
        _phoneWidthRatioLandscape = 0.50f;
        _phoneHeightRatioLandscape = 0.80f;
        _tabletWidthRatioPortrait = 0.40f;
        _tabletHeightRatioPortrait = 0.30f;
        _tabletWidthRatioLandscape = 0.30f;
        _tabletHeightRatioLandscape = 0.40f;
        _allowDismiss = YES;
        _autoClose = YES;
        _backgroundColor = nil;
    }
    return self;
}

- (instancetype)initWithPhoneWidthPortrait:(CGFloat)phoneWidthPortrait
                         phoneHeightPortrait:(CGFloat)phoneHeightPortrait
                         phoneWidthLandscape:(CGFloat)phoneWidthLandscape
                        phoneHeightLandscape:(CGFloat)phoneHeightLandscape
                        tabletWidthPortrait:(CGFloat)tabletWidthPortrait
                       tabletHeightPortrait:(CGFloat)tabletHeightPortrait
                       tabletWidthLandscape:(CGFloat)tabletWidthLandscape
                      tabletHeightLandscape:(CGFloat)tabletHeightLandscape
                              allowDismiss:(BOOL)allowDismiss {
    self = [super init];
    if (self) {
        _phoneWidthRatioPortrait = phoneWidthPortrait;
        _phoneHeightRatioPortrait = phoneHeightPortrait;
        _phoneWidthRatioLandscape = phoneWidthLandscape;
        _phoneHeightRatioLandscape = phoneHeightLandscape;
        _tabletWidthRatioPortrait = tabletWidthPortrait;
        _tabletHeightRatioPortrait = tabletHeightPortrait;
        _tabletWidthRatioLandscape = tabletWidthLandscape;
        _tabletHeightRatioLandscape = tabletHeightLandscape;
        _allowDismiss = allowDismiss;
        _autoClose = YES;
        _backgroundColor = nil;
    }
    return self;
}

@end

#pragma mark - CardConfig Implementation

@implementation StashNativeCardConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _forcePortrait = NO;
        _cardHeightRatioPortrait = 0.68f;
        _cardWidthRatioLandscape = 0.7f;
        _cardHeightRatioLandscape = 0.9f;
        _tabletWidthRatioPortrait = 0.4f;
        _tabletHeightRatioPortrait = 0.5f;
        _tabletWidthRatioLandscape = 0.3f;
        _tabletHeightRatioLandscape = 0.6f;
        _autoClose = YES;
        _backgroundColor = nil;
    }
    return self;
}

@end

#pragma mark - Private State
// Note: These statics are reset in [StashNativeCardInternal cleanupCardInstance].
// They are file-scope to this translation unit and effectively private to the SDK.

// --- Transient presentation state (reset on each dismiss) ---
static BOOL _callbackWasCalled = NO;              // Ensures dismiss callback fires only once
static BOOL _isCardCurrentlyPresented = NO;       // Guards against double-presentation
static BOOL _paymentSuccessHandled = NO;          // Ensures payment result callback fires only once


// --- User-configurable sizing (persists across presentations) ---
static BOOL _forcePortraitOnCheckout = NO;
// Phone card: portrait = full width + height ratio; landscape = width/height ratios when not forcing portrait
static CGFloat _cardHeightRatioPortrait = 0.68;
static CGFloat _cardWidthRatioLandscape = 0.7f;
static CGFloat _cardHeightRatioLandscape = 0.9f;

// Orientation-specific tablet (iPad) card configuration
static CGFloat _tabletWidthRatioPortrait = 0.4;
static CGFloat _tabletHeightRatioPortrait = 0.5;
static CGFloat _tabletWidthRatioLandscape = 0.3;
static CGFloat _tabletHeightRatioLandscape = 0.6;

// --- Popup size configuration (reset on cleanup) ---
// Non-static: referenced by StashNativeCardViewControllers.m and StashNativeCardWebViewDelegates.m
BOOL _useCustomPopupSize = NO;
CGFloat _customPortraitWidthMultiplier = kPopupPortraitWidthMultiplier;
CGFloat _customPortraitHeightMultiplier = kPopupPortraitHeightMultiplier;
CGFloat _customLandscapeWidthMultiplier = 1.753635;  // Default custom landscape is wider
CGFloat _customLandscapeHeightMultiplier = kPopupLandscapeHeightMultiplier;

// --- Presentation mode flags (reset on cleanup) ---
/** When YES, the current SFSafariViewController was opened via openBrowser (card-dismiss callbacks differ). */
static BOOL _safariOpenedViaOpenBrowser = NO;
/** Pending deliver-once for stashNativeCardDidCloseBrowser (delegate vs dismiss completion order). */
static BOOL _safariBrowserCloseDelegatePending = NO;

static void resetSafariOpenBrowserTrackingFlags(void) {
    _safariOpenedViaOpenBrowser = NO;
    _safariBrowserCloseDelegatePending = NO;
}

BOOL _usePopupPresentation = NO;
static BOOL _isCardExpanded = NO;

// --- Landscape / force-portrait orientation flags (phones only; reset on cleanup) ---
/// YES when the card was opened in the current (landscape) orientation without forcing portrait.
/// Card stays at its configured size; expand/collapse have no effect.
static BOOL _cardIsInLandscape = NO;
/// Safe-area top inset (notch / Dynamic Island) of the active card window, in points.
/// Used to clamp card height so the card never overlaps the notch. Reset to 0 on cleanup.
static CGFloat _cardSafeAreaTop = 0.0f;

// --- Modal configuration (reset on cleanup) ---
// Non-static: referenced by StashNativeCardViewControllers.m
BOOL _useModalPresentation = NO;
BOOL _modalAllowDismiss = YES;
/** When NO, dialog stays open after onPaymentSuccess/onPaymentFailure. Reset to YES on cleanup. */
static BOOL _autoCloseOnPaymentEvent = YES;
CGFloat _modalPhoneWidthRatioPortrait = 0.9f;
CGFloat _modalPhoneHeightRatioPortrait = 0.7f;
CGFloat _modalPhoneWidthRatioLandscape = 0.7f;
CGFloat _modalPhoneHeightRatioLandscape = 0.85f;
CGFloat _modalTabletWidthRatioPortrait = 0.40f;
CGFloat _modalTabletHeightRatioPortrait = 0.30f;
CGFloat _modalTabletWidthRatioLandscape = 0.30f;
CGFloat _modalTabletHeightRatioLandscape = 0.40f;

/** Optional #hex for card/modal chrome; cleared on cleanup. */
static NSString *_presentationBackgroundColorHex = nil;

#define ENABLE_IPAD_SUPPORT 1

#pragma mark - Animation Constants (Apple Pay–style: single duration + spring for consistent feel)

static const CGFloat kSpringDampingDefault = 0.82f;
static const CGFloat kSpringDampingTight = 0.82f;
static const CGFloat kAnimationDurationDefault = 0.5f;
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
static const CGFloat kHandleBarHalfWidth = 18.0f;
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
static const NSTimeInterval kRotationDelayAfterLandscape = 0.35;
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
static const CGFloat kTabletSdkExpandHeightMultiplier = 1.5f;
/** Matches Android CardConstants.EXPANDED_CARD_HEIGHT_RATIO — max card height when expanding via SDK. */
static const CGFloat kExpandedCardHeightScreenRatio = 0.95f;

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
static const CGFloat kFallbackTabletCardWidth = 600.0f;
static const CGFloat kFallbackTabletCardHeight = 700.0f;
static const CGFloat kTabletMinHeight = 500.0f;
const NSTimeInterval kPopupFrameAnimationDuration = 0.5;

#pragma mark - Message Handler Names (WKScriptMessageHandler)

static NSString * const kMessageHandlerPaymentSuccess = @"stashNativementSuccess";
static NSString * const kMessageHandlerPaymentFailure = @"stashNativementFailure";
static NSString * const kMessageHandlerPurchaseProcessing = @"stashPurchaseProcessing";
static NSString * const kMessageHandlerOptin = @"stashOptin";
static NSString * const kMessageHandlerExpand = @"stashExpand";
static NSString * const kMessageHandlerCollapse = @"stashCollapse";
static NSString * const kMessageHandlerWindowClose = @"stashWindowClose";
static NSString * const kMessageHandlerExternalPayment = @"stashExternalPayment";
static NSString * const kMessageHandlerPageReady = @"stashNativePageReady";

// All script-message handler names, registered and torn down together (order does not matter).
// Single source so adding a handler cannot drift between the add and remove sites.
static NSArray<NSString *> *stashAllMessageHandlerNames(void) {
    return @[kMessageHandlerPaymentSuccess, kMessageHandlerPaymentFailure, kMessageHandlerPurchaseProcessing,
             kMessageHandlerOptin, kMessageHandlerExpand, kMessageHandlerCollapse, kMessageHandlerExternalPayment,
             kMessageHandlerWindowClose, kMessageHandlerPageReady];
}

UIColor *StashNativeDarkSurfaceColor(void) {
    return [UIColor colorWithRed:0x1e/255.0 green:0x1e/255.0 blue:0x1e/255.0 alpha:1.0];
}

#pragma mark - Associated Object Keys

static NSString * const kAssociatedKeyWebViewDelegate = @"webViewDelegate";
static NSString * const kAssociatedKeyWebViewUIDelegate = @"webViewUIDelegate";
NSString * const StashNativeAssociatedKeyOverlayView = @"overlayView";  // extern for StashNativeCardViewControllers.m
static NSString * const kAssociatedKeyLoadingView = @"loadingView";
static NSString * const kAssociatedKeyCardView = @"cardView";
static NSString * const kAssociatedKeyInitialCardHeight = @"initialCardHeight";

#pragma mark - Helper Function Prototypes

static BOOL stash_colorIsDarkBackground(UIColor *color);
static BOOL stash_effectiveThemeIsDark(void);
static NSString *stash_cssHexFromUIColor(UIColor *color);
static UIColor *stash_parseHTMLHexColor(NSString *hex);

BOOL isRunningOniPad(void);
CGSize calculateiPadCardSize(CGRect screenBounds);
CGFloat stashTabletSdkMaxCardHeight(CGRect screenBounds, UIView *cardView);
CGFloat stashTabletSdkExpandedHeightFromBase(CGFloat baseHeight, CGRect screenBounds, UIView *cardView);
CGRect stashFrameForIPadSdkCard(CGRect screenBounds, UIView *cardView);
CGRect computePopupFrameForScreenBounds(CGRect screenBounds);
CGRect computeModalFrameForScreenBounds(CGRect screenBounds);
UIColor* getSystemBackgroundColor(void);
UIColor* stash_sheetBackgroundUIColor(void);
CGFloat getSafeAreaTopForView(UIView *view);
WKWebView* switchWebViewToFrameLayoutInCardView(UIView *cardView);
void updateDragTrayAndHandleInCardView(UIView *cardView, CGFloat cardWidth);
void configureScrollViewForWebView(UIScrollView* scrollView);
UIRectCorner getCornersToRoundForPosition(CGFloat verticalPosition, BOOL isiPad);
void setWebViewBackgroundColor(WKWebView* webView, UIColor* color);
CAShapeLayer* createCornerRadiusMask(CGRect bounds, UIRectCorner corners, CGFloat radius);
NSString* appendThemeQueryParameter(NSString* url);
UIWindow* getKeyWindow(void);
UIInterfaceOrientation getInterfaceOrientation(void);
void runWithoutImplicitAnimations(void (^block)(void));
UIView* createOverlayViewWithFrame(CGRect frame, UIView *parentView, NSInteger index, UIViewController *vc);
void applyCardShadowToLayer(CALayer *layer, BOOL phoneStyle);
void setOverlayToDismissAppearance(UIView *overlayView);
static NSString *NormalizeExternalPaymentURL(NSString *raw);
CGRect computePhoneCardFrameForBoundsAndOrientation(CGRect bounds, BOOL isLandscape);
CGRect stashSceneCoordinateBoundsForIPhoneCardWindow(UIWindow *window);

#pragma mark - StashNativeCardInternal

@interface StashNativeCardInternal : NSObject <SFSafariViewControllerDelegate, UIGestureRecognizerDelegate, WKScriptMessageHandler>

@property (nonatomic, strong) UIViewController *currentPresentedVC;
@property (nonatomic, strong) UIWindow *portraitWindow;
@property (nonatomic, strong) UIWindow *previousKeyWindow;
@property (nonatomic, strong) UIView *dragTrayView;
@property (nonatomic, assign) CGFloat initialY;
@property (nonatomic, assign) BOOL isObservingKeyboard;
@property (nonatomic, assign) BOOL isPurchaseProcessing;
@property (nonatomic, strong) SFSafariViewController *currentSafariViewController;
@property (nonatomic, strong) CADisplayLink *collapseDisplayLink;
@property (nonatomic, assign) CFTimeInterval collapseStartTime;
@property (nonatomic, assign) NSTimeInterval collapseDuration;
@property (nonatomic, copy) void (^collapseCompletion)(void);
@property (nonatomic, strong) CADisplayLink *expandDisplayLink;
@property (nonatomic, assign) CFTimeInterval expandStartTime;
@property (nonatomic, assign) NSTimeInterval expandDuration;
@property (nonatomic, assign) CGFloat expandInitialProgress;
@property (nonatomic, assign) CGFloat collapseInitialProgress;
@property (nonatomic, assign) CGFloat expandCollapseEaseOvershoot; // 0 = default; set for snap-back for stronger spring
@property (nonatomic, copy) void (^expandCompletion)(void);
@property (nonatomic, strong) WebViewLoadDelegate *activeWebViewLoadDelegate;
@property (nonatomic, strong) WebViewUIDelegate *activeWebViewUIDelegate;
/// Bumped on each card open and on teardown; WebViewLoadDelegate compares to ignore stale callbacks.
@property (nonatomic, assign) NSUInteger presentationSessionToken;
/// YES after beginDismissStoppingLoadAndTimers until cleanup finishes (avoids double token bump).
@property (nonatomic, assign) BOOL isDismissingCard;
/// The scene orientation mask in effect before forcePortrait was applied; restored on dismiss.
@property (nonatomic, assign) UIInterfaceOrientationMask previousSceneOrientationMask;
/// Dedicated portrait window created for SFSafariViewController on the external-payment path.
@property (nonatomic, strong) UIWindow *safariPresentationWindow;
/// YES when the external-payment path is about to present SFSafariViewController immediately
/// after card dismissal. cleanupCardInstance keeps the portrait window alive so Safari can
/// be presented from it without any scene-rotation animation between the card and Safari.
@property (nonatomic, assign) BOOL isHandingOffPortraitWindowToSafari;
/// YES while SFSafariViewController is actively presented in a forced-portrait window.
/// Causes the orientation swizzle to return UIInterfaceOrientationMaskPortrait for the
/// SDK window, preventing iOS from rotating Safari to landscape when the device rotates.
@property (nonatomic, assign) BOOL isSafariPortraitLocked;
@property (nonatomic, copy) dispatch_block_t pendingIPhoneCardGeometryRelayoutBlock;
@property (nonatomic, assign) BOOL iPhoneCardWindowGeometryObserversRegistered;
/// While YES, the orientation swizzle locks the card window (and system keyboard) to the card's orientation.
@property (nonatomic, assign) BOOL isIPhoneCardKeyboardVisible;
/// Last valid `UIDeviceOrientation` while the iPhone card keyboard is visible (0 = unset). Used to dismiss the keyboard when the device rotates so the next focus can present a portrait keyboard.
@property (nonatomic, assign) NSInteger stashLastValidDeviceOrientationForKeyboard;
/// Scene size when keyboard lock was applied; used with `stashIPhoneCardGeometryMayHaveChanged` to dismiss when portrait/landscape geometry flips without a device-orientation notification.
@property (nonatomic, assign) CGSize stashLastSceneSizeForKeyboardDismiss;

+ (instancetype)sharedInstance;
- (void)beginDismissStoppingLoadAndTimers;
- (void)dismissWithAnimation:(void (^)(void))completion;
- (void)cleanupCardInstance;
- (void)callDelegateCallbackOnce;
- (UIView *)cardViewForCurrentPresentation;  // Returns cardView (kCardViewTag) for iPhone/iPad; nil if none
- (void)updateDragTrayVisibilityForPurchaseProcessing:(BOOL)isProcessing;
- (void)setSkipLayoutDuringInitialSetup:(BOOL)skip forViewController:(UIViewController *)vc;
- (UIView *)createDragTray:(CGFloat)cardWidth;
- (void)expandCardToFullScreen;
- (void)collapseCardToOriginal;
- (void)animateCollapseWithDuration:(NSTimeInterval)duration completion:(void (^)(void))completion;
- (void)animateExpandWithDuration:(NSTimeInterval)duration completion:(void (^)(void))completion;
- (void)updateCardExpansionProgress:(CGFloat)progress cardView:(UIView *)cardView;
- (CGFloat)currentExpansionProgressForCardView:(UIView *)cardView;
- (CGRect)frameForExpansionProgress:(CGFloat)progress cardView:(UIView *)cardView;
- (void)collapsedRect:(CGRect *)outCollapsed expandedRect:(CGRect *)outExpanded forCardView:(UIView *)cardView;
- (void)startKeyboardObserving;
- (void)stopKeyboardObserving;
- (BOOL)isIPhoneLandscapeCurrentOrientation;
- (void)restorePrePortraitOrientation;
- (CGRect)referenceScreenBoundsForIPhoneCardLayout;
- (CGRect)collapsedPhoneCardFrameForReferenceBounds:(CGRect)actualBounds;
- (void)relayoutIPhoneCardWindowWithTargetBounds:(CGRect)targetBounds forcedCardExpansionProgress:(CGFloat)forcedProgress;
- (void)registerIPhoneCardWindowGeometryObservers;
- (void)unregisterIPhoneCardWindowGeometryObservers;
- (void)stashIPhoneCardGeometryMayHaveChanged:(NSNotification *)note;
- (UIInterfaceOrientationMask)stashKeyboardOrientationLockMaskForCardWindow;
- (void)stashApplyKeyboardOrientationLockIfNeeded;
- (void)stashClearKeyboardOrientationLockIfNeeded;

@end

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
    _callbackWasCalled = NO;
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

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
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

    if (_safariOpenedViaOpenBrowser) {
        _safariOpenedViaOpenBrowser = NO;
        _isCardCurrentlyPresented = NO;
        self.currentSafariViewController = nil;

        // External-payment handoff OR openBrowserWithURL:forcePortrait:YES — the portrait
        // window was kept/created so Safari ran in portrait. Tear it down and restore landscape.
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
        if (_safariBrowserCloseDelegatePending) {
            _safariBrowserCloseDelegatePending = NO;
            id<StashNativeCardDelegate> delegate = [StashNativeCard sharedInstance].delegate;
            if (delegate != nil
                && [delegate respondsToSelector:@selector(stashNativeCardDidCloseBrowser)]) {
                [delegate stashNativeCardDidCloseBrowser];
            }
        }
    } else {
        [self cleanupCardInstance];
        [self callDelegateCallbackOnce];
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

// Collapsed and expanded card frames for the current device/orientation. The expand/collapse
// interpolation, current-progress read, and per-frame relayout all derive from these two rects.
- (void)collapsedRect:(CGRect *)outCollapsed expandedRect:(CGRect *)outExpanded forCardView:(UIView *)cardView {
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
    if (isRunningOniPad()) {
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
                currentProgress = MIN(1.0, dragAmount / heightRange);
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
        if (isRunningOniPad()) {
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

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSString *name = message.name;
    id<StashNativeCardDelegate> delegate = [StashNativeCard sharedInstance].delegate;

    // Privileged action handlers must originate from the main frame (the checkout page), not a
    // nested third-party iframe. Payment-result handlers are intentionally not gated here.
    if (!message.frameInfo.isMainFrame &&
        ([name isEqualToString:kMessageHandlerExternalPayment] ||
         [name isEqualToString:kMessageHandlerWindowClose] ||
         [name isEqualToString:kMessageHandlerOptin] ||
         [name isEqualToString:kMessageHandlerExpand] ||
         [name isEqualToString:kMessageHandlerCollapse])) {
        return;
    }

    if ([name isEqualToString:kMessageHandlerPaymentSuccess]) {
        // When autoClose is on, the dialog tears down after the first event, so guard against
        // duplicate callbacks. When autoClose is off, the page stays alive and may legitimately
        // emit follow-up events (e.g. failure -> retry -> success), so don't gate.
        if (_autoCloseOnPaymentEvent && _paymentSuccessHandled) return;
        if (_autoCloseOnPaymentEvent) _paymentSuccessHandled = YES;
        self.isPurchaseProcessing = NO;
        
        NSString *orderString = nil;
        id body = message.body;
        if ([body isKindOfClass:[NSString class]]) {
            NSString *s = (NSString *)body;
            if (s.length > 0) {
                orderString = s;
            }
        }
        
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
    } else if ([name isEqualToString:kMessageHandlerPaymentFailure]) {
        if (_autoCloseOnPaymentEvent && _paymentSuccessHandled) return;
        if (_autoCloseOnPaymentEvent) _paymentSuccessHandled = YES;
        self.isPurchaseProcessing = NO;

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
    } else if ([name isEqualToString:kMessageHandlerPurchaseProcessing]) {
        self.isPurchaseProcessing = YES;
        [self updateDragTrayVisibilityForPurchaseProcessing:YES];
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
    } else if ([name isEqualToString:kMessageHandlerExternalPayment]) {
        NSString *raw = @"";
        if ([message.body isKindOfClass:[NSString class]]) {
            raw = (NSString *)message.body;
        }
        NSString *normalized = NormalizeExternalPaymentURL(raw);
        if (!normalized) {
            return;
        }
        // Theme is applied only to in-card content, never to URLs handed to an external browser.
        dispatch_async(dispatch_get_main_queue(), ^{
            id<StashNativeCardDelegate> externalDelegate = [StashNativeCard sharedInstance].delegate;
            if (externalDelegate
                && [externalDelegate respondsToSelector:@selector(stashNativeCardDidRequestExternalPaymentWithURL:)]) {
                [externalDelegate stashNativeCardDidRequestExternalPaymentWithURL:normalized];
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
        if (self.isPurchaseProcessing) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissWithAnimation:^{
                [self cleanupCardInstance];
                [self callDelegateCallbackOnce];
            }];
        });
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

// Maps a UIInterfaceOrientation to the corresponding single-orientation mask for restore.
static UIInterfaceOrientationMask stashOrientationMaskForOrientation(UIInterfaceOrientation orientation) {
    switch (orientation) {
        case UIInterfaceOrientationPortrait:            return UIInterfaceOrientationMaskPortrait;
        case UIInterfaceOrientationPortraitUpsideDown:  return UIInterfaceOrientationMaskPortraitUpsideDown;
        case UIInterfaceOrientationLandscapeLeft:       return UIInterfaceOrientationMaskLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:      return UIInterfaceOrientationMaskLandscapeRight;
        default:                                        return UIInterfaceOrientationMaskAll;
    }
}

BOOL isRunningOniPad(void) {
#if !ENABLE_IPAD_SUPPORT
    return NO;
#else
    // Interface idiom is constant for the process; cache it. The old per-call
    // dispatch_sync to main could deadlock when invoked from a background thread.
    static BOOL result = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        result = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad);
    });
    return result;
#endif
}

CGSize calculateiPadCardSize(CGRect screenBounds) {
    if (screenBounds.size.width <= 0 || screenBounds.size.height <= 0) {
        return CGSizeMake(kFallbackTabletCardWidth, kFallbackTabletCardHeight);
    }
    
    // Use actual current screen dimensions
    CGFloat screenWidth = screenBounds.size.width;
    CGFloat screenHeight = screenBounds.size.height;
    
    // Determine orientation and use appropriate ratios
    BOOL isLandscape = screenWidth > screenHeight;
    
    CGFloat widthRatio, heightRatio;
    if (isLandscape) {
        widthRatio = _tabletWidthRatioLandscape;
        heightRatio = _tabletHeightRatioLandscape;
    } else {
        widthRatio = _tabletWidthRatioPortrait;
        heightRatio = _tabletHeightRatioPortrait;
    }
    
    // Apply orientation-specific tablet ratios to actual screen dimensions
    CGFloat cardWidth = screenWidth * widthRatio;
    CGFloat cardHeight = screenHeight * heightRatio;
    
    if (cardWidth <= 0 || cardHeight <= 0) {
        return CGSizeMake(kFallbackTabletCardWidth, kFallbackTabletCardHeight);
    }
    
    // Enforce minimum sizes for usability
    CGFloat minWidth = kPopupBaseSizeMinIPad;
    CGFloat minHeight = kTabletMinHeight;
    if (cardWidth < minWidth) {
        cardWidth = minWidth;
    }
    if (cardHeight < minHeight) {
        cardHeight = minHeight;
    }
    
    return CGSizeMake(cardWidth, cardHeight);
}

CGRect computePopupFrameForScreenBounds(CGRect screenBounds) {
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(getInterfaceOrientation());
    CGFloat smallerDimension = fmin(screenBounds.size.width, screenBounds.size.height);
    CGFloat percentage = isRunningOniPad() ? kPopupBaseSizePercentageIPad : kPopupBaseSizePercentagePhone;
    CGFloat baseSize = fmax(
        isRunningOniPad() ? kPopupBaseSizeMinIPad : kPopupBaseSizeMinPhone,
        fmin(kPopupBaseSizeMax, smallerDimension * percentage)
    );
    CGFloat portraitWidthMultiplier = _useCustomPopupSize ? _customPortraitWidthMultiplier : kPopupPortraitWidthMultiplier;
    CGFloat portraitHeightMultiplier = _useCustomPopupSize ? _customPortraitHeightMultiplier : kPopupPortraitHeightMultiplier;
    CGFloat landscapeWidthMultiplier = _useCustomPopupSize ? _customLandscapeWidthMultiplier : kPopupLandscapeWidthMultiplier;
    CGFloat landscapeHeightMultiplier = _useCustomPopupSize ? _customLandscapeHeightMultiplier : kPopupLandscapeHeightMultiplier;
    CGFloat width = baseSize * (isLandscape ? landscapeWidthMultiplier : portraitWidthMultiplier);
    CGFloat height = baseSize * (isLandscape ? landscapeHeightMultiplier : portraitHeightMultiplier);
    CGFloat x = (screenBounds.size.width - width) / 2.0;
    CGFloat y = (screenBounds.size.height - height) / 2.0;
    return CGRectMake(x, y, width, height);
}

CGRect computeModalFrameForScreenBounds(CGRect screenBounds) {
    BOOL isLandscape = screenBounds.size.width > screenBounds.size.height;
    BOOL isTablet = isRunningOniPad();
    
    CGFloat widthRatio, heightRatio;
    if (isTablet) {
        if (isLandscape) {
            widthRatio = _modalTabletWidthRatioLandscape;
            heightRatio = _modalTabletHeightRatioLandscape;
        } else {
            widthRatio = _modalTabletWidthRatioPortrait;
            heightRatio = _modalTabletHeightRatioPortrait;
        }
    } else {
        if (isLandscape) {
            widthRatio = _modalPhoneWidthRatioLandscape;
            heightRatio = _modalPhoneHeightRatioLandscape;
        } else {
            widthRatio = _modalPhoneWidthRatioPortrait;
            heightRatio = _modalPhoneHeightRatioPortrait;
        }
    }
    
    CGFloat width = screenBounds.size.width * widthRatio;
    CGFloat height = screenBounds.size.height * heightRatio;
    
    // Apply minimum sizes
    CGFloat minWidth = isTablet ? 400.0f : 300.0f;
    CGFloat minHeight = isTablet ? 500.0f : 300.0f;
    if (width < minWidth) width = minWidth;
    if (height < minHeight) height = minHeight;
    
    // Center the modal
    CGFloat x = (screenBounds.size.width - width) / 2.0;
    CGFloat y = (screenBounds.size.height - height) / 2.0;
    
    return CGRectMake(x, y, width, height);
}

UIColor* getSystemBackgroundColor(void) {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle currentStyle = [UITraitCollection currentTraitCollection].userInterfaceStyle;
        return (currentStyle == UIUserInterfaceStyleDark) ? StashNativeDarkSurfaceColor() : [UIColor systemBackgroundColor];
    }
    return [UIColor whiteColor];
}

static double stash_srgbLinearize(double c) {
    return (c <= 0.03928) ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4);
}

static BOOL stash_colorIsDarkBackground(UIColor *color) {
    if (!color) {
        return YES;
    }
    CGFloat r, g, b, a;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w;
        if (![color getWhite:&w alpha:&a]) {
            return YES;
        }
        r = g = b = w;
    }
    double lum = 0.2126 * stash_srgbLinearize(r) + 0.7152 * stash_srgbLinearize(g) + 0.0722 * stash_srgbLinearize(b);
    return lum < 0.5;
}

static UIColor *stash_parseHTMLHexColor(NSString *hex) {
    if (hex.length == 0) {
        return nil;
    }
    NSString *s = [[hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (s.length == 0) {
        return nil;
    }
    if ([s hasPrefix:@"#"]) {
        s = [s substringFromIndex:1];
    }
    unsigned r = 0, g = 0, b = 0, a = 255;
    if (s.length == 3) {
        for (NSInteger i = 0; i < 3; i++) {
            unichar ch = [s characterAtIndex:i];
            int v = 0;
            if (ch >= '0' && ch <= '9') {
                v = (int)(ch - '0');
            } else if (ch >= 'a' && ch <= 'f') {
                v = (int)(ch - 'a' + 10);
            } else {
                return nil;
            }
            v = v * 16 + v;
            if (i == 0) {
                r = (unsigned)v;
            } else if (i == 1) {
                g = (unsigned)v;
            } else {
                b = (unsigned)v;
            }
        }
    } else if (s.length == 6) {
        unsigned value = 0;
        NSScanner *scanner = [NSScanner scannerWithString:s];
        if (![scanner scanHexInt:&value] || value > 0xFFFFFF) {
            return nil;
        }
        r = (value >> 16) & 0xFF;
        g = (value >> 8) & 0xFF;
        b = value & 0xFF;
    } else if (s.length == 8) {
        char buf[9] = {0};
        if (![s getCString:buf maxLength:sizeof(buf) encoding:NSUTF8StringEncoding]) {
            return nil;
        }
        char *end = NULL;
        unsigned long value = strtoul(buf, &end, 16);
        if (end != buf + 8 || value > 0xFFFFFFFFUL) {
            return nil;
        }
        a = (unsigned)((value >> 24) & 0xFF);
        r = (unsigned)((value >> 16) & 0xFF);
        g = (unsigned)((value >> 8) & 0xFF);
        b = (unsigned)(value & 0xFF);
    } else {
        return nil;
    }
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a / 255.0];
}

static BOOL stash_effectiveThemeIsDark(void) {
    if (_presentationBackgroundColorHex.length > 0) {
        UIColor *c = stash_parseHTMLHexColor(_presentationBackgroundColorHex);
        if (c) {
            return stash_colorIsDarkBackground(c);
        }
    }
    if (@available(iOS 13.0, *)) {
        return [UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

static NSString *stash_cssHexFromUIColor(UIColor *color) {
    CGFloat r, g, b, a;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w;
        if (![color getWhite:&w alpha:&a]) {
            return @"#1e1e1e";
        }
        r = g = b = w;
    }
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
            (unsigned long)lround(r * 255.0),
            (unsigned long)lround(g * 255.0),
            (unsigned long)lround(b * 255.0)];
}

UIColor* stash_sheetBackgroundUIColor(void) {
    if (_presentationBackgroundColorHex.length > 0) {
        UIColor *parsed = stash_parseHTMLHexColor(_presentationBackgroundColorHex);
        if (parsed) {
            return parsed;
        }
    }
    return getSystemBackgroundColor();
}

BOOL StashNativeSheetUsesDarkWebTheme(void) {
    return stash_effectiveThemeIsDark();
}

NSString *StashNativeDarkSheetBackgroundJavaScript(void) {
    NSString *hex = stash_cssHexFromUIColor(stash_sheetBackgroundUIColor());
    return [NSString stringWithFormat:
        @"(function(){try{var BG='%@';var h=document.head;if(h&&!h.querySelector('meta[name=color-scheme]')){var m=document.createElement('meta');m.setAttribute('name','color-scheme');m.setAttribute('content','dark');h.insertBefore(m,h.firstChild);}var e=document.documentElement;if(e){e.style.setProperty('background-color',BG,'important');e.style.setProperty('color-scheme','dark','important');}var b=document.body;if(b){b.style.setProperty('background-color',BG,'important');b.style.setProperty('color-scheme','dark','important');}}catch(x){}})();",
        hex];
}

CGFloat getSafeAreaTopForView(UIView *view) {
    if (!view) return _cardSafeAreaTop;
    if (@available(iOS 11.0, *)) {
        UIView *parentView = view.superview;
        if (parentView && [parentView respondsToSelector:@selector(safeAreaInsets)]) {
            CGFloat live = parentView.safeAreaInsets.top;
            // On iOS 15, safeAreaInsets can transiently read 0 during rotation
            // transitions. Fall back to the last known card safe area value.
            if (live > 0) return live;
        }
    }
    return _cardSafeAreaTop;
}

CGFloat getSafeAreaBottomForView(UIView *view) {
    if (!view) return 0;
    if (@available(iOS 11.0, *)) {
        UIView *parentView = view.superview;
        if (parentView && [parentView respondsToSelector:@selector(safeAreaInsets)]) {
            return parentView.safeAreaInsets.bottom;
        }
    }
    return 0;
}

CGFloat stashTabletSdkMaxCardHeight(CGRect screenBounds, UIView *cardView) {
    CGFloat ratioCap = screenBounds.size.height * kExpandedCardHeightScreenRatio;
    CGFloat safeTop = getSafeAreaTopForView(cardView);
    CGFloat safeBottom = getSafeAreaBottomForView(cardView);
    CGFloat insetsCap = screenBounds.size.height - safeTop - safeBottom;
    if (insetsCap < 1.0f) {
        insetsCap = screenBounds.size.height;
    }
    return MIN(ratioCap, insetsCap);
}

CGFloat stashTabletSdkExpandedHeightFromBase(CGFloat baseHeight, CGRect screenBounds, UIView *cardView) {
    CGFloat maxH = stashTabletSdkMaxCardHeight(screenBounds, cardView);
    return MIN(baseHeight * kTabletSdkExpandHeightMultiplier, maxH);
}

CGRect stashFrameForIPadSdkCard(CGRect screenBounds, UIView *cardView) {
    CGSize base = calculateiPadCardSize(screenBounds);
    CGFloat w = base.width;
    CGFloat h = base.height;
    if (_isCardExpanded) {
        h = stashTabletSdkExpandedHeightFromBase(base.height, screenBounds, cardView);
    }
    CGFloat x = (screenBounds.size.width - w) / 2.0;
    CGFloat y = (screenBounds.size.height - h) / 2.0;
    return CGRectMake(x, y, w, h);
}

CGRect computePhoneCardFrameForBoundsAndOrientation(CGRect bounds, BOOL isLandscape) {
    CGFloat cardWidth, cardHeight, cardX, cardY;
    const CGFloat minPhone = 300.0f;
    if (isLandscape) {
        cardWidth = bounds.size.width * _cardWidthRatioLandscape;
        cardHeight = bounds.size.height * _cardHeightRatioLandscape;
        if (cardWidth < minPhone) cardWidth = minPhone;
        if (cardHeight < minPhone) cardHeight = minPhone;
        cardX = (bounds.size.width - cardWidth) / 2.0f;
        cardY = bounds.size.height - cardHeight;
    } else {
        cardWidth = bounds.size.width;
        cardHeight = bounds.size.height * _cardHeightRatioPortrait;
        cardX = 0;
        cardY = bounds.size.height - cardHeight;
    }
    // In landscape, safeAreaInsets.top can be 0 (notch on the side). Enforce a minimum
    // buffer so the card doesn't collide with the notification pull-down gesture.
    CGFloat effectiveSafeTop = _cardSafeAreaTop;
    if (isLandscape && effectiveSafeTop < 8.0f) {
        effectiveSafeTop = 8.0f;
    }
    if (cardY < effectiveSafeTop) {
        cardY = effectiveSafeTop;
        cardHeight = bounds.size.height - effectiveSafeTop;
    }
    if (cardY < 0) cardY = 0;
    return CGRectMake(cardX, cardY, cardWidth, cardHeight);
}

void resetCardExpandedStateAfterRotation(void) {
    _isCardExpanded = NO;
}

WKWebView* switchWebViewToFrameLayoutInCardView(UIView *cardView) {
    if (!cardView) return nil;
    for (UIView *subview in cardView.subviews) {
        if ([subview isKindOfClass:[WKWebView class]]) {
            WKWebView *webView = (WKWebView *)subview;
            NSMutableArray *constraintsToRemove = [NSMutableArray array];
            for (NSLayoutConstraint *constraint in cardView.constraints) {
                if (constraint.firstItem == webView || constraint.secondItem == webView) {
                    [constraintsToRemove addObject:constraint];
                }
            }
            [NSLayoutConstraint deactivateConstraints:constraintsToRemove];
            webView.translatesAutoresizingMaskIntoConstraints = YES;
            return webView;
        }
    }
    return nil;
}

/// Pins every direct subview except the drag tray to cardView.bounds (strips edge constraints first).
/// Needed after rotation or when the WebView was switched to frame layout during SDK expand/collapse.
void layoutCardContentToBounds(UIView *cardView) {
    if (!cardView) return;
    CGRect bounds = cardView.bounds;
    for (UIView *subview in cardView.subviews) {
        if (subview.tag == kDragTrayViewTag) {
            continue;
        }
        NSMutableArray *constraintsToRemove = [NSMutableArray array];
        for (NSLayoutConstraint *constraint in cardView.constraints) {
            if (constraint.firstItem == subview || constraint.secondItem == subview) {
                [constraintsToRemove addObject:constraint];
            }
        }
        [NSLayoutConstraint deactivateConstraints:constraintsToRemove];
        subview.translatesAutoresizingMaskIntoConstraints = YES;
        subview.frame = bounds;
    }
    updateDragTrayAndHandleInCardView(cardView, bounds.size.width);
}

void updateDragTrayAndHandleInCardView(UIView *cardView, CGFloat cardWidth) {
    if (!cardView) return;
    UIView *dragTray = [cardView viewWithTag:kDragTrayViewTag];
    if (dragTray) {
        dragTray.frame = CGRectMake(0, 0, cardWidth, kDragTrayHeight);
        UIView *handle = [dragTray viewWithTag:kDragHandleViewTag];
        if (handle) {
            CGFloat handleX = (cardWidth / 2.0) - kHandleBarHalfWidth;
            handle.frame = CGRectMake(handleX, kHandleBarTopInset, kHandleBarWidth, kHandleBarHeight);
        }
    }
}

void configureScrollViewForWebView(UIScrollView* scrollView) {
    if (!scrollView) {
        return;
    }
    if (@available(iOS 11.0, *)) {
        scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    scrollView.contentInset = UIEdgeInsetsZero;
    scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    scrollView.bounces = NO;
    scrollView.alwaysBounceVertical = NO;
    scrollView.alwaysBounceHorizontal = NO;
    scrollView.bouncesZoom = NO;
    if (@available(iOS 17.4, *)) {
        scrollView.bouncesVertically = NO;
        scrollView.bouncesHorizontally = NO;
        scrollView.transfersVerticalScrollingToParent = NO;
        scrollView.transfersHorizontalScrollingToParent = NO;
    }
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        UIScrollEdgeEffectStyle *hardStyle = [UIScrollEdgeEffectStyle hardStyle];
        scrollView.topEdgeEffect.style = hardStyle;
        scrollView.bottomEdgeEffect.style = hardStyle;
        scrollView.leftEdgeEffect.style = hardStyle;
        scrollView.rightEdgeEffect.style = hardStyle;
    }
#endif
}

UIRectCorner getCornersToRoundForPosition(CGFloat verticalPosition, BOOL isiPad) {
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

void setWebViewBackgroundColor(WKWebView* webView, UIColor* color) {
    webView.backgroundColor = color;
    webView.scrollView.backgroundColor = color;
    for (UIView *subview in webView.subviews) {
        subview.backgroundColor = color;
        subview.opaque = YES;
    }
    for (UIView *subview in webView.scrollView.subviews) {
        subview.backgroundColor = color;
        subview.opaque = YES;
    }
}

CAShapeLayer* createCornerRadiusMask(CGRect bounds, UIRectCorner corners, CGFloat radius) {
    UIBezierPath *maskPath = [UIBezierPath bezierPathWithRoundedRect:bounds
                                                  byRoundingCorners:corners
                                                        cornerRadii:CGSizeMake(radius, radius)];
    CAShapeLayer *maskLayer = [[CAShapeLayer alloc] init];
    maskLayer.frame = bounds;
    maskLayer.path = maskPath.CGPath;
    return maskLayer;
}

/// Attach cardWindow to the same UIWindowScene as the app (e.g. Unreal) so it renders in game engines.
static void attachWindowToKeyWindowScene(UIWindow *cardWindow, UIWindow *keyWindow) {
    if (@available(iOS 13.0, *)) {
        if (keyWindow.windowScene) {
            cardWindow.windowScene = keyWindow.windowScene;
            return;
        }
        // Cold start / early presentation: key window may be nil before the scene is foreground-active.
        // Any window scene with a window is enough to attach; otherwise the card window has no scene.
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.windows.count > 0) {
                    cardWindow.windowScene = ws;
                    return;
                }
            }
        }
    }
}

UIWindow* getKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        UIWindow * (^pickFromScene)(UIWindowScene *) = ^UIWindow *(UIWindowScene *ws) {
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) {
                    return w;
                }
            }
            return ws.windows.firstObject;
        };
        for (UIScene *scene in scenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            if (scene.activationState != UISceneActivationStateForegroundActive) {
                continue;
            }
            UIWindow *w = pickFromScene((UIWindowScene *)scene);
            if (w) {
                return w;
            }
        }
        for (UIScene *scene in scenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) {
                continue;
            }
            UIWindow *w = pickFromScene((UIWindowScene *)scene);
            if (w) {
                return w;
            }
        }
        for (UIScene *scene in scenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            UIWindow *w = pickFromScene((UIWindowScene *)scene);
            if (w) {
                return w;
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
}

UIViewController *getTopPresentedViewController(void) {
    UIViewController *rootVC = getKeyWindow().rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

UIInterfaceOrientation getInterfaceOrientation(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                return ((UIWindowScene *)scene).interfaceOrientation;
            }
        }
        return UIInterfaceOrientationUnknown;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].statusBarOrientation;
#pragma clang diagnostic pop
}

void runWithoutImplicitAnimations(void (^block)(void)) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (block) block();
    [CATransaction commit];
}

UIView* createOverlayViewWithFrame(CGRect frame, UIView *parentView, NSInteger index, UIViewController *vc) {
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

void applyCardShadowToLayer(CALayer *layer, BOOL phoneStyle) {
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

void setOverlayToDismissAppearance(UIView *overlayView) {
    if (overlayView) {
        overlayView.backgroundColor = [UIColor colorWithWhite:kOverlayDismissAlpha alpha:kOverlayDismissAlpha];
    }
}

static NSString *NormalizeExternalPaymentURL(NSString *raw) {
    if (raw == nil) {
        return nil;
    }
    NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0) {
        return nil;
    }
    NSString *lower = [s lowercaseString];
    if ([lower hasPrefix:@"javascript:"] || [lower hasPrefix:@"file:"] || [lower hasPrefix:@"data:"]) {
        return nil;
    }
    if (![lower hasPrefix:@"http://"] && ![lower hasPrefix:@"https://"]) {
        s = [@"https://" stringByAppendingString:s];
    }
    NSURL *u = [NSURL URLWithString:s];
    if (u == nil || u.scheme.length == 0) {
        return nil;
    }
    NSString *scheme = [u.scheme lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return nil;
    }
    if (u.host.length == 0) {
        return nil;
    }
    // Upgrade cleartext http to https for the external payment URL (rather than rejecting it).
    if ([scheme isEqualToString:@"http"]) {
        NSURLComponents *comps = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
        comps.scheme = @"https";
        NSURL *upgraded = comps.URL;
        if (upgraded) {
            return upgraded.absoluteString;
        }
    }
    return u.absoluteString;
}

NSString* appendThemeQueryParameter(NSString* url) {
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
// Orientation unlock swizzle
//
// When forcePortrait is used the SDK installs a one-time swizzle on
// application:supportedInterfaceOrientationsForWindow: on the AppDelegate class.
// This lets the SDK's portrait window (and the dedicated Safari portrait window)
// rotate to portrait even when the host app's Info.plist is landscape-only —
// the common case for Unity, Unreal, and other landscape-locked game engines.
//
// The swizzle is surgical: for non-SDK windows it always calls through to the
// original implementation, so nothing else in the app changes behaviour.
// dispatch_once guarantees the swizzle is installed exactly once and only when
// it is first needed (not at app launch).
// ============================================================================

// Returns the orientation mask from the host app's Info.plist (UISupportedInterfaceOrientations).
// Used as fallback when the app had no application:supportedInterfaceOrientationsForWindow:.
static UIInterfaceOrientationMask stashInfoPlistSupportedOrientationMask(void) {
    static UIInterfaceOrientationMask cached = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *orientations = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UISupportedInterfaceOrientations"];
        if (!orientations || orientations.count == 0) {
            cached = UIInterfaceOrientationMaskAll;
            return;
        }
        UIInterfaceOrientationMask mask = 0;
        for (NSString *o in orientations) {
            if ([o isEqualToString:@"UIInterfaceOrientationPortrait"])           mask |= UIInterfaceOrientationMaskPortrait;
            if ([o isEqualToString:@"UIInterfaceOrientationPortraitUpsideDown"]) mask |= UIInterfaceOrientationMaskPortraitUpsideDown;
            if ([o isEqualToString:@"UIInterfaceOrientationLandscapeLeft"])      mask |= UIInterfaceOrientationMaskLandscapeLeft;
            if ([o isEqualToString:@"UIInterfaceOrientationLandscapeRight"])     mask |= UIInterfaceOrientationMaskLandscapeRight;
        }
        cached = mask ? mask : UIInterfaceOrientationMaskAll;
    });
    return cached;
}

// Resolves the interface-orientation mask for a window the SDK governs during a forced-portrait
// card/Safari presentation. Returns YES and writes *outMask when the window is the card window,
// the Safari portrait window, or a system window (keyboard/alert) shown over the card; returns NO
// when the caller should apply its own default (host window, or no card presented). Shared by the
// auto-managed swizzle and the public +supportedInterfaceOrientationsForWindow: forwarder so the
// two cannot drift; each keeps its own nil-window guard and fall-through tail.
static BOOL stashResolveCardWindowOrientationMask(StashNativeCardInternal *internal,
                                                  UIWindow *window,
                                                  UIInterfaceOrientationMask *outMask) {
    if (window && (window == internal.portraitWindow || window == internal.safariPresentationWindow)) {
        if (internal.isSafariPortraitLocked) {
            *outMask = UIInterfaceOrientationMaskPortrait;
            return YES;
        }
        if (window == internal.portraitWindow && internal.isIPhoneCardKeyboardVisible) {
            *outMask = [internal stashKeyboardOrientationLockMaskForCardWindow];
            return YES;
        }
        UIViewController *rootVC = window.rootViewController;
        *outMask = rootVC ? [rootVC supportedInterfaceOrientations] : UIInterfaceOrientationMaskAll;
        return YES;
    }
    if (internal.portraitWindow && window != internal.previousKeyWindow) {
        UIViewController *cardRootVC = internal.portraitWindow.rootViewController;
        if (cardRootVC) {
            *outMask = [cardRootVC supportedInterfaceOrientations];
            return YES;
        }
    }
    return NO;
}

static void stashInstallOrientationSwizzleIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        id appDelegate = [UIApplication sharedApplication].delegate;
        if (!appDelegate) return;

        Class delegateClass = [appDelegate class];
        SEL sel = @selector(application:supportedInterfaceOrientationsForWindow:);

        // We need a stable reference to originalIMP that the block can capture and call.
        // __block + a C-function-pointer typedef makes this safe.
        typedef UIInterfaceOrientationMask (*OriginalIMP)(id, SEL, UIApplication *, UIWindow *);
        __block OriginalIMP originalIMP = NULL;

        IMP newIMP = imp_implementationWithBlock(
            ^UIInterfaceOrientationMask(id blockSelf, UIApplication *app, UIWindow *window) {
                StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
                // Card window, Safari portrait window, or a system window (keyboard/alert) over the
                // card: lock to the card's orientation so a physical rotation can't flip it, and so
                // iOS 15 (which has no scene-geometry path) constrains rotation correctly.
                UIInterfaceOrientationMask mask;
                if (stashResolveCardWindowOrientationMask(internal, window, &mask)) {
                    return mask;
                }
                // Host app's window (or no card presented): forward to original.
                if (originalIMP) {
                    return originalIMP(blockSelf, sel, app, window);
                }
                // App had no original implementation -- return Info.plist orientations
                // so the swizzle does not permanently unlock all orientations for the host.
                return stashInfoPlistSupportedOrientationMask();
            });

        Method method = class_getInstanceMethod(delegateClass, sel);
        if (method) {
            // Method exists on this class (or a superclass) — replace and save the original.
            originalIMP = (OriginalIMP)method_setImplementation(method, newIMP);
        } else {
            // Method doesn't exist — add it; "originalIMP" stays NULL (no original to call).
            // Type encoding: return UIInterfaceOrientationMask (NSUInteger = 8 bytes on 64-bit),
            // args: self (id @8), _cmd (SEL @8), UIApplication * (@8), UIWindow * (@8) → 40 bytes.
            class_addMethod(delegateClass, sel, newIMP, "Q40@0:8@16@24");
        }
    });
}

@implementation StashNativeCard

+ (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(nullable UIWindow *)window {
    if (!window) {
        return 0;
    }
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    UIInterfaceOrientationMask mask;
    if (stashResolveCardWindowOrientationMask(internal, window, &mask)) {
        return mask;
    }
    // Host window, or no card presented: 0 lets the caller's own mask take effect.
    return 0;
}

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
    return _isCardCurrentlyPresented;
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
    if (_isCardCurrentlyPresented) {
        return;
    }

    _autoCloseOnPaymentEvent = config ? config.autoClose : YES;

    if (config) {
        _forcePortraitOnCheckout = config.forcePortrait;
        _cardHeightRatioPortrait = stashClampRatio(config.cardHeightRatioPortrait);
        _cardWidthRatioLandscape = stashClampRatio(config.cardWidthRatioLandscape);
        _cardHeightRatioLandscape = stashClampRatio(config.cardHeightRatioLandscape);
        _tabletWidthRatioPortrait = stashClampRatio(config.tabletWidthRatioPortrait);
        _tabletHeightRatioPortrait = stashClampRatio(config.tabletHeightRatioPortrait);
        _tabletWidthRatioLandscape = stashClampRatio(config.tabletWidthRatioLandscape);
        _tabletHeightRatioLandscape = stashClampRatio(config.tabletHeightRatioLandscape);
        NSString *ch = config.backgroundColor;
        ch = ch ? [ch stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
        _presentationBackgroundColorHex = (ch.length > 0) ? [ch copy] : nil;
    } else {
        _presentationBackgroundColorHex = nil;
    }

    _usePopupPresentation = NO;
    _useModalPresentation = NO;
    [self openURLInternal:url];
}

- (void)openBrowserWithURL:(NSString *)url {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openBrowserWithURL:url]; });
        return;
    }
    if (url == nil || url.length == 0) {
        return;
    }
    _safariOpenedViaOpenBrowser = YES;
    _safariBrowserCloseDelegatePending = YES;
    // External browser URLs are opened as-is; theme is applied only to in-card content.
    [self openInSafariViewController:url];
}

- (void)closeBrowser {
    [self dismissSafariViewController];
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
    if (_isCardCurrentlyPresented) {
        return;
    }

    _presentationBackgroundColorHex = nil;

    _usePopupPresentation = YES;
    
    if (sizeConfig) {
        _useCustomPopupSize = YES;
        _customPortraitWidthMultiplier = stashSanitizePopupMultiplier(sizeConfig.portraitWidthMultiplier, kPopupPortraitWidthMultiplier);
        _customPortraitHeightMultiplier = stashSanitizePopupMultiplier(sizeConfig.portraitHeightMultiplier, kPopupPortraitHeightMultiplier);
        _customLandscapeWidthMultiplier = stashSanitizePopupMultiplier(sizeConfig.landscapeWidthMultiplier, kPopupLandscapeWidthMultiplier);
        _customLandscapeHeightMultiplier = stashSanitizePopupMultiplier(sizeConfig.landscapeHeightMultiplier, kPopupLandscapeHeightMultiplier);
    } else {
        _useCustomPopupSize = NO;
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
    if (_isCardCurrentlyPresented) {
        return;
    }

    _autoCloseOnPaymentEvent = config ? config.autoClose : YES;

    _usePopupPresentation = NO;
    _useModalPresentation = YES;

    if (config) {
        _modalAllowDismiss = config.allowDismiss;
        _modalPhoneWidthRatioPortrait = stashClampRatio(config.phoneWidthRatioPortrait);
        _modalPhoneHeightRatioPortrait = stashClampRatio(config.phoneHeightRatioPortrait);
        _modalPhoneWidthRatioLandscape = stashClampRatio(config.phoneWidthRatioLandscape);
        _modalPhoneHeightRatioLandscape = stashClampRatio(config.phoneHeightRatioLandscape);
        _modalTabletWidthRatioPortrait = stashClampRatio(config.tabletWidthRatioPortrait);
        _modalTabletHeightRatioPortrait = stashClampRatio(config.tabletHeightRatioPortrait);
        _modalTabletWidthRatioLandscape = stashClampRatio(config.tabletWidthRatioLandscape);
        _modalTabletHeightRatioLandscape = stashClampRatio(config.tabletHeightRatioLandscape);
        NSString *ch = config.backgroundColor;
        ch = ch ? [ch stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
        _presentationBackgroundColorHex = (ch.length > 0) ? [ch copy] : nil;
    } else {
        // Match StashNativeModalConfig -init defaults exactly.
        _modalAllowDismiss = YES;
        _modalPhoneWidthRatioPortrait = 0.80f;
        _modalPhoneHeightRatioPortrait = 0.50f;
        _modalPhoneWidthRatioLandscape = 0.50f;
        _modalPhoneHeightRatioLandscape = 0.80f;
        _modalTabletWidthRatioPortrait = 0.40f;
        _modalTabletHeightRatioPortrait = 0.30f;
        _modalTabletWidthRatioLandscape = 0.30f;
        _modalTabletHeightRatioLandscape = 0.40f;
        _presentationBackgroundColorHex = nil;
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
    if (_isCardCurrentlyPresented) {
        return;
    }
    
    NSString *urlWithTheme = appendThemeQueryParameter(url);
    [self openInCardUI:urlWithTheme];
}

- (void)openInSafariViewController:(NSString *)url {
    NSURL *nsurl = [NSURL URLWithString:url];
    if (!nsurl) {
        resetSafariOpenBrowserTrackingFlags();
        return;
    }
    // SFSafariViewController only supports web URLs; reject any non-http(s) scheme (also avoids a crash).
    NSString *scheme = nsurl.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        resetSafariOpenBrowserTrackingFlags();
        return;
    }

    SFSafariViewController *safariVC = [[SFSafariViewController alloc] initWithURL:nsurl];
    safariVC.delegate = [StashNativeCardInternal sharedInstance];
    [StashNativeCardInternal sharedInstance].currentSafariViewController = safariVC;

    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    UIViewController *presenter;
    // Delay before presenting Safari to let the scene settle after a rotation request.
    // Without this delay, Safari spawns in landscape then snaps to portrait (visible glitch).
    NSTimeInterval rotationDelay = 0.0;

    if (internal.portraitWindow) {
        // Portrait window alive (card handoff or inline card Safari).
        // Swap to a clean SafariPortraitContainerViewController — no leftover card state.
        SafariPortraitContainerViewController *safariContainer =
            [[SafariPortraitContainerViewController alloc] init];
        safariContainer.view.backgroundColor = stash_sheetBackgroundUIColor();
        internal.portraitWindow.rootViewController = safariContainer;
        presenter = safariContainer;

        // Handoff complete — flag cleared so safariViewControllerDidFinish: owns teardown.
        internal.isHandingOffPortraitWindowToSafari = NO;

        // Defensive portrait request: if the scene is already portrait this is a true no-op
        // (no animation). Only needed if rotation somehow slipped during card dismiss.
        CGRect sceneBounds = [UIScreen mainScreen].bounds;
        BOOL sceneIsLandscape = (sceneBounds.size.width > sceneBounds.size.height);
        if (sceneIsLandscape) {
            // Scene slipped — request portrait and wait for it to settle.
            rotationDelay = kRotationDelayAfterLandscape;
            if (@available(iOS 16.0, *)) {
                UIWindowScene *scene = internal.portraitWindow.windowScene;
                if (scene) {
                    UIWindowSceneGeometryPreferencesIOS *prefs =
                        [[UIWindowSceneGeometryPreferencesIOS alloc]
                            initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
                    [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
                        STASH_DEBUG_LOG(@"StashNative: geometry update error: %@", error);
                    }];
                }
            } else {
                [[UIDevice currentDevice] setValue:@(UIInterfaceOrientationPortrait)
                                            forKey:@"orientation"];
                [UIViewController attemptRotationToDeviceOrientation];
            }
        }
        // else: scene is already portrait — present Safari immediately with no animation.

    } else if (_forcePortraitOnCheckout && !_safariOpenedViaOpenBrowser) {
        // External payment handoff from a forcePortrait card -- keep Safari in portrait.
        // Standalone openBrowser calls skip this even if a previous card used forcePortrait.
        CGRect screen = [UIScreen mainScreen].bounds;
        BOOL wasLandscape = (screen.size.width > screen.size.height);
        rotationDelay = wasLandscape ? kRotationDelayAfterLandscape : 0.0;
        presenter = [self createSafariPortraitPresenter];
    } else {
        presenter = getTopPresentedViewController();
    }

    // Present Safari after the scene has settled.
    // rotationDelay = 0 → fires on the next runloop turn (no visible delay).
    // rotationDelay > 0 → waits for the rotation animation to complete first.
    BOOL lockPortrait = (internal.portraitWindow != nil || internal.safariPresentationWindow != nil);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(rotationDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // Guard: if the window was torn down during the delay, abort.
        if (rotationDelay > 0 && internal.currentSafariViewController != safariVC) {
            resetSafariOpenBrowserTrackingFlags();
            internal.currentSafariViewController = nil;
            return;
        }
        if (presenter == nil) {
            resetSafariOpenBrowserTrackingFlags();
            internal.currentSafariViewController = nil;
            return;
        }
        // Lock the SDK window to portrait so the scene can't rotate to landscape while
        // Safari is shown. Cleared on dismissal in safariViewControllerDidFinish:.
        if (lockPortrait) {
            internal.isSafariPortraitLocked = YES;
        }
        [presenter presentViewController:safariVC animated:YES completion:^{
            _isCardCurrentlyPresented = YES;
        }];
    });
}

- (UIViewController *)createSafariPortraitPresenter {
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];

    if (!self.disableAutoOrientationUnlock) {
        stashInstallOrientationSwizzleIfNeeded();
    }

    UIWindow *gameWindow = getKeyWindow();
    internal.previousKeyWindow = gameWindow;

    CGRect screen = [UIScreen mainScreen].bounds;
    BOOL isLS = screen.size.width > screen.size.height;
    CGRect portraitFrame = CGRectMake(0, 0,
        isLS ? screen.size.height : screen.size.width,
        isLS ? screen.size.width  : screen.size.height);

    UIWindow *safariWindow = [[UIWindow alloc] initWithFrame:portraitFrame];
    attachWindowToKeyWindowScene(safariWindow, gameWindow);
    safariWindow.windowLevel = UIWindowLevelAlert;

    SafariPortraitContainerViewController *vc = [[SafariPortraitContainerViewController alloc] init];
    safariWindow.rootViewController = vc;
    internal.safariPresentationWindow = safariWindow;
    [safariWindow makeKeyAndVisible];

    // Capture current orientation and request portrait, mirroring the card path.
    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene = safariWindow.windowScene;
        if (scene) {
            UIInterfaceOrientation cur = scene.interfaceOrientation;
            if (UIInterfaceOrientationIsLandscape(cur)) {
                internal.previousSceneOrientationMask = stashOrientationMaskForOrientation(cur);
            } else {
                internal.previousSceneOrientationMask = UIInterfaceOrientationMaskAll;
            }
            UIWindowSceneGeometryPreferencesIOS *prefs = [[UIWindowSceneGeometryPreferencesIOS alloc]
                initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
            [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
                STASH_DEBUG_LOG(@"StashNative Safari portrait request failed: %@", error);
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
    return vc;
}

- (void)openInCardUI:(NSString *)url {
    StashNativeCardInternal *sessionInternal = [StashNativeCardInternal sharedInstance];
    sessionInternal.presentationSessionToken++;
    sessionInternal.isDismissingCard = NO;
    STASH_DEBUG_LOG(@"StashNativeRetryTrace open card session=%lu", (unsigned long)sessionInternal.presentationSessionToken);

    // Reset state
    _isCardCurrentlyPresented = YES;
    _callbackWasCalled = NO;
    _paymentSuccessHandled = NO;
    _isCardExpanded = NO;

    // Determine phone-only orientation flags (tablets always use normal expand/collapse logic).
    if (!isRunningOniPad() && !_useModalPresentation && !_usePopupPresentation) {
        CGRect sb = [UIScreen mainScreen].bounds;
        BOOL isLandscape = sb.size.width > sb.size.height;
        _cardIsInLandscape = !_forcePortraitOnCheckout && isLandscape;
    } else {
        _cardIsInLandscape = NO;
    }
    
    // Dispatch to appropriate presentation method based on device type
    if (_useModalPresentation) {
        [self presentModalWithURL:url];
    } else if (_usePopupPresentation) {
        [self presentPopupWithURL:url];
    } else if (isRunningOniPad()) {
        [self presentiPadModalWithURL:url];
    } else if (_forcePortraitOnCheckout) {
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
    internal.previousKeyWindow = getKeyWindow();
    
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
    attachWindowToKeyWindowScene(cardWindow, internal.previousKeyWindow);
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
    CGFloat preloadH = portraitBounds.size.height * _cardHeightRatioPortrait;
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
            cardHeight = actualBounds.size.height * _cardHeightRatioPortrait;
            cardX = (actualBounds.size.width - cardWidth) / 2.0;
            cardFinalY = actualBounds.size.height - cardHeight;
            startY = actualBounds.size.height + cardHeight;
        } else {
            // Rotation failed (iOS 16+ only path now) - present in portrait within landscape
            cardWidth = actualPortraitWidth;
            cardHeight = actualPortraitHeight * _cardHeightRatioPortrait;
            cardX = (actualBounds.size.width - cardWidth) / 2.0;
            cardFinalY = actualBounds.size.height - cardHeight;
            startY = actualBounds.size.height + cardHeight;
        }
        
        // Compute safe-area top for clamping the card so it never overlaps the notch.
        CGFloat safeTop = 0;
        if (@available(iOS 11.0, *)) {
            safeTop = cardWindow.safeAreaInsets.top;
        }
        _cardSafeAreaTop = safeTop;

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
        CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
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
            CAShapeLayer *newMaskLayer = createCornerRadiusMask(CGRectMake(0, 0, cardWidth, cardHeight), UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
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
    
    internal.previousKeyWindow = getKeyWindow();
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    BOOL isLandscape = screenBounds.size.width > screenBounds.size.height;
    
    UIWindow *cardWindow = [[UIWindow alloc] initWithFrame:screenBounds];
    attachWindowToKeyWindowScene(cardWindow, internal.previousKeyWindow);
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

    // Cache safe-area top so computePhoneCardFrameForBoundsAndOrientation uses the same clamp.
    _cardSafeAreaTop = 0;
    if (@available(iOS 11.0, *)) {
        _cardSafeAreaTop = cardWindow.safeAreaInsets.top;
    }

    CGRect actualBounds = stashSceneCoordinateBoundsForIPhoneCardWindow(cardWindow);
    cardWindow.frame = actualBounds;
    containerVC.view.frame = actualBounds;
    BOOL isLandscapeLayout = actualBounds.size.width > actualBounds.size.height;
    CGFloat cardWidth, cardHeight, cardX, cardFinalY, startY;
    
    if (isLandscapeLayout) {
        cardWidth = actualBounds.size.width * _cardWidthRatioLandscape;
        cardHeight = actualBounds.size.height * _cardHeightRatioLandscape;
        CGFloat minPhone = 300.0f;
        if (cardWidth < minPhone) cardWidth = minPhone;
        if (cardHeight < minPhone) cardHeight = minPhone;
        cardX = (actualBounds.size.width - cardWidth) / 2.0f;
        cardFinalY = actualBounds.size.height - cardHeight;
        startY = actualBounds.size.height + cardHeight;
    } else {
        cardWidth = actualBounds.size.width;
        cardHeight = actualBounds.size.height * _cardHeightRatioPortrait;
        cardX = 0;
        cardFinalY = actualBounds.size.height - cardHeight;
        startY = actualBounds.size.height + cardHeight;
    }

    // Cap so the card top never overlaps the notch / Dynamic Island.
    // In landscape, safeAreaInsets.top can be 0 (notch is on the side). Enforce a minimum
    // buffer so the card does not collide with the notification/control center pull-down gesture.
    CGFloat effectiveSafeTop = _cardSafeAreaTop;
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
    
    CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
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
        CAShapeLayer *newMaskLayer = createCornerRadiusMask(CGRectMake(0, 0, cardWidth, cardHeight), UIRectCornerTopLeft | UIRectCornerTopRight, kCornerRadiusDefault);
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
    CGSize cardSize = calculateiPadCardSize(screenBounds);
    CGFloat cardX = (screenBounds.size.width - cardSize.width) / 2.0;
    CGFloat cardY = (screenBounds.size.height - cardSize.height) / 2.0;
    
    // Create container view controller (iPad-specific, allows rotation)
    IPadModalViewController *containerVC = [[IPadModalViewController alloc] init];
    containerVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    containerVC.view.backgroundColor = [UIColor clearColor];
    containerVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    containerVC.previousScreenSize = screenBounds.size;
    
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
    internal.previousKeyWindow = getKeyWindow();
    UIWindow *cardWindow = [[UIWindow alloc] initWithFrame:screenBounds];
    attachWindowToKeyWindowScene(cardWindow, internal.previousKeyWindow);
    cardWindow.windowLevel = UIWindowLevelAlert;
    cardWindow.backgroundColor = [UIColor clearColor];
    cardWindow.rootViewController = containerVC;
    internal.portraitWindow = cardWindow;
    internal.currentPresentedVC = containerVC;
    
    _isCardExpanded = NO;
    
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
    CGRect frame = computeModalFrameForScreenBounds(screenBounds);
    
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
    internal.previousKeyWindow = getKeyWindow();
    UIWindow *cardWindow = [[UIWindow alloc] initWithFrame:screenBounds];
    attachWindowToKeyWindowScene(cardWindow, internal.previousKeyWindow);
    cardWindow.windowLevel = UIWindowLevelAlert;
    cardWindow.backgroundColor = [UIColor clearColor];
    cardWindow.rootViewController = containerVC;
    internal.portraitWindow = cardWindow;
    internal.currentPresentedVC = containerVC;
    
    // Modal is always considered expanded (no expand/collapse)
    _isCardExpanded = YES;
    
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
    CGRect frame = computePopupFrameForScreenBounds(screenBounds);
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
    internal.previousKeyWindow = getKeyWindow();
    UIWindow *cardWindow = [[UIWindow alloc] initWithFrame:screenBounds];
    attachWindowToKeyWindowScene(cardWindow, internal.previousKeyWindow);
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
    
    NSString *viewportScript = @"var meta = document.createElement('meta'); \
        meta.name = 'viewport'; \
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover'; \
        document.head.appendChild(meta);";
    WKUserScript *viewportInjection = [[WKUserScript alloc] initWithSource:viewportScript
                                                             injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                          forMainFrameOnly:YES];
    [userContentController addUserScript:viewportInjection];
    
    // Canonical spec: docs/stash-sdk-js.md. Changes here MUST be mirrored on Android (StashWebViewUtils.JS_SDK_SCRIPT).
    NSString *stashSDKScript = [NSString stringWithFormat:@"(function() {"
        "window.stash_sdk = window.stash_sdk || {};"
        "window.stash_sdk.onPaymentSuccess = function(order) {"
            "var payload = '';"
            "if (arguments.length > 0 && order !== undefined && order !== null) {"
            "  payload = (typeof order === 'string') ? order : JSON.stringify(order);"
            "}"
            "window.webkit.messageHandlers.%@.postMessage(payload);"
        "};"
        "window.stash_sdk.onPaymentFailure = function(data) {"
            "window.webkit.messageHandlers.%@.postMessage(data || {});"
        "};"
        "window.stash_sdk.onPurchaseProcessing = function(data) {"
            "window.webkit.messageHandlers.%@.postMessage(data || {});"
        "};"
        "window.stash_sdk.setPaymentChannel = function(optinType) {"
            "window.webkit.messageHandlers.%@.postMessage(optinType || '');"
        "};"
        "window.stash_sdk.expand = function() {"
            "window.webkit.messageHandlers.%@.postMessage({});"
        "};"
        "window.stash_sdk.collapse = function() {"
            "window.webkit.messageHandlers.%@.postMessage({});"
        "};"
        "window.stash_sdk.openExternalBrowser = function(url) {"
            "var s = (url !== undefined && url !== null) ? String(url) : '';"
            "window.webkit.messageHandlers.%@.postMessage(s);"
        "};"
        "try { window.close = function() {"
            "try { window.webkit.messageHandlers.%@.postMessage({}); } catch(e2) {}"
        "}; } catch(e) {}"
    "})();",
        kMessageHandlerPaymentSuccess, kMessageHandlerPaymentFailure, kMessageHandlerPurchaseProcessing,
        kMessageHandlerOptin, kMessageHandlerExpand, kMessageHandlerCollapse, kMessageHandlerExternalPayment,
        kMessageHandlerWindowClose];
    WKUserScript *stashSDKInjection = [[WKUserScript alloc] initWithSource:stashSDKScript
                                                             injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                          forMainFrameOnly:YES];
    [userContentController addUserScript:stashSDKInjection];
    
    NSString *noMarginsScript = @"var style = document.createElement('style'); \
        style.innerHTML = 'body { margin: 0 !important; padding: 0 !important; min-height: 100% !important; } \
        html { margin: 0 !important; padding: 0 !important; height: 100% !important; }'; \
        document.head.appendChild(style);";
    WKUserScript *noMarginsInjection = [[WKUserScript alloc] initWithSource:noMarginsScript
                                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                           forMainFrameOnly:YES];
    [userContentController addUserScript:noMarginsInjection];

    // Dark / custom chrome: pin HTML/body to card colour; overrideUserInterfaceStyle sets prefers-color-scheme.
    if (@available(iOS 13.0, *)) {
        if (stash_effectiveThemeIsDark()) {
            NSString *bgHex = stash_cssHexFromUIColor(stash_sheetBackgroundUIColor());
            NSString *darkBgAtStart = [NSString stringWithFormat:
                @"(function(){"
                "var BG='%@';"
                @"function paint(){try{var e=document.documentElement;if(e){e.style.setProperty('background-color',BG,'important');e.style.setProperty('color-scheme','dark','important');}var b=document.body;if(b){b.style.setProperty('background-color',BG,'important');b.style.setProperty('color-scheme','dark','important');}}catch(x){}}"
                @"paint();"
                @"document.addEventListener('readystatechange',function(){if(document.readyState==='interactive'||document.readyState==='complete')paint();});"
                @"document.addEventListener('DOMContentLoaded',paint);"
                @"})();", bgHex];
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
        NSString *pageReadyHook = [NSString stringWithFormat:
            @"(function(){"
            @"if(window.__stashNativeRevealInit)return;"
            @"window.__stashNativeRevealInit=1;"
            @"var H='%@';"
            @"function ok(){"
            @"try{"
            @"if(document.readyState==='loading')return false;"
            @"if(!document.documentElement)return false;"
            @"if(window.getComputedStyle(document.documentElement).display==='none')return false;"
            @"if(!document.body)return false;"
            @"if(window.getComputedStyle(document.body).display==='none')return false;"
            @"}catch(e){return false;}"
            @"return true;"
            @"}"
            @"function send(){"
            @"if(window.__stashNativePageReadySent)return;"
            @"if(!ok())return;"
            @"window.__stashNativePageReadySent=1;"
            @"requestAnimationFrame(function(){requestAnimationFrame(function(){"
            @"try{window.webkit.messageHandlers[H].postMessage({});}catch(e){}"
            @"});});"
            @"}"
            @"document.addEventListener('readystatechange',send);"
            @"window.addEventListener('load',send,{once:true});"
            @"send();"
            @"})();",
            kMessageHandlerPageReady];
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
    setWebViewBackgroundColor(webView, chromeBackgroundColor);
    webView.scrollView.opaque = YES;
    configureScrollViewForWebView(webView.scrollView);
    if (@available(iOS 13.0, *)) {
        if (_presentationBackgroundColorHex.length > 0) {
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
    _isCardCurrentlyPresented = NO;
}

- (void)didFinishSafariDismiss {
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    internal.currentSafariViewController = nil;
    if (self.delegate && [self.delegate respondsToSelector:@selector(stashNativeCardDidDismiss)]) {
        [self.delegate stashNativeCardDidDismiss];
    }
    if (_safariBrowserCloseDelegatePending) {
        _safariBrowserCloseDelegatePending = NO;
        if (self.delegate && [self.delegate respondsToSelector:@selector(stashNativeCardDidCloseBrowser)]) {
            [self.delegate stashNativeCardDidCloseBrowser];
        }
    }
}

- (void)dismissSafariViewController {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self dismissSafariViewController]; });
        return;
    }
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    if (internal.currentSafariViewController) {
        [internal.currentSafariViewController dismissViewControllerAnimated:YES completion:^{
            [self didFinishSafariDismiss];
        }];
    }
}

- (void)dismissSafariViewControllerWithResult:(BOOL)success {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self dismissSafariViewControllerWithResult:success]; });
        return;
    }
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    if (internal.currentSafariViewController) {
        if (success) {
            if ([self.delegate respondsToSelector:@selector(stashNativeCardDidCompletePaymentWithOrder:)]) {
                [self.delegate stashNativeCardDidCompletePaymentWithOrder:nil];
            } else if ([self.delegate respondsToSelector:@selector(stashNativeCardDidCompletePayment)]) {
                [self.delegate stashNativeCardDidCompletePayment];
            }
        } else {
            if (self.delegate && [self.delegate respondsToSelector:@selector(stashNativeCardDidFailPayment)]) {
                [self.delegate stashNativeCardDidFailPayment];
            }
        }
        [internal.currentSafariViewController dismissViewControllerAnimated:YES completion:^{
            [self didFinishSafariDismiss];
        }];
    }
}

@end

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
