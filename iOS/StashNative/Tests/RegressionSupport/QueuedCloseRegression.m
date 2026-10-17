#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativePrivate.h"

@interface StashProbeDelegate : NSObject <StashNativeDelegate>
@property NSInteger successes;
@property NSInteger failures;
@property NSInteger dismissals;
@property NSInteger networkErrors;
@property (nonatomic, strong) NSMutableArray<NSString *> *events;
@property BOOL closedBeforeNetworkCallback;
@property (nonatomic, strong) StashNative *owner;
@end
@implementation StashProbeDelegate
- (void)stashNativeDidCompletePaymentWithOrder:(NSString *)order { self.successes++; }
- (void)stashNativeDidFailPayment { self.failures++; }
- (void)stashNativeDidDismissCard { self.dismissals++; [self.events addObject:@"dismiss"]; }
- (void)stashNativeDidDismissBrowser { [self.events addObject:@"browser"]; }
- (void)stashNativeDidEncounterNetworkError {
    self.networkErrors++;
    self.closedBeforeNetworkCallback = !self.owner.isCurrentlyPresented;
}
@end

static StashCheckoutSession *newSession(StashNative *owner) {
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.owner = owner;
    session.config = [StashNativeCardConfig new];
    owner.session = session;
    return session;
}
NSDictionary *StashCallbackProbe(void) {
    StashNative *owner = [StashNative new];
    StashProbeDelegate *delegate = [StashProbeDelegate new];
    delegate.owner = owner; owner.delegate = delegate;
    StashCheckoutSession *session = newSession(owner);
    session.config.allowDismiss = NO;
    session.config.autoClose = NO;
    [session paymentSucceeded:NO order:nil];
    [session paymentSucceeded:YES order:@"order"];
    BOOL retryRemainsOpen = owner.isCurrentlyPresented;
    session.config.autoClose = YES;
    [session paymentSucceeded:YES order:@"order"];
    [session paymentSucceeded:YES order:@"duplicate"];
    BOOL closedAfterSuccess = !owner.isCurrentlyPresented;
    StashCheckoutSession *failed = newSession(owner);
    failed.config.allowDismiss = NO;
    failed.processing = YES;
    [failed handleMessage:@"stashNativementFailure" body:@{}];
    [failed handleMessage:@"stashNativementFailure" body:@{}];
    BOOL closedAfterFailure = !owner.isCurrentlyPresented;
    StashCheckoutSession *network = newSession(owner);
    network.config.allowDismiss = NO;
    [network networkFailed];
    return @{@"successes":@(delegate.successes), @"failures":@(delegate.failures), @"dismissals":@(delegate.dismissals),
        @"retryRemainsOpen":@(retryRemainsOpen), @"closedAfterSuccess":@(closedAfterSuccess),
        @"closedAfterFailure":@(closedAfterFailure),
        @"networkErrors":@(delegate.networkErrors), @"closedBeforeNetworkCallback":@(delegate.closedBeforeNetworkCallback)};
}
void StashQueuedCloseProbe(NSString *source, BOOL replace, BOOL processing, BOOL allowDismiss, void (^completion)(BOOL, NSInteger)) {
    StashNative *owner = [StashNative new];
    StashProbeDelegate *delegate = [StashProbeDelegate new];
    owner.delegate = delegate;
    StashCheckoutSession *session = newSession(owner);
    session.config.allowDismiss = allowDismiss;
    for (NSInteger attempt = 0; attempt < 2; attempt++) {
        if ([source isEqualToString:@"window"]) [session webViewDidClose:session.webView];
        else if ([source isEqualToString:@"cancel"])
            [session handlePaymentResultURL:[NSURL URLWithString:@"testapp://stash-pay/cancel"]];
        else [session handleMessage:@"stashWindowClose" body:@{}];
    }
    if (processing) [session handleMessage:@"stashPurchaseProcessing" body:@{}];
    if (replace) newSession(owner);
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(owner.isCurrentlyPresented, delegate.dismissals);
        [owner dismiss];
    });
}

NSDictionary *StashLifecycleProbe(void) {
    StashNative *owner = [StashNative new];
    StashProbeDelegate *delegate = [StashProbeDelegate new];
    delegate.owner = owner; owner.delegate = delegate;
    delegate.events = [NSMutableArray array];
    StashCheckoutSession *dismissed = newSession(owner);
    dismissed.config.allowDismiss = NO;
    dismissed.processing = YES;
    __block NSInteger dialogCompletions = 0;
    dismissed.dialogCompletion = ^(id value) { dialogCompletions++; };
    [owner dismiss];
    [dismissed completeDialog:@YES];
    [owner dismiss];
    BOOL once = delegate.dismissals == 1 && dialogCompletions == 1;
    StashCheckoutSession *reset = newSession(owner);
    reset.dialogCompletion = ^(id value) { dialogCompletions++; };
    [owner resetPresentationState];
    BOOL silent = delegate.dismissals == 1 && !owner.isCurrentlyPresented && dialogCompletions == 2;
    [delegate.events removeAllObjects];
    StashCheckoutSession *browser = newSession(owner);
    [browser browserClosed];
    [browser browserClosed];
    BOOL browserOrder = [delegate.events isEqualToArray:@[@"browser"]];
    [delegate.events removeAllObjects];
    StashCheckoutSession *userBrowser = newSession(owner);
    userBrowser.browser = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString:@"https://example.invalid"]];
    [userBrowser safariViewControllerDidFinish:userBrowser.browser];
    BOOL userBrowserOrder = [delegate.events isEqualToArray:@[@"browser"]];
    StashCheckoutSession *retired = newSession(owner);
    [owner resetPresentationState];
    StashCheckoutSession *replacement = newSession(owner);
    [retired networkFailed];
    [retired paymentSucceeded:YES order:nil];
    BOOL replacementSurvived = owner.session == replacement && delegate.networkErrors == 0 && delegate.successes == 0;
    replacement.config.autoClose = NO;
    BOOL webResultIgnored = ![replacement handlePaymentResultURL:[NSURL URLWithString:@"https://example.invalid/stash-pay/success"]] && delegate.successes == 0;
    BOOL appResultHandled = [replacement handlePaymentResultURL:[NSURL URLWithString:@"testapp://stash-pay/success"]] && delegate.successes == 1;
    [owner resetPresentationState];
    return @{@"dismissOnce":@(once), @"resetSilent":@(silent), @"browserOrder":@(browserOrder),
        @"userBrowserOrder":@(userBrowserOrder), @"replacementSurvived":@(replacementSurvived),
        @"webResultIgnored":@(webResultIgnored), @"appResultHandled":@(appResultHandled)};
}
@interface StashCheckoutViewController (GestureTest)
- (void)nativePanChanged:(UIPanGestureRecognizer *)gesture;
@end
@interface StashCancelledPan : UIPanGestureRecognizer
@end
@implementation StashCancelledPan
- (UIGestureRecognizerState)state { return UIGestureRecognizerStateCancelled; }
- (CGPoint)translationInView:(UIView *)view { return CGPointMake(0, -300); }
- (CGPoint)velocityInView:(UIView *)view { return CGPointMake(0, -600); }
@end
NSDictionary *StashPresentationStateProbe(void) {
    StashNative *owner = [StashNative new];
    StashCheckoutSession *session = newSession(owner);
    UIViewController *presenter = [UIViewController new];
    presenter.view.frame = CGRectMake(0, 0, 390, 300);
    session.presenter = presenter;
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session;
    [controller configurePresentation];
    BOOL shortSingle;
    if (@available(iOS 16.0, *)) shortSingle = controller.sheetPresentationController.detents.count == 1;
    else shortSingle = controller.sheetPresentationController.detents.count == 2;
    [session setExpanded:YES animated:NO];
    BOOL semantic = session.expanded;
    presenter.view.frame = CGRectMake(0, 0, 390, 1000);
    [controller updatePresentationAnimated:NO];
    BOOL restoredExpanded = session.expanded && controller.sheetPresentationController.detents.count == 2 &&
        [controller.sheetPresentationController.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:YES]];
    session.keyboardVisible = YES;
    [session handleMessage:@"stashCollapse" body:@{}];
    BOOL keyboardOverride = !session.expanded &&
        [controller.sheetPresentationController.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:YES]];
    session.keyboardVisible = NO;
    [controller updatePresentationAnimated:NO];
    BOOL restoredResting = [controller.sheetPresentationController.selectedDetentIdentifier isEqualToString:[controller nativeDetentIdentifierForExpanded:NO]];
    controller.dragging = YES;
    [controller contentHeightDidChange];
    BOOL deferred = controller.deferredContentLayout;
    StashCancelledPan *pan = [StashCancelledPan new];
    [controller nativePanChanged:pan];
    BOOL cancelledPreservesResting = !session.expanded && !controller.dragging;
    [owner resetPresentationState];
    return @{@"shortSingle":@(shortSingle), @"semantic":@(semantic), @"restoredExpanded":@(restoredExpanded),
        @"keyboardOverride":@(keyboardOverride), @"restoredResting":@(restoredResting), @"deferred":@(deferred), @"cancelledPreservesResting":@(cancelledPreservesResting)};
}
@interface StashCheckoutSession (ScrollTest)
- (void)rootScrollPanChanged:(UIPanGestureRecognizer *)gesture;
@end
@interface StashScrollProbePan : UIPanGestureRecognizer
@property (nonatomic) UIGestureRecognizerState probeState;
@property (nonatomic) CGPoint probeVelocity;
@property (nonatomic) CGPoint probeTranslation;
@end
@implementation StashScrollProbePan
- (UIGestureRecognizerState)state { return self.probeState; }
- (CGPoint)velocityInView:(UIView *)view { return self.probeVelocity; }
- (CGPoint)translationInView:(UIView *)view { return self.probeTranslation; }
@end
@interface StashScrollProbeTouch : UITouch
@property (nonatomic, strong) UIView *origin;
@end
@implementation StashScrollProbeTouch
- (UIView *)view { return self.origin; }
@end

NSDictionary *StashContentPanPolicyProbe(void) {
    StashNative *owner = [StashNative new];
    StashCheckoutSession *session = newSession(owner);
    UIViewController *presenter = [UIViewController new];
    presenter.view.frame = CGRectMake(0, 0, 390, 1000);
    session.presenter = presenter;
    session.webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 390, 560)];
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session;
    [controller configurePresentation];
    StashScrollProbePan *pan = [StashScrollProbePan new];
    controller.contentPan = pan; [session.webView addGestureRecognizer:pan];
    UIScrollView *nested = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, 390, 500)];
    nested.contentSize = CGSizeMake(390, 1000);
    [session.webView.scrollView addSubview:nested];
    UIView *content = [UIView new]; [nested addSubview:content];
    StashScrollProbeTouch *touch = [StashScrollProbeTouch new]; touch.origin = content;
    [controller gestureRecognizer:pan shouldReceiveTouch:touch];
    session.expanded = YES;
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    pan.probeVelocity = CGPointMake(0, 300);
    result[@"topPullOwned"] = @([controller gestureRecognizerShouldBegin:pan]);
    nested.contentOffset = CGPointMake(0, 150);
    result[@"nestedDownScrolls"] = @(![controller gestureRecognizerShouldBegin:pan]);
    pan.probeVelocity = CGPointMake(0, -300);
    result[@"nestedUpScrolls"] = @(![controller gestureRecognizerShouldBegin:pan]);
    nested.contentOffset = CGPointMake(0, 500);
    result[@"bottomPullOwned"] = @([controller gestureRecognizerShouldBegin:pan]);
    pan.probeVelocity = CGPointMake(300, -20);
    result[@"horizontalPasses"] = @(![controller gestureRecognizerShouldBegin:pan]);
    nested.contentOffset = CGPointMake(0, 150); pan.probeVelocity = CGPointMake(0, -300);
    session.expanded = NO;
    if (@available(iOS 16.0, *)) {
        result[@"collapsedUpOwnsNestedScroll"] = @([controller gestureRecognizerShouldBegin:pan] &&
            pan.cancelsTouchesInView && !controller.sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge);
    } else {
        result[@"collapsedUpUsesSystemStops"] = @(![controller gestureRecognizerShouldBegin:pan] &&
            controller.sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge);
    }
    session.keyboardVisible = YES;
    [controller gestureRecognizer:pan shouldReceiveTouch:touch];
    result[@"keyboardContentScrolls"] = @(![controller gestureRecognizerShouldBegin:pan] && !pan.cancelsTouchesInView);
    result[@"rootAndNestedObserved"] = @([controller.contentScrollPans containsObject:session.webView.scrollView.panGestureRecognizer] &&
        [controller.contentScrollPans containsObject:nested.panGestureRecognizer]);
    UITapGestureRecognizer *tap = [UITapGestureRecognizer new]; [content addGestureRecognizer:tap];
    pan.probeVelocity = CGPointZero;
    result[@"webTapsPreserved"] = @(![controller gestureRecognizerShouldBegin:pan] &&
        [controller gestureRecognizer:pan shouldBeRequiredToFailByGestureRecognizer:tap]);
    UILongPressGestureRecognizer *press = [UILongPressGestureRecognizer new]; [content addGestureRecognizer:press];
    BOOL editing = [controller gestureRecognizer:pan shouldRecognizeSimultaneouslyWithGestureRecognizer:press];
    session.keyboardVisible = NO;
    result[@"pressDoesNotActivateDuringExpansion"] = @(editing &&
        [controller gestureRecognizer:pan shouldBeRequiredToFailByGestureRecognizer:press] &&
        ![controller gestureRecognizer:pan shouldRecognizeSimultaneouslyWithGestureRecognizer:press]);
    [owner resetPresentationState];
    return result;
}

NSDictionary *StashContentExpansionProbe(void) {
    StashNative *owner = [StashNative new];
    StashCheckoutSession *session = newSession(owner);
    UIViewController *presenter = [UIViewController new];
    presenter.view.frame = CGRectMake(0, 0, 390, 1000);
    session.presenter = presenter;
    session.webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 390, 560)];
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session;
    [controller configurePresentation]; [controller loadViewIfNeeded];
    StashScrollProbePan *pan = [StashScrollProbePan new];
    [controller.contentPan.view removeGestureRecognizer:controller.contentPan];
    controller.contentPan = pan; [session.webView addGestureRecognizer:pan];
    CGFloat maximum = 950;
    CGFloat resting = [controller resolvedNativeHeightForMaximum:maximum expanded:NO];
    CGFloat expanded = [controller resolvedNativeHeightForMaximum:maximum expanded:YES];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    void (^move)(UIGestureRecognizerState, CGFloat, CGFloat) = ^(UIGestureRecognizerState state, CGFloat translation, CGFloat velocity) {
        pan.probeState = state; pan.probeTranslation = CGPointMake(0, translation);
        pan.probeVelocity = CGPointMake(0, velocity); [controller nativePanChanged:pan];
    };
    move(UIGestureRecognizerStateBegan, 0, -100);
    move(UIGestureRecognizerStateChanged, -40, -100);
    result[@"partialHeight"] = @(controller.contentExpansionActive && !session.expanded &&
        fabs([controller resolvedNativeHeightForMaximum:maximum expanded:NO] - resting - 40) < 0.5);
    move(UIGestureRecognizerStateChanged, 20, 100);
    result[@"reversalStopsAtResting"] = @(!session.expanded &&
        fabs([controller resolvedNativeHeightForMaximum:maximum expanded:NO] - resting) < 0.5);
    move(UIGestureRecognizerStateChanged, -2000, -100);
    result[@"maximumClamp"] = @(!session.expanded &&
        fabs([controller resolvedNativeHeightForMaximum:maximum expanded:NO] - expanded) < 0.5);
    move(UIGestureRecognizerStateCancelled, -2000, 0);
    result[@"cancelRestoresResting"] = @(!controller.contentExpansionActive && !session.expanded &&
        fabs([controller resolvedNativeHeightForMaximum:maximum expanded:NO] - resting) < 0.5);
    move(UIGestureRecognizerStateBegan, 0, -100);
    move(UIGestureRecognizerStateChanged, -20, -100);
    move(UIGestureRecognizerStateEnded, -20, 0);
    result[@"shortPullSettlesBack"] = @(!controller.contentExpansionActive && !session.expanded);
    move(UIGestureRecognizerStateBegan, 0, -100);
    move(UIGestureRecognizerStateChanged, resting - expanded, -100);
    move(UIGestureRecognizerStateEnded, resting - expanded, 0);
    result[@"longPullSettlesExpanded"] = @(!controller.contentExpansionActive && session.expanded &&
        [controller nativeSelectionIsExpanded]);
    move(UIGestureRecognizerStateBegan, 0, 100);
    move(UIGestureRecognizerStateEnded, 200, 100);
    result[@"expandedDownDoesNotCollapse"] = @(session.expanded && [controller nativeSelectionIsExpanded]);
    [session setExpanded:NO animated:NO];
    move(UIGestureRecognizerStateBegan, 0, -100);
    move(UIGestureRecognizerStateChanged, -30, -100);
    [session setExpanded:YES animated:NO];
    result[@"explicitExpansionCancelsDrag"] = @(!controller.contentExpansionActive && session.expanded);
    move(UIGestureRecognizerStateCancelled, -30, 0);
    [session setExpanded:NO animated:NO];
    move(UIGestureRecognizerStateBegan, 0, -100);
    move(UIGestureRecognizerStateChanged, -30, -100);
    [session handleMessage:@"stashPurchaseProcessing" body:@{}];
    result[@"processingCancelsDrag"] = @(!controller.contentExpansionActive && session.processing);
    move(UIGestureRecognizerStateCancelled, -30, 0);
    session.processing = NO;
    move(UIGestureRecognizerStateBegan, 0, -100);
    session.keyboardVisible = YES; [controller cancelContentExpansion];
    result[@"keyboardKeepsExpandedSelection"] = @(!controller.contentExpansionActive && !session.expanded &&
        [controller nativeSelectionIsExpanded]);
    [owner resetPresentationState];
    return result;
}

void StashScrollInteractionProbe(void (^completion)(NSDictionary *)) {
    StashNative *owner = [StashNative new];
    StashCheckoutSession *session = newSession(owner);
    UIViewController *presenter = [UIViewController new];
    presenter.view.frame = CGRectMake(0, 0, 390, 1000);
    session.presenter = presenter;
    session.webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 390, 560)];
    StashCheckoutViewController *controller = [StashCheckoutViewController new];
    session.controller = controller; controller.session = session;
    [controller configurePresentation];
    controller.touchOriginObserver = [UITapGestureRecognizer new];
    StashScrollProbeTouch *touch = [StashScrollProbeTouch new];
    UIView *content = [UIView new]; [session.webView addSubview:content]; touch.origin = content;
    BOOL recognized = [controller gestureRecognizer:controller.touchOriginObserver shouldReceiveTouch:touch];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"bodyBlocks"] = @(!recognized && controller.modalInPresentation &&
        ![session presentationControllerShouldDismiss:controller.presentationController]);
    UIPresentationController *browser = [[UIPresentationController alloc]
        initWithPresentedViewController:[UIViewController new] presentingViewController:controller];
    result[@"browserPreserved"] = @([session presentationControllerShouldDismiss:browser]);
    touch.origin = presenter.view;
    recognized = [controller gestureRecognizer:controller.touchOriginObserver shouldReceiveTouch:touch];
    result[@"headerAllows"] = @(!recognized && !controller.modalInPresentation &&
        [session presentationControllerShouldDismiss:controller.presentationController]);
    session.processing = YES; [controller updateDismissalPolicy];
    result[@"processingBlocks"] = @(controller.modalInPresentation &&
        ![session presentationControllerShouldDismiss:controller.presentationController]);
    session.processing = NO; session.config.allowDismiss = NO; [controller updateDismissalPolicy];
    result[@"configBlocks"] = @(controller.modalInPresentation &&
        ![session presentationControllerShouldDismiss:controller.presentationController]);
    session.config.allowDismiss = YES; [controller updateDismissalPolicy];
    StashScrollProbePan *webPan = [StashScrollProbePan new], *nativePan = [StashScrollProbePan new];
    controller.observedPans = [NSMutableArray arrayWithObjects:webPan, nativePan, nil];
    webPan.probeState = UIGestureRecognizerStateBegan;
    [session rootScrollPanChanged:webPan];
    result[@"scrollTracked"] = @(controller.dragging);
    session.pendingContentHeight = 350; session.pendingNativeWidth = 390; session.hasPendingContentHeight = YES;
    NSArray *detents = controller.sheetPresentationController.detents;
    [controller contentHeightDidChange]; [controller updatePresentationAnimated:NO];
    result[@"detentsDeferred"] = @(controller.deferredContentLayout && session.measuredContentHeight == 0 &&
        [controller.sheetPresentationController.detents isEqual:detents]);
    nativePan.probeState = UIGestureRecognizerStateBegan; [controller nativePanChanged:nativePan];
    nativePan.probeState = UIGestureRecognizerStateCancelled; [controller nativePanChanged:nativePan];
    result[@"overlapTracked"] = @(controller.dragging && session.hasPendingContentHeight);
    webPan.probeState = UIGestureRecognizerStateCancelled; [session rootScrollPanChanged:webPan];
    result[@"cancelledNotCollapsed"] = @(!controller.dragging && !session.expanded);
    dispatch_async(dispatch_get_main_queue(), ^{
        result[@"pendingAfterBoth"] = @(!session.hasPendingContentHeight && session.measuredContentHeight == 350 &&
            !controller.deferredContentLayout && !controller.dragging);
        [owner resetPresentationState]; completion(result);
    });
}

@interface StashNative (SnapshotTest)
- (void)openURL:(NSString *)url presenter:(UIViewController *)presenter
    config:(StashNativeCardConfig *)config browser:(BOOL)browser;
@end
@interface StashSnapshotCard : StashNative
@property double receivedWidth;
@end
@implementation StashSnapshotCard
- (void)openURL:(NSString *)url presenter:(UIViewController *)presenter
    config:(StashNativeCardConfig *)config browser:(BOOL)browser {
    if (NSThread.isMainThread) self.receivedWidth = config.preferredContentWidth;
    else [super openURL:url presenter:presenter config:config browser:browser];
}
@end
void StashConfigSnapshotProbe(void (^completion)(double)) {
    StashSnapshotCard *owner = [StashSnapshotCard new];
    StashNativeCardConfig *config = [StashNativeCardConfig new];
    config.preferredContentWidth = 432;
    UIViewController *presenter = [UIViewController new];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [owner openCardWithURL:@"https://example.invalid" fromViewController:presenter config:config];
        config.preferredContentWidth = 999;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(owner.receivedWidth); });
    });
}
