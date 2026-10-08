#import "StashNativeCardPrivate.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSUInteger, StashPortraitPhase) {
    StashPortraitIdle, StashPortraitPreparing, StashPortraitReady,
    StashPortraitRestoring, StashPortraitFinished
};

@interface StashPortraitPresentation ()
@property (nonatomic, strong) UIWindow *sourceWindow;
@property (nonatomic, strong) UIWindow *previousKeyWindow;
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic) StashPortraitPhase phase;
@property (nonatomic) UIInterfaceOrientation previousOrientation;
@property (nonatomic) UIInterfaceOrientation targetOrientation;
@property (nonatomic, strong) NSTimer *transitionTimer;
@property (nonatomic) CFAbsoluteTime lastForegroundTick;
@property (nonatomic) NSTimeInterval foregroundWait;
@property (nonatomic) BOOL geometryRequested;
@property (nonatomic) NSUInteger legacyRetries;
@property (nonatomic, copy) void (^preparationCompletion)(BOOL);
@property (nonatomic, strong) NSMutableArray<void (^)(void)> *restorationCompletions;
- (void)geometryChanged;
@end

@interface StashPortraitWindow : UIWindow
@property (nonatomic, STASH_WEAK) StashPortraitPresentation *portraitPresentation;
@end
@implementation StashPortraitWindow
@end

@interface StashPortraitRootViewController : UIViewController
@property (nonatomic, STASH_WEAK) StashPortraitPresentation *portraitPresentation;
@end

static char StashAppOrientationHookKey;
static char StashSceneOrientationHookKey;
static char StashOriginalScenePolicyKey;

static UIInterfaceOrientation StashWindowOrientation(UIWindow *window) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (@available(iOS 16.0, *)) {
        // Scene geometry is authoritative from iOS 16 onward.
    } else {
        UIInterfaceOrientation orientation = window.rootViewController.interfaceOrientation;
        if (orientation != UIInterfaceOrientationUnknown) return orientation;
    }
#pragma clang diagnostic pop
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        if (window.windowScene) return window.windowScene.effectiveGeometry.interfaceOrientation;
    }
#endif
    if (window.windowScene) return window.windowScene.interfaceOrientation;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // Scene-less iOS 15 hosts still expose their orientation through the root controller.
    return window.rootViewController.interfaceOrientation;
#pragma clang diagnostic pop
}

static UIInterfaceOrientationMask StashPlistOrientations(UIWindow *window) {
    NSString *key = window.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad
        ? @"UISupportedInterfaceOrientations~ipad" : @"UISupportedInterfaceOrientations~iphone";
    id values = [NSBundle.mainBundle objectForInfoDictionaryKey:key]
        ?: [NSBundle.mainBundle objectForInfoDictionaryKey:@"UISupportedInterfaceOrientations"];
    UIInterfaceOrientationMask mask = 0;
    if ([values isKindOfClass:NSArray.class]) {
        NSDictionary *orientations = @{
            @"UIInterfaceOrientationPortrait": @(UIInterfaceOrientationMaskPortrait),
            @"UIInterfaceOrientationPortraitUpsideDown": @(UIInterfaceOrientationMaskPortraitUpsideDown),
            @"UIInterfaceOrientationLandscapeLeft": @(UIInterfaceOrientationMaskLandscapeLeft),
            @"UIInterfaceOrientationLandscapeRight": @(UIInterfaceOrientationMaskLandscapeRight)
        };
        for (id value in values) if ([value isKindOfClass:NSString.class]) mask |= [orientations[value] unsignedIntegerValue];
    }
    return mask ?: (window.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad
        ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown);
}

static StashPortraitPresentation *StashPresentationForWindow(UIWindow *window) {
    return [window isKindOfClass:StashPortraitWindow.class]
        ? ((StashPortraitWindow *)window).portraitPresentation : nil;
}

static UIInterfaceOrientationMask StashPresentationOrientations(StashPortraitPresentation *presentation) {
    return 1UL << presentation.targetOrientation;
}

static void StashReplaceOrientationMethod(Class cls, SEL selector, IMP replacement, const char *types) {
    // Give the concrete delegate its own method without changing an inherited implementation.
    if (!class_addMethod(cls, selector, replacement, types)) {
        method_setImplementation(class_getInstanceMethod(cls, selector), replacement);
    }
}

static void StashInstallAppOrientationHook(id delegate) {
    Class cls = object_getClass(delegate);
    if (!cls || objc_getAssociatedObject(cls, &StashAppOrientationHookKey)) return;
    SEL selector = @selector(application:supportedInterfaceOrientationsForWindow:);
    Method method = class_getInstanceMethod(cls, selector);
    IMP original = method ? method_getImplementation(method) : NULL;
    IMP replacement = imp_implementationWithBlock(^UIInterfaceOrientationMask(id object, UIApplication *app, UIWindow *window) {
        StashPortraitPresentation *presentation = StashPresentationForWindow(window);
        if (presentation) return StashPresentationOrientations(presentation);
        return original ? ((UIInterfaceOrientationMask (*)(id, SEL, UIApplication *, UIWindow *))original)(object, selector, app, window)
            : StashPlistOrientations(window);
    });
    StashReplaceOrientationMethod(cls, selector, replacement, method ? method_getTypeEncoding(method) : "Q@:@@");
    objc_setAssociatedObject(cls, &StashAppOrientationHookKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // UIKit caches which optional delegate callbacks exist.
    if (!method && UIApplication.sharedApplication.delegate == delegate)
        UIApplication.sharedApplication.delegate = delegate;
}

static void StashInstallSceneOrientationHook(UIWindowScene *scene) {
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
    if (@available(iOS 27.0, *)) {
        Class cls = object_getClass(scene.delegate);
        if (!cls || objc_getAssociatedObject(cls, &StashSceneOrientationHookKey)) return;
        SEL selector = @selector(supportedInterfaceOrientationsForWindowScene:);
        Method method = class_getInstanceMethod(cls, selector);
        IMP original = method ? method_getImplementation(method) : NULL;
        IMP replacement = imp_implementationWithBlock(^UIInterfaceOrientationMask(id object, UIWindowScene *target) {
            UIInterfaceOrientationMask mask = original
                ? ((UIInterfaceOrientationMask (*)(id, SEL, UIWindowScene *))original)(object, selector, target)
                : StashPlistOrientations(target.windows.firstObject);
            if (!objc_getAssociatedObject(target, &StashOriginalScenePolicyKey)) {
                for (UIWindow *window in target.windows) {
                    StashPortraitPresentation *presentation = StashPresentationForWindow(window);
                    if (presentation) mask |= StashPresentationOrientations(presentation);
                }
            }
            return mask;
        });
        StashReplaceOrientationMethod(cls, selector, replacement, method ? method_getTypeEncoding(method) : "Q@:@");
        objc_setAssociatedObject(cls, &StashSceneOrientationHookKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!method) scene.delegate = scene.delegate;
    }
#endif
}

void StashInstallPortraitOrientationHooks(id applicationDelegate, UIWindowScene *scene) {
    StashInstallAppOrientationHook(applicationDelegate);
    StashInstallSceneOrientationHook(scene);
}

static UIInterfaceOrientationMask StashHostOrientations(UIWindow *window) {
    UIInterfaceOrientationMask mask = [UIApplication.sharedApplication supportedInterfaceOrientationsForWindow:window];
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
    if (@available(iOS 27.0, *)) {
        UIWindowScene *scene = window.windowScene;
        if ([scene.delegate respondsToSelector:@selector(supportedInterfaceOrientationsForWindowScene:)]) {
            objc_setAssociatedObject(scene, &StashOriginalScenePolicyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            @try { mask = [(id<UIWindowSceneDelegate>)scene.delegate supportedInterfaceOrientationsForWindowScene:scene]; }
            @finally { objc_setAssociatedObject(scene, &StashOriginalScenePolicyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        }
    }
#endif
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController &&
           (controller.presentedViewController.modalPresentationStyle == UIModalPresentationFullScreen ||
            controller.presentedViewController.modalPresentationStyle == UIModalPresentationOverFullScreen)) {
        controller = controller.presentedViewController;
    }
    return mask & controller.supportedInterfaceOrientations;
}

@implementation StashPortraitRootViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.accessibilityViewIsModal = YES;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.portraitPresentation ? StashPresentationOrientations(self.portraitPresentation) : UIInterfaceOrientationMaskAllButUpsideDown;
}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return self.portraitPresentation ? self.portraitPresentation.targetOrientation : UIInterfaceOrientationPortrait;
}
- (BOOL)shouldAutorotate { return YES; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.portraitPresentation geometryChanged];
}
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self.portraitPresentation geometryChanged]; });
    }];
}
@end

@implementation StashPortraitPresentation
- (instancetype)initWithPresenter:(UIViewController *)presenter {
    self = [super init];
    if (self) {
        self.sourceWindow = presenter.viewIfLoaded.window;
        self.restorationCompletions = [NSMutableArray array];
        self.targetOrientation = UIInterfaceOrientationPortrait;
    }
    return self;
}
- (UIViewController *)presenter { return self.phase == StashPortraitReady ? self.window.rootViewController : nil; }
- (NSArray<UIWindow *> *)sceneWindows {
    if (self.sourceWindow.windowScene) return self.sourceWindow.windowScene.windows;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.windows;
#pragma clang diagnostic pop
}
- (BOOL)isForeground {
    UIWindowScene *scene = self.sourceWindow.windowScene;
    return scene ? scene.activationState == UISceneActivationStateForegroundActive
        : UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}
- (void)prepareWithCompletion:(void (^)(BOOL))completion {
    if (self.phase != StashPortraitIdle) { if (completion) completion(self.phase == StashPortraitReady); return; }
    self.preparationCompletion = completion;
    self.phase = StashPortraitPreparing;
    for (UIWindow *window in [self sceneWindows]) {
        StashPortraitPresentation *previous = StashPresentationForWindow(window);
        if (!previous) continue;
        // Reset can release the session before its UIKit dismissal has completed.
        [previous whenRestored:^{ if (self.phase == StashPortraitPreparing) [self createWindow]; }];
        return;
    }
    [self createWindow];
}
- (void)createWindow {
    if (!self.sourceWindow || self.sourceWindow.hidden ||
        self.sourceWindow.traitCollection.userInterfaceIdiom != UIUserInterfaceIdiomPhone) {
        [self restoreWithCompletion:nil];
        return;
    }
    self.previousOrientation = StashWindowOrientation(self.sourceWindow);
    if (self.previousOrientation == UIInterfaceOrientationUnknown) {
        self.previousOrientation = self.sourceWindow.bounds.size.width > self.sourceWindow.bounds.size.height
            ? UIInterfaceOrientationLandscapeLeft : UIInterfaceOrientationPortrait;
    }
    for (UIWindow *window in [self sceneWindows]) if (window.isKeyWindow) { self.previousKeyWindow = window; break; }
    if (!self.previousKeyWindow) self.previousKeyWindow = self.sourceWindow;
    [self.sourceWindow endEditing:YES];
    StashInstallPortraitOrientationHooks(UIApplication.sharedApplication.delegate, self.sourceWindow.windowScene);
    StashPortraitWindow *window = self.sourceWindow.windowScene
        ? [[StashPortraitWindow alloc] initWithWindowScene:self.sourceWindow.windowScene]
        : [[StashPortraitWindow alloc] initWithFrame:self.sourceWindow.bounds];
    StashPortraitRootViewController *root = [[StashPortraitRootViewController alloc] init];
    self.window = window;
    window.portraitPresentation = self;
    root.portraitPresentation = self;
    window.windowLevel = self.sourceWindow.windowLevel + 1;
    window.backgroundColor = UIColor.clearColor;
    window.rootViewController = root;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(activityChanged:)
        name:UISceneDidActivateNotification object:self.sourceWindow.windowScene];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sceneDisconnected:)
        name:UISceneDidDisconnectNotification object:self.sourceWindow.windowScene];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(activityChanged:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [window makeKeyAndVisible];
    [self beginGeometryTransition];
#if !__has_feature(objc_arc)
    [root release]; [window release];
#endif
}
- (void)beginGeometryTransition {
    [self.transitionTimer invalidate];
    self.foregroundWait = 0;
    self.lastForegroundTick = 0;
    self.geometryRequested = NO;
    self.legacyRetries = 0;
    self.transitionTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self
        selector:@selector(transitionTick:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.transitionTimer forMode:NSRunLoopCommonModes];
    [self requestOrientation];
}
- (void)requestOrientation {
    if (![self isForeground] || !self.window.isKeyWindow || self.geometryRequested) return;
    self.geometryRequested = YES;
    StashPortraitPhase phase = self.phase;
    if (@available(iOS 16.0, *)) {
        [self.window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
        if (self.phase != phase) return;
        UIWindowScene *scene = self.window.windowScene;
        if (scene) {
            UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc]
                initWithInterfaceOrientations:StashPresentationOrientations(self)];
            [scene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
                if (self.phase != phase) return;
                if (phase == StashPortraitPreparing) [self restoreWithCompletion:nil];
            }];
#if !__has_feature(objc_arc)
            [preferences release];
#endif
        } else {
            [UIViewController attemptRotationToDeviceOrientation];
        }
    } else {
        // iOS 15 has no scene geometry request. Keep the legacy rotation fallback confined here.
        @try { [UIDevice.currentDevice setValue:@(self.targetOrientation) forKey:@"orientation"]; }
        @catch (NSException *exception) { /* The native presenter still declares its preferred orientation. */ }
        [UIViewController attemptRotationToDeviceOrientation];
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self geometryChanged]; });
}
- (BOOL)geometryIsSettled {
    if (!self.window || self.window.rootViewController.transitionCoordinator) return NO;
    CGSize size = self.window.bounds.size;
    BOOL portrait = UIInterfaceOrientationIsPortrait(self.targetOrientation);
    return StashWindowOrientation(self.window) == self.targetOrientation && size.width > 0 && size.height > 0 &&
        (portrait ? size.height >= size.width : size.width > size.height);
}
- (void)geometryChanged {
    if (!self.transitionTimer || (self.phase != StashPortraitPreparing && self.phase != StashPortraitRestoring) ||
        ![self geometryIsSettled]) return;
    if (self.phase == StashPortraitPreparing) {
        self.phase = StashPortraitReady;
        [self.transitionTimer invalidate]; self.transitionTimer = nil;
        [self completePreparation:YES];
    } else [self completeRestoration];
}
- (void)transitionTick:(NSTimer *)timer {
    [self geometryChanged];
    if (timer != self.transitionTimer) return;
    if (![self isForeground]) { self.lastForegroundTick = 0; self.geometryRequested = NO; return; }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (self.lastForegroundTick) self.foregroundWait += now - self.lastForegroundTick;
    self.lastForegroundTick = now;
    if (@available(iOS 16.0, *)) {
        // Scene geometry requests complete independently of the physical device orientation.
    } else if (self.geometryRequested && self.legacyRetries < 2 &&
               self.foregroundWait >= (self.legacyRetries == 0 ? 0.25 : 0.85)) {
        // iOS 15 can ignore the first request while the new key window attaches.
        self.legacyRetries++;
        self.geometryRequested = NO;
    }
    [self requestOrientation];
    if (self.foregroundWait < 4) return;
    if (self.phase == StashPortraitPreparing) [self restoreWithCompletion:nil];
    else [self completeRestoration];
}
- (void)activityChanged:(NSNotification *)note {
    if (self.phase == StashPortraitPreparing || self.phase == StashPortraitRestoring) {
        self.lastForegroundTick = 0;
        self.geometryRequested = NO;
        [self requestOrientation];
    }
}
- (void)sceneDisconnected:(NSNotification *)note { [self completeRestoration]; }
- (void)completePreparation:(BOOL)ready {
    void (^completion)(BOOL) = self.preparationCompletion;
#if !__has_feature(objc_arc)
    completion = [completion copy];
#endif
    self.preparationCompletion = nil;
    if (completion) completion(ready);
#if !__has_feature(objc_arc)
    [completion release];
#endif
}
- (void)whenRestored:(void (^)(void))completion {
    if (self.phase == StashPortraitFinished) { if (completion) completion(); return; }
    if (completion) {
        id copied = [completion copy];
        [self.restorationCompletions addObject:copied];
#if !__has_feature(objc_arc)
        [copied release];
#endif
    }
}
- (void)restoreWithCompletion:(void (^)(void))completion {
    [self whenRestored:completion];
    if (self.phase == StashPortraitFinished) return;
    if (self.phase == StashPortraitRestoring) return;
    self.phase = StashPortraitRestoring;
    if (!self.window || !self.window.isKeyWindow) { [self completeRestoration]; return; }
    UIInterfaceOrientationMask allowed = StashHostOrientations(self.sourceWindow);
    UIInterfaceOrientation target = self.previousOrientation;
    if (!(allowed & (1UL << target))) {
        for (NSNumber *orientation in @[@(UIInterfaceOrientationPortrait), @(UIInterfaceOrientationLandscapeLeft),
                                        @(UIInterfaceOrientationLandscapeRight), @(UIInterfaceOrientationPortraitUpsideDown)]) {
            if (allowed & (1UL << orientation.integerValue)) { target = orientation.integerValue; break; }
        }
    }
    self.targetOrientation = target;
    [self beginGeometryTransition];
}
- (void)completeRestoration {
    if (self.phase == StashPortraitFinished) return;
#if !__has_feature(objc_arc)
    [[self retain] autorelease];
#endif
    self.phase = StashPortraitFinished;
    [self.transitionTimer invalidate]; self.transitionTimer = nil;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    BOOL restoreKey = self.window.isKeyWindow;
    self.window.hidden = YES;
    ((StashPortraitWindow *)self.window).portraitPresentation = nil;
    ((StashPortraitRootViewController *)self.window.rootViewController).portraitPresentation = nil;
    self.window.rootViewController = nil;
    self.window = nil;
    UIWindow *previous = self.previousKeyWindow;
    if (restoreKey && !previous.hidden && previous.windowScene == self.sourceWindow.windowScene) [previous makeKeyWindow];
    self.previousKeyWindow = nil;
    self.sourceWindow = nil;
    NSArray *completions = [self.restorationCompletions copy];
    [self.restorationCompletions removeAllObjects];
    [self completePreparation:NO];
    for (void (^completion)(void) in completions) completion();
#if !__has_feature(objc_arc)
    [completions release];
#endif
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
#if !__has_feature(objc_arc)
    [_sourceWindow release]; [_previousKeyWindow release]; [_window release];
    [_transitionTimer release]; [_preparationCompletion release]; [_restorationCompletions release];
    [super dealloc];
#endif
}
@end
