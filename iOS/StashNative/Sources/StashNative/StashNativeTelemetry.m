#import "StashNativePrivate.h"
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

// WebKit converts an NSDictionary reply in arbitrary key order. Android inserts keys in this order, and one
// list serves every object because each object's keys keep the same relative order here.
static NSArray<NSString *> *StashTelemetryKeyOrder(void) {
    static NSArray<NSString *> *order;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        order = @[@"schemaVersion", @"platform", @"hardware", @"os", @"app", @"runtime", @"presentation", @"power",
            @"timing", @"manufacturer", @"model", @"memoryBytes", @"id", @"version", @"apiLevel", @"build",
            @"targetSdkVersion", @"sdkVersion", @"webViewEngine", @"webViewPackage", @"webViewVersion", @"state",
            @"keyboardVisible", @"window", @"card", @"safeAreaInsets", @"fold", @"orientationPreference",
            @"portraitApplied", @"multiWindow", @"width", @"height", @"top", @"right", @"bottom", @"left",
            @"orientation", @"separating", @"lowPowerMode", @"thermalState", @"firstCallAt", @"pageLoadStartedAt",
            @"pageLoadedAt", @"pageLoadTimeMs"];
#if !__has_feature(objc_arc)
        [order retain];
#endif
    });
    return order;
}

static void StashTelemetryAppendJSON(NSMutableString *json, id value) {
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *object = value;
        NSArray<NSString *> *order = StashTelemetryKeyOrder();
        NSArray<NSString *> *keys = [object.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            NSUInteger left = [order indexOfObject:a], right = [order indexOfObject:b];
            if (left != right) return left < right ? NSOrderedAscending : NSOrderedDescending;
            return [a compare:b];
        }];
        [json appendString:@"{"];
        for (NSUInteger i = 0; i < keys.count; i++) {
            if (i) [json appendString:@","];
            StashTelemetryAppendJSON(json, keys[i]);
            [json appendString:@":"];
            StashTelemetryAppendJSON(json, object[keys[i]]);
        }
        [json appendString:@"}"];
        return;
    }
    NSArray *wrapped = @[value ?: NSNull.null];
    NSData *data = [NSJSONSerialization isValidJSONObject:wrapped]
        ? [NSJSONSerialization dataWithJSONObject:wrapped options:NSJSONWritingWithoutEscapingSlashes error:NULL] : nil;
    NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    [json appendString:text.length > 2 ? [text substringWithRange:NSMakeRange(1, text.length - 2)] : @"null"];
#if !__has_feature(objc_arc)
    [text release];
#endif
}

// JSON text in Android's key order; WebKit would reorder an NSDictionary reply.
static NSString *StashTelemetryJSON(NSDictionary *snapshot) {
    NSMutableString *json = [NSMutableString string];
    StashTelemetryAppendJSON(json, snapshot);
    return json;
}

@implementation StashCardSession (Telemetry)
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
    BOOL keyboardVisible = self.keyboardVisible || (!CGRectIsNull(keyboard) && !CGRectIsEmpty(keyboard));
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
        @"runtime":@{@"sdkVersion":StashNative.getVersion, @"webViewEngine":@"webkit",
            @"webViewPackage":NSNull.null, @"webViewVersion":NSNull.null},
        @"presentation":@{
            @"state":self.expanded ? @"expanded" : @"resting",
            @"keyboardVisible":@(keyboardVisible),
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
    replyHandler(StashTelemetryJSON([self telemetrySnapshot]), nil);
}
@end
