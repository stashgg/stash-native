//
//  StashNativeCardWebBridge.m
//  StashNative
//
//  The window.stash_sdk -> native bridge: WKScriptMessage dispatch and the per-message handlers
//  (payment success/failure, purchase processing, opt-in, expand/collapse, external payment, window
//  close, page ready). Defines the message-name constants.
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

// JS message handler names.
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
    // Upgrade cleartext http to https for the external payment URL.
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
    // When autoClose is on, the first payment event is handled once; later events are ignored.
    // When autoClose is off, follow-up events (failure -> retry -> success) are not gated.
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
    // No expand when the card is in landscape.
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
    // No collapse when the card is in landscape.
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
    // The external payment URL is handed to the browser without theme parameters.
    dispatch_async(dispatch_get_main_queue(), ^{
        id<StashNativeCardDelegate> externalDelegate = [StashNativeCard sharedInstance].delegate;
        if (externalDelegate
            && [externalDelegate respondsToSelector:@selector(stashNativeCardDidRequestExternalPaymentWithURL:)]) {
            [externalDelegate stashNativeCardDidRequestExternalPaymentWithURL:normalized];
        }
        StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
        // Marks cleanupCardInstance to keep the portrait window alive for the Safari handoff.
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

    // External payment, window close, opt-in, expand, and collapse are dropped when not from the
    // main frame. Payment-result handlers are not gated by frame.
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
