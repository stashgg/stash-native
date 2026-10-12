#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativeCardPrivate.h"

@interface StashCodeLinkViewController (Regression)
@property (nonatomic, readonly) CGRect scanFrame;
@property (nonatomic, readonly) UIView *callout;
@property (nonatomic, readonly) UIView *closeButton;
@property (nonatomic, readonly) UIView *confirmation;
@property (nonatomic, readonly) UILabel *heading;
@property (nonatomic, readonly) UILabel *statusTitle;
@property (nonatomic, readonly) UILabel *statusMessage;
@property (nonatomic, readonly) UIActivityIndicatorView *spinner;
- (void)cameraFailed:(StashNativeCodeLinkError)code message:(NSString *)message;
@end

@interface StashCodeLinkDelegateProbe : NSObject <StashNativeCardDelegate>
@property (nonatomic, weak) StashNativeCard *owner;
@property (nonatomic, copy) NSString *content;
@property (nonatomic) NSInteger scans;
@property (nonatomic) NSInteger dismissals;
@property (nonatomic) NSInteger errors;
@property (nonatomic) BOOL closedBeforeCallback;
@end
@implementation StashCodeLinkDelegateProbe
- (void)stashNativeCardDidScanQRCode:(NSString *)content {
    self.content = content;
    self.scans++;
    self.closedBeforeCallback = !self.owner.isCurrentlyPresented;
}
- (void)stashNativeCardDidDismiss { self.dismissals++; }
- (void)stashNativeCardCodeLinkDidEncounterError:(NSError *)error { self.errors++; }
@end

@interface StashCodeLinkSessionProbe : StashCheckoutSession
@property (nonatomic, copy) void (^pendingDismissal)(void);
@end
@implementation StashCodeLinkSessionProbe
- (void)dismissPresentedSurfaceAnimated:(BOOL)animated completion:(void (^)(void))completion {
    self.pendingDismissal = completion;
}
@end

void StashCodeLinkLifecycleProbe(void (^completion)(NSDictionary *)) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCodeLinkDelegateProbe *delegate = [StashCodeLinkDelegateProbe new];
    delegate.owner = owner;
    owner.delegate = delegate;
    StashCodeLinkSessionProbe *session = [StashCodeLinkSessionProbe new];
    session.owner = owner;
    session.config = [StashNativeCardConfig new];
    session.codeLink = YES;
    owner.session = session;
    StashCodeLinkViewController *scanner = [StashCodeLinkViewController new];
    scanner.session = session;
    session.codeLinkController = scanner;
    [scanner loadViewIfNeeded];
    [scanner cameraFailed:StashNativeCodeLinkErrorCameraPermissionDenied message:@"Denied"];
    [scanner cameraFailed:StashNativeCodeLinkErrorCameraUnavailable message:@"Unavailable"];
    BOOL errorKeepsCard = owner.isCurrentlyPresented && delegate.errors == 1;
    [session completeCodeLink:@""];
    BOOL emptyIgnored = !session.closing && delegate.scans == 0;
    NSString *payload = @"https://example.invalid/link?code=hello%20world&value=+\nsecond line";
    [session completeCodeLink:payload];
    [session completeCodeLink:@"duplicate"];
    BOOL waitsForConfirmation = scanner.confirmation != nil && !session.closing && delegate.scans == 0 &&
        owner.isCurrentlyPresented && !session.canUserDismiss;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL waitsForDismissal = delegate.scans == 0 && session.closing && session.pendingDismissal != nil;
        void (^finish)(void) = session.pendingDismissal;
        session.pendingDismissal = nil;
        if (finish) finish();
        [session completeCodeLink:@"late"];
        BOOL scannedOnce = delegate.scans == 1 && [delegate.content isEqualToString:payload] && delegate.dismissals == 0;
        BOOL stopped = session.codeLinkController == nil && scanner.session == nil;

        StashCheckoutSession *cancelled = [StashCheckoutSession new];
        cancelled.owner = owner;
        cancelled.config = [StashNativeCardConfig new];
        cancelled.codeLink = YES;
        owner.session = cancelled;
        [owner dismiss];
        [cancelled completeCodeLink:@"after cancel"];
        BOOL cancelledOnce = delegate.dismissals == 1 && delegate.scans == 1;
        owner.session = cancelled;
        cancelled.closing = NO;
        [owner resetPresentationState];
        [cancelled completeCodeLink:@"after reset"];
        completion(@{@"errorKeepsCard":@(errorKeepsCard), @"emptyIgnored":@(emptyIgnored),
            @"waitsForConfirmation":@(waitsForConfirmation), @"waitsForDismissal":@(waitsForDismissal),
            @"scannedOnce":@(scannedOnce), @"closedBeforeCallback":@(delegate.closedBeforeCallback), @"stopped":@(stopped),
            @"cancelledOnce":@(cancelledOnce), @"resetSilent":@(delegate.dismissals == 1 && delegate.scans == 1)});
    });
}

void StashCodeLinkInterruptedConfirmationProbe(BOOL reset, void (^completion)(NSDictionary *)) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCodeLinkDelegateProbe *delegate = [StashCodeLinkDelegateProbe new];
    owner.delegate = delegate;
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.owner = owner;
    session.config = [StashNativeCardConfig new];
    session.codeLink = YES;
    owner.session = session;
    StashCodeLinkViewController *scanner = [StashCodeLinkViewController new];
    scanner.session = session;
    session.codeLinkController = scanner;
    [session completeCodeLink:@"interrupted"];
    if (reset) [owner resetPresentationState]; else [owner dismiss];
    StashCheckoutSession *replacement = [StashCheckoutSession new];
    replacement.owner = owner;
    owner.session = replacement;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL replacementUntouched = owner.session == replacement && !replacement.closing;
        [owner resetPresentationState];
        completion(@{@"noScanCallback":@(delegate.scans == 0),
            @"dismissalsCorrect":@(delegate.dismissals == (reset ? 0 : 1)),
            @"stopped":@(scanner.session == nil), @"replacementUntouched":@(replacementUntouched)});
    });
}

NSDictionary *StashCodeLinkLayoutProbe(CGSize size) {
    return StashCodeLinkConfiguredLayoutProbe(size, nil);
}

static NSString *StashScannerText(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqualToString:identifier] && [view isKindOfClass:UILabel.class])
        return ((UILabel *)view).text;
    for (UIView *child in view.subviews) {
        NSString *text = StashScannerText(child, identifier);
        if (text) return text;
    }
    return nil;
}

NSDictionary *StashCodeLinkConfiguredLayoutProbe(CGSize size, StashNativeCodeLinkConfig *config) {
    StashNativeCard *owner = [StashNativeCard new];
    StashCheckoutSession *session = [StashCheckoutSession new];
    session.owner = owner;
    owner.session = session;
    session.codeLinkConfig = config;
    StashCodeLinkViewController *scanner = [StashCodeLinkViewController new];
    scanner.session = session;
    scanner.view.frame = (CGRect){CGPointZero, size};
    [scanner.view setNeedsLayout];
    [scanner.view layoutIfNeeded];
    CGRect frame = scanner.scanFrame;
    CGRect callout = scanner.callout.frame;
    CGRect close = scanner.closeButton.frame;
    BOOL bounded = CGRectContainsRect(scanner.view.bounds, frame) &&
        (!scanner.callout || CGRectContainsRect(scanner.view.bounds, callout)) &&
        CGRectContainsRect(scanner.view.bounds, close);
    BOOL separate = MAX(CGRectGetMaxY(close), CGRectGetMaxY(scanner.heading.frame)) < CGRectGetMinY(frame) &&
        (!scanner.callout || CGRectGetMaxY(frame) < CGRectGetMinY(callout));
    NSMutableDictionary *result = [@{@"bounded":@(bounded), @"frameWidth":@(frame.size.width),
        @"frameHeight":@(frame.size.height), @"centerX":@(CGRectGetMidX(frame)),
        @"controlsSeparate":@(separate), @"showCallout":@(scanner.callout != nil),
        @"headerText":scanner.heading.text ?: @"",
        @"calloutTitle":StashScannerText(scanner.view, @"stash-code-link-callout-title") ?: @"",
        @"calloutSubtitle":StashScannerText(scanner.view, @"stash-code-link-callout-subtitle") ?: @"",
        @"snapshot":@(!config || session.codeLinkConfig != config),
        @"spinnerOnly":@(scanner.spinner.isAnimating && scanner.statusTitle.hidden && scanner.statusMessage.hidden),
        @"closeTargetWidth":@(close.size.width), @"closeTargetHeight":@(close.size.height)} mutableCopy];
    [scanner cameraFailed:StashNativeCodeLinkErrorCameraPermissionDenied message:@"Denied"];
    [scanner cameraFailed:StashNativeCodeLinkErrorCameraUnavailable message:@"Diagnostic detail"];
    result[@"cameraUnavailableText"] = scanner.statusTitle.text;
    result[@"unavailableMessageHidden"] = @(scanner.statusMessage.hidden && scanner.statusMessage.text.length == 0);
    [scanner showConnectedWithCompletion:nil];
    result[@"connectedText"] = StashScannerText(scanner.confirmation, @"stash-code-link-connected-title");
    [scanner dispose];
    return result;
}
