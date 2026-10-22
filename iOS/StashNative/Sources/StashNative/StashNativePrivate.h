#import "StashNative.h"
#import <WebKit/WebKit.h>
#import <SafariServices/SafariServices.h>

#if __has_feature(objc_arc)
#define STASH_WEAK weak
#define STASH_WEAK_REF __weak
#else
#define STASH_WEAK assign
#define STASH_WEAK_REF __unsafe_unretained
#endif

@class StashCardSession, StashCardViewController;
@interface StashNativeEntranceCorrection : NSObject
+ (instancetype)correctionForSurface:(CALayer *)surface container:(CALayer *)container;
- (void)update;
- (void)invalidate;
@end

@interface StashPortraitPresentation : NSObject
@property (nonatomic, readonly) UIViewController *presenter;
- (instancetype)initWithPresenter:(UIViewController *)presenter;
- (void)prepareWithCompletion:(void (^)(BOOL ready))completion;
- (void)restoreWithCompletion:(void (^)(void))completion;
@end

@interface StashSafariViewController : SFSafariViewController
@property (nonatomic) BOOL prefersPortrait;
@end

void StashInstallPortraitOrientationHooks(id applicationDelegate, UIWindowScene *scene);

@interface StashNative ()
@property (nonatomic, strong) StashCardSession *session;
- (void)deliverToDelegate:(void (^)(id<StashNativeDelegate> delegate))delivery;
- (void)deliverScannerUnavailable;
@end

typedef struct {
    CGRect frame;
    CGFloat restingContentHeight;
    CGFloat expandedContentHeight;
    BOOL centered;
} StashPresentationGeometry;

CGFloat StashFinitePositive(CGFloat value, CGFloat fallback);
StashNativeCardConfig *StashNormalizedConfig(StashNativeCardConfig *config);
CGRect StashChooseAvailableRegion(CGRect safeBounds, NSArray<NSValue *> *regions, CGPoint preferredPoint, BOOL rightToLeft);
CGRect StashChooseBottomAttachedRegion(CGRect bounds, NSArray<NSValue *> *regions);
StashPresentationGeometry StashResolveGeometry(CGRect safeBounds, StashNativeCardConfig *config,
                                               BOOL expanded, CGFloat measuredContentHeight);
BOOL StashValidateContentHeight(NSDictionary *payload, NSString *documentID, CGFloat viewportWidth,
                               CGFloat scale, CGFloat nativeWidth, CGFloat *height);
UIColor *StashSystemBackgroundColor(UITraitCollection *traits);
NSString *StashTopChromeScript(void);
WKContentWorld *StashTopChromeWorld(void);
extern NSString *const StashTopChromeHandlerName;
UIColor *StashSheetBackgroundUIColor(UITraitCollection *traits);
/** Glass loading surface: iOS 27 and later. Tests set the override to 0 or 1; -1 follows the OS. */
extern NSInteger StashGlassLoadingOverride;
BOOL StashGlassLoadingAvailable(void);
BOOL StashEffectiveThemeIsDark(UITraitCollection *traits);
NSString *StashAppendThemeQueryParameter(NSString *url, UITraitCollection *traits);
NSString *StashNormalizeExternalPaymentURL(NSString *raw);
NSArray<NSString *> *StashScriptHandlerNames(void);
NSString *StashBridgeScript(void);
NSString *StashNativeInteractionScript(void);
NSString *StashInitialContentReadinessScript(void);
void StashRemoveFormInputAccessoryView(WKWebView *webView);
NSString *StashContentMeasurementScript(NSString *documentID);
// Routes external opens through UIApplication unless a test opener is installed; nil restores the default.
void StashSetExternalURLOpener(void (^opener)(NSURL *url, NSDictionary *options, void (^completion)(BOOL success)));
void StashOpenExternalURL(NSURL *url, NSDictionary *options, void (^completion)(BOOL success));
// The scanner class from the optional StashNativeCodeLink module, or Nil when it is not linked.
Class StashScannerContentClass(void);
// Test seam: resolves a different class name; nil restores StashNativeScannerViewController.
void StashSetScannerContentClassName(NSString *name);

@interface StashCardSession : NSObject <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
    SFSafariViewControllerDelegate, UISheetPresentationControllerDelegate, StashNativeScannerHost>
@property (nonatomic, STASH_WEAK) StashNative *owner;
@property (nonatomic, STASH_WEAK) UIViewController *presenter;
@property (nonatomic, readonly) UIViewController *presentationPresenter;
@property (nonatomic, strong) StashPortraitPresentation *portraitPresentation;
@property (nonatomic) BOOL browserHandoff;
@property (nonatomic, strong) StashNativeCardConfig *config;
@property (nonatomic, strong) StashCardViewController *controller;
@property (nonatomic) BOOL scanner;
@property (nonatomic, copy) StashNativeScannerConfig *scannerConfig;
@property (nonatomic) BOOL scanCompleted;
@property (nonatomic, strong) UIViewController<StashNativeScannerContent> *scannerController;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) WKNavigation *telemetryNavigation;
@property (nonatomic, strong) NSNumber *telemetryFirstCallAt;
@property (nonatomic, strong) NSNumber *telemetryPageLoadStartedAt;
@property (nonatomic, strong) NSNumber *telemetryPageLoadedAt;
@property (nonatomic, strong) NSNumber *telemetryPageLoadTimeMs;
@property (nonatomic) CFTimeInterval telemetryLoadStart;
@property (nonatomic, strong) SFSafariViewController *browser;
/** Safari presented over a card that stays open (externalBrowser keepOpen); closing it ends nothing. */
@property (nonatomic, strong) SFSafariViewController *overlayBrowser;
/** CHHapticEngine for long haptics, kept while it plays. */
@property (nonatomic, strong) id hapticEngine;
@property (nonatomic, strong) NSTimer *loadTimer;
@property (nonatomic, strong) NSTimer *contentRevealTimer;
@property (nonatomic, copy) NSString *documentID;
@property (nonatomic) NSUInteger topChromeGeneration;
@property (nonatomic, copy) NSString *topChromeToken;
@property (nonatomic, copy) NSString *topChromeDocumentID;
@property (nonatomic, strong) WKNavigation *topChromeNavigation;
@property (nonatomic, copy) NSString *url;
@property (nonatomic) BOOL processing;
@property (nonatomic) BOOL expanded;
@property (nonatomic) BOOL keyboardVisible;
@property (nonatomic) BOOL closing;
@property (nonatomic) BOOL loaded;
@property (nonatomic) BOOL initialContentRevealed;
@property (nonatomic) BOOL initialContentFinished;
@property (nonatomic) BOOL initialContentHasCommitted;
@property (nonatomic) BOOL contentReadinessProbePending;
@property (nonatomic) NSUInteger contentRevealGeneration;
@property (nonatomic) CFAbsoluteTime contentWaitStart;
@property (nonatomic) NSTimeInterval contentWaitElapsed;
@property (nonatomic) BOOL receivedResponse;
@property (nonatomic) BOOL observingPageBackground;
@property (nonatomic, strong) UIScrollView *observedRootScroll;
@property (nonatomic) BOOL rootOffsetRepairPending;
@property (nonatomic) BOOL rootOffsetRepairQueued;
@property (nonatomic) BOOL inferredPageBackingApplied;
@property (nonatomic) BOOL applyingPageBacking;
@property (nonatomic) BOOL recoveredProcess;
@property (nonatomic) BOOL paymentHandled;
@property (nonatomic) BOOL browserCloseDelivered;
@property (nonatomic) CGFloat measuredContentHeight;
@property (nonatomic) CGFloat measuredNativeWidth;
@property (nonatomic) CGFloat pendingContentHeight;
@property (nonatomic) CGFloat pendingNativeWidth;
@property (nonatomic) BOOL hasPendingContentHeight;
@property (nonatomic) CFAbsoluteTime loadStart;
@property (nonatomic) CFAbsoluteTime foregroundLoadStart;
@property (nonatomic) NSTimeInterval foregroundLoadElapsed;
@property (nonatomic) BOOL retriedLoad;
@property (nonatomic) NSUInteger heightReportSequence;
@property (nonatomic, copy) void (^dialogCompletion)(id result);
- (BOOL)isActive;
- (BOOL)canUserDismiss;
- (void)presentCheckout;
- (void)completeScan:(NSString *)content;
- (void)observeRootScroll;
- (void)stopObservingRootScroll;
- (void)scheduleRootOffsetRepair;
- (void)retryRootOffsetRepair;
- (void)presentBrowser;
- (void)dismissPresentedSurfaceAnimated:(BOOL)animated completion:(void (^)(void))completion;
- (void)finishWithUserDismiss:(BOOL)userDismiss completion:(void (^)(void))completion;
- (void)cleanup;
- (void)retire;
- (void)paymentSucceeded:(BOOL)success order:(NSString *)order;
- (void)handleMessage:(NSString *)name body:(id)body;
- (void)networkFailed;
- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;
- (void)acceptContentHeight:(NSDictionary *)payload;
- (void)browserClosed;
- (void)openBrowserOverCardWithURL:(NSString *)url;
- (void)playLongHaptic;
- (BOOL)playContinuousHaptic;
// Ends the session when a host dismissal removes the card or Safari outside the SDK.
- (void)presentedSurfaceDidDisappear:(UIViewController *)surface;
- (void)completeDialog:(id)result;
- (void)updateLoadBudget;
- (void)beginLoadBudget;
- (void)beginInitialContentNavigation;
- (void)initialContentCommitted;
- (void)initialContentDidFinish;
- (void)updateInitialContentWait;
- (BOOL)isInitialContentForeground;
- (void)revealInitialContent;
- (void)cancelInitialContentReveal;
- (void)applyPendingContentHeight;
- (void)installTopChromeProbe:(WKUserContentController *)content;
- (void)invalidateTopChrome;
- (void)applyInferredPageBackingColor:(UIColor *)color;
- (void)activateTopChrome;
- (void)sampleTopChrome;
- (void)acceptTopChromeMessage:(WKScriptMessage *)message;
@end

@interface StashCardSession (Navigation)
- (BOOL)handlePaymentResultURL:(NSURL *)url;
@end

@interface StashCardSession (Telemetry) <WKScriptMessageHandlerWithReply>
- (void)beginTelemetryNavigation:(WKNavigation *)navigation;
- (void)finishTelemetryNavigation:(WKNavigation *)navigation;
- (NSDictionary *)telemetrySnapshot;
@end

@interface StashCardViewController : UIViewController <UIGestureRecognizerDelegate>
@property (nonatomic, STASH_WEAK) StashCardSession *session;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIView *loadingCover;
@property (nonatomic) BOOL glassLoading;
@property (nonatomic, strong) UIColor *topChromeColor;
@property (nonatomic) CGRect keyboardFrame;
@property (nonatomic, STASH_WEAK) UIWindow *keyboardNotificationWindow;
@property (nonatomic) CGRect keyboardNotificationWindowBounds;
@property (nonatomic) UIInterfaceOrientation keyboardNotificationOrientation;
@property (nonatomic) BOOL keyboardEpisodeOwned;
@property (nonatomic) BOOL keyboardNotificationVisible;
@property (nonatomic) BOOL keyboardNotificationHiding;
@property (nonatomic) BOOL keyboardGuideWasVisible;
@property (nonatomic) CGRect previousKeyboardGuideFrame;
@property (nonatomic) BOOL hasKeyboardGuideFrame;
@property (nonatomic) BOOL keyboardGuideUndocked;
@property (nonatomic) BOOL keyboardGuideLayoutQueued;
@property (nonatomic) CGFloat previousWidth;
@property (nonatomic) BOOL updatingLayout;
@property (nonatomic) BOOL awaitingHostSafeAreaUpdate;
@property (nonatomic) CGFloat hostSafeAreaBeforeUpdate;
@property (nonatomic) NSUInteger hostSafeAreaUpdateGeneration;
@property (nonatomic) BOOL dragging;
@property (nonatomic) BOOL contentExpansionActive;
@property (nonatomic) CGFloat contentExpansionStartHeight;
@property (nonatomic) CGFloat contentExpansionHeight;
@property (nonatomic) BOOL deferredContentLayout;
@property (nonatomic) BOOL singleDetent;
@property (nonatomic) BOOL configuredFloatingNativeSizing;
@property (nonatomic) NSUInteger nativeSizingGeneration;
@property (nonatomic) CGFloat nativeMaximumDetentValue;
@property (nonatomic) BOOL hasNativeMaximumDetentValue;
@property (nonatomic) BOOL nativeMaximumReconciliationQueued;
@property (nonatomic) BOOL focusRevealQueued;
@property (nonatomic) BOOL geometryTransitioning;
@property (nonatomic) CGFloat nativeContentSafeAreaCompensation;
@property (nonatomic) BOOL nativeContentCompensationQueued;
@property (nonatomic) BOOL hasRequestedNativeSelection;
@property (nonatomic) BOOL requestedNativeExpanded;
@property (nonatomic, strong) NSMutableArray<UIPanGestureRecognizer *> *observedPans;
@property (nonatomic, strong) UITapGestureRecognizer *touchOriginObserver;
@property (nonatomic, strong) UIPanGestureRecognizer *contentPan;
@property (nonatomic, strong) NSHashTable<UIPanGestureRecognizer *> *contentScrollPans;
@property (nonatomic, STASH_WEAK) UIView *contentTouchView;
@property (nonatomic) BOOL touchBeganInWebContent;
@property (nonatomic, strong) id geometryUpdateLink;
@property (nonatomic, strong) id entranceUpdateLink;
@property (nonatomic, strong) StashNativeEntranceCorrection *entranceCorrection;
@property (nonatomic) BOOL entranceCorrectionApplied;
@property (nonatomic) CGRect previousAvailableBounds;
@property (nonatomic) CGRect previousContentBounds;
- (void)updateTopChromeBackgroundColor;
- (void)stopNativeEntrance;
- (void)completeHostSafeAreaUpdate:(NSUInteger)generation;
- (void)revealInitialContentAnimated:(BOOL)animated;
@end

@interface StashCardViewController (Keyboard)
- (void)keyboardChanged:(NSNotification *)note;
- (void)keyboardSettled:(NSNotification *)note;
- (void)updateKeyboardGuideOcclusion;
- (CGRect)resolvedKeyboardFrameInView:(UIView *)view dockedOnly:(BOOL)dockedOnly;
- (NSArray<NSNumber *> *)focusKeyboardOcclusion;
- (void)scheduleFocusReveal;
- (BOOL)canNormalizeIdleRootScrollOffset;
- (BOOL)normalizeIdleRootScrollOffset;
@end

@interface StashCardViewController (Gestures)
- (void)observeContentScrollPans:(UIView *)view;
- (void)observeNativePans:(UIView *)view;
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch;
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer;
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer;
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer;
- (void)nativePanChanged:(UIPanGestureRecognizer *)gesture;
- (void)cancelContentExpansion;
- (void)updateDismissalPolicy;
@end

@interface StashCardViewController (Presentation)
- (UIView *)layoutContainer;
- (BOOL)usesFloatingNativeSizing;
- (void)reconcileNativeSizingPolicy;
- (void)configurePresentation;
- (NSString *)nativeDetentIdentifierForExpanded:(BOOL)expanded;
- (BOOL)nativeSelectionIsExpanded;
- (CGRect)availableBoundsInView:(UIView *)view;
- (CGRect)availableBoundsInView:(UIView *)view expanded:(BOOL)expanded;
- (CGFloat)contentHeightForMaximum:(CGFloat)maximum expanded:(BOOL)expanded;
- (void)reconcileNativeContentSafeArea:(CGFloat)bottomPadding;
- (void)updatePresentationAnimated:(BOOL)animated;
- (void)updateNativeLoadingBackground;
- (void)configureNativeDetents;
- (CGFloat)resolvedNativeHeightForMaximum:(CGFloat)maximum expanded:(BOOL)expanded;
- (void)contentHeightDidChange;
@end
