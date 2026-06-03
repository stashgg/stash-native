//
//  StashNativeCardWebBridge.m
//  StashNative
//
//  The window.stash_sdk -> native bridge: WKScriptMessage dispatch and the per-message handlers
//  (payment success/failure, purchase processing, opt-in, expand/collapse, external payment, window
//  close, page ready). The message-name constants live here as the single source; core injects them
//  into the page (stashSDKScript) and registers/removes them via the extern declarations in
//  StashNativeCardWebBridge.h. Methods moved verbatim from StashNativeCard.m.
//

#import "StashNativeCard.h"
#import "StashNativeCardInternal.h"
#import "StashNativeCardPrivate.h"
#import "StashNativeCardWebBridge.h"

#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

// JS message handler names (mirror Android JS_SDK_SCRIPT + docs/stash-sdk-js.md). extern in the header.
NSString * const kMessageHandlerPaymentSuccess = @"stashNativementSuccess";
NSString * const kMessageHandlerPaymentFailure = @"stashNativementFailure";
NSString * const kMessageHandlerPurchaseProcessing = @"stashPurchaseProcessing";
NSString * const kMessageHandlerOptin = @"stashOptin";
NSString * const kMessageHandlerExpand = @"stashExpand";
NSString * const kMessageHandlerCollapse = @"stashCollapse";
NSString * const kMessageHandlerWindowClose = @"stashWindowClose";
NSString * const kMessageHandlerExternalPayment = @"stashExternalPayment";
NSString * const kMessageHandlerPageReady = @"stashNativePageReady";

static NSString *NormalizeExternalPaymentURL(NSString *raw) {
    if (raw == nil) {
        return nil;
    }
    NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0) {
        return nil;
    }
    NSString *lower = [s lowercaseString];
    if ([lower hasPrefix:@"javascript:"] || [lower hasPrefix:@"file:"] || [lower hasPrefix:@"data:"]) {
        return nil;
    }
    if (![lower hasPrefix:@"http://"] && ![lower hasPrefix:@"https://"]) {
        s = [@"https://" stringByAppendingString:s];
    }
    NSURL *u = [NSURL URLWithString:s];
    if (u == nil || u.scheme.length == 0) {
        return nil;
    }
    NSString *scheme = [u.scheme lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return nil;
    }
    if (u.host.length == 0) {
        return nil;
    }
    // Upgrade cleartext http to https for the external payment URL (rather than rejecting it).
    if ([scheme isEqualToString:@"http"]) {
        NSURLComponents *comps = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
        comps.scheme = @"https";
        NSURL *upgraded = comps.URL;
        if (upgraded) {
            return upgraded.absoluteString;
        }
    }
    return u.absoluteString;
}

@implementation StashNativeCardInternal (WebBridge)

- (void)handlePaymentSuccessMessage:(WKScriptMessage *)message delegate:(id<StashNativeCardDelegate>)delegate {
    // When autoClose is on, the dialog tears down after the first event, so guard against
    // duplicate callbacks. When autoClose is off, the page stays alive and may legitimately
    // emit follow-up events (e.g. failure -> retry -> success), so don't gate.
    if (stash_autoCloseOnPaymentEvent && stash_paymentSuccessHandled) return;
    if (stash_autoCloseOnPaymentEvent) stash_paymentSuccessHandled = YES;
    self.isPurchaseProcessing = NO;

    NSString *orderString = nil;
    id body = message.body;
    if ([body isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)body;
        if (s.length > 0) {
            orderString = s;
        }
    }

    if (delegate) {
        if ([delegate respondsToSelector:@selector(stashNativeCardDidCompletePaymentWithOrder:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate stashNativeCardDidCompletePaymentWithOrder:orderString];
            });
        } else if ([delegate respondsToSelector:@selector(stashNativeCardDidCompletePayment)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate stashNativeCardDidCompletePayment];
            });
        }
    }

    if (stash_autoCloseOnPaymentEvent) {
        [self dismissWithAnimation:^{
            [self cleanupCardInstance];
        }];
    }
}

- (void)handlePaymentFailureWithDelegate:(id<StashNativeCardDelegate>)delegate {
    if (stash_autoCloseOnPaymentEvent && stash_paymentSuccessHandled) return;
    if (stash_autoCloseOnPaymentEvent) stash_paymentSuccessHandled = YES;
    self.isPurchaseProcessing = NO;

    if (delegate && [delegate respondsToSelector:@selector(stashNativeCardDidFailPayment)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate stashNativeCardDidFailPayment];
        });
    }

    if (stash_autoCloseOnPaymentEvent) {
        [self dismissWithAnimation:^{
            [self cleanupCardInstance];
        }];
    }
}

- (void)handlePurchaseProcessingMessage {
    self.isPurchaseProcessing = YES;
    [self updateDragTrayVisibilityForPurchaseProcessing:YES];
}

- (void)handleOptinMessage:(WKScriptMessage *)message delegate:(id<StashNativeCardDelegate>)delegate {
    NSString *optinType = [message.body isKindOfClass:[NSString class]] ? message.body : @"";

    if (delegate && [delegate respondsToSelector:@selector(stashNativeCardDidReceiveOptIn:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate stashNativeCardDidReceiveOptIn:optinType];
        });
    }

    [self dismissWithAnimation:^{
        [self cleanupCardInstance];
    }];
}

- (void)handleExpandMessage {
    if (stash_useModalPresentation || stash_usePopupPresentation) {
        return;
    }
    // Phones only: landscape cards stay at their configured size.
    if (stash_cardIsInLandscape) {
        return;
    }

    if (!stash_isCardExpanded && self.currentPresentedVC) {
        [self animateExpandWithDuration:kAnimationDurationDefault completion:nil];
    }
}

- (void)handleCollapseMessage {
    if (stash_useModalPresentation || stash_usePopupPresentation) {
        return;
    }
    // Phones only: landscape cards stay at their configured size.
    if (stash_cardIsInLandscape) {
        return;
    }

    if (stash_isCardExpanded && self.currentPresentedVC) {
        [self animateCollapseWithDuration:kAnimationDurationDefault completion:nil];
    }
}

- (void)handleExternalPaymentMessage:(WKScriptMessage *)message {
    NSString *raw = @"";
    if ([message.body isKindOfClass:[NSString class]]) {
        raw = (NSString *)message.body;
    }
    NSString *normalized = NormalizeExternalPaymentURL(raw);
    if (!normalized) {
        return;
    }
    // Theme is applied only to in-card content, never to URLs handed to an external browser.
    dispatch_async(dispatch_get_main_queue(), ^{
        id<StashNativeCardDelegate> externalDelegate = [StashNativeCard sharedInstance].delegate;
        if (externalDelegate
            && [externalDelegate respondsToSelector:@selector(stashNativeCardDidRequestExternalPaymentWithURL:)]) {
            [externalDelegate stashNativeCardDidRequestExternalPaymentWithURL:normalized];
        }
        StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
        // Signal cleanupCardInstance to keep the portrait window alive so Safari can be
        // presented from it immediately — no scene-rotation animation between card and Safari.
        if (stash_forcePortraitOnCheckout) {
            internal.isHandingOffPortraitWindowToSafari = YES;
        }
        [internal dismissWithAnimation:^{
            [internal cleanupCardInstance];
            [[StashNativeCard sharedInstance] openBrowserWithURL:normalized];
        }];
    });
}

- (void)handleWindowCloseMessage {
    if (self.isPurchaseProcessing) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self dismissWithAnimation:^{
            [self cleanupCardInstance];
            [self callDelegateCallbackOnce];
        }];
    });
}

- (void)handlePageReadyMessage {
    WebViewLoadDelegate *loadDelegate = self.activeWebViewLoadDelegate;
    if (loadDelegate) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [loadDelegate notifyPageReadyFromInjectedScript];
        });
    }
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSString *name = message.name;
    id<StashNativeCardDelegate> delegate = [StashNativeCard sharedInstance].delegate;

    // Privileged action handlers must originate from the main frame (the checkout page), not a
    // nested third-party iframe. Payment-result handlers are intentionally not gated here.
    if (!message.frameInfo.isMainFrame &&
        ([name isEqualToString:kMessageHandlerExternalPayment] ||
         [name isEqualToString:kMessageHandlerWindowClose] ||
         [name isEqualToString:kMessageHandlerOptin] ||
         [name isEqualToString:kMessageHandlerExpand] ||
         [name isEqualToString:kMessageHandlerCollapse])) {
        return;
    }

    if ([name isEqualToString:kMessageHandlerPaymentSuccess]) {
        [self handlePaymentSuccessMessage:message delegate:delegate];
    } else if ([name isEqualToString:kMessageHandlerPaymentFailure]) {
        [self handlePaymentFailureWithDelegate:delegate];
    } else if ([name isEqualToString:kMessageHandlerPurchaseProcessing]) {
        [self handlePurchaseProcessingMessage];
    } else if ([name isEqualToString:kMessageHandlerOptin]) {
        [self handleOptinMessage:message delegate:delegate];
    } else if ([name isEqualToString:kMessageHandlerExpand]) {
        [self handleExpandMessage];
    } else if ([name isEqualToString:kMessageHandlerCollapse]) {
        [self handleCollapseMessage];
    } else if ([name isEqualToString:kMessageHandlerExternalPayment]) {
        [self handleExternalPaymentMessage:message];
    } else if ([name isEqualToString:kMessageHandlerWindowClose]) {
        [self handleWindowCloseMessage];
    } else if ([name isEqualToString:kMessageHandlerPageReady]) {
        [self handlePageReadyMessage];
    }
}

@end

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
