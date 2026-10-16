#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativeCardPrivate.h"

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
        StashCheckoutSession *session = [StashCheckoutSession new];
        session.config = [StashNativeCardConfig new];
        UIViewController *presenter = [UIViewController new];
        StashPresentationProbeView *view = [[StashPresentationProbeView alloc] initWithFrame:
            CGRectMake(0, 0, [input[@"width"] doubleValue], [input[@"height"] doubleValue])];
        view.verticalClass = [input[@"compact"] boolValue] ? UIUserInterfaceSizeClassCompact : UIUserInterfaceSizeClassRegular;
        presenter.view = view; session.presenter = presenter;
        StashCheckoutViewController *controller = [StashCheckoutViewController new];
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
        StashNativeCard *owner = [StashNativeCard new];
        StashCheckoutSession *session = [StashCheckoutSession new];
        owner.session = session; session.owner = owner; session.config = [StashNativeCardConfig new];
        session.url = @"about:blank";
        StashOccupiedPresentationHost *presenter = [StashOccupiedPresentationHost new];
        UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 700)];
        window.rootViewController = presenter; [window addSubview:presenter.view]; session.presenter = presenter;
        StashCheckoutSession *replacement = nil;
        if ([name isEqualToString:@"closed"]) session.closing = YES;
        if ([name isEqualToString:@"replacement"]) {
            replacement = [StashCheckoutSession new]; replacement.owner = owner; owner.session = replacement;
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
