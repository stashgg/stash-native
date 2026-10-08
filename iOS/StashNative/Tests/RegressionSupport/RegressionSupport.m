#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativeCardPrivate.h"
#import <math.h>

NSDictionary *StashGeometryProbe(double width, double height, BOOL expanded, double measured,
                                double preferredWidth, double preferredHeight, double maximumHeight, double margin) {
    StashNativeCardConfig *config = [StashNativeCardConfig new];
    config.preferredContentWidth = preferredWidth;
    config.preferredContentHeight = preferredHeight;
    config.maximumContentHeight = maximumHeight;
    config.edgeMargin = margin;
    config = StashNormalizedConfig(config);
    StashPresentationGeometry result = StashResolveGeometry(CGRectMake(11, 23, width, height), config, expanded, measured);
    return @{@"x":@(result.frame.origin.x), @"y":@(result.frame.origin.y), @"width":@(result.frame.size.width),
        @"height":@(result.frame.size.height), @"resting":@(result.restingContentHeight),
        @"expanded":@(result.expandedContentHeight), @"centered":@(result.centered)};
}
NSDictionary *StashReservedRegionProbe(void) {
    CGRect bounds = CGRectMake(0, 0, 1000, 800);
    NSArray *vertical = @[[NSValue valueWithCGRect:CGRectMake(490, 0, 20, 800)]];
    CGRect trailing = StashChooseAvailableRegion(bounds, vertical, CGPointMake(500, 400), NO);
    CGRect focused = StashChooseAvailableRegion(bounds, vertical, CGPointMake(50, 50), NO);
    CGRect lower = StashChooseAvailableRegion(bounds, @[[NSValue valueWithCGRect:CGRectMake(0, 390, 1000, 20)]], CGPointMake(500, 400), NO);
    CGRect rtl = StashChooseAvailableRegion(bounds, vertical, CGPointMake(500, 400), YES);
    return @{@"rtlX":@(rtl.origin.x), @"trailingX":@(trailing.origin.x), @"focusedX":@(focused.origin.x), @"lowerY":@(lower.origin.y)};
}
BOOL StashHeightHintProbe(NSDictionary *payload, NSString *documentID, double width, double scale, double nativeWidth) {
    return StashValidateContentHeight(payload, documentID, width, scale, nativeWidth, NULL);
}
NSDictionary *StashConfigurationProbe(void) {
    StashNativeCardConfig *card = [StashNativeCardConfig new];
    card.preferredContentWidth = NAN; card.preferredContentHeight = INFINITY;
    card.maximumContentHeight = -20; card.edgeMargin = -3;
    StashNativeCardConfig *normalized = StashNormalizedConfig(card);
    StashNativeCardConfig *copy = [card copy];
    card.allowDismiss = NO;
    return @{@"width":@(normalized.preferredContentWidth), @"height":@(normalized.preferredContentHeight),
        @"maximum":@(normalized.maximumContentHeight), @"margin":@(normalized.edgeMargin), @"copiedDismiss":@(copy.allowDismiss)};
}
NSString *StashMeasurementSource(void) { return StashContentMeasurementScript(@"document-test"); }
NSString *StashNativeInteractionSource(void) { return StashNativeInteractionScript(); }
NSDictionary *StashURLProbe(void) {
    return @{@"bare":NormalizeExternalPaymentURL(@"example.invalid/path") ?: @"",
        @"javascript":NormalizeExternalPaymentURL(@"javascript:alert(1)") ?: @"",
        @"themed":appendThemeQueryParameter(@"https://example.invalid/?token=a%2Bb%26c&theme=light#section")};
}
NSDictionary *StashNativeSurfaceProbe(void) {
    CGRect safe = CGRectMake(0, 0, 466, 644);
    NSArray *regions = @[[NSValue valueWithCGRect:CGRectMake(382, 0, 84, 170)]];
    CGRect available = StashChooseBottomAttachedRegion(safe, regions);
    CGFloat maximumDetentValue = 636;
    available.size.height = MIN(CGRectGetMaxY(available), maximumDetentValue) - available.origin.y;
    StashNativeCardConfig *config = [StashNativeCardConfig new];
    StashPresentationGeometry native = StashResolveGeometry(available, config, NO, 0);
    CGFloat surfaceTop = 670 - native.frame.size.height - 34;
    CGRect blocked = StashChooseBottomAttachedRegion(safe, @[[NSValue valueWithCGRect:CGRectMake(220, 0, 20, 644)]]);
    CGRect unobstructed = StashChooseBottomAttachedRegion(safe, @[]);
    StashPresentationGeometry shortContent = StashResolveGeometry(available, config, NO, 240);
    return @{@"availableWidth":@(available.size.width), @"contentHeight":@(native.restingContentHeight),
        @"detentHeight":@(native.frame.size.height), @"surfaceTop":@(surfaceTop),
        @"blockedHeight":@(blocked.size.height),
        @"unobstructedWidth":@(unobstructed.size.width), @"shortHeight":@(shortContent.frame.size.height)};
}

@interface StashPaneProbeController : StashCheckoutViewController
@end
@implementation StashPaneProbeController
- (void)viewDidLoad {}
- (UIView *)layoutContainer { return self.session.presenter.view; }
- (CGRect)availableBoundsInView:(UIView *)view { return [self availableBoundsInView:view expanded:NO]; }
- (CGRect)availableBoundsInView:(UIView *)view expanded:(BOOL)expanded { return CGRectMake(500, 0, 460, 700); }
@end
NSDictionary *StashNativePaneProbe(void) {
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.config = [StashNativeCardConfig new];
    UIViewController *presenter = [UIViewController new];
    presenter.view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 960, 700)];
    session.presenter = presenter;
    StashPaneProbeController *controller = [StashPaneProbeController new];
    controller.session = session;

    session.config.preferredContentHeight = 300;
    [controller configurePresentation];
    CGFloat initialHeight = controller.preferredContentSize.height;
    [controller updatePresentationAnimated:NO];
    CGFloat width = controller.preferredContentSize.width;
    CGFloat restingPreferredHeight = controller.preferredContentSize.height;
    CGFloat resting = [controller contentHeightForMaximum:620 expanded:NO];
    session.measuredContentHeight = 120;
    CGFloat intrinsic = [controller contentHeightForMaximum:620 expanded:NO];
    session.expanded = YES;
    [controller updatePresentationAnimated:NO];
    return @{@"width":@(width), @"initialHeight":@(initialHeight),
        @"restingPreferredHeight":@(restingPreferredHeight),
        @"expandedPreferredHeight":@(controller.preferredContentSize.height),
        @"restingDetent":@(resting), @"intrinsicDetent":@(intrinsic),
        @"expandedDetent":@([controller contentHeightForMaximum:620 expanded:YES]),
        @"anchored":@(controller.sheetPresentationController.sourceView != nil)};
}

@interface StashGeometryProbeWindow : UIWindow
@end
@implementation StashGeometryProbeWindow
- (UIEdgeInsets)safeAreaInsets { return UIEdgeInsetsZero; }
@end

@interface StashKeyboardProbeController : StashCheckoutViewController
@property (nonatomic, strong) UIWindow *probeWindow;
@end
@implementation StashKeyboardProbeController
- (void)viewDidLoad {}
- (UIView *)layoutContainer { return self.probeWindow; }
- (CGRect)availableBoundsInView:(UIView *)view expanded:(BOOL)expanded {
    return expanded ? CGRectMake(0, 0, 382, 644) : CGRectMake(0, 170, 466, 474);
}
@end
NSDictionary *StashNativeKeyboardProbe(void) {
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.config = [StashNativeCardConfig new];
    StashKeyboardProbeController *controller = [StashKeyboardProbeController new];
    controller.session = session;

    controller.probeWindow = [[StashGeometryProbeWindow alloc] initWithFrame:CGRectMake(0, 0, 466, 678)];
    CGFloat resting = [controller contentHeightForMaximum:636 expanded:NO];
    session.keyboardVisible = YES;
    controller.keyboardFrame = CGRectMake(0, 389, 466, 289);
    CGFloat docked = [controller contentHeightForMaximum:636 expanded:YES];
    controller.keyboardFrame = CGRectMake(0, 350, 466, 200);
    CGFloat floating = [controller contentHeightForMaximum:636 expanded:YES];
    session.config.preferredContentHeight = 320;
    session.keyboardVisible = NO;
    controller.modalPresentationStyle = UIModalPresentationFormSheet;
    [controller updatePresentationAnimated:NO];
    CGFloat shortResting = [controller contentHeightForMaximum:636 expanded:NO];
    session.keyboardVisible = YES;
    controller.keyboardFrame = CGRectMake(0, 389, 466, 289);
    [controller updatePresentationAnimated:NO];
    CGFloat shortKeyboard = [controller contentHeightForMaximum:636 expanded:YES];
    BOOL keyboardSelectsExpanded = [controller.sheetPresentationController.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:YES]];
    BOOL preservesResting = !session.expanded;
    session.keyboardVisible = NO;
    [controller updatePresentationAnimated:NO];
    BOOL restoresResting = [controller.sheetPresentationController.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:NO]];
    CGFloat restored = [controller contentHeightForMaximum:636 expanded:NO];
    return @{@"resting":@(resting), @"docked":@(docked), @"floating":@(floating),
        @"shortResting":@(shortResting), @"shortKeyboard":@(shortKeyboard), @"restored":@(restored),
        @"restingTop":@(636 - shortResting),
        @"keyboardSelectsExpanded":@(keyboardSelectsExpanded), @"preservesResting":@(preservesResting),
        @"restoresResting":@(restoresResting)};
}

#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
@interface StashTestReservedRegion : NSObject
@property (nonatomic) CGRect frame;
@property (nonatomic, getter=isActive) BOOL active;
@end
@implementation StashTestReservedRegion
@end
@interface StashReservedProbeView : UIView
@property (nonatomic, strong) NSArray *regions;
@property (nonatomic) UIEdgeInsets probeInsets;
@property (nonatomic) NSUInteger layoutRequests;
@end
@implementation StashReservedProbeView
- (UIEdgeInsets)safeAreaInsets { return self.probeInsets; }
- (void)setNeedsLayout { self.layoutRequests++; [super setNeedsLayout]; }
- (NSArray<UIViewReservedRegion *> *)reservedRegionsOfKind:(UIViewReservedRegionKind *)kind API_AVAILABLE(ios(27.1)) {
    return [kind isEqual:UIViewReservedRegionKind.occlusionRegionKind] ? self.regions : @[];
}
@end
@interface StashRegionProbeController : StashCheckoutViewController
@property (nonatomic, strong) UIView *probeContainer;
@end
@implementation StashRegionProbeController
- (void)viewDidLoad {}
- (UIView *)layoutContainer { return self.probeContainer; }
@end
@interface StashSafeProbeWindow : UIWindow
@property (nonatomic) UIEdgeInsets probeInsets;
@end
@implementation StashSafeProbeWindow
- (UIEdgeInsets)safeAreaInsets { return self.probeInsets; }
@end
void StashNativeIntrinsicSafeAreaProbe(void (^completion)(NSDictionary *)) {
    NSMutableArray *cases = [NSMutableArray array];
    for (NSDictionary *metrics in @[
        @{@"name":@"compact", @"windowWidth":@466, @"windowHeight":@678, @"hostBottom":@34, @"safeBottom":@34, @"nativeExtra":@34},
        @{@"name":@"tablet", @"windowWidth":@1032, @"windowHeight":@1376, @"hostBottom":@20, @"safeBottom":@20, @"nativeExtra":@20},
        @{@"name":@"floating", @"windowWidth":@951, @"windowHeight":@669, @"hostBottom":@34, @"safeBottom":@26, @"nativeExtra":@0}]) {
        StashNativeCard *owner = [StashNativeCard new];
        StashCheckoutSession *session = [StashCheckoutSession new];
        owner.session = session; session.owner = owner; session.config = [StashNativeCardConfig new];
        session.measuredContentHeight = 220;
        session.webView = [[WKWebView alloc] initWithFrame:CGRectZero];
        CGFloat windowWidth = [metrics[@"windowWidth"] doubleValue], windowHeight = [metrics[@"windowHeight"] doubleValue];
        StashSafeProbeWindow *window = [[StashSafeProbeWindow alloc] initWithFrame:CGRectMake(0, 0, windowWidth, windowHeight)];
        window.probeInsets = UIEdgeInsetsMake(0, 0, [metrics[@"hostBottom"] doubleValue], 0);
        UIViewController *presenter = [UIViewController new];
        window.rootViewController = presenter; session.presenter = presenter;
        StashRegionProbeController *controller = [StashRegionProbeController new];
        session.controller = controller; controller.session = session; controller.probeContainer = window;
        [controller configurePresentation];
        controller.hasNativeMaximumDetentValue = YES;
        controller.nativeMaximumDetentValue = windowHeight - 16;
        CGFloat detent = [controller contentHeightForMaximum:controller.nativeMaximumDetentValue expanded:NO];
        CGFloat height = detent + [metrics[@"nativeExtra"] doubleValue], width = MIN(640, windowWidth - 16);
        StashReservedProbeView *content = [[StashReservedProbeView alloc]
            initWithFrame:CGRectMake((windowWidth - width) / 2, windowHeight - 8 - height, width, height)];
        content.probeInsets = UIEdgeInsetsMake(0, 0, [metrics[@"safeBottom"] doubleValue], 0);
        controller.view = content; [window addSubview:content]; [content addSubview:session.webView];
        controller.previousWidth = width;
        [controller viewDidLayoutSubviews];
        [cases addObject:@{@"owner":owner, @"session":session, @"window":window, @"metrics":metrics,
            @"before":@(session.webView.bounds.size.height - session.webView.scrollView.verticalScrollIndicatorInsets.bottom)}];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (NSDictionary *entry in cases) {
            StashCheckoutSession *session = entry[@"session"];
            StashRegionProbeController *controller = (id)session.controller;
            NSDictionary *metrics = entry[@"metrics"];
            NSString *name = metrics[@"name"];
            CGFloat detent = [controller contentHeightForMaximum:controller.nativeMaximumDetentValue expanded:NO];
            CGRect frame = controller.view.frame;
            CGFloat bottom = CGRectGetMaxY(frame);
            frame.size.height = detent + [metrics[@"nativeExtra"] doubleValue];
            frame.origin.y = bottom - frame.size.height;
            controller.view.frame = frame;
            [controller viewDidLayoutSubviews];
            result[[name stringByAppendingString:@"Before"]] = entry[@"before"];
            result[[name stringByAppendingString:@"Usable"]] = @(session.webView.bounds.size.height -
                session.webView.scrollView.verticalScrollIndicatorInsets.bottom);
            result[[name stringByAppendingString:@"Compensation"]] = @(controller.nativeContentSafeAreaCompensation);
            if ([name isEqualToString:@"floating"]) {
                session.config.maximumContentHeight = 230;
                result[@"cappedDetent"] = @([controller contentHeightForMaximum:653 expanded:YES]);
                result[@"nativeMaximumWins"] = @([controller contentHeightForMaximum:230 expanded:YES]);
                controller.dragging = YES;
                [controller reconcileNativeContentSafeArea:40];
                result[@"dragKeepsCompensation"] = @(controller.nativeContentSafeAreaCompensation == 26);
            }
            [(StashNativeCard *)entry[@"owner"] resetPresentationState];
        }
        completion(result);
    });
}
NSDictionary *StashNativeHostSafeAreaProbe(void) {
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.config = [StashNativeCardConfig new];
    StashSafeProbeWindow *window = [[StashSafeProbeWindow alloc] initWithFrame:CGRectMake(0, 0, 951, 669)];
    window.probeInsets = UIEdgeInsetsMake(0, 0, 34, 84);
    UIViewController *presenter = [UIViewController new];
    window.rootViewController = presenter;
    session.presenter = presenter;
    StashRegionProbeController *controller = [StashRegionProbeController new];
    controller.session = session; controller.probeContainer = window;
    StashReservedProbeView *content = [[StashReservedProbeView alloc] initWithFrame:CGRectMake(235.5, 58, 480, 603)];
    content.probeInsets = UIEdgeInsetsMake(0, 0, 6, 0);
    controller.view = content; [window addSubview:content];
    CGRect transitional = [controller availableBoundsInView:content];
    content.probeInsets = UIEdgeInsetsMake(0, 0, 26, 0);
    CGRect settled = [controller availableBoundsInView:content];
    window.frame = CGRectMake(0, 0, 466, 678);
    content.frame = CGRectMake(8, 186, 450, 484);
    content.probeInsets = UIEdgeInsetsMake(0, 0, 34, 76);
    CGRect compact = [controller availableBoundsInView:content];
    return @{@"transitionalHeight":@(transitional.size.height), @"settledHeight":@(settled.size.height),
        @"compactWidth":@(compact.size.width), @"compactHeight":@(compact.size.height),
        @"sameWindow":@(content.window == window)};
}
NSDictionary *StashNativeBottomPaintProbe(void) {
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.config = [StashNativeCardConfig new];
    session.webView = [[WKWebView alloc] initWithFrame:CGRectZero];
    StashSafeProbeWindow *window = [[StashSafeProbeWindow alloc] initWithFrame:CGRectMake(0, 0, 951, 669)];
    window.probeInsets = UIEdgeInsetsMake(0, 0, 34, 84);
    UIViewController *presenter = [UIViewController new];
    window.rootViewController = presenter; session.presenter = presenter;
    StashRegionProbeController *controller = [StashRegionProbeController new];
    controller.session = session; controller.probeContainer = window;
    StashReservedProbeView *content = [[StashReservedProbeView alloc] initWithFrame:CGRectMake(235.5, 58, 480, 603)];
    content.probeInsets = UIEdgeInsetsMake(0, 0, 6, 0);
    controller.view = content; [window addSubview:content]; [content addSubview:session.webView];
    [controller viewDidLayoutSubviews];
    CGFloat transitionalHeight = session.webView.frame.size.height;
    CGFloat transitionalInset = session.webView.scrollView.verticalScrollIndicatorInsets.bottom;
    CGFloat initialCorrection = controller.additionalSafeAreaInsets.bottom;
    [controller viewDidLayoutSubviews];
    CGFloat pendingCorrection = controller.additionalSafeAreaInsets.bottom;
    content.probeInsets = UIEdgeInsetsMake(0, 0, 26, 0);
    [controller viewDidLayoutSubviews];
    CGFloat propagatedCorrection = controller.additionalSafeAreaInsets.bottom;
    content.probeInsets = UIEdgeInsetsMake(0, 0, 46, 0);
    [controller viewDidLayoutSubviews];
    CGFloat releasedCorrection = controller.additionalSafeAreaInsets.bottom;
    content.probeInsets = UIEdgeInsetsMake(0, 0, 26, 0);
    [controller viewDidLayoutSubviews];
    CGFloat settledHeight = session.webView.frame.size.height;
    CGFloat settledInset = session.webView.scrollView.verticalScrollIndicatorInsets.bottom;
    window.probeInsets = UIEdgeInsetsMake(0, 0, 54, 84);
    [controller viewDidLayoutSubviews];
    [controller completeHostSafeAreaUpdate:controller.hostSafeAreaUpdateGeneration];
    window.probeInsets = UIEdgeInsetsMake(0, 0, 42, 84);
    [controller viewDidLayoutSubviews];
    CGFloat sameTotalCorrection = controller.additionalSafeAreaInsets.bottom;
    content.probeInsets = UIEdgeInsetsMake(0, 0, 34, 0);
    [controller viewDidLayoutSubviews];
    window.probeInsets = UIEdgeInsetsMake(0, 0, 34, 84);
    content.probeInsets = UIEdgeInsetsMake(0, 0, 54, 0);
    [controller viewDidLayoutSubviews];
    content.probeInsets = UIEdgeInsetsMake(0, 0, 26, 0);
    [controller viewDidLayoutSubviews];
    window.frame = CGRectMake(0, 0, 466, 678);
    content.frame = CGRectMake(8, 186, 450, 484);
    content.probeInsets = UIEdgeInsetsMake(0, 0, 34, 76);
    [controller viewDidLayoutSubviews];
    CGSize compact = session.webView.frame.size;
    CGFloat compactInset = session.webView.scrollView.verticalScrollIndicatorInsets.bottom;
    StashTestReservedRegion *bottomDivision = [StashTestReservedRegion new];
    bottomDivision.frame = CGRectMake(0, 460, 450, 10); bottomDivision.active = YES;
    content.regions = @[bottomDivision];
    [controller viewDidLayoutSubviews];
    CGFloat reservedBandBottom = CGRectGetMaxY(session.webView.frame);
    CGFloat reservedBandInset = session.webView.scrollView.verticalScrollIndicatorInsets.bottom;
    content.regions = @[];
    session.keyboardVisible = YES;
    controller.keyboardEpisodeOwned = YES;
    controller.keyboardNotificationVisible = YES;
    StashSetKeyboardNotificationContext(controller, window);
    controller.keyboardFrame = CGRectMake(100, 300, 200, 160);
    [controller viewDidLayoutSubviews];
    CGFloat floatingHeight = session.webView.frame.size.height;
    CGFloat floatingInset = session.webView.scrollView.verticalScrollIndicatorInsets.bottom;
    controller.keyboardFrame = CGRectMake(0, 389, 466, 289);
    session.webView.scrollView.contentInset = UIEdgeInsetsMake(0, 0, 26, 0);
    [controller viewDidLayoutSubviews];
    BOOL keyboardContentInsetCleared = UIEdgeInsetsEqualToEdgeInsets(session.webView.scrollView.contentInset, UIEdgeInsetsZero);
    CGFloat keyboardBottom = CGRectGetMaxY([session.webView convertRect:session.webView.bounds toView:window]);
    CGFloat keyboardInset = session.webView.scrollView.verticalScrollIndicatorInsets.bottom;
    session.keyboardVisible = NO;
    UIView *initiating = [[UIView alloc] initWithFrame:CGRectMake(20, 196, 50, 50)];
    [window addSubview:initiating]; presenter.view = initiating;
    StashTestReservedRegion *division = [StashTestReservedRegion new];
    division.frame = CGRectMake(0, 200, 450, 20); division.active = YES;
    content.regions = @[division];
    [controller viewDidLayoutSubviews];
    CGFloat dividerBottom = CGRectGetMaxY(session.webView.frame);
    CGFloat dividerInset = session.webView.scrollView.verticalScrollIndicatorInsets.bottom;
    division.frame = content.bounds;
    [controller viewDidLayoutSubviews];
    BOOL coveredEmpty = CGRectIsEmpty(session.webView.frame);
    content.regions = @[];
    content.frame = CGRectMake(0, 700, 450, 100);
    content.probeInsets = UIEdgeInsetsZero;
    [controller viewDidLayoutSubviews];
    CGFloat offscreenCorrection = controller.additionalSafeAreaInsets.bottom;
    return @{@"transitionalHeight":@(transitionalHeight), @"transitionalInset":@(transitionalInset),
        @"initialCorrection":@(initialCorrection), @"pendingCorrection":@(pendingCorrection),
        @"propagatedCorrection":@(propagatedCorrection), @"releasedCorrection":@(releasedCorrection),
        @"sameTotalCorrection":@(sameTotalCorrection), @"offscreenCorrection":@(offscreenCorrection),
        @"settledHeight":@(settledHeight), @"settledInset":@(settledInset),
        @"compactWidth":@(compact.width), @"compactHeight":@(compact.height), @"compactInset":@(compactInset),
        @"reservedBandBottom":@(reservedBandBottom), @"reservedBandInset":@(reservedBandInset),
        @"floatingHeight":@(floatingHeight), @"floatingInset":@(floatingInset),
        @"keyboardContentInsetCleared":@(keyboardContentInsetCleared), @"keyboardBottom":@(keyboardBottom), @"keyboardInset":@(keyboardInset),
        @"dividerBottom":@(dividerBottom), @"dividerInset":@(dividerInset),
        @"coveredEmpty":@(coveredEmpty)};
}
NSDictionary *StashCompactDividerProbe(void) {
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.config = [StashNativeCardConfig new];
    UIViewController *presenter = [UIViewController new];
    StashReservedProbeView *view = [[StashReservedProbeView alloc] initWithFrame:CGRectMake(0, 0, 500, 700)];
    view.bounds = CGRectMake(11, 23, 500, 700);
    presenter.view = view;
    session.presenter = presenter;
    StashRegionProbeController *controller = [StashRegionProbeController new];
    controller.session = session;

    controller.probeContainer = view;
    StashTestReservedRegion *region = [StashTestReservedRegion new];
    region.frame = CGRectMake(251, 23, 20, 700);
    region.active = YES;
    view.regions = @[region];
    CGRect trailing = [controller availableBoundsInView:view];
    view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    CGRect rtl = [controller availableBoundsInView:view];
    view.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    UIView *initiating = [[UIView alloc] initWithFrame:CGRectMake(30, 30, 80, 80)];
    [view addSubview:initiating];
    presenter.view = initiating;
    CGRect preferred = [controller availableBoundsInView:view];
    presenter.view = view;
    region.frame = CGRectMake(427, 23, 84, 170);
    CGRect status = [controller availableBoundsInView:view];
    region.frame = CGRectMake(11, 350, 500, 20);
    CGRect horizontal = [controller availableBoundsInView:view];
    region.frame = view.bounds;
    CGRect covered = [controller availableBoundsInView:view];
    return @{@"trailingX":@(trailing.origin.x), @"width":@(trailing.size.width), @"height":@(trailing.size.height),
        @"rtlX":@(rtl.origin.x), @"preferredX":@(preferred.origin.x),
        @"statusY":@(status.origin.y), @"statusWidth":@(status.size.width),
        @"horizontalY":@(horizontal.origin.y), @"coveredEmpty":@(CGRectIsEmpty(covered))};
}
@interface StashDetentContext : NSObject <UISheetPresentationControllerDetentResolutionContext>
@property (nonatomic) CGFloat maximumDetentValue;
@property (nonatomic, strong) UITraitCollection *containerTraitCollection;
@end
@implementation StashDetentContext
@end
NSDictionary *StashNativeExpansionProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new];
    owner.session = session; session.owner = owner;
    session.config = [StashNativeCardConfig new];
    UIViewController *presenter = [UIViewController new];
    StashReservedProbeView *container = [[StashReservedProbeView alloc] initWithFrame:CGRectMake(0, 0, 466, 678)];
    container.probeInsets = UIEdgeInsetsMake(0, 0, 34, 0);
    StashTestReservedRegion *status = [StashTestReservedRegion new];
    status.frame = CGRectMake(382, 0, 84, 170); status.active = YES;
    container.regions = @[status];
    presenter.view = container; session.presenter = presenter;
    StashRegionProbeController *controller = [StashRegionProbeController new];
    controller.session = session; session.controller = controller;
    controller.probeContainer = container;
    [controller configurePresentation];
    UISheetPresentationController *sheet = controller.sheetPresentationController;
    StashDetentContext *context = [StashDetentContext new];
    context.maximumDetentValue = 636;
    context.containerTraitCollection = container.traitCollection;
    CGFloat resolvedResting = -1, resolvedExpanded = -1;
    NSUInteger detentsBefore = sheet.detents.count;
    for (UISheetPresentationControllerDetent *detent in sheet.detents) {
        CGFloat height = [detent resolvedValueInContext:context];
        if ([detent.identifier isEqualToString:[controller nativeDetentIdentifierForExpanded:NO]]) resolvedResting = height;
        if ([detent.identifier isEqualToString:[controller nativeDetentIdentifierForExpanded:YES]]) resolvedExpanded = height;
    }
    BOOL singleBefore = controller.singleDetent;
    CGFloat restingBefore = [controller contentHeightForMaximum:636 expanded:NO];
    CGFloat expandedBefore = [controller contentHeightForMaximum:636 expanded:YES];
    [session handleMessage:@"stashExpand" body:@{}];
    CGFloat restingAfter = [controller contentHeightForMaximum:636 expanded:NO];
    CGFloat expandedAfter = [controller contentHeightForMaximum:636 expanded:YES];
    BOOL bridgeExpanded = session.expanded && [sheet.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:YES]];
    session.config.maximumContentHeight = 400;
    [controller updatePresentationAnimated:NO];
    BOOL cappedSingle = sheet.detents.count == 1 && controller.singleDetent && session.expanded;
    session.config.maximumContentHeight = 0;
    [controller updatePresentationAnimated:NO];
    BOOL restoredExpanded = sheet.detents.count == 2 && session.expanded &&
        [sheet.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:YES]];
    [session handleMessage:@"stashCollapse" body:@{}];
    session.keyboardVisible = YES;
    [controller updatePresentationAnimated:NO];
    CGFloat restingDuringKeyboard = [controller contentHeightForMaximum:636 expanded:NO];
    BOOL keyboardOverride = !session.expanded && [sheet.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:YES]];
    session.keyboardVisible = NO;
    [controller updatePresentationAnimated:NO];
    BOOL keyboardRestored = !session.expanded && [sheet.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:NO]];
    StashReservedProbeView *content = [[StashReservedProbeView alloc] initWithFrame:CGRectMake(0, 0, 450, 654)];
    content.probeInsets = UIEdgeInsetsMake(0, 0, 34, 76);
    StashTestReservedRegion *localStatus = [StashTestReservedRegion new];
    localStatus.frame = CGRectMake(374, -16, 84, 170); localStatus.active = YES;
    content.regions = @[localStatus]; controller.view = content;
    CGRect movingContent = [controller availableBoundsInView:content];
    NSUInteger layoutBefore = content.layoutRequests;
    sheet.selectedDetentIdentifier = [controller nativeDetentIdentifierForExpanded:YES];
    [session sheetPresentationControllerDidChangeSelectedDetentIdentifier:sheet];
    BOOL delegateExpanded = session.expanded;
    BOOL delegateRelayout = content.layoutRequests > layoutBefore;
    session.expanded = NO;
    controller.dragging = YES;
    [controller updatePresentationAnimated:NO];
    BOOL dragPreservesSelection = [sheet.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:YES]];
    BOOL dragDefersLayout = controller.deferredContentLayout;
    controller.dragging = NO;
    controller.requestedNativeExpanded = NO;
    controller.hasRequestedNativeSelection = YES;
    [controller updatePresentationAnimated:NO];
    BOOL passivePreservesSelection = [sheet.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:YES]];
    [session handleMessage:@"stashCollapse" body:@{}];
    BOOL explicitCollapseSelectsResting = [sheet.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:NO]];
    context.maximumDetentValue = 0;
    (void)[sheet.detents.firstObject resolvedValueInContext:context];
    [controller updatePresentationAnimated:NO];
    BOOL zeroMaximumStaysSingle = controller.singleDetent && sheet.detents.count == 1;
    context.maximumDetentValue = 636;
    (void)[sheet.detents.firstObject resolvedValueInContext:context];
    [controller updatePresentationAnimated:NO];
    BOOL nonzeroMaximumRestoresDetents = !controller.singleDetent && sheet.detents.count == 2;
    NSDictionary *result = @{@"restingBefore":@(restingBefore), @"expandedBefore":@(expandedBefore),
        @"restingAfter":@(restingAfter), @"expandedAfter":@(expandedAfter), @"resolvedResting":@(resolvedResting),
        @"resolvedExpanded":@(resolvedExpanded), @"detentsBefore":@(detentsBefore), @"singleBefore":@(singleBefore),
        @"bridgeExpanded":@(bridgeExpanded), @"cappedSingle":@(cappedSingle), @"restoredExpanded":@(restoredExpanded),
        @"restingDuringKeyboard":@(restingDuringKeyboard), @"keyboardOverride":@(keyboardOverride),
        @"keyboardRestored":@(keyboardRestored), @"movingContentX":@(movingContent.origin.x),
        @"movingContentY":@(movingContent.origin.y), @"movingContentWidth":@(movingContent.size.width),
        @"delegateExpanded":@(delegateExpanded), @"delegateRelayout":@(delegateRelayout),
        @"dragPreservesSelection":@(dragPreservesSelection), @"dragDefersLayout":@(dragDefersLayout),
        @"passivePreservesSelection":@(passivePreservesSelection),
        @"explicitCollapseSelectsResting":@(explicitCollapseSelectsResting),
        @"zeroMaximumStaysSingle":@(zeroMaximumStaysSingle),
        @"nonzeroMaximumRestoresDetents":@(nonzeroMaximumRestoresDetents)};
    [owner resetPresentationState];
    return result;
}
#else
void StashNativeIntrinsicSafeAreaProbe(void (^completion)(NSDictionary *)) { completion(@{}); }
NSDictionary *StashCompactDividerProbe(void) { return @{}; }
NSDictionary *StashNativeExpansionProbe(void) { return @{}; }
NSDictionary *StashNativeHostSafeAreaProbe(void) { return @{}; }
NSDictionary *StashNativeBottomPaintProbe(void) { return @{}; }
#endif
