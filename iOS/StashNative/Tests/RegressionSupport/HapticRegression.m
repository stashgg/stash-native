#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativePrivate.h"
#import <objc/runtime.h>

@interface StashHapticRecorder : NSObject
@property(nonatomic, strong) NSMutableArray *events;
@property(nonatomic, assign) IMP original;
@property(nonatomic, assign) IMP replacement;
- (void)stop;
@end

@implementation StashHapticRecorder
- (instancetype)init {
    if ((self = [super init])) {
        _events = [NSMutableArray new];
        NSMutableArray *events = _events;
        _replacement = imp_implementationWithBlock(^(id generator, UINotificationFeedbackType type) {
            [events addObject:@{@"success":@(type == UINotificationFeedbackTypeSuccess),
                @"mainThread":@(NSThread.isMainThread)}];
        });
        Method method = class_getInstanceMethod(UINotificationFeedbackGenerator.class, @selector(notificationOccurred:));
        _original = method_setImplementation(method, _replacement);
    }
    return self;
}
- (void)stop {
    if (!_replacement) return;
    method_setImplementation(class_getInstanceMethod(UINotificationFeedbackGenerator.class,
        @selector(notificationOccurred:)), _original);
    imp_removeBlock(_replacement);
    _replacement = NULL;
}
- (void)dealloc { [self stop]; }
@end

NSDictionary *StashHapticFixture(UIViewController *presenter) {
    StashNative *owner = [StashNative new];
    StashCheckoutSession *session = [StashCheckoutSession new];
    owner.session = session;
    session.owner = owner;
    session.config = [StashNativeCardConfig new];
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    for (NSString *name in StashScriptHandlerNames())
        [configuration.userContentController addScriptMessageHandler:session name:name];
    [configuration.userContentController addScriptMessageHandlerWithReply:session
        contentWorld:WKContentWorld.pageWorld name:@"stashTelemetry"];
    [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:StashBridgeScript()
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    WKWebView *web = [[WKWebView alloc] initWithFrame:presenter.view.bounds configuration:configuration];
    session.webView = web;
    [presenter.view addSubview:web];
    StashHapticRecorder *recorder = [StashHapticRecorder new];
    return @{@"owner":owner, @"session":session, @"web":web, @"recorder":recorder, @"events":recorder.events};
}

NSDictionary *StashHapticLifecycleProbe(NSDictionary *fixture) {
    StashNative *owner = fixture[@"owner"];
    StashCheckoutSession *session = fixture[@"session"];
    WKWebView *web = fixture[@"web"];
    NSMutableArray *events = fixture[@"events"];
    NSUInteger before = events.count;
    session.closing = YES;
    [session handleMessage:@"stashTriggerHaptic" body:@{}];
    session.closing = NO;
    session.browserHandoff = YES;
    [session handleMessage:@"stashTriggerHaptic" body:@{}];
    session.browserHandoff = NO;
    owner.session = nil;
    [session handleMessage:@"stashTriggerHaptic" body:@{}];
    owner.session = session;
    web.hidden = YES;
    [session handleMessage:@"stashTriggerHaptic" body:@{}];
    web.hidden = NO;
    UIView *parent = web.superview;
    [web removeFromSuperview];
    [session handleMessage:@"stashTriggerHaptic" body:@{}];
    [parent addSubview:web];
    BOOL suppressed = events.count == before;
    session.processing = YES;
    [session handleMessage:@"stashTriggerHaptic" body:@{}];
    return @{@"inactiveSuppressed":@(suppressed), @"processingFeedback":@(events.count == before + 1),
        @"processingUnchanged":@(session.processing), @"stillActive":@([session isActive])};
}

void StashEndHapticFixture(NSDictionary *fixture) {
    [fixture[@"recorder"] stop];
    [fixture[@"session"] cleanup];
    ((StashNative *)fixture[@"owner"]).session = nil;
}
