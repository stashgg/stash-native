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
UIViewController *getTopPresentedViewController(void);

/// Popup frame (x, y, width, height) for given screen bounds; uses current orientation and custom/default multipliers.
CGRect computePopupFrameForScreenBounds(CGRect screenBounds);

/// Modal frame (x, y, width, height) for given screen bounds; uses current orientation and modal ratios.
CGRect computeModalFrameForScreenBounds(CGRect screenBounds);

/// Phone card frame (x, y, width, height) for given bounds and orientation; used by current-orientation presentation and rotation.
CGRect computePhoneCardFrameForBoundsAndOrientation(CGRect bounds, BOOL isLandscape);
/// Updates _originalCard* in StashNativeCard.m for the given orientation (used after rotation in IPhoneCardCurrentOrientationViewController).
void updateOriginalCardRatiosForOrientation(BOOL isLandscape);

/// Monotonic token bumped on each card open and at dismiss teardown; WebViewLoadDelegate matches against the value captured at init.
NSUInteger StashNativeCurrentPresentationSessionToken(void);
/// Resets expand/collapse state to collapsed after rotation so the card always shows initial size.
void resetCardExpandedStateAfterRotation(void);

/// Updates drag tray and handle bar frame inside cardView (used by iPad transition and expand/collapse).
void updateDragTrayAndHandleInCardView(UIView *cardView, CGFloat cardWidth);
/// Lays out the card's WebView (and tray) to fill cardView.bounds; call after rotation or any card frame change so WebView resizes correctly.
void layoutCardContentToBounds(UIView *cardView);
/// Switches the card's WebView from Auto Layout to frame-based layout; call before animating card frame (e.g. rotation) so WebView resizes with the card.
WKWebView *switchWebViewToFrameLayoutInCardView(UIView *cardView);

/// Applies bounce/overscroll limits to the WKWebView's scroll view; call after creation and on navigation (WebKit may reset scroll properties).
void configureScrollViewForWebView(UIScrollView *scrollView);

/// True when checkout WebView should use dark `theme=` / color-scheme (system or custom background luminance).
BOOL StashNativeSheetUsesDarkWebTheme(void);
/// Injects document meta + html/body background for dark sheet (BG matches configured background color).
NSString *StashNativeDarkSheetBackgroundJavaScript(void);

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
