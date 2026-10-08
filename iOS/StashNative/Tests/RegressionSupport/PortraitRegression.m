#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativeCardPrivate.h"
#import <objc/runtime.h>

@interface StashOrientationDelegateBase : NSObject
@property (nonatomic) NSUInteger calls;
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window;
- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindowScene:(UIWindowScene *)scene;
@end
@implementation StashOrientationDelegateBase
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    self.calls++;
    return UIInterfaceOrientationMaskLandscape;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindowScene:(UIWindowScene *)scene {
    self.calls++;
    return UIInterfaceOrientationMaskLandscape;
}
@end
@interface StashOrientationDelegateChild : StashOrientationDelegateBase
@end
@implementation StashOrientationDelegateChild
@end
@interface StashOrientationMissingDelegate : NSObject
@end
@implementation StashOrientationMissingDelegate
@end

@interface StashOrientationSceneProbe : NSObject
@property (nonatomic, strong) id delegate;
@property (nonatomic, strong) NSArray<UIWindow *> *windows;
@end
@implementation StashOrientationSceneProbe
@end

static char StashPortraitTestKeyWindow;
static UIWindow *StashPortraitTestWindow(void) {
    Class cls = NSClassFromString(@"StashPortraitKeyWindowProbe");
    if (!cls) {
        cls = objc_allocateClassPair(NSClassFromString(@"StashPortraitWindow"), "StashPortraitKeyWindowProbe", 0);
        class_addMethod(cls, @selector(isKeyWindow), imp_implementationWithBlock(^BOOL(id window) {
            return [objc_getAssociatedObject(window, &StashPortraitTestKeyWindow) boolValue];
        }), "B@:");
        objc_registerClassPair(cls);
    }
    return [[cls alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
}

NSDictionary *StashPortraitHooksProbe(void) {
    SEL appSelector = @selector(application:supportedInterfaceOrientationsForWindow:);
    SEL sceneSelector = @selector(supportedInterfaceOrientationsForWindowScene:);
    IMP baseApp = class_getMethodImplementation(StashOrientationDelegateBase.class, appSelector);
    IMP baseScene = class_getMethodImplementation(StashOrientationDelegateBase.class, sceneSelector);
    StashOrientationDelegateChild *delegate = [StashOrientationDelegateChild new];
    StashOrientationSceneProbe *scene = [StashOrientationSceneProbe new];
    scene.delegate = delegate;
    UIWindow *host = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 844, 390)];
    UIWindow *checkout = StashPortraitTestWindow();
    StashPortraitPresentation *presentation = [[StashPortraitPresentation alloc] initWithPresenter:nil];
    [checkout setValue:presentation forKey:@"portraitPresentation"];
    scene.windows = @[host, checkout];
    StashInstallPortraitOrientationHooks(delegate, (UIWindowScene *)scene);
    IMP installed = class_getMethodImplementation(delegate.class, appSelector);
    StashInstallPortraitOrientationHooks(delegate, (UIWindowScene *)scene);
    BOOL once = installed == class_getMethodImplementation(delegate.class, appSelector);
    NSUInteger calls = delegate.calls;
    BOOL scoped = [delegate application:nil supportedInterfaceOrientationsForWindow:checkout] == UIInterfaceOrientationMaskPortrait &&
        [delegate application:nil supportedInterfaceOrientationsForWindow:host] == UIInterfaceOrientationMaskLandscape &&
        delegate.calls == calls + 1;
    BOOL parentUnchanged = baseApp == class_getMethodImplementation(StashOrientationDelegateBase.class, appSelector) &&
        baseScene == class_getMethodImplementation(StashOrientationDelegateBase.class, sceneSelector);
    BOOL scenesScoped = YES, keySceneScoped = YES;
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
    if (@available(iOS 27.0, *)) {
        StashOrientationSceneProbe *other = [StashOrientationSceneProbe new];
        other.delegate = [StashOrientationDelegateChild new]; other.windows = @[host];
        scenesScoped = [delegate supportedInterfaceOrientationsForWindowScene:(UIWindowScene *)scene] ==
            (UIInterfaceOrientationMaskLandscape | UIInterfaceOrientationMaskPortrait) &&
            [other.delegate supportedInterfaceOrientationsForWindowScene:(UIWindowScene *)other] == UIInterfaceOrientationMaskLandscape;
        objc_setAssociatedObject(checkout, &StashPortraitTestKeyWindow, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        keySceneScoped = [delegate supportedInterfaceOrientationsForWindowScene:(UIWindowScene *)scene] ==
            (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskLandscape) &&
            [other.delegate supportedInterfaceOrientationsForWindowScene:(UIWindowScene *)other] == UIInterfaceOrientationMaskLandscape;
        objc_setAssociatedObject(checkout, &StashPortraitTestKeyWindow, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
#endif
    [checkout setValue:nil forKey:@"portraitPresentation"];
    BOOL restored = [delegate application:nil supportedInterfaceOrientationsForWindow:checkout] == UIInterfaceOrientationMaskLandscape &&
        [delegate supportedInterfaceOrientationsForWindowScene:(UIWindowScene *)scene] == UIInterfaceOrientationMaskLandscape;
    StashOrientationMissingDelegate *missing = [StashOrientationMissingDelegate new];
    StashOrientationSceneProbe *missingScene = [StashOrientationSceneProbe new];
    missingScene.delegate = missing; missingScene.windows = @[checkout];
    StashInstallPortraitOrientationHooks(missing, (UIWindowScene *)missingScene);
    [checkout setValue:presentation forKey:@"portraitPresentation"];
    BOOL handlesMissing = [(id<UIApplicationDelegate>)missing application:UIApplication.sharedApplication supportedInterfaceOrientationsForWindow:checkout] == UIInterfaceOrientationMaskPortrait;
    [checkout setValue:nil forKey:@"portraitPresentation"];
    handlesMissing &= [(id<UIApplicationDelegate>)missing application:UIApplication.sharedApplication supportedInterfaceOrientationsForWindow:host] != 0;
    return @{@"windowScoped":@(scoped), @"sceneScoped":@(scenesScoped), @"parentUnchanged":@(parentUnchanged),
        @"installedOnce":@(once), @"originalsRestored":@(restored), @"missingCallbacks":@(handlesMissing),
        @"keySceneScoped":@(keySceneScoped)};
}

@interface StashDeferredPortrait : StashPortraitPresentation
@property (nonatomic, strong) NSArray<UIWindow *> *probeWindows;
@property (nonatomic) NSUInteger creations;
@end
@implementation StashDeferredPortrait
- (NSArray<UIWindow *> *)sceneWindows { return self.probeWindows ?: @[]; }
- (void)createWindow { self.creations++; /* Leave geometry pending to exercise cancellation. */ }
@end

@interface StashPortraitPresentation (ActivityRegression)
- (void)activityChanged:(NSNotification *)notification;
@end

NSDictionary *StashPortraitCancellationProbe(void) {
    StashDeferredPortrait *presentation = [[StashDeferredPortrait alloc] initWithPresenter:nil];
    __block NSUInteger preparations = 0, restorations = 0;
    __block BOOL failed = NO;
    [presentation prepareWithCompletion:^(BOOL ready) { preparations++; failed = !ready; }];
    BOOL pending = preparations == 0 && !presentation.presenter;
    [presentation setValue:@1 forKey:@"lastForegroundTick"];
    [presentation setValue:@0.25 forKey:@"foregroundWait"];
    [presentation activityChanged:nil];
    BOOL foregroundClock = [[presentation valueForKey:@"lastForegroundTick"] doubleValue] == 0 &&
        [[presentation valueForKey:@"foregroundWait"] doubleValue] == 0.25;
    [presentation restoreWithCompletion:^{ restorations++; }];
    [presentation restoreWithCompletion:^{ restorations++; }];
    UIWindow *window = StashPortraitTestWindow();
    StashPortraitPresentation *previous = [[StashPortraitPresentation alloc] initWithPresenter:nil];
    [window setValue:previous forKey:@"portraitPresentation"];
    StashDeferredPortrait *next = [[StashDeferredPortrait alloc] initWithPresenter:nil];
    next.probeWindows = @[window];
    [next prepareWithCompletion:nil];
    BOOL queued = next.creations == 0;
    [previous restoreWithCompletion:nil];
    queued &= next.creations == 1;
    [next restoreWithCompletion:nil];
    previous = [[StashPortraitPresentation alloc] initWithPresenter:nil];
    [window setValue:previous forKey:@"portraitPresentation"];
    next = [[StashDeferredPortrait alloc] initWithPresenter:nil]; next.probeWindows = @[window];
    [next prepareWithCompletion:nil]; [next restoreWithCompletion:nil];
    [previous restoreWithCompletion:nil];
    BOOL cancelledQueue = next.creations == 0;
    [window setValue:nil forKey:@"portraitPresentation"];
    return @{@"pending":@(pending), @"cancelledOnce":@(preparations == 1 && failed),
        @"restorationCompletions":@(restorations == 2), @"noPresenterAfterCancellation":@(!presentation.presenter),
        @"queuedUntilRestored":@(queued), @"cancelledQueueDoesNotOpen":@(cancelledQueue),
        @"foregroundClockExcludesSuspension":@(foregroundClock)};
}

@interface StashManualPortraitRestoration : StashPortraitPresentation
@property (nonatomic, copy) void (^pendingCompletion)(void);
@property (nonatomic) BOOL finished;
@end
@implementation StashManualPortraitRestoration
- (void)restoreWithCompletion:(void (^)(void))completion {
    if (self.finished) { if (completion) completion(); }
    else self.pendingCompletion = completion;
}
- (void)finishRestoring {
    self.finished = YES;
    void (^completion)(void) = self.pendingCompletion;
    self.pendingCompletion = nil;
    if (completion) completion();
}
@end
@interface StashPortraitCallbackProbe : NSObject <StashNativeCardDelegate>
@property (nonatomic, strong) StashNativeCard *owner;
@property (nonatomic) NSUInteger dismissals;
@property (nonatomic) NSUInteger browserCloses;
@property (nonatomic) BOOL closedBeforeCallback;
@end
@implementation StashPortraitCallbackProbe
- (void)stashNativeCardDidDismiss {
    self.dismissals++;
    self.closedBeforeCallback = !self.owner.isCurrentlyPresented;
}
- (void)stashNativeCardDidCloseBrowser { self.browserCloses++; }
@end

@interface StashPortraitBrowserProbe : UIViewController
@property (nonatomic, weak) id delegate;
@property (nonatomic, strong) UIPresentationController *probePresentation;
@end
@implementation StashPortraitBrowserProbe
- (UIPresentationController *)presentationController { return self.probePresentation; }
@end

NSDictionary *StashPortraitFinishProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new];
    StashManualPortraitRestoration *portrait = [[StashManualPortraitRestoration alloc] initWithPresenter:nil];
    StashPortraitCallbackProbe *delegate = [StashPortraitCallbackProbe new];
    owner.delegate = delegate; delegate.owner = owner;
    session.owner = owner; owner.session = session;
    session.config = [StashNativeCardConfig new]; session.portraitPresentation = portrait;
    [owner dismiss]; [owner dismiss];
    BOOL waits = owner.isCurrentlyPresented && delegate.dismissals == 0;
    [portrait finishRestoring];
    BOOL finished = !owner.isCurrentlyPresented && delegate.dismissals == 1 && delegate.closedBeforeCallback;
    [portrait finishRestoring];
    return @{@"waitsForRestoration":@(waits), @"finishedBeforeCallback":@(finished),
        @"callbackOnce":@(delegate.dismissals == 1)};
}

NSDictionary *StashPortraitBrowserDismissProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new];
    StashManualPortraitRestoration *portrait = [[StashManualPortraitRestoration alloc] initWithPresenter:nil];
    StashPortraitCallbackProbe *delegate = [StashPortraitCallbackProbe new];
    StashPortraitBrowserProbe *browser = [StashPortraitBrowserProbe new];
    browser.probePresentation = [[UIPresentationController alloc] initWithPresentedViewController:browser presentingViewController:nil];
    owner.delegate = delegate; delegate.owner = owner;
    session.owner = owner; owner.session = session; session.config = [StashNativeCardConfig new];
    session.portraitPresentation = portrait; session.browser = (SFSafariViewController *)browser;
    [session presentationControllerDidDismiss:browser.presentationController];
    BOOL waits = owner.isCurrentlyPresented && delegate.dismissals == 0 && delegate.browserCloses == 0;
    [portrait finishRestoring];
    [session presentationControllerDidDismiss:browser.presentationController];
    BOOL finished = !owner.isCurrentlyPresented && delegate.closedBeforeCallback;
    browser.probePresentation = nil;
    return @{@"waitsForRestoration":@(waits), @"finishedBeforeCallback":@(finished),
        @"callbacksOnce":@(delegate.dismissals == 1 && delegate.browserCloses == 1)};
}
