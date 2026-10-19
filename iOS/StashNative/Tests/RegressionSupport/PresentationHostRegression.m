#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativePrivate.h"

@interface StashPresentationProbeView : UIView
@property (nonatomic) UIUserInterfaceSizeClass verticalClass;
@end
@implementation StashPresentationProbeView
- (UITraitCollection *)traitCollection {
    return [UITraitCollection traitCollectionWithVerticalSizeClass:self.verticalClass];
}
@end

NSDictionary *StashNativePresentationProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSDictionary *input in @[
        @{@"name":@"compactPhone", @"width":@390, @"height":@700},
        @{@"name":@"wideTablet", @"width":@1000, @"height":@1200},
        @{@"name":@"narrowPane", @"width":@320, @"height":@900},
        @{@"name":@"compactHeight", @"width":@700, @"height":@320, @"compact":@YES}]) {
        StashCardSession *session = [StashCardSession new];
        session.config = [StashNativeCardConfig new];
        UIViewController *presenter = [UIViewController new];
        StashPresentationProbeView *view = [[StashPresentationProbeView alloc] initWithFrame:
            CGRectMake(0, 0, [input[@"width"] doubleValue], [input[@"height"] doubleValue])];
        view.verticalClass = [input[@"compact"] boolValue] ? UIUserInterfaceSizeClassCompact : UIUserInterfaceSizeClassRegular;
        presenter.view = view; session.presenter = presenter;
        StashCardViewController *controller = [StashCardViewController new];
        session.controller = controller; controller.session = session; [controller configurePresentation];
        UISheetPresentationController *sheet = controller.sheetPresentationController;
        BOOL native = sheet && sheet.delegate == session &&
            controller.modalPresentationStyle == UIModalPresentationFormSheet && !controller.transitioningDelegate;
        BOOL selected = [sheet.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:NO]];
        BOOL stops = sheet.detents.count >= 1;
        if (@available(iOS 16.0, *)) {
            stops &= [[controller nativeDetentIdentifierForExpanded:NO] isEqualToString:@"stash-resting"] &&
                [[controller nativeDetentIdentifierForExpanded:YES] isEqualToString:@"stash-expanded"];
        } else {
            BOOL compact = [input[@"compact"] boolValue];
            stops &= sheet.detents.count == (compact ? 1 : 2) &&
                [[controller nativeDetentIdentifierForExpanded:YES] isEqualToString:UISheetPresentationControllerDetentIdentifierLarge] &&
                [[controller nativeDetentIdentifierForExpanded:NO] isEqualToString:compact
                    ? UISheetPresentationControllerDetentIdentifierLarge : UISheetPresentationControllerDetentIdentifierMedium];
        }
        session.processing = YES; [controller updateDismissalPolicy];
        BOOL locked = controller.modalInPresentation && !sheet.prefersGrabberVisible;
        session.processing = NO; [controller updateDismissalPolicy];
        BOOL restored = !controller.modalInPresentation && sheet.prefersGrabberVisible;
        result[input[@"name"]] = @(native && selected && stops && locked && restored);
        [session cleanup];
    }
    return result;
}

@interface StashOccupiedPresentationHost : UIViewController
@property (nonatomic, strong) UIViewController *otherPresentation;
@property (nonatomic) BOOL dismissing;
@end
@implementation StashOccupiedPresentationHost
- (UIViewController *)presentedViewController { return self.otherPresentation; }
- (BOOL)isBeingDismissed { return self.dismissing; }
@end

NSDictionary *StashPresentationLifetimeProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *name in @[@"closed", @"replacement", @"detached", @"occupied", @"dismissing"]) {
        StashNative *owner = [StashNative new];
        StashCardSession *session = [StashCardSession new];
        owner.session = session; session.owner = owner; session.config = [StashNativeCardConfig new];
        session.url = @"about:blank";
        StashOccupiedPresentationHost *presenter = [StashOccupiedPresentationHost new];
        UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 700)];
        window.rootViewController = presenter; [window addSubview:presenter.view]; session.presenter = presenter;
        StashCardSession *replacement = nil;
        if ([name isEqualToString:@"closed"]) session.closing = YES;
        if ([name isEqualToString:@"replacement"]) {
            replacement = [StashCardSession new]; replacement.owner = owner; owner.session = replacement;
        }
        if ([name isEqualToString:@"detached"]) [presenter.view removeFromSuperview];
        if ([name isEqualToString:@"occupied"]) presenter.otherPresentation = [UIViewController new];
        if ([name isEqualToString:@"dismissing"]) presenter.dismissing = YES;
        UIViewController *other = presenter.otherPresentation;
        [session presentCheckout];
        BOOL untouched = !session.webView && !session.controller && presenter.otherPresentation == other;
        if (replacement) untouched &= owner.session == replacement;
        if ([name isEqualToString:@"detached"] || [name isEqualToString:@"occupied"] || [name isEqualToString:@"dismissing"])
            untouched &= owner.session == nil;
        result[name] = @(untouched);
        [session cleanup]; [owner resetPresentationState]; window.hidden = YES;
    }
    return result;
}

@interface StashHostDismissalReceiver : NSObject <StashNativeDelegate>
@property (nonatomic, strong) NSMutableArray<NSString *> *events;
@end
@implementation StashHostDismissalReceiver
- (instancetype)init {
    if ((self = [super init])) _events = [NSMutableArray new];
    return self;
}
- (void)stashNativeDidDismissCard { [self.events addObject:@"card-dismissed"]; }
- (void)stashNativeDidDismissBrowser { [self.events addObject:@"browser-dismissed"]; }
- (void)stashNativeDidEncounterNetworkError { [self.events addObject:@"network-error"]; }
@end

static void StashAwaitHostCondition(BOOL (^condition)(void), CFAbsoluteTime deadline, void (^completion)(BOOL)) {
    if (condition() || CFAbsoluteTimeGetCurrent() >= deadline) { completion(condition()); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        StashAwaitHostCondition(condition, deadline, completion);
    });
}

void StashHostDismissalProbe(NSString *mode, void (^completion)(NSDictionary *)) {
    UIWindow *previous = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) previous = window;
    UIWindow *window = previous.windowScene ? [[UIWindow alloc] initWithWindowScene:previous.windowScene] :
        [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    UIViewController *root = [UIViewController new];
    window.rootViewController = root; [window makeKeyAndVisible];
    UIViewController *modal = [UIViewController new];
    modal.modalPresentationStyle = UIModalPresentationFullScreen;
    StashNative *owner = [StashNative new];
    StashHostDismissalReceiver *receiver = [StashHostDismissalReceiver new];
    owner.delegate = receiver;
    BOOL browser = [mode isEqualToString:@"browser"];
    void (^finish)(NSDictionary *) = ^(NSDictionary *result) {
        [owner resetPresentationState];
        window.hidden = YES; [previous makeKeyWindow];
        completion(result);
    };
    [root presentViewController:modal animated:NO completion:^{
        if (browser) [owner openBrowserWithURL:@"https://example.invalid" fromViewController:modal];
        else [owner openCardWithURL:@"https://example.invalid" fromViewController:modal config:nil];
        StashCardSession *session = owner.session;
        // A failed load would end the session before the host acts.
        [session.webView stopLoading];
        UIViewController *surface = browser ? session.browser : session.controller;
        StashAwaitHostCondition(^BOOL { return surface.presentingViewController == modal && !surface.isBeingPresented; },
            CFAbsoluteTimeGetCurrent() + 5, ^(BOOL presented) {
            if (!presented) { finish(@{@"presented":@NO}); return; }
            if ([mode isEqualToString:@"covered"]) {
                // A full-screen cover hides the card without dismissing it.
                UIViewController *cover = [UIViewController new];
                cover.modalPresentationStyle = UIModalPresentationFullScreen;
                [surface presentViewController:cover animated:NO completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                        [surface dismissViewControllerAnimated:NO completion:^{
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                                finish(@{@"presented":@YES, @"silent":@(receiver.events.count == 0),
                                    @"survived":@(owner.session == session && session.controller == surface && [session isActive])});
                            });
                        }];
                    });
                }];
                return;
            }
            UIViewController *dismisser = [mode isEqualToString:@"card"] ? modal : root;
            [dismisser dismissViewControllerAnimated:YES completion:nil];
            StashAwaitHostCondition(^BOOL { return receiver.events.count > 0; }, CFAbsoluteTimeGetCurrent() + 5, ^(BOOL ended) {
                NSArray *expected = @[browser ? @"browser-dismissed" : @"card-dismissed"];
                BOOL closed = !owner.isCurrentlyPresented && !session.controller && !session.browser;
                // Open from the visible controller; a full-screen modal takes the root's view out of the window.
                [owner openCardWithURL:@"https://example.invalid" fromViewController:root.presentedViewController ?: root
                    config:nil];
                [owner.session.webView stopLoading];
                finish(@{@"presented":@YES, @"ended":@([receiver.events isEqualToArray:expected]), @"closed":@(closed),
                    @"reopened":@(owner.isCurrentlyPresented && owner.session != session)});
            });
        });
    }];
}
