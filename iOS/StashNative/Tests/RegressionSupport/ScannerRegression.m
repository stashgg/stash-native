#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativePrivate.h"
#import "../../Sources/StashNativeCodeLink/StashNativeScannerViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface StashNativeScannerViewController (Regression)
@property (nonatomic, readonly) CGRect scanFrame;
@property (nonatomic, readonly) UIView *callout;
@property (nonatomic, readonly) UIView *closeButton;
@property (nonatomic, readonly) UIView *confirmation;
@property (nonatomic, readonly) UILabel *heading;
@property (nonatomic, readonly) UILabel *statusTitle;
@property (nonatomic, readonly) UILabel *statusMessage;
@property (nonatomic, readonly) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) AVCaptureSession *capture;
- (AVCaptureVideoPreviewLayer *)previewLayer;
- (void)cameraFailed:(StashNativeScannerError)code message:(NSString *)message;
@end

@interface StashScannerCaptureProbe : AVCaptureSession
@property (nonatomic, strong) dispatch_semaphore_t stopEntered;
@property (nonatomic, strong) dispatch_semaphore_t finishStop;
@property (atomic) NSInteger stopCount;
@property (atomic) BOOL stopping;
@end
@implementation StashScannerCaptureProbe
- (instancetype)init {
    if ((self = [super init])) {
        _stopEntered = dispatch_semaphore_create(0);
        _finishStop = dispatch_semaphore_create(0);
    }
    return self;
}
- (void)stopRunning {
    self.stopping = YES;
    self.stopCount++;
    if (self.stopCount == 1) {
        dispatch_semaphore_signal(self.stopEntered);
        dispatch_semaphore_wait(self.finishStop, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    }
    self.stopping = NO;
}
@end

@interface StashScannerPreviewProbe : AVCaptureVideoPreviewLayer
@property (nonatomic, strong) StashScannerCaptureProbe *capture;
@property (nonatomic, copy) void (^didDetach)(BOOL, BOOL, BOOL);
@property (nonatomic) BOOL detached;
@end
@implementation StashScannerPreviewProbe
- (void)setSession:(AVCaptureSession *)session {
    if (session) {
        self.capture = (StashScannerCaptureProbe *)session;
        self.detached = NO;
        return;
    }
    self.detached = YES;
    void (^finished)(BOOL, BOOL, BOOL) = self.didDetach;
    self.didDetach = nil;
    if (finished) finished(!self.capture.stopping, self.capture.stopCount == 2, NSThread.isMainThread);
}
@end

@interface StashScannerCaptureControllerProbe : StashNativeScannerViewController
@property (nonatomic, strong) StashScannerPreviewProbe *probePreview;
@end
@implementation StashScannerCaptureControllerProbe
- (AVCaptureVideoPreviewLayer *)previewLayer { return self.probePreview; }
@end

void StashScannerCaptureOrderingProbe(void (^completion)(NSDictionary *)) {
    StashScannerCaptureControllerProbe *scanner = [StashScannerCaptureControllerProbe new];
    StashScannerCaptureProbe *capture = [StashScannerCaptureProbe new];
    StashScannerPreviewProbe *preview = [StashScannerPreviewProbe new];
    scanner.capture = capture;
    scanner.probePreview = preview;
    [scanner loadViewIfNeeded];
    [scanner stopScanning];
    BOOL stopEntered = dispatch_semaphore_wait(capture.stopEntered,
        dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0;
    __block BOOL disposalDeferred = NO;
    preview.didDetach = ^(BOOL stoppedBeforeDetach, BOOL finalStopOnly, BOOL detachedOnMain) {
        completion(@{@"stopEntered":@(stopEntered), @"disposalDeferred":@(disposalDeferred),
            @"stoppedBeforeDetach":@(stoppedBeforeDetach), @"finalStopOnly":@(finalStopOnly),
            @"detachedOnMain":@(detachedOnMain)});
    };
    [scanner dispose];
    disposalDeferred = !preview.detached;
    [scanner stopScanning];
    dispatch_semaphore_signal(capture.finishStop);
}

@interface StashScannerDelegateProbe : NSObject <StashNativeDelegate>
@property (nonatomic, weak) StashNative *owner;
@property (nonatomic, copy) NSString *content;
@property (nonatomic) NSInteger scans;
@property (nonatomic) NSInteger dismissals;
@property (nonatomic) NSInteger errors;
@property (nonatomic, strong) NSError *lastError;
@property (nonatomic) BOOL closedBeforeCallback;
@end
@implementation StashScannerDelegateProbe
- (void)stashNativeDidScanQRCode:(NSString *)content {
    self.content = content;
    self.scans++;
    self.closedBeforeCallback = !self.owner.isCurrentlyPresented;
}
- (void)stashNativeDidDismissScanner { self.dismissals++; }
- (void)stashNativeScannerDidEncounterError:(NSError *)error { self.errors++; self.lastError = error; }
@end

@interface StashScannerSessionProbe : StashCardSession
@property (nonatomic, copy) void (^pendingDismissal)(void);
@end
@implementation StashScannerSessionProbe
- (void)dismissPresentedSurfaceAnimated:(BOOL)animated completion:(void (^)(void))completion {
    self.pendingDismissal = completion;
}
@end

void StashScannerLifecycleProbe(void (^completion)(NSDictionary *)) {
    StashNative *owner = [StashNative new];
    StashScannerDelegateProbe *delegate = [StashScannerDelegateProbe new];
    delegate.owner = owner;
    owner.delegate = delegate;
    StashScannerSessionProbe *session = [StashScannerSessionProbe new];
    session.owner = owner;
    session.config = [StashNativeCardConfig new];
    session.scanner = YES;
    owner.session = session;
    StashNativeScannerViewController *scanner = [StashNativeScannerViewController new];
    scanner.scannerHost = session;
    session.scannerController = scanner;
    [scanner loadViewIfNeeded];
    [scanner cameraFailed:StashNativeScannerErrorCameraPermissionDenied message:@"Denied"];
    [scanner cameraFailed:StashNativeScannerErrorCameraUnavailable message:@"Unavailable"];
    BOOL errorKeepsCard = owner.isCurrentlyPresented && delegate.errors == 1;
    [session completeScan:@""];
    BOOL emptyIgnored = !session.closing && delegate.scans == 0;
    NSString *payload = @"https://example.invalid/link?code=hello%20world&value=+\nsecond line";
    [session completeScan:payload];
    [session completeScan:@"duplicate"];
    BOOL waitsForConfirmation = scanner.confirmation != nil && !session.closing && delegate.scans == 0 &&
        owner.isCurrentlyPresented && !session.canUserDismiss;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL waitsForDismissal = delegate.scans == 0 && session.closing && session.pendingDismissal != nil;
        void (^finish)(void) = session.pendingDismissal;
        session.pendingDismissal = nil;
        if (finish) finish();
        [session completeScan:@"late"];
        BOOL scannedOnce = delegate.scans == 1 && [delegate.content isEqualToString:payload] && delegate.dismissals == 0;
        BOOL stopped = session.scannerController == nil && scanner.scannerHost == nil;

        StashCardSession *cancelled = [StashCardSession new];
        cancelled.owner = owner;
        cancelled.config = [StashNativeCardConfig new];
        cancelled.scanner = YES;
        owner.session = cancelled;
        [owner dismiss];
        [cancelled completeScan:@"after cancel"];
        BOOL cancelledOnce = delegate.dismissals == 1 && delegate.scans == 1;
        owner.session = cancelled;
        cancelled.closing = NO;
        [owner resetPresentationState];
        [cancelled completeScan:@"after reset"];
        completion(@{@"errorKeepsCard":@(errorKeepsCard), @"emptyIgnored":@(emptyIgnored),
            @"waitsForConfirmation":@(waitsForConfirmation), @"waitsForDismissal":@(waitsForDismissal),
            @"scannedOnce":@(scannedOnce), @"closedBeforeCallback":@(delegate.closedBeforeCallback), @"stopped":@(stopped),
            @"cancelledOnce":@(cancelledOnce), @"resetSilent":@(delegate.dismissals == 1 && delegate.scans == 1)});
    });
}

void StashScannerInterruptedConfirmationProbe(BOOL reset, void (^completion)(NSDictionary *)) {
    StashNative *owner = [StashNative new];
    StashScannerDelegateProbe *delegate = [StashScannerDelegateProbe new];
    owner.delegate = delegate;
    StashCardSession *session = [StashCardSession new];
    session.owner = owner;
    session.config = [StashNativeCardConfig new];
    session.scanner = YES;
    owner.session = session;
    StashNativeScannerViewController *scanner = [StashNativeScannerViewController new];
    scanner.scannerHost = session;
    session.scannerController = scanner;
    [session completeScan:@"interrupted"];
    if (reset) [owner resetPresentationState]; else [owner dismiss];
    StashCardSession *replacement = [StashCardSession new];
    replacement.owner = owner;
    owner.session = replacement;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL replacementUntouched = owner.session == replacement && !replacement.closing;
        [owner resetPresentationState];
        completion(@{@"noScanCallback":@(delegate.scans == 0),
            @"dismissalsCorrect":@(delegate.dismissals == (reset ? 0 : 1)),
            @"stopped":@(scanner.scannerHost == nil), @"replacementUntouched":@(replacementUntouched)});
    });
}

NSDictionary *StashScannerLayoutProbe(CGSize size) {
    return StashScannerConfiguredLayoutProbe(size, nil);
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

NSDictionary *StashScannerConfiguredLayoutProbe(CGSize size, StashNativeScannerConfig *config) {
    StashNative *owner = [StashNative new];
    StashCardSession *session = [StashCardSession new];
    session.owner = owner;
    owner.session = session;
    session.scannerConfig = config;
    StashNativeScannerViewController *scanner = [StashNativeScannerViewController new];
    scanner.scannerHost = session;
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
        @"snapshot":@(!config || session.scannerConfig != config),
        @"spinnerOnly":@(scanner.spinner.isAnimating && scanner.statusTitle.hidden && scanner.statusMessage.hidden),
        @"closeTargetWidth":@(close.size.width), @"closeTargetHeight":@(close.size.height)} mutableCopy];
    [scanner cameraFailed:StashNativeScannerErrorCameraPermissionDenied message:@"Denied"];
    [scanner cameraFailed:StashNativeScannerErrorCameraUnavailable message:@"Diagnostic detail"];
    result[@"cameraUnavailableText"] = scanner.statusTitle.text;
    result[@"unavailableMessageHidden"] = @(scanner.statusMessage.hidden && scanner.statusMessage.text.length == 0);
    [scanner showConnectedWithCompletion:nil];
    result[@"connectedText"] = StashScannerText(scanner.confirmation, @"stash-code-link-connected-title");
    [scanner dispose];
    return result;
}

void StashScannerUnavailableProbe(void (^completion)(NSDictionary *)) {
    StashNative *owner = [StashNative new];
    StashScannerDelegateProbe *delegate = [StashScannerDelegateProbe new];
    delegate.owner = owner;
    owner.delegate = delegate;
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    UIViewController *host = [UIViewController new];
    window.rootViewController = host;
    window.hidden = NO;
    Class linked = StashScannerContentClass();
    StashSetScannerContentClassName(@"StashMissingScannerContent");
    BOOL resolvesNil = StashScannerContentClass() == Nil;
    [owner openScannerFromViewController:host];
    BOOL nothingPresented = !owner.isCurrentlyPresented && owner.session == nil && host.presentedViewController == nil;
    BOOL asynchronous = delegate.errors == 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *error = delegate.lastError;
        BOOL reported = delegate.errors == 1 && [error.domain isEqualToString:StashNativeScannerErrorDomain] &&
            error.code == StashNativeScannerErrorScannerUnavailable && error.localizedDescription.length > 0;
        BOOL stillIdle = !owner.isCurrentlyPresented && delegate.dismissals == 0 && host.presentedViewController == nil;
        StashSetScannerContentClassName(nil);
        BOOL restored = StashScannerContentClass() == linked && linked == StashNativeScannerViewController.class;
        window.hidden = YES;
        completion(@{@"resolvesNil":@(resolvesNil), @"nothingPresented":@(nothingPresented), @"asynchronous":@(asynchronous),
            @"reported":@(reported), @"stillIdle":@(stillIdle), @"restored":@(restored)});
    });
}
