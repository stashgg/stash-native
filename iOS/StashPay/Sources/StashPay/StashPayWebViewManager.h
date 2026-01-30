//
//  StashPayWebViewManager.h
//  StashPay
//
//  WebView configuration and management.
//

#import <WebKit/WebKit.h>
#import "StashPayCardConstants.h"

NS_ASSUME_NONNULL_BEGIN

@protocol StashPayWebViewManagerDelegate;

/**
 * Manages WKWebView configuration, JavaScript bridge, and lifecycle.
 */
@interface StashPayWebViewManager : NSObject <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>

/**
 * Delegate for WebView events.
 */
@property (nonatomic, weak, nullable) id<StashPayWebViewManagerDelegate> delegate;

/**
 * The managed WebView instance.
 */
@property (nonatomic, strong, readonly) WKWebView *webView;

/**
 * Whether scrollbar is visible.
 */
@property (nonatomic, assign) BOOL showScrollbar;

/**
 * Creates a configured WebView for the given frame.
 * @param frame Initial frame
 * @return Configured WKWebView
 */
- (WKWebView *)createWebViewWithFrame:(CGRect)frame;

/**
 * Loads a URL in the WebView.
 * @param url URL string to load
 */
- (void)loadURL:(NSString *)url;

/**
 * Creates a loading view.
 * @param frame Frame for the loading view
 * @return Configured loading view with spinner
 */
- (UIView *)createLoadingViewWithFrame:(CGRect)frame;

/**
 * Cleans up WebView resources (call before dealloc).
 */
- (void)cleanup;

/**
 * Pre-warms the WebView on high-memory devices.
 * @param completion Called when pre-warming is complete
 */
- (void)prewarmWebViewWithCompletion:(nullable void (^)(void))completion;

/**
 * Cleans up pre-warmed WebView.
 */
- (void)cleanupPrewarmedWebView;

#pragma mark - Helper Functions

/**
 * Gets the system background color (dark mode aware).
 */
+ (UIColor *)systemBackgroundColor;

/**
 * Appends theme query parameter to URL.
 * @param url Original URL
 * @return URL with theme parameter
 */
+ (NSString *)appendThemeQueryParameter:(NSString *)url;

/**
 * Configures scroll view for optimal WebView behavior.
 * @param scrollView The scroll view to configure
 */
+ (void)configureScrollView:(UIScrollView *)scrollView;

/**
 * Sets background color on WebView and all subviews.
 * @param webView The WebView
 * @param color The color to set
 */
+ (void)setWebViewBackgroundColor:(WKWebView *)webView color:(UIColor *)color;

@end

#pragma mark - Delegate Protocol

@protocol StashPayWebViewManagerDelegate <NSObject>

@optional

/**
 * Called when payment succeeds.
 */
- (void)webViewManagerDidReceivePaymentSuccess:(StashPayWebViewManager *)manager;

/**
 * Called when payment fails.
 */
- (void)webViewManagerDidReceivePaymentFailure:(StashPayWebViewManager *)manager;

/**
 * Called when purchase processing starts.
 */
- (void)webViewManagerDidStartPurchaseProcessing:(StashPayWebViewManager *)manager;

/**
 * Called when opt-in response is received.
 * @param optinType The opt-in type
 */
- (void)webViewManager:(StashPayWebViewManager *)manager didReceiveOptIn:(NSString *)optinType;

/**
 * Called when expand is requested from JavaScript.
 */
- (void)webViewManagerDidRequestExpand:(StashPayWebViewManager *)manager;

/**
 * Called when collapse is requested from JavaScript.
 */
- (void)webViewManagerDidRequestCollapse:(StashPayWebViewManager *)manager;

/**
 * Called when page finishes loading.
 * @param loadTimeMs Load time in milliseconds
 */
- (void)webViewManager:(StashPayWebViewManager *)manager didLoadPageWithTime:(double)loadTimeMs;

/**
 * Called when navigation fails.
 * @param error The error
 */
- (void)webViewManager:(StashPayWebViewManager *)manager didFailNavigationWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
