//
//  StashNativeCardPrivate.h
//  StashNative
//
//  Private declarations for view controllers and delegates used by StashNativeCard.m.
//  Implementations live in StashNativeCardViewControllers.m and StashNativeCardWebViewDelegates.m.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

/// Returns the top-most presented view controller (key window root, then walking presentedViewController chain).
UIViewController *stash_getTopPresentedViewController(void);

/// Popup frame (x, y, width, height) for given screen bounds; uses current orientation and custom/default multipliers.
CGRect stash_computePopupFrameForScreenBounds(CGRect screenBounds);

/// Modal frame (x, y, width, height) for given screen bounds; uses current orientation and modal ratios.
CGRect stash_computeModalFrameForScreenBounds(CGRect screenBounds);

/// Phone card frame (x, y, width, height) for given bounds and orientation; used by current-orientation presentation and rotation.
CGRect stash_computePhoneCardFrameForBoundsAndOrientation(CGRect bounds, BOOL isLandscape);

/// Monotonic token bumped on each card open and at dismiss teardown; WebViewLoadDelegate matches against the value captured at init.
NSUInteger StashNativeCurrentPresentationSessionToken(void);
/// Resets expand/collapse state to collapsed after rotation so the card always shows initial size.
void stash_resetCardExpandedStateAfterRotation(void);

/// Preferred full-screen bounds for a window's scene (rotation-safe vs UIScreen.main).
CGRect stashSceneCoordinateBoundsForIPhoneCardWindow(UIWindow *window);

/// Relayouts the iPhone card window, overlay, and sheet. `forcedCardExpansionProgress` in [0,1] overrides
/// measured progress (use 0 after rotation). Pass a value outside [0,1] (e.g. -1) to use automatic progress.
void stashRelayoutIPhoneCardWindowWithTargetBoundsAndProgress(CGRect targetBounds, CGFloat forcedCardExpansionProgress);

/// Updates drag tray and handle bar frame inside cardView (used by iPad transition and expand/collapse).
void stash_updateDragTrayAndHandleInCardView(UIView *cardView, CGFloat cardWidth);
/// Lays out the card's WebView (and tray) to fill cardView.bounds; call after rotation or any card frame change so WebView resizes correctly.
void stash_layoutCardContentToBounds(UIView *cardView);
/// Switches the card's WebView from Auto Layout to frame-based layout; call before animating card frame (e.g. rotation) so WebView resizes with the card.
WKWebView *stash_switchWebViewToFrameLayoutInCardView(UIView *cardView);

/// Applies bounce/overscroll limits to the WKWebView's scroll view; call after creation and on navigation (WebKit may reset scroll properties).
void stash_configureScrollViewForWebView(UIScrollView *scrollView);

/// True when checkout WebView should use dark `theme=` / color-scheme (system or custom background luminance).
BOOL StashNativeSheetUsesDarkWebTheme(void);
/// Injects document meta + html/body background for dark sheet (BG matches configured background color).
NSString *StashNativeDarkSheetBackgroundJavaScript(void);

/// Dark-surface color (#1e1e1e) for the loading overlay and the dark system-background fallback.
UIColor *StashNativeDarkSurfaceColor(void);

// Shared file-scope state and constants defined in StashNativeCard.m. Single source of truth for the
// extern declarations the sibling .m files (view controllers, delegates) rely on.
extern BOOL stash_usePopupPresentation;
extern BOOL stash_useModalPresentation;
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
extern const CGFloat kHandleBarHeight;
extern const CGFloat kHandleBarTopInset;
extern const CGFloat kHandleHitAreaInset;
extern const NSInteger kCardViewTag;
extern const NSInteger kDragTrayViewTag;
extern const NSInteger kDragHandleViewTag;
extern NSString * const StashNativeAssociatedKeyOverlayView;
BOOL stash_isRunningOniPad(void);
CGSize stash_calculateiPadCardSize(CGRect screenBounds);
CGRect stashFrameForIPadSdkCard(CGRect screenBounds, UIView *cardView);
CAShapeLayer* stash_createCornerRadiusMask(CGRect bounds, UIRectCorner corners, CGFloat radius);
UIInterfaceOrientation stash_getInterfaceOrientation(void);
UIColor* stash_sheetBackgroundUIColor(void);
void stash_setWebViewBackgroundColor(WKWebView *webView, UIColor *color);

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
@property (nonatomic, assign) CGSize previousScreenSize;
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMaskForCardView;
@end

/// Window-based modal (same pattern as iPad checkout); no portrait lock, works in game engines.
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

/// Minimal portrait-only root VC for the dedicated UIWindow used to host SFSafariViewController
/// on the external-payment path (after the card portrait window has been torn down).
@interface SafariPortraitContainerViewController : UIViewController
@end

@interface WebViewLoadDelegate : NSObject <WKNavigationDelegate>
@property (nonatomic, assign) CFAbsoluteTime pageLoadStartTime;
- (instancetype)initWithWebView:(WKWebView *)webView
                    loadingView:(UIView *)loadingView
                retryArmDelay:(NSTimeInterval)retryArmDelay
       presentationSessionToken:(NSUInteger)presentationSessionToken;
/// Arms the stall-retry timer chain once using the explicit checkout URL from presenter code (up to two stall reloads in the delegate).
- (void)armRetryTimerIfNeededForMainFrameURL:(NSURL *)url;
/// Cancel all pending timers so stale delegates from closed cards cannot fire error callbacks.
- (void)invalidateAllTimers;
/// After background/foreground or process resume: refresh deadlines and optionally reload if navigation looks dead.
- (void)recoverStaleLoadAfterApplicationForegroundIfNeeded;
/// Called when injected document-end script posts `stashNativePageReady` (readystate / load + rAF).
- (void)notifyPageReadyFromInjectedScript;
@end

@interface WebViewUIDelegate : NSObject <WKUIDelegate>
@end
