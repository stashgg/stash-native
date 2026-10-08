#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativeCardPrivate.h"

@interface StashProbeDelegate : NSObject <StashNativeCardDelegate>
@property NSInteger successes;
@property NSInteger failures;
@property NSInteger dismissals;
@property NSInteger networkErrors;
@property (nonatomic, strong) NSMutableArray<NSString *> *events;
@property BOOL closedBeforeNetworkCallback;
@property (nonatomic, strong) StashNativeCard *owner;
@end
@implementation StashProbeDelegate
- (void)stashNativeCardDidCompletePaymentWithOrder:(NSString *)order { self.successes++; }
- (void)stashNativeCardDidFailPayment { self.failures++; }
- (void)stashNativeCardDidDismiss { self.dismissals++; [self.events addObject:@"dismiss"]; }
- (void)stashNativeCardDidCloseBrowser { [self.events addObject:@"browser"]; }
- (void)stashNativeCardDidEncounterNetworkError {
    self.networkErrors++;
    self.closedBeforeNetworkCallback = !self.owner.isCurrentlyPresented;
}
@end

static StashCheckoutSession *newSession(StashNativeCard *owner) {
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.owner = owner;
    session.config = [StashNativeCardConfig new];
    owner.session = session;
    return session;
}
NSDictionary *StashCallbackProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashProbeDelegate *delegate = [StashProbeDelegate new];
    delegate.owner = owner; owner.delegate = delegate;
    StashCheckoutSession *session = newSession(owner);
    session.config.autoClose = NO;
    [session paymentSucceeded:NO order:nil];
    [session paymentSucceeded:YES order:@"order"];
    BOOL retryRemainsOpen = owner.isCurrentlyPresented;
    session.config.autoClose = YES;
    [session paymentSucceeded:YES order:@"order"];
    [session paymentSucceeded:YES order:@"duplicate"];
    BOOL closedAfterSuccess = !owner.isCurrentlyPresented;
    StashCheckoutSession *network = newSession(owner);
    [network networkFailed];
    return @{@"successes":@(delegate.successes), @"failures":@(delegate.failures), @"dismissals":@(delegate.dismissals),
        @"retryRemainsOpen":@(retryRemainsOpen), @"closedAfterSuccess":@(closedAfterSuccess),
        @"networkErrors":@(delegate.networkErrors), @"closedBeforeNetworkCallback":@(delegate.closedBeforeNetworkCallback)};
}
void StashQueuedCloseProbe(BOOL replace, BOOL processing, BOOL allowDismiss, void (^completion)(BOOL, NSInteger)) {
    StashNativeCard *owner = [StashNativeCard new];
    StashProbeDelegate *delegate = [StashProbeDelegate new];
    owner.delegate = delegate;
    StashCheckoutSession *session = newSession(owner);
    session.config.allowDismiss = allowDismiss;
    [session handleMessage:@"stashWindowClose" body:@{}];
    if (processing) [session handleMessage:@"stashPurchaseProcessing" body:@{}];
    if (replace) newSession(owner);
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(owner.isCurrentlyPresented, delegate.dismissals);
        [owner dismiss];
    });
}

NSDictionary *StashLifecycleProbe(void) {
    StashNativeCard *owner = [StashNativeCard new];
    StashProbeDelegate *delegate = [StashProbeDelegate new];
    delegate.owner = owner; owner.delegate = delegate;
    delegate.events = [NSMutableArray array];
    StashCheckoutSession *dismissed = newSession(owner);
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
    BOOL browserOrder = [delegate.events isEqualToArray:@[@"dismiss", @"browser"]];
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
    StashNativeCard *owner = [StashNativeCard new];
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
@interface StashNativeCard (SnapshotTest)
- (void)openURL:(NSString *)url presenter:(UIViewController *)presenter
    config:(StashNativeCardConfig *)config browser:(BOOL)browser;
@end
@interface StashSnapshotCard : StashNativeCard
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
