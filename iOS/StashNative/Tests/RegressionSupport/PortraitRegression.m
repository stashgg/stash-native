#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativePrivate.h"
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
@property (nonatomic, strong) UIViewController *readyPresenter;
@end
@implementation StashManualPortraitRestoration
- (UIViewController *)presenter { return self.readyPresenter ?: super.presenter; }
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
@interface StashPortraitCallbackProbe : NSObject <StashNativeDelegate>
@property (nonatomic, strong) StashNative *owner;
@property (nonatomic) NSUInteger dismissals;
@property (nonatomic) NSUInteger browserCloses;
@property (nonatomic) BOOL closedBeforeCallback;
@end
@implementation StashPortraitCallbackProbe
- (void)stashNativeDidDismissCard {
    self.dismissals++;
    self.closedBeforeCallback = !self.owner.isCurrentlyPresented;
}
- (void)stashNativeDidDismissBrowser {
    self.browserCloses++;
    self.closedBeforeCallback = !self.owner.isCurrentlyPresented;
}
@end

@interface StashPortraitBrowserProbe : UIViewController
@property (nonatomic, weak) id delegate;
@property (nonatomic, strong) UIPresentationController *probePresentation;
@end
@implementation StashPortraitBrowserProbe
- (UIPresentationController *)presentationController { return self.probePresentation; }
@end

NSDictionary *StashPortraitFinishProbe(void) {
    StashNative *owner = [StashNative new];
    StashCardSession *session = [StashCardSession new];
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
    StashNative *owner = [StashNative new];
    StashCardSession *session = [StashCardSession new];
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
        @"callbacksOnce":@(delegate.dismissals == 0 && delegate.browserCloses == 1)};
}

@interface StashNative (BrowserRegression)
- (void)openURL:(NSString *)url presenter:(UIViewController *)presenter config:(StashNativeCardConfig *)config browser:(BOOL)browser;
@end
@interface StashBrowserSnapshotCard : StashNative
@property (nonatomic, strong) NSMutableArray *orientations;
@property (nonatomic) BOOL allBrowsers;
@end
@implementation StashBrowserSnapshotCard
- (void)openURL:(NSString *)url presenter:(UIViewController *)presenter config:(StashNativeCardConfig *)config browser:(BOOL)browser {
    if (!NSThread.isMainThread) { [super openURL:url presenter:presenter config:config browser:browser]; return; }
    [self.orientations addObject:@(config.orientationPreference)];
    self.allBrowsers &= browser;
}
@end

void StashBrowserConfigurationProbe(void (^completion)(NSDictionary *)) {
    StashBrowserSnapshotCard *owner = [StashBrowserSnapshotCard new];
    owner.orientations = [NSMutableArray new]; owner.allBrowsers = YES;
    UIViewController *presenter = [UIViewController new];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        StashNativeBrowserConfig *config = [StashNativeBrowserConfig new];
        config.orientationPreference = StashNativeOrientationPreferencePortrait;
        [owner openBrowserWithURL:@"https://example.invalid" fromViewController:presenter config:config];
        config.orientationPreference = (StashNativeOrientationPreference)999;
        [owner openBrowserWithURL:@"https://example.invalid" fromViewController:presenter config:config];
        [owner openBrowserWithURL:@"https://example.invalid" fromViewController:presenter];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(@{@"orientations":owner.orientations, @"allBrowsers":@(owner.allBrowsers)});
        });
    });
}

@interface StashBrowserDeferredSession : StashCardSession
@property (nonatomic, copy) void (^preparation)(void);
@end
@implementation StashBrowserDeferredSession
- (void)preparePortraitWithCompletion:(void (^)(void))completion { self.preparation = completion; }
@end
@interface StashBrowserPresenterProbe : UIViewController
@property (nonatomic) NSUInteger presentations;
@end
@implementation StashBrowserPresenterProbe
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    self.presentations++;
    if (completion) completion();
}
@end

NSDictionary *StashBrowserPreparationProbe(void) {
    StashNative *owner = [StashNative new];
    StashPortraitCallbackProbe *delegate = [StashPortraitCallbackProbe new];
    owner.delegate = delegate; delegate.owner = owner;
    StashBrowserPresenterProbe *presenter = [StashBrowserPresenterProbe new];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 844, 390)];
    [window addSubview:presenter.view];
    StashBrowserDeferredSession *(^open)(void) = ^{
        StashBrowserDeferredSession *session = [StashBrowserDeferredSession new];
        session.owner = owner; owner.session = session; session.presenter = presenter;
        session.config = [StashNativeCardConfig new];
        session.config.orientationPreference = StashNativeOrientationPreferencePortrait;
        session.url = @"https://example.invalid";
        [session presentBrowser];
        return session;
    };
    BOOL cancellable = YES, noLateOpen = YES;
    for (NSString *action in @[@"close", @"dismiss", @"reset"]) {
        StashBrowserDeferredSession *session = open();
        cancellable &= session.browser != nil && session.preparation != nil && presenter.presentations == 0;
        void (^ready)(void) = session.preparation;
        session.preparation = nil;
        if ([action isEqualToString:@"close"]) [owner closeBrowser];
        else if ([action isEqualToString:@"dismiss"]) [owner dismiss];
        else [owner resetPresentationState];
        ready();
        noLateOpen &= !owner.isCurrentlyPresented && presenter.presentations == 0;
    }
    BOOL callbacks = delegate.browserCloses == 2 && delegate.dismissals == 0;
    StashBrowserDeferredSession *session = open();
    void (^ready)(void) = session.preparation; session.preparation = nil;
    [presenter.view removeFromSuperview];
    ready();
    // The open was accepted before preparation went asynchronous, so it still ends with the browser-closed event.
    BOOL detached = !owner.isCurrentlyPresented && presenter.presentations == 0 && delegate.browserCloses == 3;
    [window addSubview:presenter.view];
    session = open();
    ready = session.preparation; session.preparation = nil;
    ready();
    [session presentBrowser];
    BOOL once = presenter.presentations == 1 && owner.isCurrentlyPresented;
    [owner closeBrowser];
    session = open();
    ready = session.preparation; session.preparation = nil;
    StashManualPortraitRestoration *portrait = [[StashManualPortraitRestoration alloc] initWithPresenter:nil];
    portrait.readyPresenter = presenter; portrait.finished = YES;
    session.portraitPresentation = portrait;
    SFSafariViewController *nativeBrowser = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString:session.url]];
    ready();
    BOOL nativePortrait = session.browser.supportedInterfaceOrientations == UIInterfaceOrientationMaskPortrait &&
        session.browser.preferredInterfaceOrientationForPresentation == UIInterfaceOrientationPortrait &&
        session.browser.modalPresentationStyle == nativeBrowser.modalPresentationStyle &&
        session.browser.transitioningDelegate != nil && presenter.presentations == 2;
    [owner closeBrowser];
    return @{@"cancellableBeforeGeometry":@(cancellable), @"lateCompletionIgnored":@(noLateOpen),
        @"onlyBrowserCloseCallbacks":@(callbacks), @"detachedPresenterRejected":@(detached),
        @"presentedOnce":@(once), @"nativeSafariPortrait":@(nativePortrait)};
}
