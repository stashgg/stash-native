#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativeCardPrivate.h"

NSDictionary *StashTelemetryLifecycleProbe(void) {
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.config = [StashNativeCardConfig new];
    WKNavigation *first = (id)[NSObject new];
    WKNavigation *second = (id)[NSObject new];
    [session beginTelemetryNavigation:first];
    NSDictionary *initial = [session telemetrySnapshot];
    session.telemetryLoadStart -= 0.125;
    [session finishTelemetryNavigation:first];
    NSDictionary *loaded = [session telemetrySnapshot];
    [session finishTelemetryNavigation:first];
    BOOL duplicatePreserved = [[session telemetrySnapshot][@"timing"] isEqual:loaded[@"timing"]];
    [session beginTelemetryNavigation:second];
    [session finishTelemetryNavigation:first];
    NSDictionary *next = [session telemetrySnapshot];
    session.expanded = YES;
    session.keyboardVisible = YES;
    [session finishTelemetryNavigation:second];
    NSDictionary *finished = [session telemetrySnapshot];
    StashCheckoutSession *fresh = [StashCheckoutSession new];
    BOOL independent = fresh.telemetryFirstCallAt == nil && fresh.telemetryPageLoadedAt == nil;
    [session cleanup];
    return @{@"initial":initial, @"loaded":loaded, @"next":next, @"finished":finished,
        @"duplicatePreserved":@(duplicatePreserved), @"independent":@(independent),
        @"cleaned":@(session.telemetryNavigation == nil && session.telemetryFirstCallAt == nil)};
}

NSDictionary *StashTelemetryFixture(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new];
    owner.session = session;
    session.owner = owner;
    session.config = [StashNativeCardConfig new];
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addScriptMessageHandlerWithReply:session
        contentWorld:WKContentWorld.pageWorld name:@"stashTelemetry"];
    [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:StashBridgeScript()
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    WKWebView *web = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 390, 600) configuration:configuration];
    web.navigationDelegate = session;
    session.webView = web;
    return @{@"owner":owner, @"session":session, @"web":web};
}

void StashEndTelemetryFixture(NSDictionary *fixture) {
    [fixture[@"session"] cleanup];
    ((StashNativeCard *)fixture[@"owner"]).session = nil;
}
