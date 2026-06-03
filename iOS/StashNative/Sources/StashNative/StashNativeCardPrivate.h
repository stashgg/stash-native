//
//  StashNativeCardPrivate.h
//  StashNative
//
//  Private declarations for view controllers and delegates used by StashNativeCard.m.
//  Implementations live in StashNativeCardViewControllers.m and StashNativeCardWebViewDelegates.m.
//

#import <UIKit/UIKit.h>
#import "StashNativeCardLogging.h"
#import <WebKit/WebKit.h>
#import "StashNativeCardSupport.h"
#import "StashNativeCardLayout.h"
#import "StashNativeCardTheme.h"
#import "StashNativeCardGeometry.h"

/// Monotonic presentation session token, bumped on each card open and at dismiss teardown.
NSUInteger StashNativeCurrentPresentationSessionToken(void);

/// Preferred full-screen bounds for a window's scene (rotation-safe vs UIScreen.main).
CGRect stashSceneCoordinateBoundsForIPhoneCardWindow(UIWindow *window);

/// Relayouts the iPhone card window, overlay, and sheet. `forcedCardExpansionProgress` in [0,1] overrides
/// measured progress (use 0 after rotation). Pass a value outside [0,1] (e.g. -1) to use automatic progress.
void stashRelayoutIPhoneCardWindowWithTargetBoundsAndProgress(CGRect targetBounds, CGFloat forcedCardExpansionProgress);

// Shared file-scope state and constants defined in StashNativeCard.m.
extern BOOL stash_usePopupPresentation;
extern BOOL stash_useModalPresentation;
extern BOOL stash_autoCloseOnPaymentEvent;
extern BOOL stash_paymentSuccessHandled;
extern BOOL stash_cardIsInLandscape;
extern BOOL stash_isCardExpanded;
extern BOOL stash_forcePortraitOnCheckout;
extern BOOL stash_isCardCurrentlyPresented;
extern NSString *stash_presentationBackgroundColorHex;
extern CGFloat stash_cardHeightRatioPortrait;
extern CGFloat stash_cardHeightRatioLandscape;
extern CGFloat stash_cardWidthRatioLandscape;
extern CGFloat stash_cardSafeAreaTop;
extern CGFloat stash_tabletWidthRatioPortrait;
extern CGFloat stash_tabletHeightRatioPortrait;
extern CGFloat stash_tabletWidthRatioLandscape;
extern CGFloat stash_tabletHeightRatioLandscape;
extern CGFloat stash_modalPhoneWidthRatioPortrait;
extern CGFloat stash_modalPhoneHeightRatioPortrait;
extern CGFloat stash_modalPhoneWidthRatioLandscape;
extern CGFloat stash_modalPhoneHeightRatioLandscape;
extern CGFloat stash_modalTabletWidthRatioPortrait;
extern CGFloat stash_modalTabletHeightRatioPortrait;
extern CGFloat stash_modalTabletWidthRatioLandscape;
extern CGFloat stash_modalTabletHeightRatioLandscape;
extern CGFloat stash_customPortraitWidthMultiplier;
extern CGFloat stash_customPortraitHeightMultiplier;
extern CGFloat stash_customLandscapeWidthMultiplier;
extern CGFloat stash_customLandscapeHeightMultiplier;
extern BOOL stash_useCustomPopupSize;
extern const CGFloat kPopupPortraitWidthMultiplier;
extern const CGFloat kPopupPortraitHeightMultiplier;
extern const CGFloat kPopupLandscapeWidthMultiplier;
extern const CGFloat kPopupLandscapeHeightMultiplier;
extern const CGFloat kPopupBaseSizePercentageIPad;
extern const CGFloat kPopupBaseSizePercentagePhone;
extern const CGFloat kPopupBaseSizeMinIPad;
extern const CGFloat kPopupBaseSizeMinPhone;
extern const CGFloat kPopupBaseSizeMax;
extern const NSTimeInterval kPopupFrameAnimationDuration;
extern const CGFloat kCornerRadiusDefault;
extern const CGFloat kDragTrayHeight;
extern const CGFloat kHandleBarWidth;
extern const CGFloat kHandleBarHalfWidth;
extern const CGFloat kAnimationDurationDefault;
extern const CGFloat kExpandedCardHeightScreenRatio;
extern const CGFloat kFallbackTabletCardHeight;
extern const CGFloat kFallbackTabletCardWidth;
extern const CGFloat kTabletMinHeight;
extern const CGFloat kTabletSdkExpandHeightMultiplier;
extern const CGFloat kHandleBarHeight;
extern const CGFloat kHandleBarTopInset;
extern const CGFloat kHandleHitAreaInset;
extern const NSInteger kCardViewTag;
extern const NSInteger kDragTrayViewTag;
extern const NSInteger kDragHandleViewTag;
extern NSString * const StashNativeAssociatedKeyOverlayView;

@interface DragTrayView : UIView
@end

@interface IPhoneCardViewController : UIViewController
@property (nonatomic, assign) CGRect cardFrame;
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMask;
@end

/// Phone card in current orientation with rotation locked for the card's lifetime.
@interface IPhoneCardCurrentOrientationViewController : UIViewController
@property (nonatomic, assign) CGRect cardFrame;
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
/// Orientation mask to lock to while the card is presented (0 = no lock, allow all).
@property (nonatomic, assign) UIInterfaceOrientationMask lockedOrientationMask;
- (void)updateCornerRadiusMask;
@end

@interface IPadModalViewController : UIViewController
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMaskForCardView;
@end

/// Window-based modal view controller with no orientation lock.
@interface ModalViewController : UIViewController
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMaskForCardView;
@end

@interface OrientationLockedViewController : UIViewController
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL enforcePortrait;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMask;
@end

/// Portrait-only root view controller for the dedicated UIWindow that hosts SFSafariViewController
/// on the external-payment path.
@interface SafariPortraitContainerViewController : UIViewController
@end

@interface WebViewLoadDelegate : NSObject <WKNavigationDelegate>
@property (nonatomic, assign) CFAbsoluteTime pageLoadStartTime;
- (instancetype)initWithWebView:(WKWebView *)webView
                    loadingView:(UIView *)loadingView
                retryArmDelay:(NSTimeInterval)retryArmDelay
       presentationSessionToken:(NSUInteger)presentationSessionToken;
/// Arms the stall-retry timer chain once for the given main-frame URL, up to two stall reloads.
- (void)armRetryTimerIfNeededForMainFrameURL:(NSURL *)url;
/// Cancels all pending timers on this delegate.
- (void)invalidateAllTimers;
/// After background/foreground or process resume: refresh deadlines and optionally reload if navigation looks dead.
- (void)recoverStaleLoadAfterApplicationForegroundIfNeeded;
/// Called when injected document-end script posts `stashNativePageReady` (readystate / load + rAF).
- (void)notifyPageReadyFromInjectedScript;
@end

@interface WebViewUIDelegate : NSObject <WKUIDelegate>
@end
