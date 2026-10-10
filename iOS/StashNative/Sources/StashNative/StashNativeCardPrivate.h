#import "StashNativeCard.h"
#import <WebKit/WebKit.h>
#import <SafariServices/SafariServices.h>

#if __has_feature(objc_arc)
#define STASH_WEAK weak
#define STASH_WEAK_REF __weak
#else
#define STASH_WEAK assign
#define STASH_WEAK_REF __unsafe_unretained
#endif

@class StashCheckoutSession, StashCheckoutViewController, StashCodeLinkViewController;
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

void StashInstallPortraitOrientationHooks(id applicationDelegate, UIWindowScene *scene);

@interface StashNativeCard ()
@property (nonatomic, strong) StashCheckoutSession *session;
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
UIColor *getSystemBackgroundColor(void);
NSString *StashTopChromeScript(void);
WKContentWorld *StashTopChromeWorld(void);
extern NSString *const StashTopChromeHandlerName;
UIColor *stash_sheetBackgroundUIColor(void);
BOOL stash_effectiveThemeIsDark(void);
NSString *appendThemeQueryParameter(NSString *url);
NSString *NormalizeExternalPaymentURL(NSString *raw);
NSArray<NSString *> *StashScriptHandlerNames(void);
NSString *StashBridgeScript(void);
NSString *StashNativeInteractionScript(void);
NSString *StashInitialContentReadinessScript(void);
void StashRemoveFormInputAccessoryView(WKWebView *webView);
NSString *StashContentMeasurementScript(NSString *documentID);

@interface StashCheckoutSession : NSObject <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
    SFSafariViewControllerDelegate, UISheetPresentationControllerDelegate>
@property (nonatomic, STASH_WEAK) StashNativeCard *owner;
@property (nonatomic, STASH_WEAK) UIViewController *presenter;
@property (nonatomic, readonly) UIViewController *presentationPresenter;
@property (nonatomic, strong) StashPortraitPresentation *portraitPresentation;
@property (nonatomic) BOOL browserHandoff;
@property (nonatomic, strong) StashNativeCardConfig *config;
@property (nonatomic, strong) StashCheckoutViewController *controller;
@property (nonatomic) BOOL codeLink;
@property (nonatomic) BOOL codeLinkCompleted;
@property (nonatomic, strong) StashCodeLinkViewController *codeLinkController;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) WKNavigation *telemetryNavigation;
@property (nonatomic, strong) NSNumber *telemetryFirstCallAt;
@property (nonatomic, strong) NSNumber *telemetryPageLoadStartedAt;
@property (nonatomic, strong) NSNumber *telemetryPageLoadedAt;
@property (nonatomic, strong) NSNumber *telemetryPageLoadTimeMs;
@property (nonatomic) CFTimeInterval telemetryLoadStart;
@property (nonatomic, strong) SFSafariViewController *browser;
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
- (void)completeCodeLink:(NSString *)content;
- (void)observeRootScroll;
- (void)stopObservingRootScroll;
- (void)scheduleRootOffsetRepair;
- (void)retryRootOffsetRepair;
- (void)presentBrowser;
- (void)dismissPresentedSurfaceAnimated:(BOOL)animated completion:(void (^)(void))completion;
- (void)finishWithUserDismiss:(BOOL)userDismiss completion:(void (^)(void))completion;
- (void)cleanup;
- (void)paymentSucceeded:(BOOL)success order:(NSString *)order;
- (void)handleMessage:(NSString *)name body:(id)body;
- (void)networkFailed;
- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;
- (void)acceptContentHeight:(NSDictionary *)payload;
- (void)browserClosed;
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

@interface StashCodeLinkViewController : UIViewController
@property (nonatomic, STASH_WEAK) StashCheckoutSession *session;
- (void)showConnectedWithCompletion:(void (^)(void))completion;
- (void)stopScanning;
- (void)dispose;
@end

@interface StashCheckoutSession (Navigation)
- (BOOL)handlePaymentResultURL:(NSURL *)url;
@end

@interface StashCheckoutSession (Telemetry) <WKScriptMessageHandlerWithReply>
- (void)beginTelemetryNavigation:(WKNavigation *)navigation;
- (void)finishTelemetryNavigation:(WKNavigation *)navigation;
- (NSDictionary *)telemetrySnapshot;
@end

@interface StashCheckoutViewController : UIViewController <UIGestureRecognizerDelegate>
@property (nonatomic, STASH_WEAK) StashCheckoutSession *session;
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
@property (nonatomic, strong) UIView *keyboardGuideTracker;
@property (nonatomic) CGFloat previousWidth;
@property (nonatomic) BOOL updatingLayout;
@property (nonatomic) BOOL awaitingHostSafeAreaUpdate;
@property (nonatomic) CGFloat hostSafeAreaBeforeUpdate;
@property (nonatomic) NSUInteger hostSafeAreaUpdateGeneration;
@property (nonatomic) BOOL dragging;
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
- (void)configurePresentation;
- (void)nativePanChanged:(UIPanGestureRecognizer *)gesture;
- (BOOL)usesFloatingNativeSizing;
- (void)reconcileNativeSizingPolicy;
- (NSString *)nativeDetentIdentifierForExpanded:(BOOL)expanded;
- (BOOL)nativeSelectionIsExpanded;
- (void)updateTopChromeBackgroundColor;
- (void)updatePresentationAnimated:(BOOL)animated;
- (void)stopNativeEntrance;
- (CGRect)availableBoundsInView:(UIView *)view;
- (CGRect)availableBoundsInView:(UIView *)view expanded:(BOOL)expanded;
- (CGFloat)contentHeightForMaximum:(CGFloat)maximum expanded:(BOOL)expanded;
- (void)updateDismissalPolicy;
- (void)contentHeightDidChange;
- (void)completeHostSafeAreaUpdate:(NSUInteger)generation;
- (void)revealInitialContentAnimated:(BOOL)animated;
- (void)scheduleFocusReveal;
- (BOOL)canNormalizeIdleRootScrollOffset;
- (BOOL)normalizeIdleRootScrollOffset;
- (CGRect)resolvedKeyboardFrameInView:(UIView *)view dockedOnly:(BOOL)dockedOnly;
- (NSArray<NSNumber *> *)focusKeyboardOcclusion;
- (void)reconcileNativeContentSafeArea:(CGFloat)bottomPadding;
@end
