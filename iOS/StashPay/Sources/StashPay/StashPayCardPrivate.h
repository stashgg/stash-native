//
//  StashPayCardPrivate.h
//  StashPay
//
//  Private declarations for view controllers and delegates used by StashPayCard.m.
//  Implementations live in StashPayCardViewControllers.m and StashPayCardWebViewDelegates.m.
//

#import <UIKit/UIKit.h>

@class WKWebView;

@interface DragTrayView : UIView
@end

@interface IPhoneCardViewController : UIViewController
@property (nonatomic, assign) CGRect cardFrame;
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMask;
@end

@interface IPadModalViewController : UIViewController
@property (nonatomic, assign) CGSize previousScreenSize;
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMaskForCardView;
@end

@interface OrientationLockedViewController : UIViewController
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL enforcePortrait;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
@property (nonatomic, assign) CGSize previousScreenSize;
- (void)updateCornerRadiusMask;
@end

@interface WebViewLoadDelegate : NSObject
@property (nonatomic, assign) CFAbsoluteTime pageLoadStartTime;
- (instancetype)initWithWebView:(WKWebView *)webView loadingView:(UIView *)loadingView;
@end

@interface WebViewUIDelegate : NSObject
@end
