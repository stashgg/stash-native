#import "StashNativeCardPrivate.h"
#import <QuartzCore/QuartzCore.h>
#import <sys/utsname.h>

static NSNumber *StashTelemetryTimestamp(void) {
    return @((long long)(NSDate.date.timeIntervalSince1970 * 1000));
}

static id StashTelemetryString(id value) {
    return [value isKindOfClass:NSString.class] && [value length] ? value : NSNull.null;
}

static NSDictionary *StashTelemetrySize(CGSize size, BOOL available) {
    return @{@"width":available ? @(size.width) : NSNull.null,
             @"height":available ? @(size.height) : NSNull.null};
}

@implementation StashCheckoutSession (Telemetry)
- (void)beginTelemetryNavigation:(WKNavigation *)navigation {
    self.telemetryNavigation = navigation;
    self.telemetryPageLoadStartedAt = StashTelemetryTimestamp();
    self.telemetryLoadStart = CACurrentMediaTime();
    self.telemetryPageLoadedAt = nil;
    self.telemetryPageLoadTimeMs = nil;
}

- (void)finishTelemetryNavigation:(WKNavigation *)navigation {
    if (!navigation || navigation != self.telemetryNavigation || self.telemetryPageLoadedAt != nil) return;
    self.telemetryPageLoadedAt = StashTelemetryTimestamp();
    self.telemetryPageLoadTimeMs = @((long long)MAX(0, (CACurrentMediaTime() - self.telemetryLoadStart) * 1000));
}

- (NSDictionary *)telemetrySnapshot {
    if (self.telemetryFirstCallAt == nil) self.telemetryFirstCallAt = StashTelemetryTimestamp();
    NSProcessInfo *process = NSProcessInfo.processInfo;
    NSString *model = nil;
    struct utsname machine;
    if (uname(&machine) == 0) model = [NSString stringWithUTF8String:machine.machine];
#if TARGET_OS_SIMULATOR
    model = process.environment[@"SIMULATOR_MODEL_IDENTIFIER"] ?: model;
#endif
    NSString *thermal = nil;
    switch (process.thermalState) {
        case NSProcessInfoThermalStateNominal: thermal = @"nominal"; break;
        case NSProcessInfoThermalStateFair: thermal = @"fair"; break;
        case NSProcessInfoThermalStateSerious: thermal = @"serious"; break;
        case NSProcessInfoThermalStateCritical: thermal = @"critical"; break;
        default: break;
    }
    UIView *card = self.controller.viewIfLoaded;
    UIWindow *window = card.window ?: self.presentationPresenter.viewIfLoaded.window;
    UIEdgeInsets insets = window.safeAreaInsets;
    CGRect keyboard = window ? [self.controller resolvedKeyboardFrameInView:window dockedOnly:NO] : CGRectNull;
    BOOL portraitRequested = self.config.orientationPreference == StashNativeOrientationPreferencePortrait;
    BOOL portraitApplied = portraitRequested && self.portraitPresentation != nil &&
        UIInterfaceOrientationIsPortrait(window.windowScene.interfaceOrientation);
    NSDictionary *bundle = NSBundle.mainBundle.infoDictionary;
    return @{
        @"schemaVersion":@1,
        @"platform":@"ios",
        @"hardware":@{@"manufacturer":@"Apple", @"model":StashTelemetryString(model),
            @"memoryBytes":process.physicalMemory ? @(process.physicalMemory) : NSNull.null},
        @"os":@{@"version":UIDevice.currentDevice.systemVersion, @"apiLevel":NSNull.null},
        @"app":@{@"id":StashTelemetryString(NSBundle.mainBundle.bundleIdentifier),
            @"version":StashTelemetryString(bundle[@"CFBundleShortVersionString"]),
            @"build":StashTelemetryString(bundle[@"CFBundleVersion"]), @"targetSdkVersion":NSNull.null},
        @"runtime":@{@"sdkVersion":StashNativeCard.sdkVersion, @"webViewEngine":@"webkit",
            @"webViewPackage":NSNull.null, @"webViewVersion":NSNull.null},
        @"presentation":@{
            @"state":self.expanded ? @"expanded" : @"resting",
            @"keyboardVisible":@(self.keyboardVisible || (!CGRectIsNull(keyboard) && !CGRectIsEmpty(keyboard))),
            @"orientationPreference":portraitRequested ? @"portrait" : @"followHost",
            @"portraitApplied":@(portraitApplied),
            @"window":StashTelemetrySize(window.bounds.size, window != nil),
            @"card":StashTelemetrySize(card.bounds.size, card != nil),
            @"safeAreaInsets":@{@"top":window ? @(insets.top) : NSNull.null,
                @"right":window ? @(insets.right) : NSNull.null,
                @"bottom":window ? @(insets.bottom) : NSNull.null,
                @"left":window ? @(insets.left) : NSNull.null},
            @"multiWindow":NSNull.null,
            @"fold":@{@"state":NSNull.null, @"orientation":NSNull.null, @"separating":NSNull.null}},
        @"power":@{@"lowPowerMode":@(process.lowPowerModeEnabled), @"thermalState":StashTelemetryString(thermal)},
        @"timing":@{@"firstCallAt":self.telemetryFirstCallAt,
            @"pageLoadStartedAt":self.telemetryPageLoadStartedAt ?: NSNull.null,
            @"pageLoadedAt":self.telemetryPageLoadedAt ?: NSNull.null,
            @"pageLoadTimeMs":self.telemetryPageLoadTimeMs ?: NSNull.null}
    };
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message
    replyHandler:(void (^)(id reply, NSString *errorMessage))replyHandler {
    if (![message.name isEqualToString:@"stashTelemetry"] || message.webView != self.webView ||
        !message.frameInfo.isMainFrame || ![self isActive] || self.browserHandoff) {
        replyHandler(nil, @"Stash telemetry is unavailable");
        return;
    }
    replyHandler([self telemetrySnapshot], nil);
}
@end
