#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativeCardPrivate.h"
#import <objc/runtime.h>

@interface StashFocusProbeWebView : WKWebView
@property (nonatomic) NSUInteger repairs;
@property (nonatomic) CGSize repairedSize;
@property (nonatomic) CGPoint repairedRootOffset;
@property (nonatomic) BOOL focusForKeyboardProbe;
@end
@implementation StashFocusProbeWebView
- (BOOL)isFirstResponder { return self.focusForKeyboardProbe || [super isFirstResponder]; }
- (void)evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion {
    if ([script containsString:@"__stashRevealFocusedElement"]) {
        self.repairs++;
        self.repairedSize = self.bounds.size;
        self.repairedRootOffset = self.scrollView.contentOffset;
    }
    if (completion) completion(nil, nil);
}
@end

@interface StashRootScrollProbe : UIScrollView
@property (nonatomic) UIEdgeInsets probeInsets;
@property (nonatomic) BOOL probeTracking;
@property (nonatomic) BOOL probeDragging;
@property (nonatomic) BOOL probeDecelerating;
@property (nonatomic) BOOL probeZooming;
@end
@implementation StashRootScrollProbe
- (UIEdgeInsets)adjustedContentInset { return self.probeInsets; }
- (BOOL)isTracking { return self.probeTracking; }
- (BOOL)isDragging { return self.probeDragging; }
- (BOOL)isDecelerating { return self.probeDecelerating; }
- (BOOL)isZooming { return self.probeZooming; }
@end
@interface StashRootOffsetWebView : WKWebView
@property (nonatomic, strong) StashRootScrollProbe *rootProbe;
@end
@implementation StashRootOffsetWebView
- (UIScrollView *)scrollView { return self.rootProbe ?: [super scrollView]; }
@end

@interface StashRootInsetKeyboardController : StashCheckoutViewController
@property (nonatomic) CGRect probeDockedKeyboard;
@end
@implementation StashRootInsetKeyboardController
- (CGRect)resolvedKeyboardFrameInView:(UIView *)view dockedOnly:(BOOL)dockedOnly {
    // Resolver ownership/physical docking has its own captured-geometry regression coverage.
    return self.probeDockedKeyboard;
}
@end

BOOL StashNormalizeRootScrollOffset(WKWebView *webView) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new]; owner.session = session; session.owner = owner;
    session.webView = webView;
    StashCheckoutViewController *controller = [StashCheckoutViewController new]; controller.session = session;
    BOOL changed = [controller normalizeIdleRootScrollOffset];
    session.webView = nil; owner.session = nil;
    return changed;
}

NSDictionary *StashRootScrollOffsetProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new]; owner.session = session; session.owner = owner;
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 375, 700)];
    UIViewController *host = [UIViewController new]; window.rootViewController = host; window.hidden = NO;
    StashRootOffsetWebView *web = [[StashRootOffsetWebView alloc] initWithFrame:CGRectMake(0, 0, 375, 647)];
    StashRootScrollProbe *scroll = [[StashRootScrollProbe alloc] initWithFrame:web.bounds]; web.rootProbe = scroll;
    [host.view addSubview:web]; [web addSubview:scroll]; session.webView = web;
    StashRootInsetKeyboardController *controller = [StashRootInsetKeyboardController new]; controller.session = session;
    controller.probeDockedKeyboard = CGRectNull;
    scroll.contentSize = scroll.bounds.size; scroll.contentOffset = CGPointMake(0, -87);
    BOOL negative = [controller normalizeIdleRootScrollOffset] && CGPointEqualToPoint(scroll.contentOffset, CGPointZero);
    scroll.contentOffset = CGPointMake(50, 90);
    BOOL positive = [controller normalizeIdleRootScrollOffset] && CGPointEqualToPoint(scroll.contentOffset, CGPointZero);
    scroll.probeInsets = UIEdgeInsetsMake(20, 10, 30, 15); scroll.contentSize = CGSizeMake(500, 1000);
    scroll.contentOffset = CGPointMake(45, 200);
    BOOL valid = ![controller normalizeIdleRootScrollOffset] && CGPointEqualToPoint(scroll.contentOffset, CGPointMake(45, 200));
    scroll.contentOffset = CGPointMake(-10, -20);
    BOOL safeMinimum = ![controller normalizeIdleRootScrollOffset] && CGPointEqualToPoint(scroll.contentOffset, CGPointMake(-10, -20));
    scroll.contentOffset = CGPointMake(900, 900);
    BOOL safeMaximum = [controller normalizeIdleRootScrollOffset] && CGPointEqualToPoint(scroll.contentOffset, CGPointMake(140, 383));
    scroll.contentOffset = CGPointMake(0, -87);
    BOOL activeGuards = YES;
    for (NSString *key in @[@"probeTracking", @"probeDragging", @"probeDecelerating", @"probeZooming"]) {
        [scroll setValue:@YES forKey:key];
        activeGuards &= ![controller normalizeIdleRootScrollOffset] && scroll.contentOffset.y == -87;
        [scroll setValue:@NO forKey:key];
    }
    BOOL layoutGuards = YES;
    for (NSString *key in @[@"geometryTransitioning", @"dragging", @"updatingLayout"]) {
        [controller setValue:@YES forKey:key];
        layoutGuards &= ![controller normalizeIdleRootScrollOffset] && scroll.contentOffset.y == -87;
        [controller setValue:@NO forKey:key];
    }
    BOOL settled = [controller normalizeIdleRootScrollOffset] && scroll.contentOffset.y == -20;
    [web removeFromSuperview]; scroll.contentOffset = CGPointMake(0, -87);
    BOOL detached = ![controller normalizeIdleRootScrollOffset] && scroll.contentOffset.y == -87;
    [host.view addSubview:web]; web.frame = CGRectMake(0, 0, 375, 425); scroll.frame = web.bounds;
    scroll.contentSize = scroll.bounds.size; scroll.contentInset = UIEdgeInsetsZero;
    scroll.probeInsets = UIEdgeInsetsMake(0, 0, 343.66295, 0);
    controller.probeDockedKeyboard = CGRectMake(0, 425, 375, 337);
    scroll.contentOffset = CGPointMake(0, 177.6666667);
    BOOL duplicateKeyboardInset = [controller normalizeIdleRootScrollOffset] && fabs(scroll.contentOffset.y) < 0.5;
    scroll.contentInset = UIEdgeInsetsMake(0, 0, 12, 0); scroll.contentOffset = CGPointMake(0, 177.6666667);
    BOOL explicitBottomInset = [controller normalizeIdleRootScrollOffset] && fabs(scroll.contentOffset.y - 12) < 0.5;
    scroll.contentInset = UIEdgeInsetsZero;
    controller.probeDockedKeyboard = CGRectMake(0, 300, 375, 337); scroll.contentOffset = CGPointMake(0, 177.6666667);
    BOOL keyboardOverlap = ![controller normalizeIdleRootScrollOffset] && fabs(scroll.contentOffset.y - 177.6666667) < 0.5;
    controller.probeDockedKeyboard = CGRectMake(0, 427, 375, 337);
    BOOL keyboardGap = ![controller normalizeIdleRootScrollOffset] && fabs(scroll.contentOffset.y - 177.6666667) < 0.5;
    controller.probeDockedKeyboard = CGRectNull;
    BOOL undockedKeyboard = ![controller normalizeIdleRootScrollOffset] && fabs(scroll.contentOffset.y - 177.6666667) < 0.5;
    controller.probeDockedKeyboard = CGRectMake(0, 425, 375, 337); scroll.contentSize = CGSizeMake(375, 800);
    BOOL genuineRootScroll = ![controller normalizeIdleRootScrollOffset] && fabs(scroll.contentOffset.y - 177.6666667) < 0.5;
    session.webView = nil; owner.session = nil; window.hidden = YES;
    return @{@"negative":@(negative), @"positive":@(positive), @"valid":@(valid), @"safeMinimum":@(safeMinimum),
        @"safeMaximum":@(safeMaximum), @"activeGuards":@(activeGuards), @"layoutGuards":@(layoutGuards),
        @"settled":@(settled), @"detached":@(detached), @"duplicateKeyboardInset":@(duplicateKeyboardInset),
        @"explicitBottomInset":@(explicitBottomInset), @"keyboardOverlap":@(keyboardOverlap), @"keyboardGap":@(keyboardGap),
        @"undockedKeyboard":@(undockedKeyboard), @"genuineRootScroll":@(genuineRootScroll)};
}

@interface StashCheckoutViewController (FocusRegression)
- (void)keyboardChanged:(NSNotification *)notification;
- (void)updateKeyboardGuideOcclusion;
@end

@interface StashKeyboardGuideProbe : UIKeyboardLayoutGuide
@property (nonatomic) CGRect probeFrame;
@end
@implementation StashKeyboardGuideProbe
- (CGRect)layoutFrame { return self.probeFrame; }
@end
@interface StashKeyboardGuideProbeView : UIView
@property (nonatomic, strong) StashKeyboardGuideProbe *probeGuide;
@end
@implementation StashKeyboardGuideProbeView
- (UIKeyboardLayoutGuide *)keyboardLayoutGuide { return self.probeGuide ?: [super keyboardLayoutGuide]; }
@end

@interface StashKeyboardHostWindow : UIWindow
@end
@implementation StashKeyboardHostWindow
- (UIEdgeInsets)safeAreaInsets { return UIEdgeInsetsMake(0, 0, 20, 0); }
@end

NSDictionary *StashKeyboardVisibilityOwnershipProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new]; owner.session = session; session.owner = owner;
    session.config = [StashNativeCardConfig new]; session.initialContentRevealed = YES;
    session.measuredContentHeight = 220;
    StashFocusProbeWebView *web = [[StashFocusProbeWebView alloc] initWithFrame:CGRectMake(0, 0, 640, 700)];
    web.focusForKeyboardProbe = YES; session.webView = web;
    UIWindow *window = [[StashKeyboardHostWindow alloc] initWithFrame:CGRectMake(0, 0, 640, 700)];
    UIViewController *presenter = [UIViewController new]; window.rootViewController = presenter;
    session.presenter = presenter; window.hidden = NO;
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session;
    StashKeyboardGuideProbeView *view = [[StashKeyboardGuideProbeView alloc] initWithFrame:window.bounds];
    StashKeyboardGuideProbe *guide = [StashKeyboardGuideProbe new]; view.probeGuide = guide; [view addLayoutGuide:guide];
    controller.view = view; [presenter.view addSubview:view]; [view addSubview:web];
    [controller configurePresentation];
    guide.probeFrame = CGRectMake(0, 200, 640, 100);
    [controller updateKeyboardGuideOcclusion];
    BOOL guideAloneStaysHidden = !session.keyboardVisible;
    [session setExpanded:YES animated:NO];
    guide.probeFrame = CGRectMake(0, 700, 640, 0); [controller updateKeyboardGuideOcclusion];
    [session setExpanded:NO animated:NO];
    BOOL hiddenCollapseRestoresResting = !session.keyboardVisible && !session.expanded &&
        [controller.sheetPresentationController.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:NO]];
    CGRect floating = [window convertRect:CGRectMake(80, 200, 334, 300) toCoordinateSpace:window.screen.coordinateSpace];
    guide.probeFrame = CGRectMake(80, 200, 334, 300);
    [controller keyboardChanged:[NSNotification notificationWithName:UIKeyboardWillChangeFrameNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:floating]}]];
    CGRect hidden = [window convertRect:CGRectMake(0, 700, 640, 0) toCoordinateSpace:window.screen.coordinateSpace];
    [controller keyboardChanged:[NSNotification notificationWithName:UIKeyboardWillHideNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:hidden]}]];
    BOOL floatingAfterZeroHide = session.keyboardVisible;
    session.keyboardVisible = NO; [controller updateKeyboardGuideOcclusion];
    BOOL unchangedGuideRestoresVisibility = session.keyboardVisible;
    guide.probeFrame = CGRectMake(0, 700, 640, 0); [controller updateKeyboardGuideOcclusion];
    BOOL hiddenGuideEndsEpisode = !session.keyboardVisible && [controller focusKeyboardOcclusion] == nil;
    guide.probeFrame = CGRectMake(0, 680, 640, 20); [controller updateKeyboardGuideOcclusion];
    BOOL safeBottomIsHidden = !session.keyboardVisible;
    guide.probeFrame = CGRectMake(80, 200, 334, 300); [controller updateKeyboardGuideOcclusion];
    BOOL endedEpisodeCannotRestartFromGuide = !session.keyboardVisible;
    [controller keyboardChanged:[NSNotification notificationWithName:UIKeyboardWillChangeFrameNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:floating]}]];
    [controller keyboardChanged:[NSNotification notificationWithName:UIKeyboardWillHideNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:floating]}]];
    BOOL visibleHidePreservesFloating = session.keyboardVisible;
    guide.probeFrame = CGRectMake(0, 680, 640, 20); [controller updateKeyboardGuideOcclusion];
    BOOL staleVisibleHideEndsAtHiddenGuide = !session.keyboardVisible && !controller.keyboardEpisodeOwned;
    [session cleanup]; owner.session = nil; window.hidden = YES;
    return @{@"guideAloneStaysHidden":@(guideAloneStaysHidden), @"hiddenCollapseRestoresResting":@(hiddenCollapseRestoresResting),
        @"floatingAfterZeroHide":@(floatingAfterZeroHide), @"unchangedGuideRestoresVisibility":@(unchangedGuideRestoresVisibility),
        @"hiddenGuideEndsEpisode":@(hiddenGuideEndsEpisode), @"safeBottomIsHidden":@(safeBottomIsHidden),
        @"endedEpisodeCannotRestartFromGuide":@(endedEpisodeCannotRestartFromGuide),
        @"visibleHidePreservesFloating":@(visibleHidePreservesFloating),
        @"staleVisibleHideEndsAtHiddenGuide":@(staleVisibleHideEndsAtHiddenGuide)};
}

NSDictionary *StashUndockedKeyboardLayoutProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new]; owner.session = session; session.owner = owner;
    session.config = [StashNativeCardConfig new];
    session.initialContentRevealed = YES; session.keyboardVisible = YES;
    StashFocusProbeWebView *web = [[StashFocusProbeWebView alloc] initWithFrame:CGRectZero];
    web.focusForKeyboardProbe = YES; session.webView = web;
    UIWindow *window = [[StashKeyboardHostWindow alloc] initWithFrame:CGRectMake(0, 0, 744, 1133)];
    UIViewController *presenter = [UIViewController new]; window.rootViewController = presenter;
    session.presenter = presenter; window.hidden = NO;
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session;
    CGRect surface = CGRectMake(52, 213, 640, 900);
    StashKeyboardGuideProbeView *view = [[StashKeyboardGuideProbeView alloc] initWithFrame:surface];
    StashKeyboardGuideProbe *guide = [StashKeyboardGuideProbe new]; view.probeGuide = guide; [view addLayoutGuide:guide];
    controller.view = view; [presenter.view addSubview:view]; [view addSubview:web];
    CGFloat rawTop = 786;
    controller.keyboardFrame = [window convertRect:CGRectMake(0, rawTop, 744, 1133 - rawTop)
        toCoordinateSpace:window.screen.coordinateSpace];
    guide.probeFrame = CGRectMake(-52, 573, 744, 347);
    [controller keyboardChanged:[NSNotification notificationWithName:UIKeyboardWillChangeFrameNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:controller.keyboardFrame]}]];
    [controller viewDidLayoutSubviews];
    CGFloat dockedHeight = web.bounds.size.height;
    BOOL docked = !controller.keyboardGuideUndocked;
    guide.probeFrame = CGRectMake(-surface.origin.x, 100, 744, 336);
    [controller viewDidLayoutSubviews];
    CGFloat undockedHeight = web.bounds.size.height;
    BOOL undocked = controller.keyboardGuideUndocked;
    guide.probeFrame = CGRectMake(-surface.origin.x, surface.size.height, 744, 1133 - CGRectGetMaxY(surface));
    [controller viewDidLayoutSubviews];
    BOOL restoredDocked = !controller.keyboardGuideUndocked;
    NSString *prefix = @"card";
    result[[prefix stringByAppendingString:@"DockedHeight"]] = @(dockedHeight);
    result[[prefix stringByAppendingString:@"UndockedHeight"]] = @(undockedHeight);
    result[[prefix stringByAppendingString:@"Classification"]] = @(docked && undocked && restoredDocked);
    [session cleanup]; owner.session = nil; window.hidden = YES;
    return result;
}

NSDictionary *StashFloatingKeyboardGuideProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new]; owner.session = session; session.owner = owner;
    session.config = [StashNativeCardConfig new]; session.initialContentRevealed = YES;
    StashFocusProbeWebView *web = [[StashFocusProbeWebView alloc] initWithFrame:CGRectZero];
    web.focusForKeyboardProbe = YES; session.webView = web;
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 744, 1133)];
    UIViewController *presenter = [UIViewController new]; window.rootViewController = presenter;
    session.presenter = presenter; window.hidden = NO;
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session;
    StashKeyboardGuideProbeView *view = [[StashKeyboardGuideProbeView alloc] initWithFrame:CGRectMake(50, 80, 500, 600)];
    StashKeyboardGuideProbe *guide = [StashKeyboardGuideProbe new]; view.probeGuide = guide; [view addLayoutGuide:guide];
    controller.view = view; [presenter.view addSubview:view]; [view addSubview:web];
    web.frame = CGRectMake(20, 0, 480, 600);
    controller.keyboardFrame = [window convertRect:CGRectMake(100, 300, 334, 333.5) toCoordinateSpace:window.screen.coordinateSpace];
    guide.probeFrame = CGRectMake(60, 40, 334, 280);
    [controller keyboardChanged:[NSNotification notificationWithName:UIKeyboardWillChangeFrameNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:controller.keyboardFrame]}]];
    web.frame = CGRectMake(20, 0, 480, 600);
    session.keyboardVisible = NO; [controller updateKeyboardGuideOcclusion];
    NSArray *current = [controller focusKeyboardOcclusion];
    BOOL restoredVisible = session.keyboardVisible;
    guide.probeFrame = CGRectMake(90, 200, 334, 300); [controller updateKeyboardGuideOcclusion];
    NSArray *moved = [controller focusKeyboardOcclusion];
    [controller keyboardChanged:[NSNotification notificationWithName:UIKeyboardWillHideNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:CGRectZero]}]];
    guide.probeFrame = CGRectMake(0, 600, 500, 0); [controller updateKeyboardGuideOcclusion];
    BOOL hiddenGuideClearsOcclusion = !session.keyboardVisible && [controller focusKeyboardOcclusion] == nil;
    [session cleanup]; owner.session = nil; window.hidden = YES;
    return @{@"current":current ?: @[], @"moved":moved ?: @[], @"restoredVisible":@(restoredVisible),
        @"hiddenGuideClearsOcclusion":@(hiddenGuideClearsOcclusion)};
}

NSDictionary *StashFloatingSheetKeyboardBaselineProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new]; owner.session = session; session.owner = owner;
    session.config = [StashNativeCardConfig new]; session.initialContentRevealed = YES;
    StashFocusProbeWebView *web = [[StashFocusProbeWebView alloc] initWithFrame:CGRectMake(0, 0, 480, 520)];
    web.focusForKeyboardProbe = YES; session.webView = web;
    UIWindow *window = [[StashKeyboardHostWindow alloc] initWithFrame:CGRectMake(0, 0, 951, 669)];
    UIViewController *presenter = [UIViewController new]; window.rootViewController = presenter;
    session.presenter = presenter; window.hidden = NO;
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session;
    StashKeyboardGuideProbeView *view = [[StashKeyboardGuideProbeView alloc] initWithFrame:CGRectMake(193.5, 65.5, 480, 520)];
    StashKeyboardGuideProbe *guide = [StashKeyboardGuideProbe new]; view.probeGuide = guide; [view addLayoutGuide:guide];
    controller.view = view; [presenter.view addSubview:view]; [view addSubview:web];
    guide.probeFrame = CGRectMake(-193.5, 520, 951, 83.5);
    CGRect docked = [window convertRect:CGRectMake(0, 405, 951, 264) toCoordinateSpace:window.screen.coordinateSpace];
    CGRect hidden = [window convertRect:CGRectMake(0, 669, 951, 264) toCoordinateSpace:window.screen.coordinateSpace];
    NSNotification *show = [NSNotification notificationWithName:UIKeyboardWillChangeFrameNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:docked]}];
    [controller keyboardChanged:show];
    BOOL positiveDockedPreserved = session.keyboardVisible && controller.keyboardEpisodeOwned && !controller.keyboardGuideUndocked;
    [controller keyboardChanged:[NSNotification notificationWithName:UIKeyboardWillHideNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:hidden]}]];
    BOOL hiddenBaselineEndsEpisode = !session.keyboardVisible && !controller.keyboardEpisodeOwned;
    [controller updateKeyboardGuideOcclusion];
    BOOL unchangedBaselineStaysHidden = !session.keyboardVisible;
    [controller keyboardChanged:show];
    BOOL nextDockedEpisode = session.keyboardVisible && controller.keyboardEpisodeOwned;
    guide.probeFrame = CGRectMake(6.5, 234.5, 334, 300);
    CGRect floating = [window convertRect:CGRectMake(200, 300, 334, 300) toCoordinateSpace:window.screen.coordinateSpace];
    [controller keyboardChanged:[NSNotification notificationWithName:UIKeyboardWillChangeFrameNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:floating]}]];
    [controller keyboardChanged:[NSNotification notificationWithName:UIKeyboardWillHideNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:hidden]}]];
    BOOL floatingAfterZeroHide = session.keyboardVisible && controller.keyboardGuideUndocked;
    guide.probeFrame = CGRectMake(-193.5, 540, 951, 20);
    [controller updateKeyboardGuideOcclusion];
    BOOL undockedBelowContentPreserved = session.keyboardVisible && controller.keyboardGuideUndocked;
    [session cleanup]; owner.session = nil; window.hidden = YES;
    return @{ @"positiveDockedPreserved":@(positiveDockedPreserved), @"hiddenBaselineEndsEpisode":@(hiddenBaselineEndsEpisode),
        @"unchangedBaselineStaysHidden":@(unchangedBaselineStaysHidden), @"nextDockedEpisode":@(nextDockedEpisode),
        @"floatingAfterZeroHide":@(floatingAfterZeroHide), @"undockedBelowContentPreserved":@(undockedBelowContentPreserved) };
}

NSDictionary *StashFloatingKeyboardNotificationProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new]; owner.session = session; session.owner = owner;
    session.config = [StashNativeCardConfig new]; session.initialContentRevealed = YES;
    StashFocusProbeWebView *web = [[StashFocusProbeWebView alloc] initWithFrame:CGRectZero];
    web.focusForKeyboardProbe = YES; session.webView = web;
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 744, 1133)];
    UIViewController *presenter = [UIViewController new]; window.rootViewController = presenter;
    session.presenter = presenter; window.hidden = NO;
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session; [presenter.view addSubview:controller.view];
    CGRect floating = [window convertRect:CGRectMake(190, 457, 334, 333.5) toCoordinateSpace:window.screen.coordinateSpace];
    NSNotification *hideFloating = [NSNotification notificationWithName:UIKeyboardWillHideNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:floating]}];
    session.keyboardVisible = YES; [controller keyboardChanged:hideFloating];
    BOOL floatingRemainsVisible = session.keyboardVisible;
    web.focusForKeyboardProbe = NO; [controller keyboardChanged:hideFloating];
    BOOL resignedFocusHides = !session.keyboardVisible;
    web.focusForKeyboardProbe = YES; session.keyboardVisible = YES;
    CGRect hidden = [window convertRect:CGRectMake(0, 1133, 744, 340) toCoordinateSpace:window.screen.coordinateSpace];
    [controller keyboardChanged:[NSNotification notificationWithName:UIKeyboardWillHideNotification object:window.screen
        userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:hidden]}]];
    BOOL offscreenHides = !session.keyboardVisible;
    BOOL semanticPreserved = !session.expanded;
    [session cleanup]; owner.session = nil; window.hidden = YES;
    return @{@"floatingRemainsVisible":@(floatingRemainsVisible), @"resignedFocusHides":@(resignedFocusHides),
        @"offscreenHides":@(offscreenHides), @"semanticPreserved":@(semanticPreserved)};
}

void StashFocusSettleProbe(void (^completion)(NSDictionary *)) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new];
    owner.session = session; session.owner = owner;
    session.config = [StashNativeCardConfig new];
    session.initialContentRevealed = YES;
    StashFocusProbeWebView *web = [[StashFocusProbeWebView alloc] initWithFrame:CGRectZero];
    web.focusForKeyboardProbe = YES;
    session.webView = web;
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 640, 700)];
    UIViewController *presenter = [UIViewController new];
    window.rootViewController = presenter; session.presenter = presenter;
    window.hidden = NO;
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session;
    [presenter.view addSubview:controller.view];
    session.keyboardVisible = YES;
    controller.keyboardEpisodeOwned = YES;
    controller.keyboardNotificationVisible = YES;
    controller.view.frame = CGRectMake(0, 0, 400, 500);
    [controller viewDidLayoutSubviews];
    controller.view.frame = CGRectMake(0, 0, 500, 180);
    [controller viewDidLayoutSubviews];
    [controller scheduleFocusReveal];
    web.scrollView.contentSize = web.bounds.size;
    web.scrollView.contentOffset = CGPointMake(0, -87);
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL finalViewport = web.repairs == 1 && CGSizeEqualToSize(web.repairedSize, web.bounds.size) &&
            CGPointEqualToPoint(web.repairedRootOffset, CGPointZero);
        [controller viewDidLayoutSubviews];
        [controller scheduleFocusReveal];
        session.keyboardVisible = NO;
        controller.keyboardEpisodeOwned = NO;
        controller.keyboardNotificationVisible = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL hideDiscardsRepair = web.repairs == 1;
            session.keyboardVisible = YES;
            controller.keyboardEpisodeOwned = YES;
            controller.keyboardNotificationVisible = YES;
            [controller scheduleFocusReveal];
            owner.session = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL closeDiscardsRepair = web.repairs == 1;
                [session cleanup];
                window.hidden = YES;
                completion(@{@"finalViewport":@(finalViewport), @"hideDiscardsRepair":@(hideDiscardsRepair),
                    @"closeDiscardsRepair":@(closeDiscardsRepair)});
            });
        });
    });
}

@interface StashWKContentProbeA : UIView
@property (nonatomic, strong) UIView *accessory;
@end
@implementation StashWKContentProbeA
- (UIView *)inputAccessoryView { return self.accessory; }
@end
@interface StashWKContentProbeB : UIView
@property (nonatomic, strong) UIView *accessory;
@end
@implementation StashWKContentProbeB
- (UIView *)inputAccessoryView { return self.accessory; }
@end

NSDictionary *StashInputAccessoryProbe(void) {
    WKWebView *web = [[WKWebView alloc] initWithFrame:CGRectZero];
    StashWKContentProbeA *first = [StashWKContentProbeA new]; first.accessory = [UIView new];
    StashWKContentProbeA *untouched = [StashWKContentProbeA new]; untouched.accessory = [UIView new];
    StashWKContentProbeB *second = [StashWKContentProbeB new]; second.accessory = [UIView new];
    UIBarButtonItemGroup *group = [[UIBarButtonItemGroup alloc] initWithBarButtonItems:@[
        [[UIBarButtonItem alloc] initWithTitle:@"Next" style:UIBarButtonItemStylePlain target:nil action:nil]] representativeItem:nil];
    for (UIResponder *responder in @[web, first, second, untouched]) {
        responder.inputAssistantItem.leadingBarButtonGroups = @[group];
        responder.inputAssistantItem.trailingBarButtonGroups = @[group];
    }
    [web.scrollView addSubview:first];
    UIView *wrapper = [UIView new]; [wrapper addSubview:second]; [web.scrollView addSubview:wrapper];
    StashRemoveFormInputAccessoryView(web);
    Class firstReplacement = object_getClass(first), secondReplacement = object_getClass(second);
    first.inputAssistantItem.leadingBarButtonGroups = @[group];
    StashRemoveFormInputAccessoryView(web);
    return @{@"hidden":@(!first.inputAccessoryView && !second.inputAccessoryView),
        @"assistantHidden":@(!web.inputAssistantItem.leadingBarButtonGroups.count &&
            !web.inputAssistantItem.trailingBarButtonGroups.count && !first.inputAssistantItem.leadingBarButtonGroups.count &&
            !first.inputAssistantItem.trailingBarButtonGroups.count && !second.inputAssistantItem.leadingBarButtonGroups.count &&
            !second.inputAssistantItem.trailingBarButtonGroups.count),
        @"assistantUntouched":@(untouched.inputAssistantItem.leadingBarButtonGroups.count == 1 &&
            untouched.inputAssistantItem.trailingBarButtonGroups.count == 1),
        @"untouched":@(untouched.inputAccessoryView == untouched.accessory),
        @"originalClasses":@(class_getSuperclass(firstReplacement) == StashWKContentProbeA.class &&
            class_getSuperclass(secondReplacement) == StashWKContentProbeB.class),
        @"idempotent":@(object_getClass(first) == firstReplacement && object_getClass(second) == secondReplacement)};
}

NSDictionary *StashFloatingKeyboardCoordinateProbe(void) {
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.config = [StashNativeCardConfig new];
    session.initialContentRevealed = YES; session.keyboardVisible = YES;
    session.webView = [[WKWebView alloc] initWithFrame:CGRectZero];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 640, 700)];
    UIViewController *presenter = [UIViewController new];
    window.rootViewController = presenter; session.presenter = presenter; window.hidden = NO;
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session;
    [presenter.view addSubview:controller.view];
    controller.view.frame = CGRectMake(50, 80, 500, 600);
    session.webView.frame = CGRectMake(20, 0, 480, 600);
    CGRect keyboardInWindow = CGRectMake(100, 300, 334, 333.5);
    controller.keyboardEpisodeOwned = YES;
    controller.keyboardNotificationVisible = YES;
    StashSetKeyboardNotificationContext(controller, window);
    controller.keyboardFrame = [window convertRect:keyboardInWindow toCoordinateSpace:window.screen.coordinateSpace];
    NSArray *floating = [controller focusKeyboardOcclusion];
    session.webView.frame = CGRectMake(20, 0, 480, 200);
    BOOL clippedDockedExcluded = [controller focusKeyboardOcclusion] == nil;
    session.webView.frame = CGRectMake(20, 0, 480, 600);
    session.keyboardVisible = NO;
    BOOL hiddenExcluded = [controller focusKeyboardOcclusion] == nil;
    session.keyboardVisible = YES;
    [session.webView removeFromSuperview];
    BOOL detachedExcluded = [controller focusKeyboardOcclusion] == nil;
    [session cleanup]; window.hidden = YES;
    return @{@"floating":floating ?: @[], @"clippedDockedExcluded":@(clippedDockedExcluded),
        @"hiddenExcluded":@(hiddenExcluded), @"detachedExcluded":@(detachedExcluded)};
}

@interface StashChromeProbeWindow : UIWindow
@end
@implementation StashChromeProbeWindow
- (UIEdgeInsets)safeAreaInsets { return UIEdgeInsetsZero; }
@end
@interface StashChromeProbeView : UIView
@end
@implementation StashChromeProbeView
- (UIEdgeInsets)safeAreaInsets { return UIEdgeInsetsZero; }
@end
@interface StashChromeProbeController : StashCheckoutViewController
@end
@implementation StashChromeProbeController
- (void)loadView { self.view = [[StashChromeProbeView alloc] init]; }
@end

static BOOL StashMaterialOverWebHeader(StashCheckoutViewController *controller, WKWebView *web) {
    CGRect header = CGRectMake(CGRectGetMidX(web.frame) - 36, CGRectGetMinY(web.frame), 72, 24);
    BOOL aboveWeb = NO;
    for (UIView *view in controller.view.subviews) {
        if (view == web) { aboveWeb = YES; continue; }
        if (aboveWeb && !view.hidden && view.alpha > 0.01 &&
            [view isKindOfClass:UIVisualEffectView.class] && CGRectIntersectsRect(view.frame, header)) return YES;
    }
    return NO;
}

NSDictionary *StashNativeGrabberContentProbe(void) {
    if (@available(iOS 16.0, *)) {
        StashCheckoutSession *session = [StashCheckoutSession new];
        session.config = [StashNativeCardConfig new]; session.initialContentRevealed = YES;
        session.webView = [[WKWebView alloc] initWithFrame:CGRectZero];
        UIWindow *window = [[StashChromeProbeWindow alloc] initWithFrame:CGRectMake(0, 0, 800, 900)];
        UIViewController *presenter = [UIViewController new];
        window.rootViewController = presenter; session.presenter = presenter; window.hidden = NO;
        StashCheckoutViewController *controller = [StashChromeProbeController new];
        session.controller = controller; controller.session = session;
        [controller configurePresentation]; [presenter.view addSubview:controller.view];
        [controller.spinner stopAnimating];
        controller.view.frame = CGRectMake(0, 0, 450, 484); [controller viewDidLayoutSubviews];
        BOOL headerClear = !StashMaterialOverWebHeader(controller, session.webView);
        BOOL nativeVisible = controller.sheetPresentationController.prefersGrabberVisible;
        BOOL centered = YES;
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
        if (@available(iOS 27.0, *)) {
            centered = controller.sheetPresentationController.preferredPlacement == UISheetPresentationControllerPlacementCenter;
            controller.sheetPresentationController.preferredPlacement = UISheetPresentationControllerPlacementLeading;
            [controller updatePresentationAnimated:NO];
            centered &= controller.sheetPresentationController.preferredPlacement == UISheetPresentationControllerPlacementCenter;
        }
#endif
        UIView *hit = [controller.view hitTest:CGPointMake(225, 20) withEvent:nil];
        BOOL webReceivesInput = hit == session.webView || [hit isDescendantOfView:session.webView];
        CGRect webFrame = session.webView.frame;
        NSArray *detents = controller.sheetPresentationController.detents;
        NSString *selected = controller.sheetPresentationController.selectedDetentIdentifier;
        [controller viewDidLayoutSubviews];
        BOOL unchanged = CGRectEqualToRect(webFrame, session.webView.frame) && CGRectEqualToRect(webFrame, controller.view.bounds) &&
            UIEdgeInsetsEqualToEdgeInsets(session.webView.scrollView.contentInset, UIEdgeInsetsZero) &&
            [controller.sheetPresentationController.detents isEqual:detents] &&
            [controller.sheetPresentationController.selectedDetentIdentifier isEqual:selected] && !session.expanded;
        session.processing = YES; [controller updateDismissalPolicy];
        BOOL hiddenWhileProcessing = !controller.sheetPresentationController.prefersGrabberVisible && controller.modalInPresentation;
        session.processing = NO; [controller updateDismissalPolicy];
        BOOL restored = controller.sheetPresentationController.prefersGrabberVisible && !controller.modalInPresentation;
        controller.view.frame = CGRectMake(0, 0, 640, 700); [controller viewDidLayoutSubviews];
        BOOL resizedClear = !StashMaterialOverWebHeader(controller, session.webView) &&
            CGRectEqualToRect(session.webView.frame, controller.view.bounds);
        [session cleanup]; window.hidden = YES;
        return @{@"headerClear":@(headerClear), @"centered":@(centered), @"nativeVisible":@(nativeVisible),
            @"webReceivesInput":@(webReceivesInput), @"unchanged":@(unchanged),
            @"hiddenWhileProcessing":@(hiddenWhileProcessing), @"restored":@(restored),
            @"resizedClear":@(resizedClear)};
    }
    return @{};
}

NSDictionary *StashChromeSurfaceGeometryProbe(CGRect bounds, BOOL expanded, CGFloat measured,
    CGFloat preferred, CGFloat maximum) {
    StashNativeCardConfig *config = [StashNativeCardConfig new];
    config.preferredContentHeight = preferred; config.maximumContentHeight = maximum;
    StashPresentationGeometry geometry = StashResolveGeometry(bounds, config, expanded, measured);
    return @{@"frame":[NSValue valueWithCGRect:geometry.frame], @"resting":@(geometry.restingContentHeight),
        @"expanded":@(geometry.expandedContentHeight)};
}

NSDictionary *StashChromeContentFixture(WKWebView *web, UIViewController *presenter, CGFloat measured) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new];
    owner.session = session; session.owner = owner; session.presenter = presenter;
    session.config = [StashNativeCardConfig new]; session.measuredContentHeight = measured;
    session.webView = web; session.initialContentRevealed = YES;
    StashCheckoutViewController *controller = [StashChromeProbeController new];
    session.controller = controller; controller.session = session;
    [controller configurePresentation];
    [presenter.view addSubview:controller.view]; [controller.spinner stopAnimating];
    CGFloat height = [controller contentHeightForMaximum:800 expanded:NO];
    controller.view.frame = CGRectMake(30, 50, 390, height);
    [controller viewDidLayoutSubviews];
    controller.previousWidth = web.bounds.size.width;
    return @{@"owner":owner, @"session":session, @"controller":controller,
        @"height":@(height), @"webFrame":[NSValue valueWithCGRect:web.frame]};
}

CGRect StashChromeProcessingFrame(NSDictionary *fixture, BOOL processing) {
    StashCheckoutSession *session = fixture[@"session"];
    StashCheckoutViewController *controller = fixture[@"controller"];
    session.processing = processing; [controller updateDismissalPolicy]; [controller viewDidLayoutSubviews];
    return session.webView.frame;
}

void StashEndChromeContentFixture(NSDictionary *fixture) {
    StashCheckoutViewController *controller = fixture[@"controller"];
    [controller.view removeFromSuperview];
    [(StashNativeCard *)fixture[@"owner"] resetPresentationState];
}

void StashEnableChromeFixtureProbe(NSDictionary *fixture) {
    StashCheckoutSession *session = fixture[@"session"];
    session.loaded = YES;
    [session installTopChromeProbe:session.webView.configuration.userContentController];
    session.webView.navigationDelegate = session;
}
UIColor *StashChromeFixtureInferredColor(NSDictionary *fixture) {
    return ((StashCheckoutViewController *)fixture[@"controller"]).topChromeColor;
}

UIColor *StashChromeFixtureBackingColor(NSDictionary *fixture) {
    StashCheckoutSession *session = fixture[@"session"];
    SEL selector = NSSelectorFromString(@"inferredPageBackingApplied");
    BOOL applied = [session respondsToSelector:selector] && ((BOOL (*)(id,SEL))[session methodForSelector:selector])(session, selector);
    return applied ? session.webView.underPageBackgroundColor : nil;
}


@interface StashKeyboardRectangleProbeView : StashKeyboardGuideProbeView
@end
@implementation StashKeyboardRectangleProbeView
- (UIEdgeInsets)safeAreaInsets { return UIEdgeInsetsZero; }
@end
@interface StashKeyboardRectangleProbeController : StashCheckoutViewController
@end
@implementation StashKeyboardRectangleProbeController
- (void)viewDidLoad {}
- (UIView *)layoutContainer { return self.view.window; }
- (void)updatePresentationAnimated:(BOOL)animated {}
- (void)scheduleFocusReveal {}
@end

void StashSetKeyboardNotificationContext(id controller, UIWindow *window) {
    // Keep the same regression Tests buildable against the unfixed SDK for negative proof.
    if (![controller respondsToSelector:NSSelectorFromString(@"setKeyboardNotificationWindow:")]) return;
    [controller setValue:window forKey:@"keyboardNotificationWindow"];
    [controller setValue:[NSValue valueWithCGRect:window.bounds] forKey:@"keyboardNotificationWindowBounds"];
    UIInterfaceOrientation orientation;
    if (@available(iOS 26.0, *)) orientation = window.windowScene.effectiveGeometry.interfaceOrientation;
    else orientation = window.windowScene.interfaceOrientation;
    [controller setValue:@(orientation) forKey:@"keyboardNotificationOrientation"];
}

NSDictionary *StashKeyboardRectangleResolutionProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new]; owner.session = session; session.owner = owner;
    session.config = [StashNativeCardConfig new]; session.initialContentRevealed = YES;
    StashFocusProbeWebView *web = [[StashFocusProbeWebView alloc] initWithFrame:CGRectZero];
    web.focusForKeyboardProbe = YES; session.webView = web;
    UIWindow *window = [[StashKeyboardHostWindow alloc] initWithFrame:CGRectMake(0, 0, 1210, 834)];
    UIViewController *presenter = [UIViewController new]; window.rootViewController = presenter;
    session.presenter = presenter; window.hidden = NO;
    StashKeyboardRectangleProbeController *controller = [StashKeyboardRectangleProbeController new];
    controller.session = session; session.controller = controller;
    StashKeyboardRectangleProbeView *view = [[StashKeyboardRectangleProbeView alloc] initWithFrame:CGRectMake(315, 76, 580, 738)];
    StashKeyboardGuideProbe *guide = [StashKeyboardGuideProbe new]; view.probeGuide = guide; [view addLayoutGuide:guide];
    controller.view = view; [presenter.view addSubview:view]; [view addSubview:web];
    void (^notify)(CGRect, BOOL) = ^(CGRect inWindow, BOOL hide) {
        CGRect frame = [window convertRect:inWindow toCoordinateSpace:window.screen.coordinateSpace];
        [controller keyboardChanged:[NSNotification notificationWithName:hide ? UIKeyboardWillHideNotification : UIKeyboardWillChangeFrameNotification
            object:window.screen userInfo:@{UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:frame]}]];
    };
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    // Captured iPad: the notification is scaled/stale while the guide matches the visible docked keyboard.
    guide.probeFrame = CGRectMake(-315, 330, 1210, 428);
    notify(CGRectMake(0, 340.492561983471, 574.8396694214875, 234.3471074380165), NO);
    web.frame = CGRectMake(0, 16, 580, 722);
    result[@"ipadBeforeFocus"] = [controller focusKeyboardOcclusion] ?: @[];
    CGFloat nativeContainerBefore = CGRectGetMaxY([controller availableBoundsInView:window]);
    [controller viewDidLayoutSubviews];
    result[@"ipadHeight"] = @(web.bounds.size.height);
    result[@"ipadAvailableBottom"] = @(CGRectGetMaxY([controller availableBoundsInView:view]));
    result[@"ipadFocusClearedAfterClipping"] = @([controller focusKeyboardOcclusion] == nil);
    result[@"nativeContainerNotDoubleClipped"] = @(nativeContainerBefore == 814);
    // Captured Book: the current notification is taller than the lagging guide.
    window.frame = CGRectMake(0, 0, 951, 669); view.frame = CGRectMake(8, 0, 447.5, 661);
    guide.probeFrame = CGRectMake(-8, 397, 951, 264);
    notify(CGRectMake(0, 278.3333333333333, 951, 390.6666666666667), NO);
    web.frame = CGRectMake(0, 16, 447.5, 645);
    result[@"bookBeforeFocus"] = [controller focusKeyboardOcclusion] ?: @[];
    [controller viewDidLayoutSubviews]; result[@"bookHeight"] = @(web.bounds.size.height);
    result[@"bookFocusClearedAfterClipping"] = @([controller focusKeyboardOcclusion] == nil);
    // Captured native sheet: the equal-sized guide is anchored eight points above the window bottom.
    guide.probeFrame = CGRectMake(-8, 397, 951, 264);
    notify(CGRectMake(0, 405, 951, 264), NO);
    web.frame = CGRectMake(0, 16, 447.5, 645);
    result[@"insetGuideBeforeFocus"] = [controller focusKeyboardOcclusion] ?: @[];
    [controller viewDidLayoutSubviews]; result[@"insetGuideHeight"] = @(web.bounds.size.height);
    result[@"insetGuideAvailableBottom"] = @(CGRectGetMaxY([controller availableBoundsInView:view]));
    result[@"insetGuideFocusClearedAfterClipping"] = @([controller focusKeyboardOcclusion] == nil);
    // A shifted guide outside the bottom safe tail is not explained by native sheet padding.
    view.frame = CGRectMake(8, 0, 447.5, 630);
    guide.probeFrame = CGRectMake(-8, 366, 951, 264);
    notify(CGRectMake(0, 405, 951, 264), NO);
    [controller viewDidLayoutSubviews]; result[@"outsideSafeTailHeight"] = @(web.bounds.size.height);
    view.frame = CGRectMake(8, 0, 447.5, 661);
    // Matching dimensions alone do not override a guide not anchored to the content bottom.
    guide.probeFrame = CGRectMake(-8, 393, 951, 264);
    notify(CGRectMake(0, 405, 951, 264), NO);
    [controller viewDidLayoutSubviews]; result[@"unanchoredGuideHeight"] = @(web.bounds.size.height);
    result[@"unanchoredGuideFocus"] = [controller focusKeyboardOcclusion] ?: @[];
    // An earlier guide top remains protective against a later, smaller notification.
    guide.probeFrame = CGRectMake(-8, 260, 951, 409);
    notify(CGRectMake(0, 397, 951, 272), NO);
    [controller viewDidLayoutSubviews]; result[@"earlierGuideHeight"] = @(web.bounds.size.height);
    // An old notification cannot contribute after the owning window's bounds or orientation change.
    guide.probeFrame = CGRectMake(-8, 397, 951, 264);
    notify(CGRectMake(0, 278.3333333333333, 951, 390.6666666666667), NO);
    BOOL hasContext = [controller respondsToSelector:NSSelectorFromString(@"setKeyboardNotificationWindow:")];
    if (hasContext) [controller setValue:[NSValue valueWithCGRect:CGRectMake(0, 0, 669, 951)] forKey:@"keyboardNotificationWindowBounds"];
    [controller viewDidLayoutSubviews]; result[@"staleBoundsHeight"] = @(web.bounds.size.height);
    if (hasContext) {
        StashSetKeyboardNotificationContext(controller, window);
        NSInteger current = [[controller valueForKey:@"keyboardNotificationOrientation"] integerValue];
        [controller setValue:@(current == UIInterfaceOrientationPortraitUpsideDown
            ? UIInterfaceOrientationPortrait : UIInterfaceOrientationPortraitUpsideDown) forKey:@"keyboardNotificationOrientation"];
    }
    [controller viewDidLayoutSubviews]; result[@"staleOrientationHeight"] = @(web.bounds.size.height);
    // Early notification fallback, followed by a current floating guide that must never resize the card.
    controller.keyboardGuideWasVisible = NO;
    guide.probeFrame = CGRectMake(0, 661, 447.5, 0);
    notify(CGRectMake(0, 278.3333333333333, 951, 390.6666666666667), NO);
    [controller viewDidLayoutSubviews]; result[@"earlyNotificationHeight"] = @(web.bounds.size.height);
    guide.probeFrame = CGRectMake(20, 200, 334, 300);
    [controller viewDidLayoutSubviews]; result[@"floatingHeight"] = @(web.bounds.size.height);
    result[@"floatingOcclusion"] = [controller focusKeyboardOcclusion] ?: @[];
    notify(CGRectZero, YES);
    [controller viewDidLayoutSubviews];
    result[@"floatingHideStillVisible"] = @(session.keyboardVisible && [controller focusKeyboardOcclusion] != nil);
    guide.probeFrame = CGRectMake(0, 661, 447.5, 0);
    [controller viewDidLayoutSubviews];
    result[@"hiddenGuideEndsEpisode"] = @(!session.keyboardVisible && [controller focusKeyboardOcclusion] == nil);
    // No source is usable for a different destination window or an unowned/stopped episode.
    guide.probeFrame = CGRectMake(20, 200, 334, 300);
    notify(CGRectMake(28, 200, 334, 300), NO);
    controller.keyboardEpisodeOwned = NO;
    result[@"unownedExcluded"] = @([controller focusKeyboardOcclusion] == nil);
    controller.keyboardEpisodeOwned = YES;
    UIWindow *other = [[UIWindow alloc] initWithFrame:window.bounds]; [other addSubview:web];
    result[@"foreignWindowExcluded"] = @([controller focusKeyboardOcclusion] == nil);
    [view addSubview:web]; session.keyboardVisible = NO;
    result[@"hiddenExcluded"] = @([controller focusKeyboardOcclusion] == nil);
    // Captured iPad mini docked and split states from the same checkout document.
    window.frame = CGRectMake(0, 0, 744, 1133);
    view.frame = CGRectMake(172, 42, 400, 740);
    guide.probeFrame = CGRectMake(-172, 740, 744, 351);
    notify(CGRectMake(0, 793, 744, 340), NO);
    [controller viewDidLayoutSubviews];
    result[@"capturedDockedHeight"] = @(web.bounds.size.height);
    result[@"capturedDockedClassified"] = @(!controller.keyboardGuideUndocked);
    view.frame = CGRectMake(172, 196.5, 400, 740);
    guide.probeFrame = CGRectMake(-172, 589.5, 744, 336);
    notify(CGRectMake(0, 786, 744, 336), NO);
    [controller viewDidLayoutSubviews];
    result[@"capturedSplitHeight"] = @(web.bounds.size.height);
    result[@"capturedSplitUndocked"] = @(controller.keyboardGuideUndocked);
    result[@"capturedSplitOcclusion"] = [controller focusKeyboardOcclusion] ?: @[];
    result[@"capturedSplitNoDockedCrop"] = @(CGRectIsNull([controller resolvedKeyboardFrameInView:web dockedOnly:YES]));
    // Returning to the captured docked state must retain the full card and current ownership.
    view.frame = CGRectMake(172, 42, 400, 740);
    guide.probeFrame = CGRectMake(-172, 740, 744, 351);
    notify(CGRectMake(0, 793, 744, 340), NO);
    [controller viewDidLayoutSubviews];
    result[@"capturedRedockedHeight"] = @(web.bounds.size.height);
    result[@"capturedRedockedOwned"] = @(!controller.keyboardGuideUndocked && controller.keyboardEpisodeOwned && session.keyboardVisible);
    [session cleanup]; owner.session = nil; window.hidden = YES;
    return result;
}
