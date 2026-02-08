//
//  StashNativeCard.m
//  StashNative
//
//  Native iOS SDK for Stash Native checkout integration.
//  Ported from Unity plugin - removes Unity dependencies and uses native delegate pattern.
//

#import "StashNativeCard.h"
#import "StashNativeCardPrivate.h"
#import <SafariServices/SafariServices.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

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
        _showDragBar = YES;
        _allowDismiss = YES;
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
                               showDragBar:(BOOL)showDragBar
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
        _showDragBar = showDragBar;
        _allowDismiss = allowDismiss;
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
        _cardWidthRatioLandscape = 0.9f;
        _cardHeightRatioLandscape = 0.6f;
        _tabletWidthRatioPortrait = 0.4f;
        _tabletHeightRatioPortrait = 0.5f;
        _tabletWidthRatioLandscape = 0.3f;
        _tabletHeightRatioLandscape = 0.6f;
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
static BOOL _paymentSuccessCallbackCalled = NO;   // Tracks if success callback was already invoked

// --- Expand/collapse original values (stored when card is presented) ---
static CGFloat _originalCardHeightRatio = 0.68;
static CGFloat _originalCardVerticalPosition = 1.0;
static CGFloat _originalCardWidthRatio = 1.0;
static CGFloat _originalTabletWidthRatio = 0.8;
static CGFloat _originalTabletHeightRatio = 0.75;

// --- User-configurable sizing (persists across presentations) ---
static BOOL _forcePortraitOnCheckout = NO;
// Phone card: portrait = full width + height ratio; landscape = width/height ratios when not forcing portrait
static CGFloat _cardHeightRatioPortrait = 0.68;
static CGFloat _cardWidthRatioLandscape = 0.9f;
static CGFloat _cardHeightRatioLandscape = 0.6f;

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
/** When YES, the current SFSafariViewController was opened via openBrowser (no callbacks on dismiss). */
static BOOL _safariOpenedViaOpenBrowser = NO;
BOOL _usePopupPresentation = NO;
static BOOL _isCardExpanded = NO;
static BOOL _showScrollbar = NO;

// --- Modal configuration (reset on cleanup) ---
// Non-static: referenced by StashNativeCardViewControllers.m
BOOL _useModalPresentation = NO;
BOOL _modalShowDragBar = YES;
BOOL _modalAllowDismiss = YES;
CGFloat _modalPhoneWidthRatioPortrait = 0.9f;
CGFloat _modalPhoneHeightRatioPortrait = 0.7f;
CGFloat _modalPhoneWidthRatioLandscape = 0.7f;
CGFloat _modalPhoneHeightRatioLandscape = 0.85f;
CGFloat _modalTabletWidthRatioPortrait = 0.40f;
CGFloat _modalTabletHeightRatioPortrait = 0.30f;
CGFloat _modalTabletWidthRatioLandscape = 0.30f;
CGFloat _modalTabletHeightRatioLandscape = 0.40f;

#define ENABLE_IPAD_SUPPORT 1

#pragma mark - Animation Constants (Apple Pay–style: single duration + spring for consistent feel)

/// Primary duration for all card motion (present, expand, collapse, snap-back). Matches system sheet feel.
__unused static const NSTimeInterval kCardAnimationDuration = 0.5;
/// Spring damping for card animations. 0.82 = subtle bounce, Apple-like.
__unused static const CGFloat kSpringDampingCard = 0.82f;
/// Legacy names for call sites that expect these symbols
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
static const CGFloat kHandleBarGray = 0.8f;
const CGFloat kHandleHitAreaInset = 15.0f;

#pragma mark - Overlay / Dismiss Appearance

static const CGFloat kOverlayDismissAlpha = 0.0f;
static const CGFloat kDismissCardAlpha = 0.0f;
static const CGFloat kDismissCardScale = 0.9f;
static const CGFloat kOverlayOpacity = 0.4f;  /* Unified overlay dim (40%) - same on all modes and as Android */
static const CGFloat kIPhoneLandscapeExpandedHeightRatio = 0.9f;  /* Expand = 90% screen height in landscape */
static const NSTimeInterval kOverlayFadeInDuration = 0.25;

#pragma mark - Snap-Back / Entry Animation (same timing as card animations)

static const CGFloat kSpringDampingSnapBack = 0.82f;
static const NSTimeInterval kSnapBackAnimationDuration = 0.45;
static const NSTimeInterval kEntryAnimationDuration = 0.5;
/// Ease-out-back constant for display-link expand/collapse.
static const CGFloat kEaseOutBackOvershoot = 1.70158f;
/// Stronger overshoot for snap-back when dismiss gesture does not hit threshold (smooth spring back).
static const CGFloat kEaseOutBackSnapBackOvershoot = 2.4f;
static const NSTimeInterval kEntryAnimationDelay = 0.05;

static inline CGFloat easeOutBackWithOvershoot(CGFloat t, CGFloat overshoot) {
    if (t <= 0.0f) return 0.0f;
    if (t >= 1.0f) return 1.0f;
    CGFloat k = overshoot;
    CGFloat u = t - 1.0f;
    return 1.0f + (k + 1.0f) * u * u * u + k * u * u;
}
__unused static inline CGFloat easeOutBack(CGFloat t) {
    return easeOutBackWithOvershoot(t, kEaseOutBackOvershoot);
}
static const NSTimeInterval kRotationDelayAfterLandscape = 0.35;

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

static const CGFloat kMinRatio = 0.1f;
static const CGFloat kMaxRatio = 1.0f;
__unused static CGFloat clampRatio(CGFloat ratio) {
    return ratio < kMinRatio ? kMinRatio : (ratio > kMaxRatio ? kMaxRatio : ratio);
}

static NSMutableURLRequest *requestForURL(NSURL *url) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReturnCacheDataElseLoad
                                                       timeoutInterval:kRequestTimeoutSeconds];
    [request setValue:kAcceptEncodingHeader forHTTPHeaderField:@"Accept-Encoding"];
    return request;
}

#pragma mark - Timing

static const NSTimeInterval kWebViewRemoveDelaySeconds = 0.05;
static const NSTimeInterval kDismissAnimationDurationPopup = 0.35;

#pragma mark - Spring Velocities (expand/collapse)

static const CGFloat kSpringVelocityExpand = 0.5f;
static const CGFloat kSpringVelocityCollapse = 0.3f;

#pragma mark - iPad Collapsed Size

static const CGFloat kIPadCollapsedSizeRatio = 0.7f;

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
__unused static const CGFloat kVelocityDivisorForSpringFast = 800.0f;
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

#pragma mark - Associated Object Keys

static NSString * const kAssociatedKeyWebViewDelegate = @"webViewDelegate";
static NSString * const kAssociatedKeyWebViewUIDelegate = @"webViewUIDelegate";
NSString * const StashNativeAssociatedKeyOverlayView = @"overlayView";  // extern for StashNativeCardViewControllers.m
static NSString * const kAssociatedKeyLoadingView = @"loadingView";
static NSString * const kAssociatedKeyCardView = @"cardView";
static NSString * const kAssociatedKeyInitialCardHeight = @"initialCardHeight";

#pragma mark - Helper Function Prototypes

BOOL isRunningOniPad(void);
CGSize calculateiPadCardSize(CGRect screenBounds);
CGRect computePopupFrameForScreenBounds(CGRect screenBounds);
CGRect computeModalFrameForScreenBounds(CGRect screenBounds);
UIColor* getSystemBackgroundColor(void);
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
CGRect computePhoneCardFrameForBoundsAndOrientation(CGRect bounds, BOOL isLandscape);
void updateOriginalCardRatiosForOrientation(BOOL isLandscape);

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

+ (instancetype)sharedInstance;
- (void)dismissWithAnimation:(void (^)(void))completion;
- (void)cleanupCardInstance;
- (void)callDelegateCallbackOnce;
- (UIView *)cardViewForCurrentPresentation;  // Returns cardView (kCardViewTag) for iPhone/iPad; nil if none
- (void)setSkipLayoutDuringInitialSetup:(BOOL)skip forViewController:(UIViewController *)vc;
- (UIView *)createDragTray:(CGFloat)cardWidth;
- (UIView *)createDragTrayVisualOnly:(CGFloat)cardWidth;  // Same look, no pan gesture (for tablet modal)
- (void)expandCardToFullScreen;
- (void)collapseCardToOriginal;
- (void)animateCollapseWithDuration:(NSTimeInterval)duration completion:(void (^)(void))completion;
- (void)animateExpandWithDuration:(NSTimeInterval)duration completion:(void (^)(void))completion;
- (void)updateCardExpansionProgress:(CGFloat)progress cardView:(UIView *)cardView;
- (CGFloat)currentExpansionProgressForCardView:(UIView *)cardView;
- (void)startKeyboardObserving;
- (void)stopKeyboardObserving;
- (BOOL)isIPhoneLandscapeCurrentOrientation;

@end

@implementation StashNativeCardInternal

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

- (BOOL)isIPhoneLandscapeCurrentOrientation {
    if (!self.currentPresentedVC) return NO;
    if (![self.currentPresentedVC isKindOfClass:[IPhoneCardCurrentOrientationViewController class]]) return NO;
    CGRect b = [UIScreen mainScreen].bounds;
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

- (void)cleanupCardInstance {
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
        // Clear all associated objects to break retain cycles and allow deallocation
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyWebViewDelegate, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyWebViewUIDelegate, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)StashNativeAssociatedKeyOverlayView, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyLoadingView, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyCardView, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self.currentPresentedVC, (__bridge const void *)kAssociatedKeyInitialCardHeight, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        for (UIView *subview in [self.currentPresentedVC.view.subviews copy]) {
            if ([subview isKindOfClass:[WKWebView class]]) {
                WKWebView *webView = (WKWebView *)subview;
                
                [webView stopLoading];
                webView.navigationDelegate = nil;
                webView.UIDelegate = nil;
                
                [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerPaymentSuccess];
                [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerPaymentFailure];
                [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerPurchaseProcessing];
                [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerOptin];
                [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerExpand];
                [webView.configuration.userContentController removeScriptMessageHandlerForName:kMessageHandlerCollapse];
                [webView.configuration.userContentController removeAllUserScripts];
                
                [webView loadHTMLString:@"" baseURL:nil];
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWebViewRemoveDelaySeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [webView removeFromSuperview];
                });
                break;
            }
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
        if (self.portraitWindow.rootViewController) {
            [self.portraitWindow.rootViewController dismissViewControllerAnimated:NO completion:nil];
        }
        
        self.portraitWindow.hidden = YES;
        self.portraitWindow.rootViewController = nil;
        
        if (self.previousKeyWindow) {
            [self.previousKeyWindow makeKeyAndVisible];
            self.previousKeyWindow = nil;
        }
        
        self.portraitWindow = nil;
    }
    
    self.currentPresentedVC = nil;
    self.isPurchaseProcessing = NO;
    _isCardExpanded = NO;
    _isCardCurrentlyPresented = NO;
    _usePopupPresentation = NO;
    _useModalPresentation = NO;
    _useCustomPopupSize = NO;
    _callbackWasCalled = NO;
    _paymentSuccessHandled = NO;
    _paymentSuccessCallbackCalled = NO;
}

- (void)dismissWithAnimation:(void (^)(void))completion {
    if (!self.currentPresentedVC) {
        if (completion) completion();
        return;
    }
    
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
                CGRect screenBounds = [UIScreen mainScreen].bounds;
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
    if (_safariOpenedViaOpenBrowser) {
        _safariOpenedViaOpenBrowser = NO;
        _isCardCurrentlyPresented = NO;
        self.currentSafariViewController = nil;
    } else {
        [self cleanupCardInstance];
        [self callDelegateCallbackOnce];
    }
}

- (UIView *)createDragTrayViewWithWidth:(CGFloat)cardWidth {
    // Shared: build drag tray + handle bar (no gesture). Used by createDragTray and createDragTrayVisualOnly.
    DragTrayView *dragTrayView = [[DragTrayView alloc] init];
    dragTrayView.frame = CGRectMake(0, 0, cardWidth, kDragTrayHeight);
    dragTrayView.tag = kDragTrayViewTag;
    dragTrayView.backgroundColor = [UIColor clearColor];
    
    UIView *handleView = [[UIView alloc] init];
    handleView.backgroundColor = [UIColor colorWithWhite:kHandleBarGray alpha:1.0];
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

- (UIView *)createDragTrayVisualOnly:(CGFloat)cardWidth {
    return [self createDragTrayViewWithWidth:cardWidth];
}

- (void)expandCardToFullScreen {
    UIView *cardView = [self cardViewForCurrentPresentation];
    if (!cardView) return;

    _isCardExpanded = YES;

    CGRect screenBounds = [UIScreen mainScreen].bounds;
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
        
        cardView.backgroundColor = getSystemBackgroundColor();
        
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

    CGRect screenBounds = [UIScreen mainScreen].bounds;
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
            CGFloat radius = isRunningOniPad() ? kCornerRadiusExpanded : kCornerRadiusDefault;
            CAShapeLayer *maskLayer = createCornerRadiusMask(cardView.bounds, UIRectCornerTopLeft | UIRectCornerTopRight, radius);
            cardView.layer.mask = maskLayer;
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

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat safeTop = getSafeAreaTopForView(cardView);

    CGFloat collapsedWidth, collapsedHeight, collapsedX, collapsedY;
    CGFloat expandedWidth, expandedHeight, expandedX, expandedY;

    if (isRunningOniPad()) {
        CGSize cardSize = calculateiPadCardSize(screenBounds);
        expandedWidth = cardSize.width;
        expandedHeight = cardSize.height;
        expandedX = (screenBounds.size.width - expandedWidth) / 2;
        expandedY = (screenBounds.size.height - expandedHeight) / 2;

        collapsedWidth = expandedWidth * kIPadCollapsedSizeRatio;
        collapsedHeight = expandedHeight * kIPadCollapsedSizeRatio;
        collapsedX = (screenBounds.size.width - collapsedWidth) / 2;
        collapsedY = (screenBounds.size.height - collapsedHeight) / 2;
    } else {
        // iPhone: use same canonical collapsed frame as initial present (includes min clamp)
        CGRect collapsedFrame = computePhoneCardFrameForBoundsAndOrientation(screenBounds, [self isIPhoneLandscapeCurrentOrientation]);
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
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat safeTop = getSafeAreaTopForView(cardView);
    CGFloat collapsedHeight, expandedHeight;
    if (isRunningOniPad()) {
        CGSize cardSize = calculateiPadCardSize(screenBounds);
        expandedHeight = cardSize.height;
        collapsedHeight = expandedHeight * kIPadCollapsedSizeRatio;
    } else {
        CGRect collapsedFrame = computePhoneCardFrameForBoundsAndOrientation(screenBounds, [self isIPhoneLandscapeCurrentOrientation]);
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
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat safeTop = getSafeAreaTopForView(cardView);
    CGFloat collapsedWidth, collapsedHeight, collapsedX, collapsedY;
    CGFloat expandedWidth, expandedHeight, expandedX, expandedY;
    if (isRunningOniPad()) {
        CGSize cardSize = calculateiPadCardSize(screenBounds);
        expandedWidth = cardSize.width;
        expandedHeight = cardSize.height;
        expandedX = (screenBounds.size.width - expandedWidth) / 2;
        expandedY = (screenBounds.size.height - expandedHeight) / 2;
        collapsedWidth = expandedWidth * kIPadCollapsedSizeRatio;
        collapsedHeight = expandedHeight * kIPadCollapsedSizeRatio;
        collapsedX = (screenBounds.size.width - collapsedWidth) / 2;
        collapsedY = (screenBounds.size.height - collapsedHeight) / 2;
    } else {
        CGRect collapsedFrame = computePhoneCardFrameForBoundsAndOrientation(screenBounds, [self isIPhoneLandscapeCurrentOrientation]);
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
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    if (_usePopupPresentation || _useModalPresentation || isRunningOniPad()) return;
    if (_isCardExpanded) return;
    
    if (!self.currentPresentedVC) return;
    
    if ([self.currentPresentedVC isKindOfClass:[OrientationLockedViewController class]]) {
        OrientationLockedViewController *containerVC = (OrientationLockedViewController *)self.currentPresentedVC;
        containerVC.skipLayoutDuringInitialSetup = YES;
    }
    
    [self expandCardToFullScreen];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    // Keep expanded after keyboard hides - user can collapse manually
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
    
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat safeTop = getSafeAreaTopForView(cardView);
        BOOL landscapeHeightOnly = [self isIPhoneLandscapeCurrentOrientation];
        CGRect collapsedFrame = computePhoneCardFrameForBoundsAndOrientation(screenBounds, landscapeHeightOnly);
        CGFloat collapsedWidth = collapsedFrame.size.width;
        CGFloat collapsedHeight = collapsedFrame.size.height;
        CGFloat collapsedX = collapsedFrame.origin.x;
        CGFloat expandedHeight = landscapeHeightOnly ? (screenBounds.size.height * kIPhoneLandscapeExpandedHeightRatio) : (screenBounds.size.height - safeTop);
        CGFloat currentProgress = 0.0;
        
        if (currentTravel < 0) {
            if (_isCardExpanded) {
                currentProgress = 1.0;
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
            if (!_isCardExpanded) shouldExpand = YES;
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
            CGSize cardSize = calculateiPadCardSize(screenBounds);
            CGFloat originalWidth = cardSize.width;
            CGFloat originalHeight = cardSize.height;
            CGPoint screenCenter = CGPointMake(screenBounds.size.width / 2.0, screenBounds.size.height / 2.0);
            CGRect newBounds = CGRectMake(0, 0, originalWidth, originalHeight);
            
            [UIView animateWithDuration:kAnimationDurationFast 
                                  delay:0 
                 usingSpringWithDamping:kSpringDampingSnapBack 
                  initialSpringVelocity:fabs(velocity.y) / kVelocityDivisorForSpring 
                                options:UIViewAnimationOptionCurveEaseOut 
                             animations:^{
                cardView.bounds = newBounds;
                cardView.center = screenCenter;
                
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
                    [UIView animateWithDuration:kSnapBackAnimationDuration
                                          delay:0
                     usingSpringWithDamping:kSpringDampingSnapBack
                      initialSpringVelocity:fabs(velocity.y) / kVelocityDivisorForSpring
                                    options:UIViewAnimationOptionCurveEaseOut
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
    
    if ([name isEqualToString:kMessageHandlerPaymentSuccess]) {
        if (_paymentSuccessHandled) return;
        _paymentSuccessHandled = YES;
        _paymentSuccessCallbackCalled = YES;
        self.isPurchaseProcessing = NO;
        
        if (delegate && [delegate respondsToSelector:@selector(stashNativeCardDidCompletePayment)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate stashNativeCardDidCompletePayment];
            });
        }
        
        [self dismissWithAnimation:^{
            [self cleanupCardInstance];
        }];
    } else if ([name isEqualToString:kMessageHandlerPaymentFailure]) {
        if (_paymentSuccessHandled) return;
        _paymentSuccessHandled = YES;
        self.isPurchaseProcessing = NO;
        
        if (delegate && [delegate respondsToSelector:@selector(stashNativeCardDidFailPayment)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate stashNativeCardDidFailPayment];
            });
        }
        
        [self dismissWithAnimation:^{
            [self cleanupCardInstance];
        }];
    } else if ([name isEqualToString:kMessageHandlerPurchaseProcessing]) {
        self.isPurchaseProcessing = YES;
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
        // Modal and tablets use fixed sizing - ignore expand/collapse messages
        if (_useModalPresentation || isRunningOniPad()) {
            return;
        }
        
        if (!_usePopupPresentation && !_isCardExpanded && self.currentPresentedVC) {
            [self animateExpandWithDuration:kAnimationDurationDefault completion:nil];
        }
    } else if ([name isEqualToString:kMessageHandlerCollapse]) {
        // Modal and tablets use fixed sizing - ignore expand/collapse messages
        if (_useModalPresentation || isRunningOniPad()) {
            return;
        }
        
        if (!_usePopupPresentation && _isCardExpanded && self.currentPresentedVC) {
            [self animateCollapseWithDuration:kAnimationDurationDefault completion:nil];
        }
    }
}

@end

#pragma mark - Helper Functions

BOOL isRunningOniPad(void) {
#if !ENABLE_IPAD_SUPPORT
    return NO;
#endif
    
    if (![NSThread isMainThread]) {
        __block BOOL result = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = isRunningOniPad();
        });
        return result;
    }
    
    return ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad);
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
        return (currentStyle == UIUserInterfaceStyleDark) ? [UIColor blackColor] : [UIColor systemBackgroundColor];
    }
    return [UIColor whiteColor];
}

CGFloat getSafeAreaTopForView(UIView *view) {
    if (!view) return 0;
    if (@available(iOS 11.0, *)) {
        UIView *parentView = view.superview;
        if (parentView && [parentView respondsToSelector:@selector(safeAreaInsets)]) {
            return parentView.safeAreaInsets.top;
        }
    }
    return 0;
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
    if (cardY < 0) cardY = 0;
    return CGRectMake(cardX, cardY, cardWidth, cardHeight);
}

void updateOriginalCardRatiosForOrientation(BOOL isLandscape) {
    if (isLandscape) {
        _originalCardWidthRatio = _cardWidthRatioLandscape;
        _originalCardHeightRatio = _cardHeightRatioLandscape;
    } else {
        _originalCardWidthRatio = 1.0f;
        _originalCardHeightRatio = _cardHeightRatioPortrait;
    }
    _originalCardVerticalPosition = 1.0f;
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

/// Sets the WebView (and other fill-the-card subviews) to cardView.bounds so the card and WebView stay in sync after rotation or any card frame change.
void layoutCardContentToBounds(UIView *cardView) {
    if (!cardView) return;
    CGRect bounds = cardView.bounds;
    for (UIView *subview in cardView.subviews) {
        if ([subview isKindOfClass:[WKWebView class]]) {
            subview.frame = bounds;
            break;
        }
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
    if (@available(iOS 11.0, *)) {
        scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    scrollView.contentInset = UIEdgeInsetsZero;
    scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    scrollView.bounces = NO;
    scrollView.alwaysBounceVertical = NO;
    scrollView.alwaysBounceHorizontal = NO;
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
        }
    }
}

UIWindow* getKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) return w;
                }
                if (ws.windows.count > 0) return ws.windows.firstObject;
                break;
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

NSString* appendThemeQueryParameter(NSString* url) {
    if (url == nil || url.length == 0) {
        return url;
    }
    
    NSString *theme = kThemeLight;
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle currentStyle = [UITraitCollection currentTraitCollection].userInterfaceStyle;
        if (currentStyle == UIUserInterfaceStyleDark) {
            theme = kThemeDark;
        }
    }
    
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

@implementation StashNativeCard

+ (instancetype)sharedInstance {
    static StashNativeCard *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[StashNativeCard alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // No instance-specific defaults; card sizing comes from config passed to openCardWithURL:config:
    }
    return self;
}

- (BOOL)isCurrentlyPresented {
    return _isCardCurrentlyPresented;
}

- (BOOL)isPurchaseProcessing {
    return [StashNativeCardInternal sharedInstance].isPurchaseProcessing;
}

// ============================================================================
// openCardWithURL:config: (applies config to static sizing, then opens)
// ============================================================================

- (void)openCardWithURL:(NSString *)url config:(StashNativeCardConfig *)config {
    if (url == nil || url.length == 0) {
        return;
    }
    
    if (config) {
        _forcePortraitOnCheckout = config.forcePortrait;
        _cardHeightRatioPortrait = config.cardHeightRatioPortrait;
        _cardWidthRatioLandscape = config.cardWidthRatioLandscape;
        _cardHeightRatioLandscape = config.cardHeightRatioLandscape;
        _tabletWidthRatioPortrait = config.tabletWidthRatioPortrait;
        _tabletHeightRatioPortrait = config.tabletHeightRatioPortrait;
        _tabletWidthRatioLandscape = config.tabletWidthRatioLandscape;
        _tabletHeightRatioLandscape = config.tabletHeightRatioLandscape;
    }
    
    _usePopupPresentation = NO;
    _useModalPresentation = NO;
    [self openURLInternal:url];
}

- (void)openBrowserWithURL:(NSString *)url {
    if (url == nil || url.length == 0) {
        return;
    }
    NSString *urlWithTheme = appendThemeQueryParameter(url);
    _safariOpenedViaOpenBrowser = YES;
    [self openInSafariViewController:urlWithTheme];
}

- (void)closeBrowser {
    [self dismissSafariViewController];
}

- (void)openPopupWithURL:(NSString *)url {
    [self openPopupWithURL:url sizeConfig:nil];
}

- (void)openPopupWithURL:(NSString *)url sizeConfig:(StashNativePopupSizeConfig *)sizeConfig {
    if (url == nil || url.length == 0) {
        return;
    }
    
    _usePopupPresentation = YES;
    
    if (sizeConfig) {
        _useCustomPopupSize = YES;
        _customPortraitWidthMultiplier = sizeConfig.portraitWidthMultiplier;
        _customPortraitHeightMultiplier = sizeConfig.portraitHeightMultiplier;
        _customLandscapeWidthMultiplier = sizeConfig.landscapeWidthMultiplier;
        _customLandscapeHeightMultiplier = sizeConfig.landscapeHeightMultiplier;
    } else {
        _useCustomPopupSize = NO;
    }
    
    [self openURLInternal:url];
}

- (void)openModalWithURL:(NSString *)url {
    [self openModalWithURL:url config:nil];
}

- (void)openModalWithURL:(NSString *)url config:(StashNativeModalConfig *)config {
    if (url == nil || url.length == 0) {
        return;
    }
    
    _usePopupPresentation = NO;
    _useModalPresentation = YES;
    
    if (config) {
        _modalShowDragBar = config.showDragBar;
        _modalAllowDismiss = config.allowDismiss;
        _modalPhoneWidthRatioPortrait = config.phoneWidthRatioPortrait;
        _modalPhoneHeightRatioPortrait = config.phoneHeightRatioPortrait;
        _modalPhoneWidthRatioLandscape = config.phoneWidthRatioLandscape;
        _modalPhoneHeightRatioLandscape = config.phoneHeightRatioLandscape;
        _modalTabletWidthRatioPortrait = config.tabletWidthRatioPortrait;
        _modalTabletHeightRatioPortrait = config.tabletHeightRatioPortrait;
        _modalTabletWidthRatioLandscape = config.tabletWidthRatioLandscape;
        _modalTabletHeightRatioLandscape = config.tabletHeightRatioLandscape;
    } else {
        // Use defaults
        _modalShowDragBar = YES;
        _modalAllowDismiss = YES;
        _modalPhoneWidthRatioPortrait = 0.9f;
        _modalPhoneHeightRatioPortrait = 0.7f;
        _modalPhoneWidthRatioLandscape = 0.7f;
        _modalPhoneHeightRatioLandscape = 0.85f;
        _modalTabletWidthRatioPortrait = 0.40f;
        _modalTabletHeightRatioPortrait = 0.30f;
        _modalTabletWidthRatioLandscape = 0.30f;
        _modalTabletHeightRatioLandscape = 0.40f;
    }
    
    [self openURLInternal:url];
}

- (void)openURLInternal:(NSString *)url {
    if (_isCardCurrentlyPresented) {
        return;
    }
    
    NSString *urlWithTheme = appendThemeQueryParameter(url);
    [self openInCardUI:urlWithTheme];
}

- (void)openInSafariViewController:(NSString *)url {
    NSURL *nsurl = [NSURL URLWithString:url];
    if (!nsurl) return;
    
    SFSafariViewController *safariVC = [[SFSafariViewController alloc] initWithURL:nsurl];
    safariVC.delegate = [StashNativeCardInternal sharedInstance];
    [StashNativeCardInternal sharedInstance].currentSafariViewController = safariVC;
    
    UIViewController *topVC = getTopPresentedViewController();
    [topVC presentViewController:safariVC animated:YES completion:^{
        _isCardCurrentlyPresented = YES;
    }];
}

- (void)openInCardUI:(NSString *)url {
    // Reset state
    _isCardCurrentlyPresented = YES;
    _callbackWasCalled = NO;
    _paymentSuccessHandled = NO;
    _paymentSuccessCallbackCalled = NO;
    _isCardExpanded = NO;
    
    // Store original (collapsed) configuration from orientation-specific values
    _originalTabletWidthRatio = _tabletWidthRatioPortrait;
    _originalTabletHeightRatio = _tabletHeightRatioPortrait;
    
    if (isRunningOniPad()) {
        // Tablet uses portrait ratios for initial store; not used for phone path
        _originalCardHeightRatio = _cardHeightRatioPortrait;
        _originalCardVerticalPosition = 1.0;
        _originalCardWidthRatio = 1.0;
    } else if (_forcePortraitOnCheckout) {
        _originalCardHeightRatio = _cardHeightRatioPortrait;
        _originalCardVerticalPosition = 1.0;
        _originalCardWidthRatio = 1.0;  // Phone card is always full width in portrait
    } else {
        // Current-orientation path: set originals from current screen orientation
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        BOOL isLandscape = screenBounds.size.width > screenBounds.size.height;
        if (isLandscape) {
            _originalCardWidthRatio = _cardWidthRatioLandscape;
            _originalCardHeightRatio = _cardHeightRatioLandscape;
            _originalCardVerticalPosition = 1.0;
        } else {
            _originalCardWidthRatio = 1.0;
            _originalCardHeightRatio = _cardHeightRatioPortrait;
            _originalCardVerticalPosition = 1.0;
        }
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
    
    // CRITICAL: Force device rotation to portrait BEFORE showing window
    // This must happen before makeKeyAndVisible for proper keyboard orientation
    [[UIDevice currentDevice] setValue:@(UIInterfaceOrientationPortrait) forKey:@"orientation"];
    [UIViewController attemptRotationToDeviceOrientation];
    
    // For iOS 16+, also request geometry update
    if (@available(iOS 16.0, *)) {
        UIWindowScene *windowScene = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                windowScene = (UIWindowScene *)scene;
                break;
            }
        }
        if (windowScene) {
            UIWindowSceneGeometryPreferencesIOS *prefs = [[UIWindowSceneGeometryPreferencesIOS alloc] 
                initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
            [windowScene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
                // Silently handle - rotation may still work via UIDevice.setValue
            }];
        }
    }
    
    // Make window visible AFTER rotation request
    // The portrait-only VC will help maintain the rotation
    cardWindow.hidden = NO;
    [cardWindow makeKeyAndVisible];
    [containerVC.view setNeedsLayout];
    [containerVC.view layoutIfNeeded];
    
    // Wait for rotation to complete before setting up UI
    NSTimeInterval rotationDelay = isLandscape ? kRotationDelayAfterLandscape : 0.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(rotationDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Get actual screen bounds after rotation
        CGRect actualBounds = [UIScreen mainScreen].bounds;
        
        // If still landscape (rotation didn't work), we still use portrait dimensions
        // but the keyboard will be in landscape - this is the fallback behavior
        CGFloat actualPortraitWidth = fmin(actualBounds.size.width, actualBounds.size.height);
        CGFloat actualPortraitHeight = fmax(actualBounds.size.width, actualBounds.size.height);
        BOOL rotationSucceeded = (actualBounds.size.width < actualBounds.size.height);
        
        // Update window frame to actual screen bounds
        cardWindow.frame = actualBounds;
        containerVC.view.frame = actualBounds;
        
        // Calculate card dimensions using portrait dimensions
        CGFloat cardWidth, cardHeight, cardX, cardFinalY, startY;
        
        if (rotationSucceeded) {
            // Rotation worked - use actual bounds (phone card is always full width)
            cardWidth = actualBounds.size.width;
            cardHeight = actualBounds.size.height * _cardHeightRatioPortrait;
            cardX = (actualBounds.size.width - cardWidth) / 2.0;
            cardFinalY = actualBounds.size.height - cardHeight;
            startY = actualBounds.size.height + cardHeight;
        } else {
            // Rotation failed - present in portrait orientation within landscape screen
            cardWidth = actualPortraitWidth;
            cardHeight = actualPortraitHeight * _cardHeightRatioPortrait;
            cardX = (actualBounds.size.width - cardWidth) / 2.0;
            cardFinalY = actualBounds.size.height - cardHeight;
            startY = actualBounds.size.height + cardHeight;
        }
        
        if (cardFinalY < 0) cardFinalY = 0;
        
        // Create overlay (full screen, behind the card)
        UIView *overlayView = createOverlayViewWithFrame(actualBounds, cardWindow, 0, containerVC);
        
        // Create cardView
        UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(cardX, startY, cardWidth, cardHeight)];
        cardView.backgroundColor = getSystemBackgroundColor();
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
        
        // Create WebView and load URL
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
        
        // Add drag tray so it is part of the card from the start (visible during slide-up)
        UIView *dragTray = [internal createDragTray:cardWidth];
        [cardView addSubview:dragTray];
        internal.dragTrayView = dragTray;
        
        WebViewLoadDelegate *delegate = [[WebViewLoadDelegate alloc] initWithWebView:webView loadingView:loadingView];
        webView.navigationDelegate = delegate;
        WebViewUIDelegate *uiDelegate = [[WebViewUIDelegate alloc] init];
        webView.UIDelegate = uiDelegate;
        objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewDelegate, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewUIDelegate, uiDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        NSURL *nsurl = [NSURL URLWithString:url];
        if (nsurl) {
            NSMutableURLRequest *request = requestForURL(nsurl);
            delegate.pageLoadStartTime = CFAbsoluteTimeGetCurrent();
            [webView loadRequest:request];
        }
        
        // Animate overlay fade in
        [UIView animateWithDuration:kOverlayFadeInDuration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:kOverlayOpacity];
        } completion:nil];
        
        // Animate card sliding UP from BOTTOM
        [UIView animateWithDuration:kEntryAnimationDuration
                              delay:kEntryAnimationDelay
             usingSpringWithDamping:kSpringDampingTight
              initialSpringVelocity:kSpringVelocityExpand
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
            
            [internal startKeyboardObserving];
            
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
    
    cardWindow.rootViewController = containerVC;
    internal.currentPresentedVC = containerVC;
    
    cardWindow.hidden = NO;
    [cardWindow makeKeyAndVisible];
    [containerVC.view setNeedsLayout];
    [containerVC.view layoutIfNeeded];
    
    CGRect actualBounds = screenBounds;
    CGFloat cardWidth, cardHeight, cardX, cardFinalY, startY;
    
    if (isLandscape) {
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
    
    if (cardFinalY < 0) cardFinalY = 0;
    
    UIView *overlayView = createOverlayViewWithFrame(actualBounds, cardWindow, 0, containerVC);
    
    UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(cardX, startY, cardWidth, cardHeight)];
    cardView.backgroundColor = getSystemBackgroundColor();
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
    
    WebViewLoadDelegate *delegate = [[WebViewLoadDelegate alloc] initWithWebView:webView loadingView:loadingView];
    webView.navigationDelegate = delegate;
    WebViewUIDelegate *uiDelegate = [[WebViewUIDelegate alloc] init];
    webView.UIDelegate = uiDelegate;
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewDelegate, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewUIDelegate, uiDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    NSURL *nsurl = [NSURL URLWithString:url];
    if (nsurl) {
        NSMutableURLRequest *request = requestForURL(nsurl);
        delegate.pageLoadStartTime = CFAbsoluteTimeGetCurrent();
        [webView loadRequest:request];
    }
    
    [UIView animateWithDuration:kOverlayFadeInDuration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:kOverlayOpacity];
    } completion:nil];
    
    [UIView animateWithDuration:kEntryAnimationDuration
                          delay:kEntryAnimationDelay
         usingSpringWithDamping:kSpringDampingTight
          initialSpringVelocity:kSpringVelocityExpand
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
        [internal startKeyboardObserving];
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
    cardView.backgroundColor = getSystemBackgroundColor();
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
    WebViewLoadDelegate *delegate = [[WebViewLoadDelegate alloc] initWithWebView:webView loadingView:loadingView];
    webView.navigationDelegate = delegate;
    WebViewUIDelegate *uiDelegate = [[WebViewUIDelegate alloc] init];
    webView.UIDelegate = uiDelegate;
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewDelegate, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewUIDelegate, uiDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyCardView, cardView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Load URL
    NSURL *nsurl = [NSURL URLWithString:url];
    if (nsurl) {
        NSMutableURLRequest *request = requestForURL(nsurl);
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
    
    // iPad tablets don't use expand/collapse
    _isCardExpanded = YES;
    
    UIView *overlayView = createOverlayViewWithFrame(screenBounds, containerVC.view, 0, containerVC);
    
    [containerVC updateCornerRadiusMaskForCardView];
    applyCardShadowToLayer(cardView.layer, NO);
    
    // Short delay before showing (helps rendering in game engines e.g. Unreal)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
    cardView.backgroundColor = getSystemBackgroundColor();
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
    
    // Add visual-only drag tray if configured (modal never supports drag gestures)
    if (_modalShowDragBar) {
        UIView *dragTray = [internal createDragTrayVisualOnly:frame.size.width];
        [cardView addSubview:dragTray];
        internal.dragTrayView = dragTray;
    }
    
    // Create delegates
    WebViewLoadDelegate *delegate = [[WebViewLoadDelegate alloc] initWithWebView:webView loadingView:loadingView];
    webView.navigationDelegate = delegate;
    WebViewUIDelegate *uiDelegate = [[WebViewUIDelegate alloc] init];
    webView.UIDelegate = uiDelegate;
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewDelegate, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewUIDelegate, uiDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyCardView, cardView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Load URL
    NSURL *nsurl = [NSURL URLWithString:url];
    if (nsurl) {
        NSMutableURLRequest *request = requestForURL(nsurl);
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        cardWindow.hidden = NO;
        [cardWindow makeKeyAndVisible];
        [containerVC.view setNeedsLayout];
        [containerVC.view layoutIfNeeded];
        
        // Modal waits for page load before showing anything
        // Both overlay and cardView stay hidden until WebViewLoadDelegate reveals them
        // Add dismiss button on overlay if allowDismiss is enabled (button is invisible until overlay fades in)
        if (_modalAllowDismiss) {
            UIButton *dismissButton = [UIButton buttonWithType:UIButtonTypeCustom];
            dismissButton.frame = overlayView.bounds;
            dismissButton.backgroundColor = [UIColor clearColor];
            dismissButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [overlayView addSubview:dismissButton];
            [dismissButton addTarget:self action:@selector(handleOverlayTap) forControlEvents:UIControlEventTouchUpInside];
        }
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
    WebViewLoadDelegate *delegate = [[WebViewLoadDelegate alloc] initWithWebView:webView loadingView:loadingView];
    webView.navigationDelegate = delegate;
    WebViewUIDelegate *uiDelegate = [[WebViewUIDelegate alloc] init];
    webView.UIDelegate = uiDelegate;
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewDelegate, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewUIDelegate, uiDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyLoadingView, loadingView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Load URL
    NSURL *nsurl = [NSURL URLWithString:url];
    if (nsurl) {
        NSMutableURLRequest *request = requestForURL(nsurl);
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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

- (WKWebView *)createConfiguredWebViewWithInternal:(StashNativeCardInternal *)internal {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.allowsAirPlayForMediaPlayback = YES;
    config.allowsPictureInPictureMediaPlayback = YES;
    
    if (@available(iOS 14.0, *)) {
        config.limitsNavigationsToAppBoundDomains = NO;
    }
    if (@available(iOS 11.0, *)) {
        config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
        config.dataDetectorTypes = WKDataDetectorTypeAll;
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
    
    NSString *stashSDKScript = [NSString stringWithFormat:@"(function() {"
        "window.stash_sdk = window.stash_sdk || {};"
        "window.stash_sdk.onPaymentSuccess = function(data) {"
            "window.webkit.messageHandlers.%@.postMessage(data || {});"
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
    "})();",
        kMessageHandlerPaymentSuccess, kMessageHandlerPaymentFailure, kMessageHandlerPurchaseProcessing,
        kMessageHandlerOptin, kMessageHandlerExpand, kMessageHandlerCollapse];
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
    
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerPaymentSuccess];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerPaymentFailure];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerPurchaseProcessing];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerOptin];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerExpand];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerCollapse];
    config.userContentController = userContentController;
    
    UIColor *systemBackgroundColor = getSystemBackgroundColor();
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    webView.opaque = YES;
    webView.hidden = NO;
    setWebViewBackgroundColor(webView, systemBackgroundColor);
    webView.scrollView.opaque = YES;
    configureScrollViewForWebView(webView.scrollView);
    webView.scrollView.scrollEnabled = YES;
    webView.scrollView.showsVerticalScrollIndicator = _showScrollbar;
    webView.scrollView.showsHorizontalScrollIndicator = NO;
    
    return webView;
}

- (UIView *)createLoadingViewWithFrame:(CGRect)frame {
    UIView *loadingView = [[UIView alloc] initWithFrame:frame];
    
    BOOL isDarkMode = NO;
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle currentStyle = [UITraitCollection currentTraitCollection].userInterfaceStyle;
        isDarkMode = (currentStyle == UIUserInterfaceStyleDark);
    }
    
    UIColor *backgroundColor = isDarkMode ? [UIColor blackColor] : [UIColor whiteColor];
    loadingView.backgroundColor = backgroundColor;
    loadingView.opaque = YES;
    
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.color = isDarkMode ? [UIColor whiteColor] : [UIColor darkGrayColor];
    
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
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    [internal dismissWithAnimation:^{
        [internal cleanupCardInstance];
        [internal callDelegateCallbackOnce];
    }];
}

- (void)resetPresentationState {
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
}

- (void)dismissSafariViewController {
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    if (internal.currentSafariViewController) {
        [internal.currentSafariViewController dismissViewControllerAnimated:YES completion:^{
            [self didFinishSafariDismiss];
        }];
    }
}

- (void)dismissSafariViewControllerWithResult:(BOOL)success {
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    if (internal.currentSafariViewController) {
        if (success) {
            if (self.delegate && [self.delegate respondsToSelector:@selector(stashNativeCardDidCompletePayment)]) {
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
