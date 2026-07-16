//
//  StashNativeCard.m
//  StashNative
//
//  Core implementation: public API, orientation swizzle, presentation paths, WebView factory,
//  Safari flow, and the single home for all shared state and cross-file constants.
//  Shared symbols are extern'd via StashNativeCardPrivate.h and consumed by the other .m files.
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
// Non-static: extern'd via StashNativeCardPrivate.h.
// Also used below to initialize _custom* multipliers, so definitions stay in this file.
const CGFloat kPopupPortraitWidthMultiplier = 1.0285;
const CGFloat kPopupPortraitHeightMultiplier = 1.485;
const CGFloat kPopupLandscapeWidthMultiplier = 1.2275445;
const CGFloat kPopupLandscapeHeightMultiplier = 1.1385;

// CLAUDE.md contract: all card/modal sizing ratios clamp to [0.1, 1.0] (parity with Android clampRatio).
// The inverted first comparison catches NaN (all ordered comparisons with NaN are false),
// which would otherwise flow into CGRectMake and raise a CALayer NaN exception.
static CGFloat stashClampRatio(CGFloat v) {
    if (!(v >= 0.1f)) return 0.1f;
    if (v > 1.0f) return 1.0f;
    return v;
}

// Popup multipliers legitimately exceed 1.0, so they get the popup defaults as fallback
// instead of the [0.1, 1.0] clamp. Inverted comparison catches NaN; isinf catches the rest
// of what CGRectMake cannot digest.
static CGFloat stashSanitizePopupMultiplier(CGFloat v, CGFloat fallback) {
    if (!(v > 0.0f) || isinf(v)) return fallback;
    return v;
}

#pragma mark - Private State
// Note: These statics are reset in [StashNativeCardInternal cleanupCardInstance].
// They are file-scope to this translation unit and effectively private to the SDK.

// --- Transient presentation state (reset on each dismiss) ---
BOOL _callbackWasCalled = NO;              // Ensures dismiss callback fires only once
BOOL _isCardCurrentlyPresented = NO;       // Guards against double-presentation
BOOL _paymentSuccessHandled = NO;          // Ensures payment result callback fires only once

// --- Expand/collapse original values (stored when card is presented) ---
// Non-static: extern'd via StashNativeCardPrivate.h
CGFloat _originalCardHeightRatio = 0.68;
CGFloat _originalCardVerticalPosition = 1.0;
CGFloat _originalCardWidthRatio = 1.0;

// --- User-configurable sizing (persists across presentations) ---
// Card/tablet ratios non-static: extern'd via StashNativeCardPrivate.h
BOOL _forcePortraitOnCheckout = NO;
// Phone card: portrait = full width + height ratio; landscape = width/height ratios when not forcing portrait
CGFloat _cardHeightRatioPortrait = 0.68;
CGFloat _cardWidthRatioLandscape = 0.7f;
CGFloat _cardHeightRatioLandscape = 0.9f;

// Orientation-specific tablet (iPad) card configuration
CGFloat _tabletWidthRatioPortrait = 0.4;
CGFloat _tabletHeightRatioPortrait = 0.5;
CGFloat _tabletWidthRatioLandscape = 0.3;
CGFloat _tabletHeightRatioLandscape = 0.6;

// --- Popup size configuration (reset on cleanup) ---
// Non-static: extern'd via StashNativeCardPrivate.h
BOOL _useCustomPopupSize = NO;
CGFloat _customPortraitWidthMultiplier = kPopupPortraitWidthMultiplier;
CGFloat _customPortraitHeightMultiplier = kPopupPortraitHeightMultiplier;
CGFloat _customLandscapeWidthMultiplier = 1.753635;  // Default custom landscape is wider
CGFloat _customLandscapeHeightMultiplier = kPopupLandscapeHeightMultiplier;

// --- Presentation mode flags (reset on cleanup) ---
/** When YES, the current SFSafariViewController was opened via openBrowser (card-dismiss callbacks differ). */
BOOL _safariOpenedViaOpenBrowser = NO;
/** Pending deliver-once for stashNativeCardDidCloseBrowser (delegate vs dismiss completion order). */
BOOL _safariBrowserCloseDelegatePending = NO;

static void resetSafariOpenBrowserTrackingFlags(void) {
    _safariOpenedViaOpenBrowser = NO;
    _safariBrowserCloseDelegatePending = NO;
}

BOOL _usePopupPresentation = NO;
BOOL _isCardExpanded = NO;

// --- Landscape / force-portrait orientation flags (phones only; reset on cleanup) ---
/// YES when the card was opened in the current (landscape) orientation without forcing portrait.
/// Card stays at its configured size; expand/collapse have no effect.
BOOL _cardIsInLandscape = NO;
/// Safe-area top inset (notch / Dynamic Island) of the active card window, in points.
/// Used to clamp card height so the card never overlaps the notch. Reset to 0 on cleanup.
CGFloat _cardSafeAreaTop = 0.0f;

// --- Modal configuration (reset on cleanup) ---
// Non-static: extern'd via StashNativeCardPrivate.h
BOOL _useModalPresentation = NO;
BOOL _modalAllowDismiss = YES;
/** When NO, dialog stays open after onPaymentSuccess/onPaymentFailure. Reset to YES on cleanup. */
BOOL _autoCloseOnPaymentEvent = YES;
CGFloat _modalPhoneWidthRatioPortrait = 0.9f;
CGFloat _modalPhoneHeightRatioPortrait = 0.7f;
CGFloat _modalPhoneWidthRatioLandscape = 0.7f;
CGFloat _modalPhoneHeightRatioLandscape = 0.85f;
CGFloat _modalTabletWidthRatioPortrait = 0.40f;
CGFloat _modalTabletHeightRatioPortrait = 0.30f;
CGFloat _modalTabletWidthRatioLandscape = 0.30f;
CGFloat _modalTabletHeightRatioLandscape = 0.40f;

/** Optional #hex for card/modal chrome; cleared on cleanup. */
NSString *_presentationBackgroundColorHex = nil;  // Non-static: extern'd via StashNativeCardPrivate.h

#pragma mark - Animation Constants (Apple Pay–style: single duration + spring for consistent feel)

const CGFloat kSpringDampingDefault = 0.82f;
const CGFloat kAnimationDurationDefault = 0.5f;
// Non-static: extern'd via StashNativeCardPrivate.h
const CGFloat kCornerRadiusDefault = 20.0f;
const CGFloat kDragTrayHeight = 44.0f;

#pragma mark - View Tag Constants
// Non-static: extern'd via StashNativeCardPrivate.h
const NSInteger kCardViewTag = 9999;
const NSInteger kDragTrayViewTag = 8888;
const NSInteger kDragHandleViewTag = 8889;

#pragma mark - Handle Bar (Drag Tray) Constants
// Non-static: extern'd via StashNativeCardPrivate.h
const CGFloat kHandleBarWidth = 36.0f;
const CGFloat kHandleBarHeight = 5.0f;
const CGFloat kHandleBarTopInset = 8.0f;
const CGFloat kHandleBarHalfWidth = 18.0f;
const CGFloat kHandleHitAreaInset = 15.0f;

#pragma mark - Overlay / Dismiss Appearance

static const CGFloat kOverlayOpacity = 0.4f;  /* Unified overlay dim (40%) - same on all modes and as Android */
const NSTimeInterval kOverlayFadeInDuration = 0.25;

#pragma mark - Snap-Back / Entry Animation (same timing as card animations)

/// Slide-up presentation: duration tuned for sheet feel. Damping 1 + zero velocity avoids spring overshoot
/// past the rest Y (undershoot in UIKit spring briefly lifts the card → visible gap above screen bottom).
static const NSTimeInterval kCardEntrySpringDuration = 0.55;
static const CGFloat kCardEntrySpringDamping = 1.0f;
static const CGFloat kCardEntrySpringVelocity = 0.0f;
/// After overlay fade finishes, brief hold before sheet slide so off-screen WebView can advance load.
static const NSTimeInterval kCardEntryHoldAfterOverlayFadeIn = 0.2;

static const NSTimeInterval kRotationDelayAfterLandscape = 0.35;

#pragma mark - Shadow (iPhone card vs iPad/popup)
// Non-static: extern'd via StashNativeCardPrivate.h

const CGFloat kShadowOpacityPhone = 0.2f;
const CGFloat kShadowRadiusPhone = 10.0f;
const CGFloat kShadowOffsetYPhone = -3.0f;
const CGFloat kShadowOpacityPopup = 0.15f;
const CGFloat kShadowRadiusPopup = 12.0f;
const CGFloat kShadowOffsetYPopup = 4.0f;

#pragma mark - Request (timeout, Accept-Encoding)

static const NSTimeInterval kRequestTimeoutSeconds = 15.0;
static NSString * const kAcceptEncodingHeader = @"gzip, deflate, br";

static NSMutableURLRequest *requestForURL(NSURL *url) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                       timeoutInterval:kRequestTimeoutSeconds];
    [request setValue:kAcceptEncodingHeader forHTTPHeaderField:@"Accept-Encoding"];
    return request;
}

#pragma mark - Timing

const NSTimeInterval kDismissAnimationDurationPopup = 0.35;

#pragma mark - Spring Velocities (expand/collapse)

const CGFloat kSpringVelocityExpand = 0.5f;

#pragma mark - Gesture Thresholds (iPhone)

const CGFloat kDismissVelocityThreshold = 500.0f;

#pragma mark - Popup Frame (OrientationLockedViewController)
// Non-static: extern'd via StashNativeCardPrivate.h
const CGFloat kPopupBaseSizePercentageIPad = 0.5f;
const CGFloat kPopupBaseSizePercentagePhone = 0.75f;
const CGFloat kPopupBaseSizeMinIPad = 400.0f;
const CGFloat kPopupBaseSizeMinPhone = 300.0f;
const CGFloat kPopupBaseSizeMax = 500.0f;
const NSTimeInterval kPopupFrameAnimationDuration = 0.5;

#pragma mark - Message Handler Names (WKScriptMessageHandler)

NSString * const kMessageHandlerPaymentSuccess = @"stashNativementSuccess";
NSString * const kMessageHandlerPaymentFailure = @"stashNativementFailure";
NSString * const kMessageHandlerPurchaseProcessing = @"stashPurchaseProcessing";
NSString * const kMessageHandlerProcessingCompleted = @"stashProcessingCompleted";
NSString * const kMessageHandlerOptin = @"stashOptin";
NSString * const kMessageHandlerExpand = @"stashExpand";
NSString * const kMessageHandlerCollapse = @"stashCollapse";
NSString * const kMessageHandlerWindowClose = @"stashWindowClose";
NSString * const kMessageHandlerExternalPayment = @"stashExternalPayment";
NSString * const kMessageHandlerOpenLink = @"stashOpenLink";
NSString * const kMessageHandlerPageReady = @"stashNativePageReady";

#pragma mark - Associated Object Keys

NSString * const kAssociatedKeyWebViewDelegate = @"webViewDelegate";
NSString * const kAssociatedKeyWebViewUIDelegate = @"webViewUIDelegate";
NSString * const StashNativeAssociatedKeyOverlayView = @"overlayView";  // extern for StashNativeCardViewControllers.m
NSString * const kAssociatedKeyLoadingView = @"loadingView";
NSString * const kAssociatedKeyCardView = @"cardView";
NSString * const kAssociatedKeyInitialCardHeight = @"initialCardHeight";



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
                if (window && (window == internal.portraitWindow ||
                               window == internal.safariPresentationWindow)) {
                    // Dedicated Safari portrait window (external payment path).
                    if (window == internal.safariPresentationWindow && internal.isSafariPortraitLocked) {
                        return UIInterfaceOrientationMaskPortrait;
                    }
                    // While Safari is actively presented in forced-portrait mode, lock the window
                    // to portrait so the device physically rotating to landscape doesn't flip it.
                    if (internal.isSafariPortraitLocked) {
                        return UIInterfaceOrientationMaskPortrait;
                    }
                    // Card window + keyboard: lock to the card's orientation (must NOT answer
                    // portrait for nil/host windows — that intersects to empty with landscape-only
                    // roots and raises UIApplicationInvalidInterfaceOrientation).
                    if (window == internal.portraitWindow && internal.isIPhoneCardKeyboardVisible) {
                        return [internal stashKeyboardOrientationLockMaskForCardWindow];
                    }
                    // Card window (no keyboard): return the root VC's orientation mask so iOS 15
                    // constrains rotation to the card's intended orientation. On iOS 16+ scene
                    // geometry preferences take precedence. If rootVC is not yet set (brief window
                    // during initial creation), fall back to MaskAll.
                    UIViewController *rootVC = window.rootViewController;
                    if (rootVC) {
                        return [rootVC supportedInterfaceOrientations];
                    }
                    return UIInterfaceOrientationMaskAll;
                }
                // While an orientation-locked card is presented, system windows
                // (keyboard, alerts) must match the card's orientation. On iOS 16+
                // scene geometry handles this; on iOS 15 the delegate callback is
                // the only mechanism. Return the card's mask for any window that is
                // not the host app's own window.
                if (internal.portraitWindow && window != internal.previousKeyWindow) {
                    UIViewController *cardRootVC = internal.portraitWindow.rootViewController;
                    if (cardRootVC) {
                        return [cardRootVC supportedInterfaceOrientations];
                    }
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
    if (window == internal.portraitWindow || window == internal.safariPresentationWindow) {
        if (internal.isSafariPortraitLocked) {
            return UIInterfaceOrientationMaskPortrait;
        }
        if (window == internal.portraitWindow && internal.isIPhoneCardKeyboardVisible) {
            return [internal stashKeyboardOrientationLockMaskForCardWindow];
        }
        UIViewController *rootVC = window.rootViewController;
        if (rootVC) {
            return [rootVC supportedInterfaceOrientations];
        }
        return UIInterfaceOrientationMaskAll;
    }
    // System windows (keyboard, alerts) while card is presented: match the card.
    if (internal.portraitWindow && window != internal.previousKeyWindow) {
        UIViewController *cardRootVC = internal.portraitWindow.rootViewController;
        if (cardRootVC) {
            return [cardRootVC supportedInterfaceOrientations];
        }
    }
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
    return @"2.2.4";
}

- (instancetype)init {
    self = [super init];
    if (self) {
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

// Mirrors openURLInternal's rejection check. Entry points must run it BEFORE writing any
// mode/config globals: a rejected open must not poison the live session's state.
static BOOL stashLivePresentationBlocksOpen(void) {
    if (!_isCardCurrentlyPresented) {
        return NO;
    }
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    return internal.currentPresentedVC != nil
        || internal.currentSafariViewController != nil
        || internal.portraitWindow != nil
        || internal.safariPresentationWindow != nil;
}

- (void)openCardWithURL:(NSString *)url config:(StashNativeCardConfig *)config {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openCardWithURL:url config:config]; });
        return;
    }
    if (url == nil || url.length == 0) {
        return;
    }
    if (stashLivePresentationBlocksOpen()) {
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
    NSString *urlWithTheme = appendThemeQueryParameter(url);
    [self openInSafariViewController:urlWithTheme];
}

- (void)closeBrowser {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self closeBrowser]; });
        return;
    }
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
    if (stashLivePresentationBlocksOpen()) {
        return;
    }

    _presentationBackgroundColorHex = nil;

    _usePopupPresentation = YES;
    
    if (sizeConfig) {
        _useCustomPopupSize = YES;
        _customPortraitWidthMultiplier =
            stashSanitizePopupMultiplier(sizeConfig.portraitWidthMultiplier, kPopupPortraitWidthMultiplier);
        _customPortraitHeightMultiplier =
            stashSanitizePopupMultiplier(sizeConfig.portraitHeightMultiplier, kPopupPortraitHeightMultiplier);
        _customLandscapeWidthMultiplier =
            stashSanitizePopupMultiplier(sizeConfig.landscapeWidthMultiplier, kPopupLandscapeWidthMultiplier);
        _customLandscapeHeightMultiplier =
            stashSanitizePopupMultiplier(sizeConfig.landscapeHeightMultiplier, kPopupLandscapeHeightMultiplier);
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
    if (stashLivePresentationBlocksOpen()) {
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
        // Block only when a presentation is live. A stale flag with nothing on screen is cleared
        // and the open proceeds, rather than returning silently with no callback to the host.
        StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
        BOOL hasLivePresentation = internal.currentPresentedVC != nil
            || internal.currentSafariViewController != nil
            || internal.portraitWindow != nil
            || internal.safariPresentationWindow != nil;
        if (hasLivePresentation) {
            return;
        }
        STASH_DEBUG_LOG(@"StashNative: clearing stale presentation guard before opening card");
        _isCardCurrentlyPresented = NO;
        resetSafariOpenBrowserTrackingFlags();
    }

    NSString *urlWithTheme = appendThemeQueryParameter(url);
    [self openInCardUI:urlWithTheme];
}

- (void)openInSafariViewController:(NSString *)url {
    NSURL *nsurl = [NSURL URLWithString:url];
    if (!nsurl) {
        resetSafariOpenBrowserTrackingFlags();
        StashNativeCardInternal *staleInternal = [StashNativeCardInternal sharedInstance];
        if (staleInternal.isHandingOffPortraitWindowToSafari || staleInternal.safariPresentationWindow) {
            staleInternal.isHandingOffPortraitWindowToSafari = NO;
            [staleInternal tearDownSafariPresentationState];
        }
        return;
    }

    SFSafariViewController *safariVC = [[SFSafariViewController alloc] initWithURL:nsurl];
    safariVC.delegate = [StashNativeCardInternal sharedInstance];
    [StashNativeCardInternal sharedInstance].currentSafariViewController = safariVC;

    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    // A live card must be torn down before Safari takes the window; keep the window alive for
    // the swap (same handoff mechanism as the external-payment path).
    if (internal.currentPresentedVC) {
        if (internal.portraitWindow) {
            internal.isHandingOffPortraitWindowToSafari = YES;
        }
        [internal cleanupCardInstance];
    }
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

        // Modal/popup windows start hidden behind a 50 ms token-guarded reveal; the token
        // bump in cleanupCardInstance cancels that reveal, so a handoff inside that window
        // would otherwise present Safari into a still-hidden UIWindow.
        if (internal.portraitWindow.hidden) {
            internal.portraitWindow.hidden = NO;
            [internal.portraitWindow makeKeyAndVisible];
        }

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
        // Guard: if this Safari was superseded before the present fired -- torn down during a
        // rotation delay, or replaced by a newer openBrowser call -- abort WITHOUT touching
        // shared state. The successor (or the teardown path) owns the tracking flags and
        // currentSafariViewController now; clobbering them here would abort its present too.
        if (internal.currentSafariViewController != safariVC) {
            return;
        }
        if (presenter == nil) {
            resetSafariOpenBrowserTrackingFlags();
            internal.currentSafariViewController = nil;
            // A card handoff may already have swapped the kept window to the Safari
            // container; nothing will ever present into it, so dismantle it.
            if (internal.currentPresentedVC == nil &&
                (internal.portraitWindow || internal.safariPresentationWindow)) {
                [internal tearDownSafariPresentationState];
            }
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
            
            if (internal.currentPresentedVC) {
                [internal startKeyboardObserving];
                [internal registerIPhoneCardWindowGeometryObservers];
            }
            
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
        if (internal.currentPresentedVC) {
            [internal startKeyboardObserving];
            [internal registerIPhoneCardWindowGeometryObservers];
        }
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
    WebViewLoadDelegate *delegate = [[WebViewLoadDelegate alloc] initWithWebView:webView
                                                                     loadingView:loadingView
                                                                   retryArmDelay:0.0
                                                        presentationSessionToken:internal.presentationSessionToken];
    webView.navigationDelegate = delegate;
    WebViewUIDelegate *uiDelegate = [[WebViewUIDelegate alloc] init];
    webView.UIDelegate = uiDelegate;
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewDelegate, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewUIDelegate, uiDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyCardView, cardView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    internal.activeWebViewLoadDelegate = delegate;
    internal.activeWebViewUIDelegate = uiDelegate;
    
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
    WebViewLoadDelegate *delegate = [[WebViewLoadDelegate alloc] initWithWebView:webView
                                                                     loadingView:loadingView
                                                                   retryArmDelay:0.0
                                                        presentationSessionToken:internal.presentationSessionToken];
    webView.navigationDelegate = delegate;
    WebViewUIDelegate *uiDelegate = [[WebViewUIDelegate alloc] init];
    webView.UIDelegate = uiDelegate;
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewDelegate, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewUIDelegate, uiDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyCardView, cardView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    internal.activeWebViewLoadDelegate = delegate;
    internal.activeWebViewUIDelegate = uiDelegate;
    
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
    WebViewLoadDelegate *delegate = [[WebViewLoadDelegate alloc] initWithWebView:webView
                                                                     loadingView:loadingView
                                                                   retryArmDelay:0.0
                                                        presentationSessionToken:internal.presentationSessionToken];
    webView.navigationDelegate = delegate;
    WebViewUIDelegate *uiDelegate = [[WebViewUIDelegate alloc] init];
    webView.UIDelegate = uiDelegate;
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewDelegate, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyWebViewUIDelegate, uiDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(containerVC, (__bridge const void *)kAssociatedKeyLoadingView, loadingView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    internal.activeWebViewLoadDelegate = delegate;
    internal.activeWebViewUIDelegate = uiDelegate;
    
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
            if (internal.currentPresentedVC) {
                [internal startKeyboardObserving];
            }
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
        // Checkout pages: phone numbers/addresses must not become tappable detector links.
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
        "window.stash_sdk.onProcessingCompleted = function(data) {"
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
        "window.stash_sdk.openLink = function(url) {"
            "var s = (url !== undefined && url !== null) ? String(url) : '';"
            "window.webkit.messageHandlers.%@.postMessage(s);"
        "};"
        "try { window.close = function() {"
            "try { window.webkit.messageHandlers.%@.postMessage({}); } catch(e2) {}"
        "}; } catch(e) {}"
    "})();",
        kMessageHandlerPaymentSuccess, kMessageHandlerPaymentFailure, kMessageHandlerPurchaseProcessing,
        kMessageHandlerProcessingCompleted, kMessageHandlerOptin, kMessageHandlerExpand, kMessageHandlerCollapse,
        kMessageHandlerExternalPayment, kMessageHandlerOpenLink, kMessageHandlerWindowClose];
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
            NSString *darkBgAtEnd = [NSString stringWithFormat:
                @"(function(){try{var BG='%@';var h=document.head;if(h&&!h.querySelector('meta[name=color-scheme]')){var m=document.createElement('meta');m.setAttribute('name','color-scheme');m.setAttribute('content','dark');h.insertBefore(m,h.firstChild);}var e=document.documentElement;if(e){e.style.setProperty('background-color',BG,'important');e.style.setProperty('color-scheme','dark','important');}var b=document.body;if(b){b.style.setProperty('background-color',BG,'important');b.style.setProperty('color-scheme','dark','important');}}catch(x){}})();",
                bgHex];
            WKUserScript *darkEnd = [[WKUserScript alloc] initWithSource:darkBgAtEnd
                                                          injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                       forMainFrameOnly:YES];
            [userContentController addUserScript:darkEnd];
        }
    }
    
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerPaymentSuccess];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerPaymentFailure];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerPurchaseProcessing];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerProcessingCompleted];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerOptin];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerExpand];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerCollapse];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerExternalPayment];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerOpenLink];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerWindowClose];
    [userContentController addScriptMessageHandler:internal name:kMessageHandlerPageReady];
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
    if (internal.isDismissingCard) {
        return;
    }
    if (!internal.currentPresentedVC) {
        if (internal.currentSafariViewController) {
            [self dismissSafariViewController];
        }
        return;
    }
    [internal dismissWithAnimation:^{
        [internal callDelegateCallbackOnce];
        [internal cleanupCardInstance];
    }];
}

- (void)resetPresentationState {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self resetPresentationState]; });
        return;
    }
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    [internal cleanupCardInstance];
    // cleanupCardInstance leaves a Safari-owned window alone (openBrowser handoff); reset
    // means reset, so dismantle any live Safari session and its windows here too.
    if (internal.currentSafariViewController || internal.safariPresentationWindow ||
        internal.portraitWindow) {
        UIViewController *presenting = internal.currentSafariViewController.presentingViewController;
        if (presenting) {
            [presenting dismissViewControllerAnimated:NO completion:nil];
        }
        [internal tearDownSafariPresentationState];
    }
    _isCardCurrentlyPresented = NO;
}

- (void)didFinishSafariDismiss {
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];

    // Programmatic dismissal does not invoke safariViewControllerDidFinish:; run the shared
    // teardown here so the presentation state and any portrait window/orientation lock are reset.
    [internal tearDownSafariPresentationState];

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
