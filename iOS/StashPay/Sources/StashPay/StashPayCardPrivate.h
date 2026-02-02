//
//  StashPayCardPrivate.h
//  StashPay
//
//  Private declarations for view controllers and delegates used by StashPayCard.m.
//  Implementations live in StashPayCardViewControllers.m and StashPayCardWebViewDelegates.m.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

/// Returns the top-most presented view controller (key window root, then walking presentedViewController chain).
UIViewController *getTopPresentedViewController(void);

/// Popup frame (x, y, width, height) for given screen bounds; uses current orientation and custom/default multipliers.
CGRect computePopupFrameForScreenBounds(CGRect screenBounds);

/// Modal frame (x, y, width, height) for given screen bounds; uses current orientation and modal ratios.
CGRect computeModalFrameForScreenBounds(CGRect screenBounds);

/// Phone card frame (x, y, width, height) for given bounds and orientation; used by current-orientation presentation and rotation.
CGRect computePhoneCardFrameForBoundsAndOrientation(CGRect bounds, BOOL isLandscape);
/// Updates _originalCard* in StashPayCard.m for the given orientation (used after rotation in IPhoneCardCurrentOrientationViewController).
void updateOriginalCardRatiosForOrientation(BOOL isLandscape);
/// Resets expand/collapse state to collapsed after rotation so the card always shows initial size.
void resetCardExpandedStateAfterRotation(void);

/// Updates drag tray and handle bar frame inside cardView (used by iPad transition and expand/collapse).
void updateDragTrayAndHandleInCardView(UIView *cardView, CGFloat cardWidth);
/// Lays out the card's WebView (and tray) to fill cardView.bounds; call after rotation or any card frame change so WebView resizes correctly.
void layoutCardContentToBounds(UIView *cardView);

@interface DragTrayView : UIView
@end

@interface IPhoneCardViewController : UIViewController
@property (nonatomic, assign) CGRect cardFrame;
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMask;
@end

/// Phone card in current orientation (no rotation); allows all orientations.
@interface IPhoneCardCurrentOrientationViewController : UIViewController
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

/// Window-based modal (same pattern as iPad checkout); no portrait lock, works in game engines.
@interface ModalViewController : UIViewController
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
- (void)updateCornerRadiusMaskForCardView;
@end

@interface OrientationLockedViewController : UIViewController
@property (nonatomic, assign) CGRect customFrame;
@property (nonatomic, assign) BOOL enforcePortrait;
@property (nonatomic, assign) BOOL skipLayoutDuringInitialSetup;
@property (nonatomic, assign) CGSize previousScreenSize;
@property (nonatomic, assign) BOOL isModalPresentation;
- (void)updateCornerRadiusMask;
@end

@interface WebViewLoadDelegate : NSObject <WKNavigationDelegate>
@property (nonatomic, assign) CFAbsoluteTime pageLoadStartTime;
- (instancetype)initWithWebView:(WKWebView *)webView loadingView:(UIView *)loadingView;
@end

@interface WebViewUIDelegate : NSObject <WKUIDelegate>
@end
