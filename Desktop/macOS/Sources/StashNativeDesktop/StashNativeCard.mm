//
//  StashNativeCard.mm
//  StashNativeDesktop
//
//  AppKit facade: the public StashNativeCard singleton over StashDesktopCore, and the mapping
//  from ABI event types to StashNativeCardDelegate.
//

#import "StashNativeCardPrivate.h"

#include <cstdlib>

static void StashRunOnMain(dispatch_block_t block) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

@implementation StashNativeCard

+ (instancetype)sharedInstance {
    static StashNativeCard *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[StashNativeCard alloc] init];
    });
    return instance;
}

+ (NSString *)sdkVersion {
    return @STASH_NATIVE_DESKTOP_VERSION;
}

+ (void)setInspectableWebViewsEnabled:(BOOL)enabled {
    StashRunOnMain(^{
        [StashDesktopCore sharedInstance].inspectableWebViews = enabled;
    });
}

+ (BOOL)isInspectableWebViewsEnabled {
    return [StashDesktopCore sharedInstance].inspectableWebViews;
}

- (NSWindow *)hostWindow {
    return [StashDesktopCore sharedInstance].explicitHostWindow;
}

- (void)setHostWindow:(NSWindow *)hostWindow {
    [StashDesktopCore sharedInstance].explicitHostWindow = hostWindow;
}

- (BOOL)isCurrentlyPresented {
    return [[StashDesktopCore sharedInstance] isCurrentlyPresented];
}

- (BOOL)isPurchaseProcessing {
    return [[StashDesktopCore sharedInstance] isPurchaseProcessing];
}

- (void)openCardWithURL:(NSString *)url config:(StashNativeCardConfig *)config {
    stash::desktop::SurfaceConfig surface = StashSurfaceConfigFromCardConfig(config);
    NSString *urlCopy = [url copy];
    StashRunOnMain(^{
        [[StashDesktopCore sharedInstance] openURL:urlCopy ?: @"" config:surface];
    });
}

- (void)openModalWithURL:(NSString *)url {
    [self openModalWithURL:url config:nil];
}

- (void)openModalWithURL:(NSString *)url config:(StashNativeModalConfig *)config {
    stash::desktop::SurfaceConfig surface = StashSurfaceConfigFromModalConfig(config);
    NSString *urlCopy = [url copy];
    StashRunOnMain(^{
        [[StashDesktopCore sharedInstance] openURL:urlCopy ?: @"" config:surface];
    });
}

- (void)dismiss {
    StashRunOnMain(^{
        [[StashDesktopCore sharedInstance] dismiss];
    });
}

- (void)resetPresentationState {
    StashRunOnMain(^{
        [[StashDesktopCore sharedInstance] resetPresentationState];
    });
}

- (void)openBrowserWithURL:(NSString *)url {
    NSString *urlCopy = [url copy];
    StashRunOnMain(^{
        [[StashDesktopCore sharedInstance] openBrowser:urlCopy ?: @""];
    });
}

- (void)prewarm {
    StashRunOnMain(^{
        [[StashDesktopCore sharedInstance] prewarm];
    });
}

- (void)shutdown {
    StashRunOnMain(^{
        [[StashDesktopCore sharedInstance] shutdown];
    });
}

@end

@implementation StashNativeCard (Internal)

// Always on the main thread (the core dispatches asynchronously, as iOS does for its delegate).
- (void)deliverEventType:(NSString *)type payload:(NSString *)payload {
    id<StashNativeCardDelegate> delegate = self.delegate;
    if (!delegate) {
        return;
    }
    if ([type isEqualToString:@STASH_NATIVE_DESKTOP_EVENT_PAYMENT_SUCCESS]) {
        if ([delegate respondsToSelector:@selector(stashNativeCardDidCompletePaymentWithOrder:)]) {
            [delegate stashNativeCardDidCompletePaymentWithOrder:payload.length > 0 ? payload : nil];
        } else if ([delegate respondsToSelector:@selector(stashNativeCardDidCompletePayment)]) {
            [delegate stashNativeCardDidCompletePayment];
        }
    } else if ([type isEqualToString:@STASH_NATIVE_DESKTOP_EVENT_PAYMENT_FAILURE]) {
        if ([delegate respondsToSelector:@selector(stashNativeCardDidFailPayment)]) {
            [delegate stashNativeCardDidFailPayment];
        }
    } else if ([type isEqualToString:@STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED]) {
        if ([delegate respondsToSelector:@selector(stashNativeCardDidDismiss)]) {
            [delegate stashNativeCardDidDismiss];
        }
    } else if ([type isEqualToString:@STASH_NATIVE_DESKTOP_EVENT_OPT_IN_RESPONSE]) {
        if ([delegate respondsToSelector:@selector(stashNativeCardDidReceiveOptIn:)]) {
            [delegate stashNativeCardDidReceiveOptIn:payload];
        }
    } else if ([type isEqualToString:@STASH_NATIVE_DESKTOP_EVENT_PAGE_LOADED]) {
        if ([delegate respondsToSelector:@selector(stashNativeCardDidLoadPage:)]) {
            [delegate stashNativeCardDidLoadPage:std::strtod(payload.UTF8String ?: "0", nullptr)];
        }
    } else if ([type isEqualToString:@STASH_NATIVE_DESKTOP_EVENT_NETWORK_ERROR]) {
        if ([delegate respondsToSelector:@selector(stashNativeCardDidEncounterNetworkError)]) {
            [delegate stashNativeCardDidEncounterNetworkError];
        }
    } else if ([type isEqualToString:@STASH_NATIVE_DESKTOP_EVENT_EXTERNAL_PAYMENT]) {
        if ([delegate respondsToSelector:@selector(stashNativeCardDidRequestExternalPaymentWithURL:)]) {
            [delegate stashNativeCardDidRequestExternalPaymentWithURL:payload];
        }
    }
    // purchaseProcessing / processingCompleted and the diagnostics have no delegate method; they
    // are observable through isPurchaseProcessing and the C ABI callback.
}

@end
