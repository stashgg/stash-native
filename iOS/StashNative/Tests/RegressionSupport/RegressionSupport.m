#import "RegressionSupport.h"
#import "StashNativeCard.h"
#import "../../Sources/StashNative/StashNativeCardPrivate.h"
#import <objc/runtime.h>
#import <SafariServices/SafariServices.h>
@interface StashNativeCard (AuditBoundary)
- (void)openURLInternal:(NSString *)url;
@end
@interface AuditCallback : NSObject <StashNativeCardDelegate>
@property(nonatomic) NSInteger calls;
@property(nonatomic) BOOL onMain;
@end
@implementation AuditCallback
- (void)stashNativeCardDidCompletePaymentWithOrder:(NSString *)order {
    self.calls++; self.onMain=[NSThread isMainThread];
}
@end
@interface AuditSafari : SFSafariViewController
@end
@implementation AuditSafari
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {
    // Deliberately hold UIKit's completion to inspect SDK behavior during dismissal.
}
@end
static void NoPresentation(id obj, SEL sel, NSString *url) {}
NSDictionary *AuditSynchronous(void) {
    NSCAssert([NSThread isMainThread], @"main thread required");
    StashNativeCard *sdk=[StashNativeCard sharedInstance];
    [sdk resetPresentationState];
    Method entry=class_getInstanceMethod([StashNativeCard class], @selector(openURLInternal:));
    IMP original=method_setImplementation(entry,(IMP)NoPresentation);
    StashNativeCardConfig *cfg=[StashNativeCardConfig new];
    cfg.forcePortrait=YES; cfg.cardHeightRatioPortrait=0.42;
    [sdk openCardWithURL:@"https://audit.invalid/" config:cfg];
    [sdk resetPresentationState];
    [sdk openCardWithURL:@"https://audit.invalid/" config:nil];
    double ratio=_cardHeightRatioPortrait; BOOL portrait=_forcePortraitOnCheckout;
    [sdk openCardWithURL:@"https://audit.invalid/" config:[StashNativeCardConfig new]];
    method_setImplementation(entry,original);
    NSMutableArray *exceptions=[NSMutableArray new];
    for (NSString *url in @[@"example.invalid", @"mailto:person@example.invalid"]) {
        @try { [sdk openBrowserWithURL:url]; [exceptions addObject:@"none"]; }
        @catch(NSException *exception) { [exceptions addObject:exception.name]; }
        [sdk resetPresentationState];
    }
    BOOL invalidHexFallsBack=YES;
    for (NSString *invalid in @[@"#ffzzzz", @"#0x1234", @"#+1234567"]) {
        _presentationBackgroundColorHex=invalid;
        invalidHexFallsBack &= [stash_sheetBackgroundUIColor() isEqual:getSystemBackgroundColor()];
    }
    _presentationBackgroundColorHex=nil;
    _usePopupPresentation=YES;
    OrientationLockedViewController *popup=[OrientationLockedViewController new];
    UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,430,932)];
    popup.view=[[UIView alloc] initWithFrame:window.bounds];
    [window addSubview:popup.view];
    CGRect first=computePopupFrameForScreenBounds(window.bounds);
    popup.view.frame=first;
    [popup viewWillLayoutSubviews];
    [popup viewWillLayoutSubviews];
    CGRect next=popup.view.frame;
    _usePopupPresentation=NO;
    [sdk resetPresentationState];
    return @{@"nilRatio":@(ratio), @"nilPortrait":@(portrait), @"browserExceptions":exceptions,
             @"invalidHexFallsBack":@(invalidHexFallsBack), @"popupFirstWidth":@(first.size.width),
             @"popupNextWidth":@(next.size.width)};
}
void AuditRetention(void (^completion)(BOOL)) {
    StashNativeCardInternal *internal=[StashNativeCardInternal sharedInstance];
    __weak NSObject *weakSentinel;
    @autoreleasepool {
        NSObject *sentinel=[NSObject new]; weakSentinel=sentinel;
        stashScheduleForcePortraitCardLayoutAfterPortraitSettle(nil,YES,
            internal.presentationSessionToken+1,internal, ^{ (void)[sentinel description]; }, ^{});
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        completion(weakSentinel != nil);
    });
}
void AuditSafariThread(void (^completion)(BOOL, NSInteger)) {
    StashNativeCard *sdk=[StashNativeCard sharedInstance];
    AuditCallback *delegate=[AuditCallback new];
    id prior=sdk.delegate; sdk.delegate=delegate;
    StashNativeCardInternal *internal=[StashNativeCardInternal sharedInstance];
    internal.isDismissingSafari=NO;
    internal.currentSafariViewController=[[AuditSafari alloc] initWithURL:[NSURL URLWithString:@"https://audit.invalid/"]];
    dispatch_async(dispatch_get_main_queue(),^{
        [sdk dismissSafariViewControllerWithResult:YES];
        [sdk dismissSafariViewControllerWithResult:YES];
        dispatch_async(dispatch_get_main_queue(),^{
            BOOL onMain=delegate.onMain; NSInteger calls=delegate.calls;
            internal.currentSafariViewController=nil; sdk.delegate=prior;
            [sdk resetPresentationState]; completion(onMain,calls);
        });
    });
}

static void (^HeldAnimationCompletion)(BOOL);
static void HoldAnimation(id cls, SEL selector, NSTimeInterval duration, NSTimeInterval delay,
                         UIViewAnimationOptions options, void (^animations)(void), void (^completion)(BOOL)) {
    if (animations) animations();
    HeldAnimationCompletion=[completion copy];
}
BOOL AuditDismissResetReopen(void) {
    NSCAssert([NSThread isMainThread], @"main required");
    StashNativeCard *sdk=[StashNativeCard sharedInstance];
    StashNativeCardInternal *internal=[StashNativeCardInternal sharedInstance];
    [sdk resetPresentationState];
    internal.currentPresentedVC=[UIViewController new];
    internal.currentPresentedVC.view=[[UIView alloc] initWithFrame:CGRectMake(0,0,430,932)];
    _isCardCurrentlyPresented=YES;
    Method method=class_getClassMethod([UIView class],@selector(animateWithDuration:delay:options:animations:completion:));
    IMP prior=method_setImplementation(method,(IMP)HoldAnimation);
    [sdk dismiss];
    method_setImplementation(method,prior);
    [sdk resetPresentationState];
    UIViewController *next=[UIViewController new];
    internal.currentPresentedVC=next; _isCardCurrentlyPresented=YES;
    void (^finish)(BOOL)=HeldAnimationCompletion;
    HeldAnimationCompletion=nil;
    if (finish) finish(YES);
    BOOL clearedNext=(internal.currentPresentedVC != next || !_isCardCurrentlyPresented);
    [sdk resetPresentationState];
    return clearedNext;
}

NSDictionary *RegressionURLs(void) {
    _presentationBackgroundColorHex=@"#000000";
    NSString *themed=appendThemeQueryParameter(@"https://example.invalid/path?token=a%2Bb%26c&theme=light&theme=light#section");
    _presentationBackgroundColorHex=nil;
    return @{@"themed":themed,
             @"bare":NormalizeExternalPaymentURL(@" example.invalid/path ") ?: @"",
             @"mailto":NormalizeExternalPaymentURL(@"mailto:a@example.invalid") ?: @"",
             @"javascript":NormalizeExternalPaymentURL(@"javascript:alert(1)") ?: @""};
}
BOOL RegressionAccessibility(void) {
    StashNativeCardInternal *internal=[StashNativeCardInternal sharedInstance];
    ModalViewController *vc=[ModalViewController new];
    internal.currentPresentedVC=vc;
    _useModalPresentation=YES; _modalAllowDismiss=NO;
    BOOL locked=![vc accessibilityPerformEscape];
    _modalAllowDismiss=YES; internal.isPurchaseProcessing=YES;
    BOOL processing=![vc accessibilityPerformEscape];
    internal.isPurchaseProcessing=NO;
    [[StashNativeCard sharedInstance] resetPresentationState];
    return locked && processing;
}
