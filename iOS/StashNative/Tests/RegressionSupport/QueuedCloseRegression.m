#import "RegressionSupport.h"
#import "StashNativeCard.h"
#import "../../Sources/StashNative/StashNativeCardPrivate.h"

@interface QueuedCloseDelegate : NSObject <StashNativeCardDelegate>
@property(nonatomic) NSInteger dismissals;
@end

@implementation QueuedCloseDelegate
- (void)stashNativeCardDidDismiss {
    self.dismissals++;
}
@end

void AuditQueuedClose(BOOL replace, BOOL startProcessing, void (^completion)(BOOL, NSInteger)) {
    NSCAssert([NSThread isMainThread], @"main thread required");
    StashNativeCard *sdk = [StashNativeCard sharedInstance];
    StashNativeCardInternal *internal = [StashNativeCardInternal sharedInstance];
    [sdk resetPresentationState];
    id previousDelegate = sdk.delegate;
    QueuedCloseDelegate *delegate = [QueuedCloseDelegate new];
    sdk.delegate = delegate;
    UIViewController *controller = [UIViewController new];
    controller.view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 430, 932)];
    internal.currentPresentedVC = controller;
    _isCardCurrentlyPresented = YES;
    [internal handleWindowCloseSignal];
    [internal handleWindowCloseSignal];
    if (replace) {
        [sdk resetPresentationState];
        controller = [UIViewController new];
        controller.view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 430, 932)];
        internal.currentPresentedVC = controller;
        _isCardCurrentlyPresented = YES;
    }
    if (startProcessing) internal.isPurchaseProcessing = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL survived = internal.currentPresentedVC == controller && _isCardCurrentlyPresented;
        NSInteger dismissals = delegate.dismissals;
        [sdk resetPresentationState];
        sdk.delegate = previousDelegate;
        completion(survived, dismissals);
    });
}
