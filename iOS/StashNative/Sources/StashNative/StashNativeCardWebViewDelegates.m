#import "StashNativeCardPrivate.h"

@implementation StashCheckoutSession (Navigation)
- (BOOL)handlePaymentResultURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    if (!scheme.length || [@[@"http", @"https", @"about", @"blob", @"data", @"file", @"javascript"] containsObject:scheme]) return NO;
    NSString *lower = url.absoluteString.lowercaseString;
    if ([lower containsString:@"stash-pay/success"]) [self paymentSucceeded:YES order:nil];
    else if ([lower containsString:@"stash-pay/failure"]) [self paymentSucceeded:NO order:nil];
    else if ([lower containsString:@"stash-pay/cancel"]) [self handleMessage:@"stashWindowClose" body:@{}];
    else return NO;
    return YES;
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    if (![self isActive]) return;
    [self beginTelemetryNavigation:navigation];
    [self invalidateTopChrome];
    self.topChromeNavigation = navigation;
    [self beginInitialContentNavigation];
    self.documentID = nil;
    self.heightReportSequence++;
    self.measuredContentHeight = 0;
    self.measuredNativeWidth = 0;
    self.hasPendingContentHeight = NO;
    [self.controller.spinner startAnimating];
    [self.controller updatePresentationAnimated:NO];
}
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    if (![self isActive]) return;
    StashRemoveFormInputAccessoryView(webView);
    self.topChromeNavigation = nil;
    [self activateTopChrome];
    [self initialContentCommitted];
    self.documentID = NSUUID.UUID.UUIDString;
    [webView evaluateJavaScript:StashContentMeasurementScript(self.documentID) completionHandler:nil];
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (![self isActive]) return;
    [self finishTelemetryNavigation:navigation];
    [self sampleTopChrome];
    self.loaded = YES;
    [self.loadTimer invalidate];
    self.loadTimer = nil;
    [self initialContentDidFinish];
    if (self.documentID.length) {
        NSString *script = [NSString stringWithFormat:
            @"if(window.__stashContentDocumentId!=='%@'){%@}else if(window.__stashMeasureContent){window.__stashMeasureContent();}",
            self.documentID, StashContentMeasurementScript(self.documentID)];
        [webView evaluateJavaScript:script completionHandler:nil];
    }
    if (self.loadStart > 0) {
        double milliseconds = (CFAbsoluteTimeGetCurrent() - self.loadStart) * 1000;
        self.loadStart = 0;
        id<StashNativeCardDelegate> delegate = self.owner.delegate;
        if ([delegate respondsToSelector:@selector(stashNativeCardDidLoadPage:)]) [delegate stashNativeCardDidLoadPage:milliseconds];
    }
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (![self isActive]) { decisionHandler(WKNavigationActionPolicyCancel); return; }
    NSURL *url = action.request.URL;
    NSString *scheme = url.scheme.lowercaseString;
    BOOL webScheme = [@[@"http", @"https", @"about", @"blob", @"data", @"file", @"javascript"] containsObject:scheme];
    if (!webScheme && scheme.length) {
        decisionHandler(WKNavigationActionPolicyCancel);
        if (![self handlePaymentResultURL:url]) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        return;
    }
    if ([@[@"apps.apple.com", @"itunes.apple.com"] containsObject:url.host.lowercaseString]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        return;
    }
    if (action.navigationType == WKNavigationTypeLinkActivated && action.targetFrame.isMainFrame &&
        ([@[@"http", @"https"] containsObject:scheme])) {
        [UIApplication.sharedApplication openURL:url options:@{UIApplicationOpenURLOptionUniversalLinksOnly:@YES}
            completionHandler:^(BOOL success) {
                decisionHandler(success || ![self isActive] ? WKNavigationActionPolicyCancel : WKNavigationActionPolicyAllow);
            }];
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)response
    decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (![self isActive]) { decisionHandler(WKNavigationResponsePolicyCancel); return; }
    if (response.isForMainFrame && [response.response isKindOfClass:NSHTTPURLResponse.class]) {
        NSInteger status = ((NSHTTPURLResponse *)response.response).statusCode;
        if (status >= 400 && !self.loaded) {
            decisionHandler(WKNavigationResponsePolicyCancel);
            [self networkFailed];
            return;
        }
        if ((status >= 200 && status < 300) || status == 304) {
            self.receivedResponse = YES;
            [self.loadTimer invalidate];
            self.loadTimer = nil;
        }
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled || ![self isActive]) return;
    if (!self.loaded) [self networkFailed]; else [self finishWithUserDismiss:YES completion:nil];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    BOOL keepsDocument = error.code == NSURLErrorCancelled && [self isActive] && webView == self.webView &&
        navigation == self.topChromeNavigation;
    if (keepsDocument) {
        self.topChromeNavigation = nil;
        [self activateTopChrome];
    }
    [self webView:webView didFailNavigation:navigation withError:error];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    if (![self isActive]) return;
    if (self.recoveredProcess || self.processing) { [self networkFailed]; return; }
    [self invalidateTopChrome];
    self.recoveredProcess = YES;
    self.loaded = NO;
    [self beginLoadBudget];
    [webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self.url]
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60]];
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    NSURL *url = action.request.URL;
    if ([self isActive] && url.absoluteString.length && ![url.absoluteString isEqualToString:@"about:blank"]) {
        if (![self handlePaymentResultURL:url]) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }
    return nil;
}
- (void)webViewDidClose:(WKWebView *)webView { [self handleMessage:@"stashWindowClose" body:@{}]; }
- (void)webView:(WKWebView *)webView contextMenuConfigurationForElement:(WKContextMenuElementInfo *)element
    completionHandler:(void (^)(UIContextMenuConfiguration *))completion { completion(nil); }
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completion {
    if (![self isActive] || self.controller.presentedViewController) { completion(); return; }
    self.dialogCompletion = ^(id result) { completion(); };
    StashCheckoutSession *session = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [session completeDialog:nil]; }]];
    [self.controller presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completion {
    if (![self isActive] || self.controller.presentedViewController) { completion(NO); return; }
    self.dialogCompletion = ^(id result) { completion([result boolValue]); };
    StashCheckoutSession *session = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { [session completeDialog:@NO]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [session completeDialog:@YES]; }]];
    [self.controller presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText
    initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString *))completion {
    if (![self isActive] || self.controller.presentedViewController) { completion(nil); return; }
    self.dialogCompletion = ^(id result) { completion(result); };
    StashCheckoutSession *session = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:prompt preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = defaultText; }];
    STASH_WEAK_REF UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { [session completeDialog:nil]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [session completeDialog:weakAlert.textFields.firstObject.text]; }]];
    [self.controller presentViewController:alert animated:YES completion:nil];
}
@end
