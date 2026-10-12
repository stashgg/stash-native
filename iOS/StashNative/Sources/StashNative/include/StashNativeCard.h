#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const StashNativeCodeLinkErrorDomain;
typedef NS_ERROR_ENUM(StashNativeCodeLinkErrorDomain, StashNativeCodeLinkError) {
    StashNativeCodeLinkErrorCameraPermissionDenied = 1,
    StashNativeCodeLinkErrorCameraUnavailable,
    StashNativeCodeLinkErrorCameraConfigurationFailed,
    StashNativeCodeLinkErrorMissingCameraUsageDescription
};

typedef NS_ENUM(NSInteger, StashNativeOrientationPreference) {
    StashNativeOrientationPreferenceFollowHost = 0,
    StashNativeOrientationPreferencePortrait = 1
};

/** Responsive card. Defaults: 400 x 560 content, 16 margin, 720 maximum content height.
 * Dimensions are points of web content, excluding safe areas.
 * Preferred height is the resting ceiling and fallback; shorter intrinsic content can shrink it.
 */
@interface StashNativeCardConfig : NSObject <NSCopying>
@property (nonatomic) CGFloat preferredContentWidth;
@property (nonatomic) CGFloat preferredContentHeight;
/** Zero uses all available height. */
@property (nonatomic) CGFloat maximumContentHeight;
@property (nonatomic) CGFloat edgeMargin;
/** Allows user dismissal. Page close, payment callbacks, and native dismiss are independent. */
@property (nonatomic) BOOL allowDismiss;
@property (nonatomic) BOOL autoClose;
/** On iPhone, presents portrait checkout in an SDK window, including landscape-only hosts. Ignored on iPad. */
@property (nonatomic) StashNativeOrientationPreference orientationPreference;
@end

/** Scanner copy. Nil or empty text uses the built-in wording. Copied when CodeLink opens. */
@interface StashNativeCodeLinkConfig : NSObject <NSCopying>
/** Default: "Scan QR code". */
@property (nonatomic, copy, nullable) NSString *headerText;
/** Default: "Scan the webshop code". */
@property (nonatomic, copy, nullable) NSString *calloutTitle;
/** Default: "Keep the QR code centered inside the frame." */
@property (nonatomic, copy, nullable) NSString *calloutSubtitle;
/** Default: "Camera unavailable". */
@property (nonatomic, copy, nullable) NSString *cameraUnavailableText;
/** Default: "Connected". */
@property (nonatomic, copy, nullable) NSString *connectedText;
/** Defaults to YES. NO removes the callout and gives its space to the scan frame. */
@property (nonatomic) BOOL showCallout;
@end

@protocol StashNativeCardDelegate <NSObject>

@optional

/**
 * Called when a payment completes successfully.
 *
 * @param order Optional string from \c window.stash_sdk.onPaymentSuccess(order) (plain or JSON
 *     string). \c nil when the page omits the argument or passes an empty string.
 */
- (void)stashNativeCardDidCompletePaymentWithOrder:(nullable NSString *)order
    NS_SWIFT_NAME(stashNativeCardDidCompletePayment(withOrder:));

/**
 * Called when a payment completes successfully (legacy; prefer \c stashNativeCardDidCompletePaymentWithOrder: when you need order data).
 */
- (void)stashNativeCardDidCompletePayment;

/**
 * Called when a payment fails.
 */
- (void)stashNativeCardDidFailPayment;

/**
 * Called after user dismissal, page window.close() outside processing, or programmatic dismiss.
 */
- (void)stashNativeCardDidDismiss;

/**
 * Called when the checkout page finishes loading.
 * @param loadTimeMs The page load time in milliseconds
 */
- (void)stashNativeCardDidLoadPage:(double)loadTimeMs;

/**
 * Called when a network error occurs during initial page load.
 * This includes no connection, a failed initial response, or a 15-second foreground response deadline.
 * The dialog is automatically dismissed before this callback is invoked.
 */
- (void)stashNativeCardDidEncounterNetworkError;

/**
 * Called when the checkout page calls \c window.stash_sdk.openExternalBrowser(url). The SDK closes the
 * checkout without invoking \c stashNativeCardDidDismiss, then opens the URL in
 * \c SFSafariViewController using the OpenBrowser callbacks. The \c url string includes
 * the theme query parameter when applicable. An iPhone portrait checkout keeps its portrait window
 * through a native Safari sheet and restores the host orientation when the browser closes.
 */
- (void)stashNativeCardDidRequestExternalPaymentWithURL:(NSString *)url
    NS_SWIFT_NAME(stashNativeCardDidRequestExternalPayment(with:));

/**
 * Called when \c SFSafariViewController is dismissed after \c -openBrowserWithURL:fromViewController: or external
 * payment (same browser path), either by the user (Done) or programmatically via \c -closeBrowser.
 */
- (void)stashNativeCardDidCloseBrowser;

/** CodeLink returns the unmodified QR payload once, after the scanner card has closed.
 * No URL is opened and no payment callback or user-dismiss callback is emitted on success.
 */
- (void)stashNativeCardDidScanQRCode:(NSString *)content
    NS_SWIFT_NAME(stashNativeCardDidScanQRCode(_:));

/** CodeLink cannot use the camera. Delivered once per scanner session; the card stays
 * open so the user can close it or grant access in Settings and return to scanning.
 */
- (void)stashNativeCardCodeLinkDidEncounterError:(NSError *)error
    NS_SWIFT_NAME(stashNativeCardCodeLinkDidEncounterError(_:));

@end

/** One active checkout, CodeLink scanner, or browser per instance. Callbacks use the main thread. */
@interface StashNativeCard : NSObject
#if __has_feature(objc_arc)
@property (nonatomic, weak, nullable) id<StashNativeCardDelegate> delegate;
#else
@property (nonatomic, assign, nullable) id<StashNativeCardDelegate> delegate;
#endif
@property (nonatomic, readonly) BOOL isCurrentlyPresented;
@property (nonatomic, readonly) BOOL isPurchaseProcessing;
+ (instancetype)sharedInstance;
+ (NSString *)sdkVersion;
+ (void)setInspectableWebViewsEnabled:(BOOL)enabled;
+ (BOOL)isInspectableWebViewsEnabled;
/** The presenter must belong to the window that initiated checkout. Invalid/busy opens are ignored. */
- (void)openCardWithURL:(NSString *)url fromViewController:(UIViewController *)presenter
               config:(nullable StashNativeCardConfig *)config NS_SWIFT_NAME(openCard(withURL:from:config:));
- (void)openBrowserWithURL:(NSString *)url fromViewController:(UIViewController *)presenter
    NS_SWIFT_NAME(openBrowser(withURL:from:));
/** Opens a QR camera in the responsive native card, following the host app's orientation.
 * The host must provide NSCameraUsageDescription. Requests camera access when opened;
 * uses no microphone and saves no images. The first framed QR code shows a brief Connected
 * confirmation, then closes the card before delivering the scan callback.
 */
- (void)codeLinkFromViewController:(UIViewController *)presenter NS_SWIFT_NAME(codeLink(from:));
/** Opens CodeLink with optional custom scanner copy and callout visibility. */
- (void)codeLinkFromViewController:(UIViewController *)presenter config:(nullable StashNativeCodeLinkConfig *)config
    NS_SWIFT_NAME(codeLink(from:config:));
/** Programmatic dismissal remains available while purchase processing prevents user dismissal. */
- (void)dismiss;
/** Immediately tears down the session without delegate callbacks. */
- (void)resetPresentationState;
- (void)closeBrowser;
- (void)dismissSafariViewControllerWithResult:(BOOL)success;
@end

NS_ASSUME_NONNULL_END
