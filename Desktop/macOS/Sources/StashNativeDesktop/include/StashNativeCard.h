//
//  StashNativeCard.h
//  StashNativeDesktop
//
//  Native macOS SDK for Stash Native checkout integration. Same class, delegate and config
//  shapes as the iOS SDK (iOS/StashNative/.../StashNativeCard.h) minus the UIKit-only members.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Configuration for modal presentation.
 *
 * The ratio fields exist for API parity with the mobile SDKs and are ignored on desktop, where
 * the modal is a fixed 480 x 600 pt surface clamped to the host window.
 */
@interface StashNativeModalConfig : NSObject

/** Phone width ratio for portrait (0.1-1.0). Default 0.80. Ignored on desktop. */
@property (nonatomic, assign) CGFloat phoneWidthRatioPortrait;
/** Phone height ratio for portrait (0.1-1.0). Default 0.50. Ignored on desktop. */
@property (nonatomic, assign) CGFloat phoneHeightRatioPortrait;
/** Phone width ratio for landscape (0.1-1.0). Default 0.50. Ignored on desktop. */
@property (nonatomic, assign) CGFloat phoneWidthRatioLandscape;
/** Phone height ratio for landscape (0.1-1.0). Default 0.80. Ignored on desktop. */
@property (nonatomic, assign) CGFloat phoneHeightRatioLandscape;
/** Tablet width ratio for portrait (0.1-1.0). Default 0.40. Ignored on desktop. */
@property (nonatomic, assign) CGFloat tabletWidthRatioPortrait;
/** Tablet height ratio for portrait (0.1-1.0). Default 0.30. Ignored on desktop. */
@property (nonatomic, assign) CGFloat tabletHeightRatioPortrait;
/** Tablet width ratio for landscape (0.1-1.0). Default 0.30. Ignored on desktop. */
@property (nonatomic, assign) CGFloat tabletWidthRatioLandscape;
/** Tablet height ratio for landscape (0.1-1.0). Default 0.40. Ignored on desktop. */
@property (nonatomic, assign) CGFloat tabletHeightRatioLandscape;
/** Whether the close button, backdrop click and Esc can dismiss the modal. Default YES. */
@property (nonatomic, assign) BOOL allowDismiss;
/** When NO, dialog stays open after onPaymentSuccess/onPaymentFailure (callbacks still fire). Default YES. */
@property (nonatomic, assign) BOOL autoClose;
/** Optional HTML hex (#RGB, #RRGGBB, #AARRGGBB) for sheet background. Omit for default Stash theme. */
@property (nonatomic, copy, nullable) NSString *backgroundColor;

/**
 * Creates a default modal configuration.
 */
- (instancetype)init;

/**
 * Creates a modal configuration with all sizing and behavior options.
 */
- (instancetype)initWithPhoneWidthPortrait:(CGFloat)phoneWidthPortrait
                         phoneHeightPortrait:(CGFloat)phoneHeightPortrait
                         phoneWidthLandscape:(CGFloat)phoneWidthLandscape
                        phoneHeightLandscape:(CGFloat)phoneHeightLandscape
                        tabletWidthPortrait:(CGFloat)tabletWidthPortrait
                       tabletHeightPortrait:(CGFloat)tabletHeightPortrait
                       tabletWidthLandscape:(CGFloat)tabletWidthLandscape
                      tabletHeightLandscape:(CGFloat)tabletHeightLandscape
                              allowDismiss:(BOOL)allowDismiss;

@end

/**
 * Configuration for card presentation (openCard).
 *
 * The ratio fields exist for API parity with the mobile SDKs and are ignored on desktop, where
 * the card is a fixed 480 x 720 pt surface clamped to the host window.
 */
@interface StashNativeCardConfig : NSObject

/** Accepted for parity with mobile; has no effect on desktop. Default NO. */
@property (nonatomic, assign) BOOL forcePortrait;
/** Phone card height ratio in portrait (0.1-1.0). Default 0.68. Ignored on desktop. */
@property (nonatomic, assign) CGFloat cardHeightRatioPortrait;
/** Phone card width ratio in landscape (0.1-1.0). Default 0.7. Ignored on desktop. */
@property (nonatomic, assign) CGFloat cardWidthRatioLandscape;
/** Phone card height ratio in landscape (0.1-1.0). Default 0.9. Ignored on desktop. */
@property (nonatomic, assign) CGFloat cardHeightRatioLandscape;
/** Tablet width ratio in portrait (0.1-1.0). Default 0.4. Ignored on desktop. */
@property (nonatomic, assign) CGFloat tabletWidthRatioPortrait;
/** Tablet height ratio in portrait (0.1-1.0). Default 0.5. Ignored on desktop. */
@property (nonatomic, assign) CGFloat tabletHeightRatioPortrait;
/** Tablet width ratio in landscape (0.1-1.0). Default 0.3. Ignored on desktop. */
@property (nonatomic, assign) CGFloat tabletWidthRatioLandscape;
/** Tablet height ratio in landscape (0.1-1.0). Default 0.6. Ignored on desktop. */
@property (nonatomic, assign) CGFloat tabletHeightRatioLandscape;
/** When NO, dialog stays open after onPaymentSuccess/onPaymentFailure (callbacks still fire). Default YES. */
@property (nonatomic, assign) BOOL autoClose;
/** Optional HTML hex (#RGB, #RRGGBB, #AARRGGBB) for sheet background. Omit for default Stash theme. */
@property (nonatomic, copy, nullable) NSString *backgroundColor;

/**
 * Creates a default card configuration.
 */
- (instancetype)init;

@end

/**
 * Protocol for receiving StashNativeCard events. All methods are called on the main thread.
 */
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
 * Called when the checkout dialog is dismissed by the user, or when the embedded page calls window.close().
 */
- (void)stashNativeCardDidDismiss;

/**
 * Called when an opt-in response is received.
 * @param optinType The type of opt-in response
 */
- (void)stashNativeCardDidReceiveOptIn:(NSString *)optinType;

/**
 * Called when the checkout page finishes loading.
 * @param loadTimeMs The page load time in milliseconds
 */
- (void)stashNativeCardDidLoadPage:(double)loadTimeMs;

/**
 * Called when a network error occurs during initial page load.
 * This includes: no network connection, page load failure, or timeout (15 seconds).
 * The dialog is automatically dismissed before this callback is invoked.
 */
- (void)stashNativeCardDidEncounterNetworkError;

/**
 * Called when the checkout page calls \c window.stash_sdk.openExternalBrowser(url). The SDK closes the
 * checkout without invoking \c stashNativeCardDidDismiss, then opens the URL in the system browser
 * (same behavior as \c -openBrowserWithURL:). The \c url string includes the theme query parameter.
 */
- (void)stashNativeCardDidRequestExternalPaymentWithURL:(NSString *)url
    NS_SWIFT_NAME(stashNativeCardDidRequestExternalPayment(with:));

@end

/**
 * StashNativeCard - Native macOS SDK for Stash Native checkout integration.
 *
 * The checkout is presented as a card over the host window's content, with the app still
 * rendering underneath. Use the shared instance from the main thread.
 *
 * @code
 * StashNativeCard *stashNative = [StashNativeCard sharedInstance];
 * stashNative.delegate = self;
 * [stashNative openCardWithURL:@"https://your-checkout-url.com" config:nil];
 * @endcode
 *
 * Threading and callback contract: every call goes on the main thread. Delegate methods and
 * the C ABI callback are delivered on the main thread through a dispatch_async, so they arrive
 * after the WebKit callback that produced them has unwound, never re-entrantly. target=_blank,
 * window.open and openLink open the system browser and the checkout stays presented;
 * externalPayment closes it. A non-web URL from the page goes to the OS as a deeplink.
 * Full guide: docs/macos.md in the stash-native repository.
 */
@interface StashNativeCard : NSObject

/**
 * The delegate to receive StashNativeCard events.
 */
#if __has_feature(objc_arc)
@property (nonatomic, weak, nullable) id<StashNativeCardDelegate> delegate;
#else
@property (nonatomic, assign, nullable) id<StashNativeCardDelegate> delegate;
#endif

/**
 * Window the card is presented over. Optional: when nil the key window (then the main window)
 * is used. Set it when the app has several windows or presents from a non-key window.
 */
@property (nonatomic, weak, nullable) NSWindow *hostWindow;

/**
 * Checks if a checkout card or modal is currently displayed.
 */
@property (nonatomic, readonly) BOOL isCurrentlyPresented;

/**
 * Checks if a purchase is currently being processed.
 * When YES, the checkout dialog cannot be dismissed by the user.
 */
@property (nonatomic, readonly) BOOL isPurchaseProcessing;

/**
 * Gets the shared singleton instance of StashNativeCard.
 */
+ (instancetype)sharedInstance;

/**
 * Returns the SDK version string (e.g. "2.4.0").
 */
+ (NSString *)sdkVersion;

/**
 * Enables remote inspection (Safari Web Inspector) of the SDK's checkout webviews. Off by default.
 * When enabled, checkout WKWebViews are created with \c inspectable = YES on macOS 13.3+.
 *
 * Intended for debug/QA builds and automated UI testing only. Do NOT enable in production.
 * Set before opening any checkout.
 *
 * @param enabled YES to make the SDK's webviews inspectable
 */
+ (void)setInspectableWebViewsEnabled:(BOOL)enabled;

/**
 * Whether webview inspection is enabled. Default NO.
 */
+ (BOOL)isInspectableWebViewsEnabled;

/**
 * Opens a URL in a card over the host window.
 *
 * Pass nil for config to use default sizing and behavior.
 *
 * @param url The URL to load in the card
 * @param config Card behavior configuration (nil for defaults)
 */
- (void)openCardWithURL:(NSString *)url config:(nullable StashNativeCardConfig *)config NS_SWIFT_NAME(openCard(withURL:config:));

/**
 * Opens a URL in a centered modal dialog with default configuration.
 *
 * @param url The URL to load in the modal
 */
- (void)openModalWithURL:(NSString *)url;

/**
 * Opens a URL in a centered modal dialog with custom configuration.
 *
 * @param url The URL to load in the modal
 * @param config Configuration for dismiss behavior (nil for defaults)
 */
- (void)openModalWithURL:(NSString *)url config:(nullable StashNativeModalConfig *)config;

/**
 * Opens a card with the JSON config the game-engine wrappers send (see docs/macos.md). Same keys
 * as \c StashNativeCardConfig plus the desktop-only \c presentation ("attached" or "window"),
 * \c width, \c height and \c allowFileUrls. nil or empty for defaults.
 */
- (void)openCardWithURL:(NSString *)url configJSON:(nullable NSString *)configJSON NS_SWIFT_NAME(openCard(withURL:configJSON:));

/**
 * Opens a modal with the JSON config the game-engine wrappers send. nil or empty for defaults.
 */
- (void)openModalWithURL:(NSString *)url configJSON:(nullable NSString *)configJSON NS_SWIFT_NAME(openModal(withURL:configJSON:));

/**
 * Dismisses any currently displayed checkout dialog. Invokes \c stashNativeCardDidDismiss.
 */
- (void)dismiss;

/**
 * Resets the presentation state and dismisses any displayed dialog without callbacks.
 */
- (void)resetPresentationState;

/**
 * Opens a URL in the system browser. There is no browser-closed callback on desktop.
 *
 * @param url The URL to open in the browser
 */
- (void)openBrowserWithURL:(NSString *)url;

/**
 * Creates the web content processes and a hidden webview ahead of time so the first checkout
 * opens instantly. Optional; call once at app start.
 */
- (void)prewarm;

/**
 * Releases the prewarmed webview and any presented checkout without callbacks. Call at app
 * termination. The SDK can be used again afterwards.
 */
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
