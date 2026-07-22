//
//  StashNativeCardGeometry.m
//  StashNative
//
//  Device/orientation queries and frame/size computation for all presentation modes.
//  Reads sizing state defined in StashNativeCard.m; extern'd via StashNativeCardPrivate.h.
//

#import "StashNativeCard.h"
#import "StashNativeCardPrivate.h"
#import <UIKit/UIKit.h>
#import <math.h>

// Non-ARC compatibility: These warnings are suppressed when compiling without ARC
// (e.g., in game engines like Unreal Engine that manage memory manually).
// ARC builds do not need these suppressions.
#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

#define ENABLE_IPAD_SUPPORT 1

#pragma mark - Tablet Sizing Constants

static const CGFloat kFallbackTabletCardWidth = 600.0f;
static const CGFloat kFallbackTabletCardHeight = 700.0f;
static const CGFloat kTabletMinHeight = 500.0f;
/** Base height × this value when expanded via JS (50% growth); clamped by max card height. */
static const CGFloat kTabletSdkExpandHeightMultiplier = 1.5f;
/** Matches Android CardConstants.EXPANDED_CARD_HEIGHT_RATIO — max card height when expanding via SDK. */
static const CGFloat kExpandedCardHeightScreenRatio = 0.95f;

#pragma mark - Device / Orientation

BOOL isRunningOniPad(void) {
#if !ENABLE_IPAD_SUPPORT
    return NO;
#endif
    
    if (![NSThread isMainThread]) {
        __block BOOL result = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = isRunningOniPad();
        });
        return result;
    }
    
    return ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad);
}

UIInterfaceOrientation getInterfaceOrientation(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                return ((UIWindowScene *)scene).interfaceOrientation;
            }
        }
        return UIInterfaceOrientationUnknown;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].statusBarOrientation;
#pragma clang diagnostic pop
}

// Maps a UIInterfaceOrientation to the corresponding single-orientation mask for restore.
UIInterfaceOrientationMask stashOrientationMaskForOrientation(UIInterfaceOrientation orientation) {
    switch (orientation) {
        case UIInterfaceOrientationPortrait:            return UIInterfaceOrientationMaskPortrait;
        case UIInterfaceOrientationPortraitUpsideDown:  return UIInterfaceOrientationMaskPortraitUpsideDown;
        case UIInterfaceOrientationLandscapeLeft:       return UIInterfaceOrientationMaskLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:      return UIInterfaceOrientationMaskLandscapeRight;
        default:                                        return UIInterfaceOrientationMaskAll;
    }
}

#pragma mark - Safe Areas / Frames

/// Backdrop is this many times larger than the card window (centered) so dimming edges stay off-screen during rotation.
static const CGFloat kIPhoneCardBackdropOverscanFactor = 5.0f;
/// Centered frame larger than `windowBounds` so the dimming layer does not show rotating edges during scene orientation changes.
CGRect stashIPhoneCardOverscanBackdropFrameForWindowBounds(CGRect windowBounds) {
    CGFloat w = windowBounds.size.width;
    CGFloat h = windowBounds.size.height;
    if (w <= 0 || h <= 0) {
        return windowBounds;
    }
    CGFloat ow = w * kIPhoneCardBackdropOverscanFactor;
    CGFloat oh = h * kIPhoneCardBackdropOverscanFactor;
    CGFloat cx = CGRectGetMidX(windowBounds);
    CGFloat cy = CGRectGetMidY(windowBounds);
    return CGRectMake(cx - ow * 0.5f, cy - oh * 0.5f, ow, oh);
}

CGSize calculateiPadCardSize(CGRect screenBounds) {
    if (screenBounds.size.width <= 0 || screenBounds.size.height <= 0) {
        return CGSizeMake(kFallbackTabletCardWidth, kFallbackTabletCardHeight);
    }
    
    // Use actual current screen dimensions
    CGFloat screenWidth = screenBounds.size.width;
    CGFloat screenHeight = screenBounds.size.height;
    
    // Determine orientation and use appropriate ratios
    BOOL isLandscape = screenWidth > screenHeight;
    
    CGFloat widthRatio, heightRatio;
    if (isLandscape) {
        widthRatio = _tabletWidthRatioLandscape;
        heightRatio = _tabletHeightRatioLandscape;
    } else {
        widthRatio = _tabletWidthRatioPortrait;
        heightRatio = _tabletHeightRatioPortrait;
    }
    
    // Apply orientation-specific tablet ratios to actual screen dimensions
    CGFloat cardWidth = screenWidth * widthRatio;
    CGFloat cardHeight = screenHeight * heightRatio;
    
    if (cardWidth <= 0 || cardHeight <= 0) {
        return CGSizeMake(kFallbackTabletCardWidth, kFallbackTabletCardHeight);
    }
    
    // Enforce minimum sizes for usability
    CGFloat minWidth = kPopupBaseSizeMinIPad;
    CGFloat minHeight = kTabletMinHeight;
    if (cardWidth < minWidth) {
        cardWidth = minWidth;
    }
    if (cardHeight < minHeight) {
        cardHeight = minHeight;
    }
    
    return CGSizeMake(cardWidth, cardHeight);
}

CGRect computePopupFrameForScreenBounds(CGRect screenBounds) {
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(getInterfaceOrientation());
    CGFloat smallerDimension = fmin(screenBounds.size.width, screenBounds.size.height);
    CGFloat percentage = isRunningOniPad() ? kPopupBaseSizePercentageIPad : kPopupBaseSizePercentagePhone;
    CGFloat baseSize = fmax(
        isRunningOniPad() ? kPopupBaseSizeMinIPad : kPopupBaseSizeMinPhone,
        fmin(kPopupBaseSizeMax, smallerDimension * percentage)
    );
    CGFloat portraitWidthMultiplier = _useCustomPopupSize ? _customPortraitWidthMultiplier : kPopupPortraitWidthMultiplier;
    CGFloat portraitHeightMultiplier = _useCustomPopupSize ? _customPortraitHeightMultiplier : kPopupPortraitHeightMultiplier;
    CGFloat landscapeWidthMultiplier = _useCustomPopupSize ? _customLandscapeWidthMultiplier : kPopupLandscapeWidthMultiplier;
    CGFloat landscapeHeightMultiplier = _useCustomPopupSize ? _customLandscapeHeightMultiplier : kPopupLandscapeHeightMultiplier;
    CGFloat width = baseSize * (isLandscape ? landscapeWidthMultiplier : portraitWidthMultiplier);
    CGFloat height = baseSize * (isLandscape ? landscapeHeightMultiplier : portraitHeightMultiplier);
    CGFloat x = (screenBounds.size.width - width) / 2.0;
    CGFloat y = (screenBounds.size.height - height) / 2.0;
    return CGRectMake(x, y, width, height);
}

CGRect computeModalFrameForScreenBounds(CGRect screenBounds) {
    BOOL isLandscape = screenBounds.size.width > screenBounds.size.height;
    BOOL isTablet = isRunningOniPad();
    
    CGFloat widthRatio, heightRatio;
    if (isTablet) {
        if (isLandscape) {
            widthRatio = _modalTabletWidthRatioLandscape;
            heightRatio = _modalTabletHeightRatioLandscape;
        } else {
            widthRatio = _modalTabletWidthRatioPortrait;
            heightRatio = _modalTabletHeightRatioPortrait;
        }
    } else {
        if (isLandscape) {
            widthRatio = _modalPhoneWidthRatioLandscape;
            heightRatio = _modalPhoneHeightRatioLandscape;
        } else {
            widthRatio = _modalPhoneWidthRatioPortrait;
            heightRatio = _modalPhoneHeightRatioPortrait;
        }
    }
    
    CGFloat width = screenBounds.size.width * widthRatio;
    CGFloat height = screenBounds.size.height * heightRatio;
    
    // Apply minimum sizes
    CGFloat minWidth = isTablet ? 400.0f : 300.0f;
    CGFloat minHeight = isTablet ? 500.0f : 300.0f;
    if (width < minWidth) width = minWidth;
    if (height < minHeight) height = minHeight;
    
    // Center the modal
    CGFloat x = (screenBounds.size.width - width) / 2.0;
    CGFloat y = (screenBounds.size.height - height) / 2.0;
    
    return CGRectMake(x, y, width, height);
}

CGFloat getSafeAreaTopForView(UIView *view) {
    if (!view) return _cardSafeAreaTop;
    if (@available(iOS 11.0, *)) {
        UIView *parentView = view.superview;
        if (parentView && [parentView respondsToSelector:@selector(safeAreaInsets)]) {
            CGFloat live = parentView.safeAreaInsets.top;
            // On iOS 15, safeAreaInsets can transiently read 0 during rotation
            // transitions. Fall back to the last known card safe area value.
            if (live > 0) return live;
        }
    }
    return _cardSafeAreaTop;
}

CGFloat getSafeAreaBottomForView(UIView *view) {
    if (!view) return 0;
    if (@available(iOS 11.0, *)) {
        UIView *parentView = view.superview;
        if (parentView && [parentView respondsToSelector:@selector(safeAreaInsets)]) {
            return parentView.safeAreaInsets.bottom;
        }
    }
    return 0;
}

CGFloat stashTabletSdkMaxCardHeight(CGRect screenBounds, UIView *cardView) {
    CGFloat ratioCap = screenBounds.size.height * kExpandedCardHeightScreenRatio;
    CGFloat safeTop = getSafeAreaTopForView(cardView);
    CGFloat safeBottom = getSafeAreaBottomForView(cardView);
    CGFloat insetsCap = screenBounds.size.height - safeTop - safeBottom;
    if (insetsCap < 1.0f) {
        insetsCap = screenBounds.size.height;
    }
    return MIN(ratioCap, insetsCap);
}

CGFloat stashTabletSdkExpandedHeightFromBase(CGFloat baseHeight, CGRect screenBounds, UIView *cardView) {
    CGFloat maxH = stashTabletSdkMaxCardHeight(screenBounds, cardView);
    return MIN(baseHeight * kTabletSdkExpandHeightMultiplier, maxH);
}

CGRect stashFrameForIPadSdkCard(CGRect screenBounds, UIView *cardView) {
    CGSize base = calculateiPadCardSize(screenBounds);
    CGFloat w = base.width;
    CGFloat h = base.height;
    if (_isCardExpanded) {
        h = stashTabletSdkExpandedHeightFromBase(base.height, screenBounds, cardView);
    }
    CGFloat x = (screenBounds.size.width - w) / 2.0;
    CGFloat y = (screenBounds.size.height - h) / 2.0;
    return CGRectMake(x, y, w, h);
}

CGRect computePhoneCardFrameForBoundsAndOrientation(CGRect bounds, BOOL isLandscape) {
    CGFloat cardWidth, cardHeight, cardX, cardY;
    const CGFloat minPhone = 300.0f;
    if (isLandscape) {
        cardWidth = bounds.size.width * _cardWidthRatioLandscape;
        cardHeight = bounds.size.height * _cardHeightRatioLandscape;
        if (cardWidth < minPhone) cardWidth = minPhone;
        if (cardHeight < minPhone) cardHeight = minPhone;
        cardX = (bounds.size.width - cardWidth) / 2.0f;
        cardY = bounds.size.height - cardHeight;
    } else {
        cardWidth = bounds.size.width;
        cardHeight = bounds.size.height * _cardHeightRatioPortrait;
        cardX = 0;
        cardY = bounds.size.height - cardHeight;
    }
    // In landscape, safeAreaInsets.top can be 0 (notch on the side). Enforce a minimum
    // buffer so the card doesn't collide with the notification pull-down gesture.
    CGFloat effectiveSafeTop = _cardSafeAreaTop;
    if (isLandscape && effectiveSafeTop < 8.0f) {
        effectiveSafeTop = 8.0f;
    }
    if (cardY < effectiveSafeTop) {
        cardY = effectiveSafeTop;
        cardHeight = bounds.size.height - effectiveSafeTop;
    }
    if (cardY < 0) cardY = 0;
    return CGRectMake(cardX, cardY, cardWidth, cardHeight);
}

void updateOriginalCardRatiosForOrientation(BOOL isLandscape) {
    if (isLandscape) {
        _originalCardWidthRatio = _cardWidthRatioLandscape;
        _originalCardHeightRatio = _cardHeightRatioLandscape;
    } else {
        _originalCardWidthRatio = 1.0f;
        _originalCardHeightRatio = _cardHeightRatioPortrait;
    }
    _originalCardVerticalPosition = 1.0f;
}

void resetCardExpandedStateAfterRotation(void) {
    _isCardExpanded = NO;
}

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
