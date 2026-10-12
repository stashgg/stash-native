#import "StashNativeCardPrivate.h"
#import <math.h>

@implementation StashCheckoutViewController (Presentation)
- (UIView *)layoutContainer {
    return self.session.presentationPresenter.view.window ?: self.session.presentationPresenter.view;
}
- (BOOL)usesFloatingNativeSizing {
    UITraitCollection *traits = [self layoutContainer].traitCollection;
    return traits.horizontalSizeClass == UIUserInterfaceSizeClassRegular &&
        traits.verticalSizeClass == UIUserInterfaceSizeClassRegular;
}
- (void)reconcileNativeSizingPolicy {
    BOOL floating = [self usesFloatingNativeSizing];
    if (floating == self.configuredFloatingNativeSizing) return;
    self.configuredFloatingNativeSizing = floating;
    self.nativeSizingGeneration += 1;
    self.hasNativeMaximumDetentValue = NO;
    self.nativeMaximumDetentValue = 0;
    self.nativeContentSafeAreaCompensation = 0;
    self.hasRequestedNativeSelection = NO;
}
- (void)configurePresentation {
    self.preferredContentSize = CGSizeMake(self.session.config.preferredContentWidth,
        [self usesFloatingNativeSizing] ? self.session.config.preferredContentHeight : 0);
    self.modalPresentationStyle = UIModalPresentationFormSheet;
    UISheetPresentationController *sheet = self.sheetPresentationController;
    sheet.delegate = self.session;
    sheet.prefersGrabberVisible = YES;
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
    if (@available(iOS 27.0, *)) sheet.preferredPlacement = UISheetPresentationControllerPlacementCenter;
#endif
    sheet.prefersEdgeAttachedInCompactHeight = YES;
    sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = YES;
    // Custom detents track the finger independently of WebKit's nested scrollers.
    if (@available(iOS 16.0, *)) sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
    else sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    if (@available(iOS 17.0, *)) sheet.prefersPageSizing = NO;
    [self configureNativeDetents];
    BOOL expanded = self.session.expanded || self.session.keyboardVisible;
    sheet.selectedDetentIdentifier = [self nativeDetentIdentifierForExpanded:expanded];
    self.hasRequestedNativeSelection = YES;
    self.requestedNativeExpanded = expanded;
    [self updateDismissalPolicy];
}
- (NSString *)nativeDetentIdentifierForExpanded:(BOOL)expanded {
    if ([self usesFloatingNativeSizing]) return UISheetPresentationControllerDetentIdentifierLarge;
    if (@available(iOS 16.0, *)) return expanded ? @"stash-expanded" : @"stash-resting";
    return expanded || self.singleDetent ? UISheetPresentationControllerDetentIdentifierLarge
        : UISheetPresentationControllerDetentIdentifierMedium;
}
- (BOOL)nativeSelectionIsExpanded {
    if ([self usesFloatingNativeSizing]) return self.session.expanded;
    return [self.sheetPresentationController.selectedDetentIdentifier
        isEqualToString:[self nativeDetentIdentifierForExpanded:YES]];
}
- (CGRect)availableBoundsInView:(UIView *)view {
    return [self availableBoundsInView:view expanded:self.session.expanded || self.session.keyboardVisible];
}
- (CGRect)availableBoundsInView:(UIView *)view expanded:(BOOL)expanded {
    UIEdgeInsets insets = view.safeAreaInsets;
    BOOL compactNative = [self layoutContainer].bounds.size.width < 600;
    BOOL bottomAttached = compactNative && !expanded;
    NSMutableArray<NSValue *> *regions = [NSMutableArray array];
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        for (UIViewReservedRegionKind *kind in @[UIViewReservedRegionKind.occlusionRegionKind, UIViewReservedRegionKind.divisionRegionKind]) {
            for (UIViewReservedRegion *region in [view reservedRegionsOfKind:kind]) {
                if (!region.active) continue;
                CGRect rect = region.frame;
                if (rect.size.width == 0) rect.size.width = 1;
                if (rect.size.height == 0) rect.size.height = 1;
                [regions addObject:[NSValue valueWithCGRect:rect]];
            }
        }
    }
#endif
    if (compactNative && view == self.viewIfLoaded) {
        // Content follows the moving surface before UIKit commits a detent selection.
        bottomAttached = YES;
        for (NSValue *value in regions) {
            if (CGRectIntersectsRect(view.bounds, value.CGRectValue)) { bottomAttached = NO; break; }
        }
    }
    if (bottomAttached) { insets.left = 0; insets.right = 0; }
    CGRect bounds = UIEdgeInsetsInsetRect(view.bounds, insets);
    if (view == self.viewIfLoaded && view.window) {
        UIView *host = [self layoutContainer];
        if (host == view.window || host.window == view.window) {
            // UIKit's inherited sheet insets can lag a fold transition.
            CGRect hostSafe = [view convertRect:UIEdgeInsetsInsetRect(host.bounds, host.safeAreaInsets) fromView:host];
            CGFloat top = MAX(CGRectGetMinY(bounds), CGRectGetMinY(hostSafe));
            CGFloat bottom = MIN(CGRectGetMaxY(bounds), CGRectGetMaxY(hostSafe));
            bounds.origin.y = top;
            bounds.size.height = MAX(0, bottom - top);
        }
    }
    // UIKit already accounts for the keyboard in the native detent maximum.
    CGRect keyboard = (view == self.viewIfLoaded)
        ? [self resolvedKeyboardFrameInView:view dockedOnly:YES] : CGRectNull;
    if (!CGRectIsNull(keyboard)) {
        CGRect intersection = CGRectIntersection(bounds, keyboard);
        if (!CGRectIsNull(intersection) && intersection.size.width > bounds.size.width * 0.75 &&
            CGRectGetMaxY(keyboard) >= CGRectGetMaxY(view.bounds) - 0.5) {
            bounds.size.height = MAX(0, CGRectGetMinY(intersection) - CGRectGetMinY(bounds));
        }
    }
    CGPoint preferred = [self.session.presentationPresenter.view convertPoint:CGPointMake(CGRectGetMidX(self.session.presentationPresenter.view.bounds),
        CGRectGetMidY(self.session.presentationPresenter.view.bounds)) toView:view];
    if (bottomAttached) {
        CGRect attached = StashChooseBottomAttachedRegion(bounds, regions);
        if (!CGRectIsEmpty(attached) && !CGRectIsNull(attached)) return attached;
    }
    return StashChooseAvailableRegion(bounds, regions, preferred, view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft);
}
- (CGFloat)contentHeightForMaximum:(CGFloat)maximum expanded:(BOOL)expanded {
    UIView *container = [self layoutContainer];
    CGRect available = [self availableBoundsInView:container expanded:expanded];
    if (container.bounds.size.width < 600) {
        CGFloat nativeBottom = CGRectGetMinY(container.bounds) + container.safeAreaInsets.top + maximum;
        available.size.height = MAX(0, MIN(CGRectGetMaxY(available), nativeBottom) - CGRectGetMinY(available));
    }
    StashPresentationGeometry geometry = StashResolveGeometry(available, self.session.config, expanded,
        self.session.measuredContentHeight);
    CGFloat surface = geometry.frame.size.height;
    CGFloat detent = surface > 0 ? MIN(MAX(0, maximum), surface + self.nativeContentSafeAreaCompensation) : 0;
    return detent;
}
- (void)reconcileNativeContentSafeArea:(CGFloat)bottomPadding {
    if ([self usesFloatingNativeSizing]) return;
    if (![self.session isActive] || self.session.keyboardVisible || self.dragging ||
        self.updatingLayout || self.geometryTransitioning || self.isBeingPresented || !self.view.window ||
        !self.hasNativeMaximumDetentValue || self.nativeContentCompensationQueued) return;
    NSString *selection = self.sheetPresentationController.selectedDetentIdentifier;
    if (![@[[self nativeDetentIdentifierForExpanded:NO], [self nativeDetentIdentifierForExpanded:YES]]
        containsObject:selection]) return;
    BOOL expanded = [self nativeSelectionIsExpanded];
    CGFloat detent = [self contentHeightForMaximum:self.nativeMaximumDetentValue expanded:expanded];
    if (detent <= 0) return;
    CGSize size = self.view.bounds.size;
    CGFloat addedByUIKit = size.height - detent;
    CGFloat reserve = MAX(bottomPadding, MAX(self.view.safeAreaInsets.bottom, [self layoutContainer].safeAreaInsets.bottom));
    // A different surface height means UIKit has not reached the selected detent yet.
    if (addedByUIKit < -0.5 || addedByUIKit > reserve + 0.5) return;
    CGFloat compensation = MAX(0, bottomPadding - MAX(0, addedByUIKit));
    if (fabs(compensation - self.nativeContentSafeAreaCompensation) < 0.5) return;
    self.nativeContentCompensationQueued = YES;
    NSUInteger generation = self.nativeSizingGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.nativeContentCompensationQueued = NO;
        if (generation != self.nativeSizingGeneration || [self usesFloatingNativeSizing]) return;
        if (![self.session isActive] || self.session.keyboardVisible || self.dragging || self.geometryTransitioning ||
            !self.view.window) return;
        if (!CGSizeEqualToSize(size, self.view.bounds.size) ||
            ![selection isEqualToString:self.sheetPresentationController.selectedDetentIdentifier] ||
            fabs(bottomPadding - self.session.webView.scrollView.verticalScrollIndicatorInsets.bottom) > 0.5 ||
            fabs(detent - [self contentHeightForMaximum:self.nativeMaximumDetentValue expanded:expanded]) > 0.5) {
            [self.view setNeedsLayout];
            return;
        }
        self.nativeContentSafeAreaCompensation = compensation;
        [self updatePresentationAnimated:NO];
    });
}
- (void)updatePresentationAnimated:(BOOL)animated {
    if (self.updatingLayout || !self.session || self.session.closing) return;
    if (self.dragging) {
        self.deferredContentLayout = YES;
        [self.viewIfLoaded setNeedsLayout];
        return;
    }
    self.updatingLayout = YES;
    [self reconcileNativeSizingPolicy];
    UIView *container = [self layoutContainer];
    CGRect bounds = [self availableBoundsInView:container];
    StashPresentationGeometry geometry = StashResolveGeometry(bounds, self.session.config,
        self.session.expanded || self.session.keyboardVisible, self.session.measuredContentHeight);
    BOOL floatingSizing = [self usesFloatingNativeSizing];
    CGFloat preferredHeight = floatingSizing ? geometry.frame.size.height : 0;
    CGSize preferredSize = CGSizeMake(geometry.frame.size.width, preferredHeight);
    UISheetPresentationController *sheet = self.sheetPresentationController;
    BOOL floating = container.bounds.size.width >= 600;
    if (floating) {
        CGFloat margin = MIN(self.session.config.edgeMargin, MIN(bounds.size.width, bounds.size.height) / 4);
        preferredSize = CGSizeMake(MIN(self.session.config.preferredContentWidth,
            MAX(0, bounds.size.width - 2 * margin)), preferredHeight);
    }
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
    if (@available(iOS 27.0, *)) sheet.preferredPlacement = UISheetPresentationControllerPlacementCenter;
#endif
    sheet.sourceView = nil;
    if (!floatingSizing) self.preferredContentSize = preferredSize;
    void (^changes)(void) = ^{
        if (floatingSizing) self.preferredContentSize = preferredSize;
        [self configureNativeDetents];
        if (@available(iOS 16.0, *)) [sheet invalidateDetents];
        BOOL expanded = self.session.expanded || self.session.keyboardVisible;
        BOOL containsSelection = [sheet.selectedDetentIdentifier isEqualToString:[self nativeDetentIdentifierForExpanded:NO]] ||
            [sheet.selectedDetentIdentifier isEqualToString:[self nativeDetentIdentifierForExpanded:YES]];
        if (!self.hasRequestedNativeSelection || expanded != self.requestedNativeExpanded ||
            self.singleDetent || !containsSelection) {
            sheet.selectedDetentIdentifier = [self nativeDetentIdentifierForExpanded:expanded];
        }
        self.hasRequestedNativeSelection = YES;
        self.requestedNativeExpanded = expanded;
    };
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) [sheet animateChanges:changes]; else changes();
    self.updatingLayout = NO;
    [self.view setNeedsLayout];
}
- (void)updateNativeLoadingBackground {
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 260100
    if (@available(iOS 26.1, *)) {
        BOOL loading = self.isViewLoaded ? self.loadingCover != nil : !self.session.initialContentRevealed;
        UIBlurEffect *effect = loading && [self usesFloatingNativeSizing]
            ? [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial] : nil;
        for (UISheetPresentationControllerDetent *detent in self.sheetPresentationController.detents)
            detent.backgroundEffect = effect;
    }
#endif
}
- (void)configureNativeDetents {
    [self reconcileNativeSizingPolicy];
    if ([self usesFloatingNativeSizing]) {
        self.singleDetent = YES;
        self.sheetPresentationController.detents = @[[UISheetPresentationControllerDetent largeDetent]];
        [self updateNativeLoadingBackground];
        return;
    }
    if (@available(iOS 16.0, *)) {
        CGFloat maximum = self.hasNativeMaximumDetentValue ? self.nativeMaximumDetentValue : CGFLOAT_MAX;
        CGFloat resting = [self contentHeightForMaximum:maximum expanded:NO];
        CGFloat expandedHeight = [self contentHeightForMaximum:maximum expanded:YES];
        self.singleDetent = fabs(expandedHeight - resting) < 1;
        BOOL expanded = self.session.expanded || self.session.keyboardVisible;
        STASH_WEAK_REF StashCheckoutViewController *weakSelf = self;
        NSMutableArray *detents = [NSMutableArray array];
        if (!self.singleDetent || !expanded) [detents addObject:[UISheetPresentationControllerDetent
            customDetentWithIdentifier:[self nativeDetentIdentifierForExpanded:NO] resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                return [weakSelf resolvedNativeHeightForMaximum:context.maximumDetentValue expanded:NO];
            }]];
        if (!self.singleDetent || expanded) [detents addObject:[UISheetPresentationControllerDetent
            customDetentWithIdentifier:[self nativeDetentIdentifierForExpanded:YES] resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                return [weakSelf resolvedNativeHeightForMaximum:context.maximumDetentValue expanded:YES];
            }]];
        self.sheetPresentationController.detents = detents;
    } else {
        // iOS 15 provides system stops on the same native sheet.
        BOOL single = [self layoutContainer].traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
        if (single != self.singleDetent) self.hasRequestedNativeSelection = NO;
        self.singleDetent = single;
        self.sheetPresentationController.detents = self.singleDetent
            ? @[[UISheetPresentationControllerDetent largeDetent]]
            : @[[UISheetPresentationControllerDetent mediumDetent], [UISheetPresentationControllerDetent largeDetent]];
    }
    [self updateNativeLoadingBackground];
}
- (CGFloat)resolvedNativeHeightForMaximum:(CGFloat)maximum expanded:(BOOL)expanded {
    if ([self usesFloatingNativeSizing]) return [self contentHeightForMaximum:maximum expanded:expanded];
    self.nativeMaximumDetentValue = maximum;
    self.hasNativeMaximumDetentValue = YES;
    CGFloat resting = [self contentHeightForMaximum:maximum expanded:NO];
    CGFloat expandedHeight = [self contentHeightForMaximum:maximum expanded:YES];
    BOOL single = fabs(expandedHeight - resting) < 1;
    if (single != self.singleDetent) {
        self.singleDetent = single;
        if (!self.nativeMaximumReconciliationQueued) {
            self.nativeMaximumReconciliationQueued = YES;
            NSUInteger generation = self.nativeSizingGeneration;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.nativeMaximumReconciliationQueued = NO;
                if (generation != self.nativeSizingGeneration || [self usesFloatingNativeSizing]) return;
                if ([self.session isActive]) [self updatePresentationAnimated:NO];
            });
        }
    }
    if (!expanded && self.contentExpansionActive)
        return MIN(expandedHeight, MAX(resting, self.contentExpansionHeight));
    return expanded ? expandedHeight : resting;
}
- (void)contentHeightDidChange {
    if (self.dragging) self.deferredContentLayout = YES;
    else [self updatePresentationAnimated:YES];
}
@end
