//
//  StashNativeCardInternal.h
//  StashNative
//
//  Internal interface for the StashNativeCardInternal singleton: presentation state and the private
//  methods shared across the SDK translation units (core + category files). Not published in the
//  framework Headers.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <SafariServices/SafariServices.h>

@class WebViewLoadDelegate;
@class WebViewUIDelegate;

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
@property (nonatomic, assign) CGFloat expandCollapseEaseOvershoot; // Easing overshoot amount; 0 selects the default ease-out-back overshoot (1.70158).
@property (nonatomic, copy) void (^expandCompletion)(void);
@property (nonatomic, strong) WebViewLoadDelegate *activeWebViewLoadDelegate;
@property (nonatomic, strong) WebViewUIDelegate *activeWebViewUIDelegate;
/// Bumped on each card open and on teardown; WebViewLoadDelegate compares it to identify stale callbacks.
@property (nonatomic, assign) NSUInteger presentationSessionToken;
/// YES from beginDismissStoppingLoadAndTimers until cleanup finishes.
@property (nonatomic, assign) BOOL isDismissingCard;
/// The scene orientation mask in effect before forcePortrait was applied; restored on dismiss.
@property (nonatomic, assign) UIInterfaceOrientationMask previousSceneOrientationMask;
/// Dedicated portrait window created for SFSafariViewController on the external-payment path.
@property (nonatomic, strong) UIWindow *safariPresentationWindow;
/// YES when the external-payment path is about to present SFSafariViewController immediately
/// after card dismissal. While YES, cleanupCardInstance keeps the portrait window alive and
/// presents Safari from it.
@property (nonatomic, assign) BOOL isHandingOffPortraitWindowToSafari;
/// YES while SFSafariViewController is presented in a forced-portrait window.
/// While YES, the orientation swizzle returns UIInterfaceOrientationMaskPortrait for the SDK window.
@property (nonatomic, assign) BOOL isSafariPortraitLocked;
@property (nonatomic, copy) dispatch_block_t pendingIPhoneCardGeometryRelayoutBlock;
@property (nonatomic, assign) BOOL iPhoneCardWindowGeometryObserversRegistered;
/// While YES, the orientation swizzle locks the card window (and system keyboard) to the card's orientation.
@property (nonatomic, assign) BOOL isIPhoneCardKeyboardVisible;
/// Last valid `UIDeviceOrientation` while the iPhone card keyboard is visible (0 = unset).
@property (nonatomic, assign) NSInteger stashLastValidDeviceOrientationForKeyboard;
/// Scene size when keyboard lock was applied; compared by `stashIPhoneCardGeometryMayHaveChanged` to detect a portrait/landscape geometry flip.
@property (nonatomic, assign) CGSize stashLastSceneSizeForKeyboardDismiss;

+ (instancetype)sharedInstance;
- (void)beginDismissStoppingLoadAndTimers;
- (void)dismissWithAnimation:(void (^)(void))completion;
- (void)cleanupCardInstance;
- (void)callDelegateCallbackOnce;
- (UIView *)cardViewForCurrentPresentation;  // kCardViewTag view for the current presentation; on iPhone falls back to the presented VC's view; nil when none is presented.
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
- (void)teardownPresentationWindow:(UIWindow *)window;
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
