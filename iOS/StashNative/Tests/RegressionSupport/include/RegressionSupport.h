#import <Foundation/Foundation.h>
@class WKWebView, UIViewController, UIColor, UIWindow;
NSDictionary *StashGeometryProbe(double width, double height, BOOL expanded, double measured,
                                double preferredWidth, double preferredHeight, double maximumHeight, double margin);
NSDictionary *StashReservedRegionProbe(void);
BOOL StashHeightHintProbe(NSDictionary *payload, NSString *documentID, double actualWidth, double scale, double nativeWidth);
NSDictionary *StashConfigurationProbe(void);
NSDictionary *StashCallbackProbe(void);
void StashQueuedCloseProbe(BOOL replace, BOOL processing, BOOL allowDismiss, void (^completion)(BOOL, NSInteger));
NSString *StashMeasurementSource(void);
NSString *StashNativeInteractionSource(void);
NSString *StashInitialContentReadinessSource(void);
NSDictionary *StashLoadingPresentationProbe(void);
void StashFocusSettleProbe(void (^completion)(NSDictionary *));
NSDictionary *StashRootScrollOffsetProbe(void);
BOOL StashNormalizeRootScrollOffset(WKWebView *webView);
NSDictionary *StashFloatingKeyboardCoordinateProbe(void);
NSDictionary *StashFloatingKeyboardNotificationProbe(void);
NSDictionary *StashFloatingKeyboardGuideProbe(void);
NSDictionary *StashFloatingSheetKeyboardBaselineProbe(void);
NSDictionary *StashKeyboardVisibilityOwnershipProbe(void);
NSDictionary *StashInputAccessoryProbe(void);
NSDictionary *StashNativeGrabberContentProbe(void);
void StashNativeIntrinsicSafeAreaProbe(void (^completion)(NSDictionary *));
NSDictionary *StashURLProbe(void);
NSDictionary *StashLifecycleProbe(void);
NSDictionary *StashPresentationStateProbe(void);
void StashConfigSnapshotProbe(void (^completion)(double));
NSDictionary *StashNativeSurfaceProbe(void);
NSDictionary *StashNativePaneProbe(void);
NSDictionary *StashNativeKeyboardProbe(void);
NSDictionary *StashCompactDividerProbe(void);
NSDictionary *StashNativeExpansionProbe(void) API_AVAILABLE(ios(16.0));
NSDictionary *StashNativeHostSafeAreaProbe(void);
NSDictionary *StashNativeBottomPaintProbe(void);

FOUNDATION_EXPORT NSDictionary *StashUndockedKeyboardLayoutProbe(void);


NSDictionary *StashChromeSurfaceGeometryProbe(CGRect bounds, BOOL expanded, CGFloat measured, CGFloat preferred, CGFloat maximum);
NSDictionary *StashChromeContentFixture(WKWebView *web, UIViewController *presenter, CGFloat measured);
CGRect StashChromeProcessingFrame(NSDictionary *fixture, BOOL processing);
void StashEndChromeContentFixture(NSDictionary *fixture);

NSDictionary *StashTopChromeLifecycleProbe(void);
NSString *StashTopChromeProbeSource(void);

void StashEnableChromeFixtureProbe(NSDictionary *fixture);
UIColor *StashChromeFixtureInferredColor(NSDictionary *fixture);

NSDictionary *StashChromeLoadingCoverProbe(void);
NSDictionary *StashLoadingCoverBackgroundProbe(void);

NSDictionary *StashNativePresentationProbe(void);
NSDictionary *StashPresentationLifetimeProbe(void);

NSDictionary *StashPageBackingLifecycleProbe(void);
UIColor *StashChromeFixtureBackingColor(NSDictionary *fixture);

NSDictionary *StashObservedChromeContentFixture(UIViewController *presenter, CGFloat measured);

NSDictionary *StashKeyboardRectangleResolutionProbe(void);
void StashSetKeyboardNotificationContext(id controller, UIWindow *window);

NSDictionary *StashPortraitHooksProbe(void);
NSDictionary *StashPortraitCancellationProbe(void);
NSDictionary *StashPortraitFinishProbe(void);
NSDictionary *StashPortraitBrowserDismissProbe(void);
