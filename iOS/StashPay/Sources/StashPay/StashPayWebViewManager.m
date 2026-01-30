//
//  StashPayWebViewManager.m
//  StashPay
//
//  WebView configuration and management.
//

#import "StashPayWebViewManager.h"

@interface StashPayWebViewManager ()

@property (nonatomic, strong, readwrite) WKWebView *webView;
@property (nonatomic, assign) CFAbsoluteTime pageLoadStartTime;
@property (nonatomic, weak) UIView *loadingView;
@property (nonatomic, strong) NSTimer *timeoutTimer;
@property (nonatomic, assign) BOOL paymentSuccessHandled;

@end

@implementation StashPayWebViewManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _showScrollbar = NO;
        _paymentSuccessHandled = NO;
    }
    return self;
}

#pragma mark - WebView Creation

- (WKWebView *)createWebViewWithFrame:(CGRect)frame {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // Media playback
    config.allowsInlineMediaPlayback = YES;
    config.allowsAirPlayForMediaPlayback = YES;
    config.allowsPictureInPictureMediaPlayback = YES;
    
    // Security settings
    if (@available(iOS 14.0, *)) {
        config.limitsNavigationsToAppBoundDomains = NO;
    }
    if (@available(iOS 11.0, *)) {
        config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
        config.dataDetectorTypes = WKDataDetectorTypeAll;
    }
    
    // Preferences
    WKPreferences *preferences = [[WKPreferences alloc] init];
    preferences.javaScriptEnabled = YES;
    preferences.javaScriptCanOpenWindowsAutomatically = YES;
    if (@available(iOS 14.0, *)) {
        preferences.fraudulentWebsiteWarningEnabled = YES;
    }
    config.preferences = preferences;
    
    if (@available(iOS 14.0, *)) {
        config.defaultWebpagePreferences.allowsContentJavaScript = YES;
    }
    if (@available(iOS 13.0, *)) {
        config.defaultWebpagePreferences.preferredContentMode = WKContentModeRecommended;
    }
    
    // User content controller with scripts
    WKUserContentController *userContentController = [[WKUserContentController alloc] init];
    [self addUserScripts:userContentController];
    [self addScriptMessageHandlers:userContentController];
    config.userContentController = userContentController;
    
    // Create WebView
    UIColor *backgroundColor = [[self class] systemBackgroundColor];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
    webView.opaque = YES;
    webView.hidden = NO;
    webView.alpha = 0.0; // Start at 0 for cross-fade
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [[self class] setWebViewBackgroundColor:webView color:backgroundColor];
    
    webView.scrollView.opaque = YES;
    [[self class] configureScrollView:webView.scrollView];
    webView.scrollView.scrollEnabled = YES;
    webView.scrollView.showsVerticalScrollIndicator = self.showScrollbar;
    webView.scrollView.showsHorizontalScrollIndicator = NO;
    
    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    
    self.webView = webView;
    return webView;
}

- (void)addUserScripts:(WKUserContentController *)controller {
    // Viewport meta tag
    NSString *viewportScript = @"var meta = document.createElement('meta'); \
        meta.name = 'viewport'; \
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover'; \
        document.head.appendChild(meta);";
    WKUserScript *viewportInjection = [[WKUserScript alloc] initWithSource:viewportScript
                                                             injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                          forMainFrameOnly:YES];
    [controller addUserScript:viewportInjection];
    
    // Stash SDK JavaScript bridge
    NSString *stashSDKScript = @"(function() {"
        "window.stash_sdk = window.stash_sdk || {};"
        "window.stash_sdk.onPaymentSuccess = function(data) {"
            "window.webkit.messageHandlers.stashPaymentSuccess.postMessage(data || {});"
        "};"
        "window.stash_sdk.onPaymentFailure = function(data) {"
            "window.webkit.messageHandlers.stashPaymentFailure.postMessage(data || {});"
        "};"
        "window.stash_sdk.onPurchaseProcessing = function(data) {"
            "window.webkit.messageHandlers.stashPurchaseProcessing.postMessage(data || {});"
        "};"
        "window.stash_sdk.setPaymentChannel = function(optinType) {"
            "window.webkit.messageHandlers.stashOptin.postMessage(optinType || '');"
        "};"
        "window.stash_sdk.expand = function() {"
            "window.webkit.messageHandlers.stashExpand.postMessage({});"
        "};"
        "window.stash_sdk.collapse = function() {"
            "window.webkit.messageHandlers.stashCollapse.postMessage({});"
        "};"
    "})();";
    WKUserScript *stashSDKInjection = [[WKUserScript alloc] initWithSource:stashSDKScript
                                                             injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                          forMainFrameOnly:YES];
    [controller addUserScript:stashSDKInjection];
    
    // No margins CSS
    NSString *noMarginsScript = @"var style = document.createElement('style'); \
        style.innerHTML = 'body { margin: 0 !important; padding: 0 !important; min-height: 100% !important; } \
        html { margin: 0 !important; padding: 0 !important; height: 100% !important; }'; \
        document.head.appendChild(style);";
    WKUserScript *noMarginsInjection = [[WKUserScript alloc] initWithSource:noMarginsScript
                                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                           forMainFrameOnly:YES];
    [controller addUserScript:noMarginsInjection];
}

- (void)addScriptMessageHandlers:(WKUserContentController *)controller {
    [controller addScriptMessageHandler:self name:@"stashPaymentSuccess"];
    [controller addScriptMessageHandler:self name:@"stashPaymentFailure"];
    [controller addScriptMessageHandler:self name:@"stashPurchaseProcessing"];
    [controller addScriptMessageHandler:self name:@"stashOptin"];
    [controller addScriptMessageHandler:self name:@"stashExpand"];
    [controller addScriptMessageHandler:self name:@"stashCollapse"];
}

#pragma mark - Loading

- (void)loadURL:(NSString *)url {
    NSString *urlWithTheme = [[self class] appendThemeQueryParameter:url];
    NSURL *nsurl = [NSURL URLWithString:urlWithTheme];
    if (nsurl) {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsurl
                                                               cachePolicy:NSURLRequestReturnCacheDataElseLoad
                                                           timeoutInterval:15.0];
        [request setValue:@"gzip, deflate, br" forHTTPHeaderField:@"Accept-Encoding"];
        self.pageLoadStartTime = CFAbsoluteTimeGetCurrent();
        [self.webView loadRequest:request];
    }
}

- (UIView *)createLoadingViewWithFrame:(CGRect)frame {
    UIView *loadingView = [[UIView alloc] initWithFrame:frame];
    
    BOOL isDarkMode = NO;
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle currentStyle = [UITraitCollection currentTraitCollection].userInterfaceStyle;
        isDarkMode = (currentStyle == UIUserInterfaceStyleDark);
    }
    
    UIColor *backgroundColor = isDarkMode ? [UIColor blackColor] : [UIColor whiteColor];
    loadingView.backgroundColor = backgroundColor;
    loadingView.opaque = YES;
    
    UIActivityIndicatorView *spinner;
    if (@available(iOS 13.0, *)) {
        spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        spinner.color = isDarkMode ? [UIColor whiteColor] : [UIColor darkGrayColor];
    } else {
        spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        if (!isDarkMode) {
            spinner.color = [UIColor darkGrayColor];
        }
    }
    
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [loadingView addSubview:spinner];
    [spinner startAnimating];
    
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:loadingView.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:loadingView.centerYAnchor]
    ]];
    
    self.loadingView = loadingView;
    
    // Start timeout timer
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                         target:self
                                                       selector:@selector(handleTimeout)
                                                       userInfo:nil
                                                        repeats:NO];
    
    return loadingView;
}

- (void)handleTimeout {
    [self showWebViewAndRemoveLoading];
}

- (void)showWebViewAndRemoveLoading {
    if (self.timeoutTimer) {
        [self.timeoutTimer invalidate];
        self.timeoutTimer = nil;
    }
    
    if (self.webView.alpha < 0.01) {
        UIColor *backgroundColor = [[self class] systemBackgroundColor];
        self.webView.backgroundColor = backgroundColor;
        self.webView.scrollView.backgroundColor = backgroundColor;
        self.webView.scrollView.opaque = YES;
        self.webView.opaque = YES;
        
        // Force background color in dark mode
        if (@available(iOS 13.0, *)) {
            UIUserInterfaceStyle currentStyle = [UITraitCollection currentTraitCollection].userInterfaceStyle;
            if (currentStyle == UIUserInterfaceStyleDark) {
                NSString *forceColor = @"document.documentElement.style.backgroundColor = 'black'; \
                                      document.body.style.backgroundColor = 'black'; \
                                      var style = document.createElement('style'); \
                                      style.innerHTML = 'body, html { background-color: black !important; }'; \
                                      document.head.appendChild(style);";
                [self.webView evaluateJavaScript:forceColor completionHandler:nil];
            }
        }
        
        UIView *loadingView = self.loadingView;
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            loadingView.alpha = 0.0;
            self.webView.alpha = 1.0;
        } completion:^(BOOL finished) {
            [loadingView removeFromSuperview];
        }];
    }
}

#pragma mark - Cleanup

- (void)cleanup {
    // Invalidate timer
    if (self.timeoutTimer) {
        [self.timeoutTimer invalidate];
        self.timeoutTimer = nil;
    }
    
    if (self.webView) {
        [self.webView stopLoading];
        self.webView.navigationDelegate = nil;
        self.webView.UIDelegate = nil;
        
        // Remove script handlers BEFORE removing from view hierarchy
        WKUserContentController *controller = self.webView.configuration.userContentController;
        [controller removeScriptMessageHandlerForName:@"stashPaymentSuccess"];
        [controller removeScriptMessageHandlerForName:@"stashPaymentFailure"];
        [controller removeScriptMessageHandlerForName:@"stashPurchaseProcessing"];
        [controller removeScriptMessageHandlerForName:@"stashOptin"];
        [controller removeScriptMessageHandlerForName:@"stashExpand"];
        [controller removeScriptMessageHandlerForName:@"stashCollapse"];
        [controller removeAllUserScripts];
        
        // Load empty content
        [self.webView loadHTMLString:@"" baseURL:nil];
        
        // Delayed removal
        WKWebView *webViewToRemove = self.webView;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [webViewToRemove removeFromSuperview];
        });
        
        self.webView = nil;
    }
    
    self.paymentSuccessHandled = NO;
}

- (void)prewarmWebViewWithCompletion:(void (^)(void))completion {
    // TODO: Implement smart pre-warming based on available memory
    if (completion) completion();
}

- (void)cleanupPrewarmedWebView {
    // TODO: Clean up pre-warmed WebView
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction 
  decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    NSString *urlString = url.absoluteString;
    
    // Handle special URL schemes
    if ([url.scheme isEqualToString:@"tel"] ||
        [url.scheme isEqualToString:@"mailto"] ||
        [url.scheme isEqualToString:@"sms"]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    
    // Handle App Store links
    if ([urlString containsString:@"apps.apple.com"] ||
        [urlString containsString:@"itunes.apple.com"]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (self.pageLoadStartTime > 0) {
        CFAbsoluteTime loadEndTime = CFAbsoluteTimeGetCurrent();
        double loadTimeMs = (loadEndTime - self.pageLoadStartTime) * 1000.0;
        
        if ([self.delegate respondsToSelector:@selector(webViewManager:didLoadPageWithTime:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate webViewManager:self didLoadPageWithTime:loadTimeMs];
            });
        }
        
        self.pageLoadStartTime = 0;
    }
    
    // Check if page is ready
    [self checkPageReadyAndShowWebView];
}

- (void)checkPageReadyAndShowWebView {
    __weak typeof(self) weakSelf = self;
    
    NSString *readyCheck = @"(function() { \
        if (document.readyState !== 'complete') return false; \
        if (document.documentElement.style.display === 'none') return false; \
        if (document.body === null) return false; \
        if (window.getComputedStyle(document.body).display === 'none') return false; \
        return true; \
    })()";
    
    [self.webView evaluateJavaScript:readyCheck completionHandler:^(id result, NSError *error) {
        if ([result boolValue]) {
            [weakSelf applyDarkModeColorsIfNeeded:^{
                [weakSelf showWebViewAndRemoveLoading];
            }];
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf checkPageReadyAndShowWebView];
            });
        }
    }];
}

- (void)applyDarkModeColorsIfNeeded:(void (^)(void))completion {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle currentStyle = [UITraitCollection currentTraitCollection].userInterfaceStyle;
        if (currentStyle == UIUserInterfaceStyleDark) {
            NSString *forceColor = @"document.documentElement.style.backgroundColor = 'black'; \
                                  document.body.style.backgroundColor = 'black'; \
                                  var style = document.createElement('style'); \
                                  style.innerHTML = 'body, html { background-color: black !important; }'; \
                                  document.head.appendChild(style);";
            [self.webView evaluateJavaScript:forceColor completionHandler:^(id result, NSError *error) {
                if (completion) completion();
            }];
            return;
        }
    }
    if (completion) completion();
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    [self showWebViewAndRemoveLoading];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled) return;
    
    if ([self.delegate respondsToSelector:@selector(webViewManager:didFailNavigationWithError:)]) {
        [self.delegate webViewManager:self didFailNavigationWithError:error];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled) return;
    
    if ([self.delegate respondsToSelector:@selector(webViewManager:didFailNavigationWithError:)]) {
        [self.delegate webViewManager:self didFailNavigationWithError:error];
    }
}

#pragma mark - WKUIDelegate

- (void)webView:(WKWebView *)webView contextMenuConfigurationForElement:(WKContextMenuElementInfo *)elementInfo 
  completionHandler:(void (^)(UIContextMenuConfiguration *))completionHandler API_AVAILABLE(ios(13.0)) {
    completionHandler(nil);
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message 
  initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler();
    }]];
    
    UIViewController *presentingVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (presentingVC.presentedViewController) {
        presentingVC = presentingVC.presentedViewController;
    }
    [presentingVC presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message 
  initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        completionHandler(NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler(YES);
    }]];
    
    UIViewController *presentingVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (presentingVC.presentedViewController) {
        presentingVC = presentingVC.presentedViewController;
    }
    [presentingVC presentViewController:alert animated:YES completion:nil];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message {
    NSString *name = message.name;
    
    if ([name isEqualToString:@"stashPaymentSuccess"]) {
        if (self.paymentSuccessHandled) return;
        self.paymentSuccessHandled = YES;
        
        if ([self.delegate respondsToSelector:@selector(webViewManagerDidReceivePaymentSuccess:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate webViewManagerDidReceivePaymentSuccess:self];
            });
        }
    } else if ([name isEqualToString:@"stashPaymentFailure"]) {
        if (self.paymentSuccessHandled) return;
        self.paymentSuccessHandled = YES;
        
        if ([self.delegate respondsToSelector:@selector(webViewManagerDidReceivePaymentFailure:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate webViewManagerDidReceivePaymentFailure:self];
            });
        }
    } else if ([name isEqualToString:@"stashPurchaseProcessing"]) {
        if ([self.delegate respondsToSelector:@selector(webViewManagerDidStartPurchaseProcessing:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate webViewManagerDidStartPurchaseProcessing:self];
            });
        }
    } else if ([name isEqualToString:@"stashOptin"]) {
        NSString *optinType = [message.body isKindOfClass:[NSString class]] ? message.body : @"";
        
        if ([self.delegate respondsToSelector:@selector(webViewManager:didReceiveOptIn:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate webViewManager:self didReceiveOptIn:optinType];
            });
        }
    } else if ([name isEqualToString:@"stashExpand"]) {
        if ([self.delegate respondsToSelector:@selector(webViewManagerDidRequestExpand:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate webViewManagerDidRequestExpand:self];
            });
        }
    } else if ([name isEqualToString:@"stashCollapse"]) {
        if ([self.delegate respondsToSelector:@selector(webViewManagerDidRequestCollapse:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate webViewManagerDidRequestCollapse:self];
            });
        }
    }
}

#pragma mark - Helper Class Methods

+ (UIColor *)systemBackgroundColor {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle currentStyle = [UITraitCollection currentTraitCollection].userInterfaceStyle;
        return (currentStyle == UIUserInterfaceStyleDark) ? [UIColor blackColor] : [UIColor systemBackgroundColor];
    }
    return [UIColor whiteColor];
}

+ (NSString *)appendThemeQueryParameter:(NSString *)url {
    if (url == nil || url.length == 0) {
        return url;
    }
    
    NSString *theme = @"light";
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle currentStyle = [UITraitCollection currentTraitCollection].userInterfaceStyle;
        if (currentStyle == UIUserInterfaceStyleDark) {
            theme = @"dark";
        }
    }
    
    NSURLComponents *components = [NSURLComponents componentsWithString:url];
    if (components == nil) {
        NSString *separator = [url containsString:@"?"] ? @"&" : @"?";
        return [NSString stringWithFormat:@"%@%@theme=%@", url, separator, theme];
    }
    
    NSMutableArray *queryItems = [NSMutableArray arrayWithArray:components.queryItems ?: @[]];
    
    NSMutableArray *filteredItems = [NSMutableArray array];
    for (NSURLQueryItem *item in queryItems) {
        if (![item.name isEqualToString:@"theme"]) {
            [filteredItems addObject:item];
        }
    }
    
    [filteredItems addObject:[NSURLQueryItem queryItemWithName:@"theme" value:theme]];
    components.queryItems = filteredItems;
    
    return components.URL.absoluteString;
}

+ (void)configureScrollView:(UIScrollView *)scrollView {
    if (@available(iOS 11.0, *)) {
        scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    scrollView.contentInset = UIEdgeInsetsZero;
    scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    scrollView.bounces = NO;
    scrollView.alwaysBounceVertical = NO;
    scrollView.alwaysBounceHorizontal = NO;
}

+ (void)setWebViewBackgroundColor:(WKWebView *)webView color:(UIColor *)color {
    webView.backgroundColor = color;
    webView.scrollView.backgroundColor = color;
    for (UIView *subview in webView.subviews) {
        subview.backgroundColor = color;
        subview.opaque = YES;
    }
    for (UIView *subview in webView.scrollView.subviews) {
        subview.backgroundColor = color;
        subview.opaque = YES;
    }
}

- (void)dealloc {
    [self cleanup];
}

@end
