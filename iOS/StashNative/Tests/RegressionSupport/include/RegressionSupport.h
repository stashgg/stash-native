#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

// Fixtures declare their own reserved regions; the host scene's (such as iPhone Duo's camera) must not leak in.
@interface StashFixtureWindow : UIWindow
@end
// A fixture window in the foreground scene, for screen-coordinate conversion, keeping the given frame.
UIWindow * _Nonnull StashSceneFixtureWindow(Class _Nonnull windowClass, CGRect frame);

void StashScannerLifecycleProbe(void (^completion)(NSDictionary *));
void StashScannerInterruptedConfirmationProbe(BOOL reset, void (^completion)(NSDictionary *));
void StashScannerCaptureOrderingProbe(void (^completion)(NSDictionary *));
void StashScannerUnavailableProbe(void (^completion)(NSDictionary *));
NSDictionary *StashScannerLayoutProbe(CGSize size);
@class StashNativeScannerConfig;
NSDictionary *StashScannerConfiguredLayoutProbe(CGSize size, StashNativeScannerConfig * _Nullable config);
@class WKWebView, UIViewController, UIColor, UIWindow;
NSDictionary *StashTelemetryLifecycleProbe(void);
NSDictionary *StashTelemetryFixture(void);
void StashEndTelemetryFixture(NSDictionary *fixture);
NSDictionary *StashHapticFixture(UIViewController *presenter);
NSDictionary *StashHapticLifecycleProbe(NSDictionary *fixture);
void StashEndHapticFixture(NSDictionary *fixture);
NSDictionary *StashGeometryProbe(double width, double height, BOOL expanded, double measured,
                                double preferredWidth, double preferredHeight, double maximumHeight, double margin);
NSDictionary *StashReservedRegionProbe(void);
BOOL StashHeightHintProbe(NSDictionary *payload, NSString *documentID, double actualWidth, double scale, double nativeWidth);
NSDictionary *StashConfigurationProbe(void);
NSDictionary *StashCallbackProbe(void);
void StashQueuedCloseProbe(NSString *source, BOOL replace, BOOL processing, BOOL allowDismiss, void (^completion)(BOOL, NSInteger));
NSString *StashMeasurementSource(void);
NSString *StashNativeInteractionSource(void);
NSString *StashInitialContentReadinessSource(void);
NSDictionary *StashLoadingPresentationProbe(void);
NSDictionary *StashNavigationPolicyProbe(void);
NSDictionary *StashNavigationResponseProbe(void);
NSDictionary *StashLoadBudgetProbe(void);
NSDictionary *StashNewWindowProbe(void);
NSDictionary *StashJavaScriptDialogProbe(void);
NSDictionary *StashPostLoadFailureProbe(void);
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
NSString * _Nullable StashNormalizedURLProbe(NSString * _Nullable raw);
NSDictionary *StashLifecycleProbe(void);
NSDictionary *StashPresentationStateProbe(void);
void StashScrollInteractionProbe(void (^completion)(NSDictionary *));
NSDictionary *StashCardViewportCoverageProbe(void);
NSDictionary *StashContentPanPolicyProbe(void);
NSDictionary *StashContentExpansionProbe(void);
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
/// Runs the loading-surface checks with the glass surface forced on or off, then restores the OS default.
NSDictionary *StashLoadingCoverBackgroundProbe(BOOL glass);
/// Whether the SDK uses the glass loading surface on this OS, without a test override.
BOOL StashGlassLoadingSurfaceDefault(void);

NSDictionary *StashNativePresentationProbe(void);
NSDictionary *StashPresentationLifetimeProbe(void);
void StashHostDismissalProbe(NSString *mode, void (^completion)(NSDictionary *));
void StashLandscapeCardWidthProbe(CGFloat preferredWidth, void (^ _Nonnull completion)(NSDictionary * _Nonnull));
NSDictionary *StashNativeEntranceProbe(void);

NSDictionary *StashPageBackingLifecycleProbe(void);
UIColor *StashChromeFixtureBackingColor(NSDictionary *fixture);

NSDictionary *StashObservedChromeContentFixture(UIViewController *presenter, CGFloat measured);

NSDictionary *StashKeyboardRectangleResolutionProbe(void);
void StashSetKeyboardNotificationContext(id controller, UIWindow *window);

NSDictionary *StashPortraitHooksProbe(void);
NSDictionary *StashPortraitCancellationProbe(void);
NSDictionary *StashPortraitFinishProbe(void);
NSDictionary *StashPortraitBrowserDismissProbe(void);
void StashBrowserConfigurationProbe(void (^completion)(NSDictionary *));
NSDictionary *StashBrowserPreparationProbe(void);
void StashInstanceOwnerReleaseProbe(BOOL background, BOOL portrait, void (^completion)(NSDictionary *));
NSDictionary *StashInstanceThemeProbe(void);
NSDictionary *StashInstanceClosingOwnerReleaseProbe(void);
NSDictionary * _Nonnull StashCallbackDismissalProbe(void);
void StashLatePresentationFailureProbe(void (^ _Nonnull completion)(NSDictionary * _Nonnull));
NSDictionary * _Nonnull StashCallbackLiveReceiverProbe(BOOL clear);
NSDictionary * _Nonnull StashCallbackReentrantProbe(void);
NSDictionary * _Nonnull StashCallbackReopenProbe(void);
NSDictionary * _Nonnull StashCallbackDelayedProbe(void);
NSDictionary * _Nonnull StashCallbackIsolationProbe(void);
