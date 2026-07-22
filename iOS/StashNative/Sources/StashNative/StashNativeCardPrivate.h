//
//  StashNativeCardPrivate.h
//  StashNative
//
//  Internal shared declarations: state and constants defined in StashNativeCard.m,
//  helper functions (Geometry/Theme/ViewUtils), and the internal class interfaces
//  implemented in StashNativeCardViewControllers.m, StashNativeCardWebViewDelegates.m,
//  and StashNativeCardInternal.m.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <SafariServices/SafariServices.h>

#pragma mark - Shared state and constants (defined in StashNativeCard.m)

/// Default popup size multipliers; also the defaults for StashNativePopupSizeConfig.
extern const CGFloat kPopupPortraitWidthMultiplier;
extern const CGFloat kPopupPortraitHeightMultiplier;
extern const CGFloat kPopupLandscapeWidthMultiplier;
extern const CGFloat kPopupLandscapeHeightMultiplier;

/// Popup base sizing.
extern const CGFloat kPopupBaseSizePercentageIPad;
extern const CGFloat kPopupBaseSizePercentagePhone;
extern const CGFloat kPopupBaseSizeMinIPad;
extern const CGFloat kPopupBaseSizeMinPhone;
extern const CGFloat kPopupBaseSizeMax;
extern const NSTimeInterval kPopupFrameAnimationDuration;

/// Presentation mode flags.
extern BOOL _usePopupPresentation;
extern BOOL _useModalPresentation;

/// Custom popup sizing (openPopupWithURL:sizeConfig:).
extern BOOL _useCustomPopupSize;
extern CGFloat _customPortraitWidthMultiplier;
extern CGFloat _customPortraitHeightMultiplier;
extern CGFloat _customLandscapeWidthMultiplier;
extern CGFloat _customLandscapeHeightMultiplier;

/// Modal sizing ratios and dismiss flag.
extern BOOL _modalAllowDismiss;
extern CGFloat _modalPhoneWidthRatioPortrait;
extern CGFloat _modalPhoneHeightRatioPortrait;
extern CGFloat _modalPhoneWidthRatioLandscape;
extern CGFloat _modalPhoneHeightRatioLandscape;
extern CGFloat _modalTabletWidthRatioPortrait;
extern CGFloat _modalTabletHeightRatioPortrait;
extern CGFloat _modalTabletWidthRatioLandscape;
extern CGFloat _modalTabletHeightRatioLandscape;

/// Card / tablet sizing ratios (config-applied) and live card state.
extern CGFloat _cardHeightRatioPortrait;
extern CGFloat _cardWidthRatioLandscape;
extern CGFloat _cardHeightRatioLandscape;
extern CGFloat _tabletWidthRatioPortrait;
extern CGFloat _tabletHeightRatioPortrait;
extern CGFloat _tabletWidthRatioLandscape;
extern CGFloat _tabletHeightRatioLandscape;
extern CGFloat _originalCardWidthRatio;
extern CGFloat _originalCardHeightRatio;
extern CGFloat _originalCardVerticalPosition;
extern BOOL _isCardExpanded;
/// Safe-area top inset of the active card window; clamps card height below the notch.
extern CGFloat _cardSafeAreaTop;

/// Card chrome, view tags, drag handle metrics.
extern const CGFloat kCornerRadiusDefault;
extern const CGFloat kDragTrayHeight;
extern const NSInteger kCardViewTag;
extern const NSInteger kDragTrayViewTag;
extern const NSInteger kDragHandleViewTag;
extern const CGFloat kHandleBarWidth;
extern const CGFloat kHandleBarHeight;
extern const CGFloat kHandleBarTopInset;
extern const CGFloat kHandleBarHalfWidth;
extern const CGFloat kHandleHitAreaInset;

/// Shadow (iPhone card vs iPad/popup).
extern const CGFloat kShadowOpacityPhone;
extern const CGFloat kShadowRadiusPhone;
extern const CGFloat kShadowOffsetYPhone;
extern const CGFloat kShadowOpacityPopup;
extern const CGFloat kShadowRadiusPopup;
extern const CGFloat kShadowOffsetYPopup;

/// Associated-object key for the overlay view on presentation VCs.
extern NSString * const StashNativeAssociatedKeyOverlayView;

/// Transient presentation flags (reset on dismiss/cleanup in StashNativeCard.m).
extern BOOL _callbackWasCalled;
extern BOOL _isCardCurrentlyPresented;
extern BOOL _paymentSuccessHandled;
extern BOOL _forcePortraitOnCheckout;
extern BOOL _safariOpenedViaOpenBrowser;
extern BOOL _safariBrowserCloseDelegatePending;
extern BOOL _cardIsInLandscape;
extern BOOL _autoCloseOnPaymentEvent;

/// Animation constants shared by presentation and interaction code.
extern const CGFloat kSpringDampingDefault;
extern const CGFloat kAnimationDurationDefault;
extern const NSTimeInterval kOverlayFadeInDuration;
extern const NSTimeInterval kDismissAnimationDurationPopup;
extern const CGFloat kSpringVelocityExpand;
extern const CGFloat kDismissVelocityThreshold;

/// WKScriptMessageHandler names (registered in StashNativeCard.m, dispatched in StashNativeCardInternal.m).
extern NSString * const kMessageHandlerPaymentSuccess;
extern NSString * const kMessageHandlerPaymentFailure;
extern NSString * const kMessageHandlerPurchaseProcessing;
extern NSString * const kMessageHandlerProcessingCompleted;
extern NSString * const kMessageHandlerOptin;
extern NSString * const kMessageHandlerExpand;
extern NSString * const kMessageHandlerCollapse;
extern NSString * const kMessageHandlerWindowClose;
extern NSString * const kMessageHandlerExternalPayment;
extern NSString * const kMessageHandlerOpenLink;
extern NSString * const kMessageHandlerPageReady;

/// Associated-object keys.
extern NSString * const kAssociatedKeyWebViewDelegate;
extern NSString * const kAssociatedKeyWebViewUIDelegate;
extern NSString * const kAssociatedKeyLoadingView;
extern NSString * const kAssociatedKeyCardView;
extern NSString * const kAssociatedKeyInitialCardHeight;


#pragma mark - Theme / colors (StashNativeCardTheme.m)

/// Normalized #hex from the last openCard/openModal config; nil = follow system theme.
extern NSString *_presentationBackgroundColorHex;

UIColor *getSystemBackgroundColor(void);
UIColor *stash_sheetBackgroundUIColor(void);
BOOL stash_colorIsDarkBackground(UIColor *color);
BOOL stash_effectiveThemeIsDark(void);
NSString *stash_cssHexFromUIColor(UIColor *color);
/// Sets (or replaces) the `theme=` query parameter based on the effective theme.
NSString *appendThemeQueryParameter(NSString *url);

#pragma mark - Geometry (StashNativeCardGeometry.m)

BOOL isRunningOniPad(void);
UIInterfaceOrientation getInterfaceOrientation(void);
/// Maps a UIInterfaceOrientation to the corresponding single-orientation mask for restore.
UIInterfaceOrientationMask stashOrientationMaskForOrientation(UIInterfaceOrientation orientation);
CGSize calculateiPadCardSize(CGRect screenBounds);
CGFloat getSafeAreaTopForView(UIView *view);
CGFloat getSafeAreaBottomForView(UIView *view);
CGFloat stashTabletSdkMaxCardHeight(CGRect screenBounds, UIView *cardView);
CGFloat stashTabletSdkExpandedHeightFromBase(CGFloat baseHeight, CGRect screenBounds, UIView *cardView);
CGRect stashFrameForIPadSdkCard(CGRect screenBounds, UIView *cardView);
/// Centered frame larger than windowBounds so the dimming layer hides rotating edges.
CGRect stashIPhoneCardOverscanBackdropFrameForWindowBounds(CGRect windowBounds);

#pragma mark - View / window utilities (StashNativeCardViewUtils.m)

/// Invalidates a pending rotation-resize display link on the VC (defined in StashNativeCardViewControllers.m).
void stashInvalidateRotationResizeArtifacts(UIViewController *vc);

/// Recursively find the first WKWebView in a view subtree.
WKWebView *findWebViewInView(UIView *view);
UIRectCorner getCornersToRoundForPosition(CGFloat verticalPosition, BOOL isiPad);
void setWebViewBackgroundColor(WKWebView *webView, UIColor *color);
CAShapeLayer *createCornerRadiusMask(CGRect bounds, UIRectCorner corners, CGFloat radius);
/// Attach cardWindow to the same UIWindowScene as the app (e.g. Unreal) so it renders in game engines.
void attachWindowToKeyWindowScene(UIWindow *cardWindow, UIWindow *keyWindow);
UIWindow *getKeyWindow(void);
void runWithoutImplicitAnimations(void (^block)(void));
UIView *createOverlayViewWithFrame(CGRect frame, UIView *parentView, NSInteger index, UIViewController *vc);
void applyCardShadowToLayer(CALayer *layer, BOOL phoneStyle);
void setOverlayToDismissAppearance(UIView *overlayView);
/// Trims, defaults to https, and rejects non-http(s) URLs; nil when invalid.
NSString *NormalizeExternalPaymentURL(NSString *raw);

#pragma mark - Shared functions

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

/// Preferred full-screen bounds for a window's scene (rotation-safe vs UIScreen.main).
CGRect stashSceneCoordinateBoundsForIPhoneCardWindow(UIWindow *window);

/// Relayouts the iPhone card window, overlay, and sheet. `forcedCardExpansionProgress` in [0,1] overrides
/// measured progress (use 0 after rotation). Pass a value outside [0,1] (e.g. -1) to use automatic progress.
void stashRelayoutIPhoneCardWindowWithTargetBoundsAndProgress(CGRect targetBounds, CGFloat forcedCardExpansionProgress);

@class StashNativeCardInternal;
/// After opening from landscape, poll until the scene is portrait or timeout, optionally retrying geometry updates (iOS 16+).
void stashScheduleForcePortraitCardLayoutAfterPortraitSettle(UIWindow *cardWindow,
                                                             BOOL openedFromLandscape,
                                                             NSUInteger sessionToken,
                                                             StashNativeCardInternal *internal,
                                                             void (^onStaleSession)(void),
                                                             void (^onContinueLayout)(void));

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

#pragma mark - StashNativeCardInternal (StashNativeCardInternal.m)


/// Card interaction engine singleton; implementation in StashNativeCardInternal.m.
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
- (void)tearDownSafariPresentationState;  // Resets Safari/portrait presentation state; fires no callbacks
- (UIView *)cardViewForCurrentPresentation;  // Returns cardView (kCardViewTag) for iPhone/iPad; nil if none
- (void)updateDragTrayVisibilityForPurchaseProcessing:(BOOL)isProcessing;
/// Payment/close flows shared by the JS bridge messages and stash-pay result deeplinks.
- (void)handlePaymentSuccessSignalWithOrder:(NSString *)orderString;
- (void)handlePaymentFailureSignal;
- (void)handleWindowCloseSignal;
- (void)setSkipLayoutDuringInitialSetup:(BOOL)skip forViewController:(UIViewController *)vc;
- (UIView *)createDragTray:(CGFloat)cardWidth;
- (void)expandCardToFullScreen;
- (void)collapseCardToOriginal;
- (void)animateCollapseWithDuration:(NSTimeInterval)duration completion:(void (^)(void))completion;
- (void)animateExpandWithDuration:(NSTimeInterval)duration completion:(void (^)(void))completion;
- (void)updateCardExpansionProgress:(CGFloat)progress cardView:(UIView *)cardView;
- (CGFloat)currentExpansionProgressForCardView:(UIView *)cardView;
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
