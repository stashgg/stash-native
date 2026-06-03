//
//  StashNativeCardGeometry.m
//  StashNative
//
//  Sheet sizing math: computes card, modal, and popup frames from the stash_*Ratio /
//  stash_custom*Multiplier externs and the current orientation/idiom, plus iPad/tablet sizing,
//  safe-area insets, and the rotation expand-reset.
//

#import "StashNativeCardPrivate.h"
#import "StashNativeCardGeometry.h"

#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

CGSize stash_calculateiPadCardSize(CGRect screenBounds) {
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
        widthRatio = stash_tabletWidthRatioLandscape;
        heightRatio = stash_tabletHeightRatioLandscape;
    } else {
        widthRatio = stash_tabletWidthRatioPortrait;
        heightRatio = stash_tabletHeightRatioPortrait;
    }
    
    // Apply orientation-specific tablet ratios to actual screen dimensions
    CGFloat cardWidth = screenWidth * widthRatio;
    CGFloat cardHeight = screenHeight * heightRatio;
    
    if (cardWidth <= 0 || cardHeight <= 0) {
        return CGSizeMake(kFallbackTabletCardWidth, kFallbackTabletCardHeight);
    }
    
    // Enforce minimum sizes.
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

CGRect stash_computePopupFrameForScreenBounds(CGRect screenBounds) {
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(stash_getInterfaceOrientation());
    CGFloat smallerDimension = fmin(screenBounds.size.width, screenBounds.size.height);
    CGFloat percentage = stash_isRunningOniPad() ? kPopupBaseSizePercentageIPad : kPopupBaseSizePercentagePhone;
    CGFloat baseSize = fmax(
        stash_isRunningOniPad() ? kPopupBaseSizeMinIPad : kPopupBaseSizeMinPhone,
        fmin(kPopupBaseSizeMax, smallerDimension * percentage)
    );
    CGFloat portraitWidthMultiplier = stash_useCustomPopupSize ? stash_customPortraitWidthMultiplier : kPopupPortraitWidthMultiplier;
    CGFloat portraitHeightMultiplier = stash_useCustomPopupSize ? stash_customPortraitHeightMultiplier : kPopupPortraitHeightMultiplier;
    CGFloat landscapeWidthMultiplier = stash_useCustomPopupSize ? stash_customLandscapeWidthMultiplier : kPopupLandscapeWidthMultiplier;
    CGFloat landscapeHeightMultiplier = stash_useCustomPopupSize ? stash_customLandscapeHeightMultiplier : kPopupLandscapeHeightMultiplier;
    CGFloat width = baseSize * (isLandscape ? landscapeWidthMultiplier : portraitWidthMultiplier);
    CGFloat height = baseSize * (isLandscape ? landscapeHeightMultiplier : portraitHeightMultiplier);
    CGFloat x = (screenBounds.size.width - width) / 2.0;
    CGFloat y = (screenBounds.size.height - height) / 2.0;
    return CGRectMake(x, y, width, height);
}

CGRect stash_computeModalFrameForScreenBounds(CGRect screenBounds) {
    BOOL isLandscape = screenBounds.size.width > screenBounds.size.height;
    BOOL isTablet = stash_isRunningOniPad();
    
    CGFloat widthRatio, heightRatio;
    if (isTablet) {
        if (isLandscape) {
            widthRatio = stash_modalTabletWidthRatioLandscape;
            heightRatio = stash_modalTabletHeightRatioLandscape;
        } else {
            widthRatio = stash_modalTabletWidthRatioPortrait;
            heightRatio = stash_modalTabletHeightRatioPortrait;
        }
    } else {
        if (isLandscape) {
            widthRatio = stash_modalPhoneWidthRatioLandscape;
            heightRatio = stash_modalPhoneHeightRatioLandscape;
        } else {
            widthRatio = stash_modalPhoneWidthRatioPortrait;
            heightRatio = stash_modalPhoneHeightRatioPortrait;
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



CGFloat stash_getSafeAreaTopForView(UIView *view) {
    if (!view) return stash_cardSafeAreaTop;
    if (@available(iOS 11.0, *)) {
        UIView *parentView = view.superview;
        if (parentView && [parentView respondsToSelector:@selector(safeAreaInsets)]) {
            CGFloat live = parentView.safeAreaInsets.top;
            // Returns the live top inset when positive, else stash_cardSafeAreaTop.
            if (live > 0) return live;
        }
    }
    return stash_cardSafeAreaTop;
}

CGFloat stash_getSafeAreaBottomForView(UIView *view) {
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
    CGFloat safeTop = stash_getSafeAreaTopForView(cardView);
    CGFloat safeBottom = stash_getSafeAreaBottomForView(cardView);
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
    CGSize base = stash_calculateiPadCardSize(screenBounds);
    CGFloat w = base.width;
    CGFloat h = base.height;
    if (stash_isCardExpanded) {
        h = stashTabletSdkExpandedHeightFromBase(base.height, screenBounds, cardView);
    }
    CGFloat x = (screenBounds.size.width - w) / 2.0;
    CGFloat y = (screenBounds.size.height - h) / 2.0;
    return CGRectMake(x, y, w, h);
}

CGRect stash_computePhoneCardFrameForBoundsAndOrientation(CGRect bounds, BOOL isLandscape) {
    CGFloat cardWidth, cardHeight, cardX, cardY;
    const CGFloat minPhone = 300.0f;
    if (isLandscape) {
        cardWidth = bounds.size.width * stash_cardWidthRatioLandscape;
        cardHeight = bounds.size.height * stash_cardHeightRatioLandscape;
        if (cardWidth < minPhone) cardWidth = minPhone;
        if (cardHeight < minPhone) cardHeight = minPhone;
        cardX = (bounds.size.width - cardWidth) / 2.0f;
        cardY = bounds.size.height - cardHeight;
    } else {
        cardWidth = bounds.size.width;
        cardHeight = bounds.size.height * stash_cardHeightRatioPortrait;
        cardX = 0;
        cardY = bounds.size.height - cardHeight;
    }
    // In landscape, enforces an 8pt minimum top inset.
    CGFloat effectiveSafeTop = stash_cardSafeAreaTop;
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

void stash_resetCardExpandedStateAfterRotation(void) {
    stash_isCardExpanded = NO;
}

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
