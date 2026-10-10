#import "StashNativeCardPrivate.h"
#import <math.h>

static BOOL StashContainsFirstResponder(UIView *view) {
    if (view.isFirstResponder) return YES;
    for (UIView *child in view.subviews) if (StashContainsFirstResponder(child)) return YES;
    return NO;
}

static UIInterfaceOrientation StashKeyboardWindowOrientation(UIWindow *window) {
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) return window.windowScene.effectiveGeometry.interfaceOrientation;
#endif
    return window.windowScene.interfaceOrientation;
}

static BOOL StashKeyboardFrameIsVisible(CGRect frame, UIWindow *window) {
    if (!isfinite(frame.origin.x) || !isfinite(frame.origin.y) || !isfinite(frame.size.width) ||
        !isfinite(frame.size.height) || CGRectIsEmpty(frame)) return NO;
    CGRect overlap = CGRectIntersection(window.bounds, frame);
    CGFloat safeBottom = CGRectGetMaxY(window.bounds) - window.safeAreaInsets.bottom;
    return !CGRectIsNull(overlap) && overlap.size.width > 0.5 && overlap.size.height > 0.5 &&
        CGRectGetMinY(overlap) < safeBottom - 0.5;
}

static BOOL StashKeyboardFrameIsDocked(CGRect frame, UIWindow *window) {
    CGFloat windowBottom = CGRectGetMaxY(window.bounds);
    return StashKeyboardFrameIsVisible(frame, window) &&
        CGRectGetMinX(frame) <= CGRectGetMinX(window.bounds) + 0.5 &&
        CGRectGetMaxX(frame) >= CGRectGetMaxX(window.bounds) - 0.5 &&
        CGRectGetMaxY(frame) >= windowBottom - 0.5;
}

static BOOL StashKeyboardGuideIsInsetDocked(CGRect frame, UIWindow *window, UIView *content) {
    CGFloat bottom = CGRectGetMaxY(frame);
    CGFloat windowBottom = CGRectGetMaxY(window.bounds);
    CGRect contentFrame = [window convertRect:content.bounds fromView:content];
    return StashKeyboardFrameIsVisible(frame, window) &&
        CGRectGetMinX(frame) <= CGRectGetMinX(window.bounds) + 0.5 &&
        CGRectGetMaxX(frame) >= CGRectGetMaxX(window.bounds) - 0.5 &&
        fabs(bottom - CGRectGetMaxY(contentFrame)) <= 0.5 &&
        bottom >= windowBottom - window.safeAreaInsets.bottom - 0.5 && bottom < windowBottom - 0.5;
}

@implementation StashCheckoutViewController
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
    // Content pans request a native expansion; only native chrome drives interactive resizing.
    sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
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
- (void)viewDidLoad {
    [super viewDidLoad];
    UIColor *initialBackground = stash_sheetBackgroundUIColor();
    if (@available(iOS 26.0, *)) self.glassLoading = !self.session.initialContentRevealed;
    self.view.backgroundColor = initialBackground;
    self.view.accessibilityIdentifier = @"stash-card";
    self.view.clipsToBounds = YES;
    self.view.keyboardLayoutGuide.followsUndockedKeyboard = YES;
    if (@available(iOS 17.0, *)) self.view.keyboardLayoutGuide.usesBottomSafeArea = NO;
    UIView *tracker = [[UIView alloc] init];
    tracker.hidden = YES;
    tracker.userInteractionEnabled = NO;
    tracker.accessibilityElementsHidden = YES;
    tracker.translatesAutoresizingMaskIntoConstraints = NO;
    self.keyboardGuideTracker = tracker;
    [self.view addSubview:tracker];
    UIKeyboardLayoutGuide *guide = self.view.keyboardLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [tracker.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [tracker.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [tracker.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [tracker.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
    ]];
#if !__has_feature(objc_arc)
    [tracker release];
#endif
    [self updateTopChromeBackgroundColor];
    UIViewController *content = self.session.codeLinkController;
    if (content) {
        [self addChildViewController:content];
        [self.view addSubview:content.view];
        [content didMoveToParentViewController:self];
    } else [self installWebContentWithBackground:initialBackground];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardSettled:) name:UIKeyboardDidShowNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardSettled:) name:UIKeyboardDidChangeFrameNotification object:nil];
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
    if (@available(iOS 18.0, *)) {
        STASH_WEAK_REF StashCheckoutViewController *weakSelf = self;
        UIUpdateLink *link = [UIUpdateLink updateLinkForView:self.view actionHandler:^(UIUpdateLink *updateLink, UIUpdateInfo *info) {
            StashCheckoutViewController *controller = weakSelf;
            if (![controller.session isActive]) return;
            [controller updateKeyboardGuideOcclusion];
            UIView *container = [controller layoutContainer];
            CGRect bounds = [controller availableBoundsInView:container];
            CGRect contentBounds = [controller availableBoundsInView:controller.view];
            if (!CGRectEqualToRect(bounds, controller.previousAvailableBounds)) {
                controller.previousAvailableBounds = bounds;
                [controller updatePresentationAnimated:NO];
            }
            if (!CGRectEqualToRect(contentBounds, controller.previousContentBounds)) {
                controller.previousContentBounds = contentBounds;
                [controller.view setNeedsLayout];
            }
        }];
        [link addActionToPhase:UIUpdateActionPhase.afterUpdateComplete handler:^(UIUpdateLink *updateLink, UIUpdateInfo *info) {
            [weakSelf updateKeyboardGuideOcclusion];
            [weakSelf.session retryRootOffsetRepair];
        }];
        link.requiresContinuousUpdates = NO;
        link.enabled = YES;
        self.geometryUpdateLink = link;
        if (@available(iOS 26.0, *)) {
            UITraitCollection *traits = [self layoutContainer].traitCollection;
            if (traits.userInterfaceIdiom == UIUserInterfaceIdiomPhone &&
                traits.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
                UIUpdateLink *entrance = [UIUpdateLink updateLinkForView:self.view];
                [entrance addActionToPhase:UIUpdateActionPhase.beforeCATransactionCommit
                    handler:^(UIUpdateLink *updateLink, UIUpdateInfo *info) { [weakSelf updateNativeEntrance]; }];
                entrance.enabled = YES;
                self.entranceUpdateLink = entrance;
            }
        }
    }
#endif
}
- (void)installWebContentWithBackground:(UIColor *)initialBackground {
    [self.view addSubview:self.session.webView];
    StashRemoveFormInputAccessoryView(self.session.webView);
    self.session.webView.accessibilityIdentifier = @"stash-web-content";
    UIPanGestureRecognizer *contentPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(contentPanChanged:)];
    contentPan.delegate = self;
    contentPan.cancelsTouchesInView = NO;
    contentPan.delaysTouchesBegan = NO;
    contentPan.delaysTouchesEnded = NO;
    self.contentPan = contentPan;
    [self.session.webView addGestureRecognizer:contentPan];
    [self observeContentScrollPans:self.session.webView];
#if !__has_feature(objc_arc)
    [contentPan release];
#endif
    if (!self.session.initialContentRevealed) {
        UIView *cover = [[UIView alloc] init];
        cover.backgroundColor = self.glassLoading ? UIColor.clearColor : initialBackground;
        cover.accessibilityIdentifier = @"stash-initial-loading";
        self.loadingCover = cover;
        [self.view addSubview:cover];
        self.session.webView.userInteractionEnabled = NO;
        self.session.webView.accessibilityElementsHidden = YES;
        if (self.glassLoading) self.session.webView.alpha = 0;
#if !__has_feature(objc_arc)
        [cover release];
#endif
    }
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner = spinner;
    spinner.hidesWhenStopped = YES;
    spinner.accessibilityIdentifier = @"stash-loading-spinner";
    spinner.accessibilityLabel = @"Loading checkout";
    [self.view addSubview:spinner];
    [spinner startAnimating];
#if !__has_feature(objc_arc)
    [spinner release];
#endif
}
- (void)updateNativeEntrance {
    if (self.entranceCorrection) {
        [self.entranceCorrection update];
        return;
    }
    id<UIViewControllerTransitionCoordinator> transition = self.transitionCoordinator;
    if (self.entranceCorrectionApplied || !self.isBeingPresented || !transition) return;
    // Inspect only the first presentation update. Never attach a correction mid-transition.
    self.entranceCorrectionApplied = YES;
    if (self.geometryTransitioning || !transition.isAnimated || transition.isInteractive ||
        transition.initiallyInteractive || transition.isCancelled || UIAccessibilityIsReduceMotionEnabled() ||
        [transition viewControllerForKey:UITransitionContextToViewControllerKey] != self) {
        [self stopNativeEntrance];
        return;
    }
    self.entranceCorrection = [StashNativeEntranceCorrection
        correctionForSurface:self.presentationController.presentedView.layer
        container:self.presentationController.containerView.layer];
    if (!self.entranceCorrection) [self stopNativeEntrance];
}
- (void)stopNativeEntrance {
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
    if (@available(iOS 18.0, *)) ((UIUpdateLink *)self.entranceUpdateLink).enabled = NO;
#endif
    self.entranceUpdateLink = nil;
    [self.entranceCorrection invalidate];
    self.entranceCorrection = nil;
    self.entranceCorrectionApplied = YES;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self stopNativeEntrance];
    [self.view setNeedsLayout];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self stopNativeEntrance];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateKeyboardGuideOcclusion];
    [self reconcileHostSafeAreaInsets];
    if (self.session.codeLinkController) {
        self.session.codeLinkController.view.frame = self.view.bounds;
        [self observeNativePans:self.presentationController.containerView];
        return;
    }
    CGFloat width = self.view.bounds.size.width;
    CGFloat top = self.view.safeAreaInsets.top;
    CGFloat bottom = self.view.bounds.size.height - self.view.safeAreaInsets.bottom;
    CGRect keyboard = [self resolvedKeyboardFrameInView:self.view dockedOnly:YES];
    if (!CGRectIsNull(keyboard)) {
        CGRect overlap = CGRectIntersection(self.view.bounds, keyboard);
        if (!CGRectIsNull(overlap) && overlap.size.width > width * 0.75 &&
            CGRectGetMaxY(overlap) >= CGRectGetMaxY(self.view.bounds) - 0.5) bottom = MIN(bottom, CGRectGetMinY(overlap));
    }
    CGRect content = CGRectMake(0, top, width, MAX(0, bottom - top));
    CGRect available = [self availableBoundsInView:self.view];
    content = CGRectIntersection(content, available);
    CGRect webFrame = CGRectIsNull(content) ? CGRectZero : content;
    CGFloat bottomInset = 0;
    if (!CGRectIsEmpty(webFrame)) {
        CGFloat safeBottom = CGRectGetMaxY(self.view.bounds) - self.view.safeAreaInsets.bottom;
        UIView *host = [self layoutContainer];
        if (self.view.window && (host == self.view.window || host.window == self.view.window)) {
            CGRect hostSafe = [self.view convertRect:UIEdgeInsetsInsetRect(host.bounds, host.safeAreaInsets) fromView:host];
            safeBottom = MIN(safeBottom, CGRectGetMaxY(hostSafe));
        }
        // Paint through the home-indicator area without extending across a keyboard or divider.
        if (fabs(CGRectGetMaxY(webFrame) - safeBottom) < 0.5) {
            CGFloat paintBottom = CGRectGetMaxY(self.view.bounds);
            if (!CGRectIsNull(keyboard)) {
                CGRect overlap = CGRectIntersection(self.view.bounds, keyboard);
                if (!CGRectIsNull(overlap) && overlap.size.width > width * 0.75 &&
                    CGRectGetMaxY(overlap) >= CGRectGetMaxY(self.view.bounds) - 0.5) paintBottom = MIN(paintBottom, CGRectGetMinY(overlap));
            }
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
            if (@available(iOS 27.1, *)) {
                CGRect strip = CGRectMake(webFrame.origin.x, CGRectGetMaxY(webFrame), webFrame.size.width,
                    MAX(0, paintBottom - CGRectGetMaxY(webFrame)));
                for (UIViewReservedRegionKind *kind in @[UIViewReservedRegionKind.occlusionRegionKind, UIViewReservedRegionKind.divisionRegionKind]) {
                    for (UIViewReservedRegion *region in [self.view reservedRegionsOfKind:kind]) {
                        if (!region.active) continue;
                        CGRect frame = region.frame;
                        if (frame.size.width == 0) frame.size.width = 1;
                        if (frame.size.height == 0) frame.size.height = 1;
                        if (CGRectIntersectsRect(strip, frame)) paintBottom = MIN(paintBottom, CGRectGetMinY(frame));
                    }
                }
            }
#endif
            bottomInset = MAX(0, paintBottom - CGRectGetMaxY(webFrame));
            webFrame.size.height += bottomInset;
        }
    }
    [self updateTopChromeBackgroundColor];
    BOOL viewportChanged = !CGSizeEqualToSize(self.session.webView.bounds.size, webFrame.size);
    self.session.webView.frame = webFrame;
    self.loadingCover.frame = webFrame;
    // A native content inset can shrink WebKit's viewport again after keyboard dismissal.
    self.session.webView.scrollView.contentInset = UIEdgeInsetsZero;
    self.session.webView.scrollView.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottomInset, 0);
    [self reconcileNativeContentSafeArea:bottomInset];
    self.spinner.center = CGPointMake(CGRectGetMidX(webFrame), CGRectGetMidY(webFrame));
    if (viewportChanged) { [self scheduleFocusReveal]; [self.session sampleTopChrome]; }
    [self observeContentScrollPans:self.session.webView];
    [self observeNativePans:self.presentationController.containerView];
    [self.session retryRootOffsetRepair];
    CGFloat contentWidth = self.session.webView.bounds.size.width;
    if (fabs(self.previousWidth - contentWidth) > 0.5) {
        self.previousWidth = contentWidth;
        self.session.measuredContentHeight = 0;
        self.session.measuredNativeWidth = 0;
        self.session.hasPendingContentHeight = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self.session isActive]) return;
            [self updatePresentationAnimated:NO];
            [self.session.webView evaluateJavaScript:@"if(window.__stashMeasureContent)window.__stashMeasureContent()" completionHandler:nil];
        });
    }
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateTopChromeBackgroundColor];
        [self.session sampleTopChrome];
    }
}
- (void)revealInitialContentAnimated:(BOOL)animated {
    UIView *cover = self.loadingCover;
    WKWebView *web = self.session.webView;
    if (!cover) {
        [self.spinner stopAnimating];
        web.userInteractionEnabled = YES;
        web.accessibilityElementsHidden = NO;
        return;
    }
    [cover.layer removeAllAnimations];
    BOOL glass = self.glassLoading;
    self.glassLoading = NO;
    void (^reveal)(void) = ^{
        [self updateTopChromeBackgroundColor];
        web.alpha = 1;
        cover.alpha = 0;
        self.spinner.alpha = 0;
    };
    void (^finish)(void) = ^{
        if (self.loadingCover != cover) return;
        [cover removeFromSuperview];
        self.loadingCover = nil;
        [self updateNativeLoadingBackground];
        [self.spinner stopAnimating];
        self.spinner.alpha = 1;
        web.userInteractionEnabled = YES;
        web.accessibilityElementsHidden = NO;
    };
    if (animated && cover.window && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:glass ? 0.25 : 0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState |
            UIViewAnimationOptionCurveEaseOut animations:reveal
            completion:^(BOOL finished) { finish(); }];
    } else {
        [UIView performWithoutAnimation:reveal];
        finish();
    }
}
- (void)reconcileHostSafeAreaInsets {
    if (!self.view.window) return;
    UIView *host = [self layoutContainer];
    if (host != self.view.window && host.window != self.view.window) return;
    CGFloat observed = self.view.safeAreaInsets.bottom;
    if (self.awaitingHostSafeAreaUpdate) {
        // Do not subtract an addition that UIKit has not propagated yet.
        if (fabs(observed - self.hostSafeAreaBeforeUpdate) < 0.5) return;
        self.awaitingHostSafeAreaUpdate = NO;
    }
    CGRect hostSafe = [self.view convertRect:UIEdgeInsetsInsetRect(host.bounds, host.safeAreaInsets) fromView:host];
    CGFloat required = MIN(self.view.bounds.size.height, MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMaxY(hostSafe)));
    UIEdgeInsets additional = self.additionalSafeAreaInsets;
    CGFloat inherited = MAX(0, observed - additional.bottom);
    CGFloat correction = MAX(0, required - inherited);
    if (fabs(additional.bottom - correction) < 0.5) return;
    self.hostSafeAreaBeforeUpdate = observed;
    self.awaitingHostSafeAreaUpdate = YES;
    additional.bottom = correction;
    NSUInteger generation = ++self.hostSafeAreaUpdateGeneration;
    self.additionalSafeAreaInsets = additional;
    dispatch_async(dispatch_get_main_queue(), ^{ [self completeHostSafeAreaUpdate:generation]; });
}
- (void)completeHostSafeAreaUpdate:(NSUInteger)generation {
    if (generation != self.hostSafeAreaUpdateGeneration) return;
    if (self.session.closing || !self.viewIfLoaded.window) {
        self.awaitingHostSafeAreaUpdate = NO;
        return;
    }
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    if (generation != self.hostSafeAreaUpdateGeneration) return;
    // UIKit can change its inherited inset while applying ours, leaving the total unchanged.
    self.awaitingHostSafeAreaUpdate = NO;
    [self.view setNeedsLayout];
}
- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self updatePresentationAnimated:NO];
}
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    self.geometryTransitioning = YES;
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self updatePresentationAnimated:NO];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        self.geometryTransitioning = NO;
        [self.session retryRootOffsetRepair];
        [self updatePresentationAnimated:NO];
        [self.view layoutIfNeeded];
        [self scheduleFocusReveal];
    }];
}
- (BOOL)accessibilityPerformEscape {
    if (![self.session canUserDismiss]) return NO;
    [self.session finishWithUserDismiss:YES completion:nil];
    return YES;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.session.presentationPresenter ? self.session.presentationPresenter.supportedInterfaceOrientations : UIInterfaceOrientationMaskAll;
}
- (BOOL)shouldAutorotate { return YES; }
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
    return expanded ? expandedHeight : resting;
}
- (void)observeContentScrollPans:(UIView *)view {
    if (!self.contentScrollPans) self.contentScrollPans = [NSHashTable weakObjectsHashTable];
    if ([view isKindOfClass:UIScrollView.class]) {
        UIPanGestureRecognizer *pan = ((UIScrollView *)view).panGestureRecognizer;
        if (![self.contentScrollPans containsObject:pan]) {
            [pan requireGestureRecognizerToFail:self.contentPan];
            [pan addTarget:self action:@selector(nativePanChanged:)];
            [self.contentScrollPans addObject:pan];
        }
    }
    for (UIView *child in view.subviews) [self observeContentScrollPans:child];
}
- (void)observeNativePans:(UIView *)view {
    if (!view || view == self.session.webView) return;
    if (view == self.presentationController.containerView && self.touchOriginObserver.view != view) {
        if (!self.touchOriginObserver) {
            UITapGestureRecognizer *observer = [[UITapGestureRecognizer alloc] init];
            observer.delegate = self;
            observer.cancelsTouchesInView = NO;
            observer.delaysTouchesBegan = NO;
            observer.delaysTouchesEnded = NO;
            self.touchOriginObserver = observer;
#if !__has_feature(objc_arc)
            [observer release];
#endif
        }
        [view addGestureRecognizer:self.touchOriginObserver];
    }
    if (!self.observedPans) self.observedPans = [NSMutableArray array];
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        if ([gesture isKindOfClass:UIPanGestureRecognizer.class] && ![self.observedPans containsObject:(UIPanGestureRecognizer *)gesture]) {
            [gesture addTarget:self action:@selector(nativePanChanged:)];
            [self.observedPans addObject:(UIPanGestureRecognizer *)gesture];
        }
    }
    for (UIView *child in view.subviews) [self observeNativePans:child];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.contentPan) {
        self.contentTouchView = touch.view;
        [self observeContentScrollPans:self.session.webView];
        return YES;
    }
    if (gestureRecognizer != self.touchOriginObserver) return YES;
    self.touchBeganInWebContent = [touch.view isDescendantOfView:self.session.webView];
    [self updateDismissalPolicy];
    // Observe the origin without recognizing, delaying, or cancelling any touch.
    return NO;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.contentPan) return YES;
    CGPoint velocity = [self.contentPan velocityInView:self.session.webView];
    if (fabs(velocity.y) <= fabs(velocity.x)) return NO;
    if (velocity.y < 0 && ![self usesFloatingNativeSizing] && !self.singleDetent &&
        !self.session.expanded && !self.session.keyboardVisible) return YES;
    for (UIView *view = self.contentTouchView; view && view != self.session.webView; view = view.superview) {
        if (![view isKindOfClass:UIScrollView.class]) continue;
        UIScrollView *scroll = (UIScrollView *)view;
        if (!scroll.scrollEnabled) continue;
        CGFloat minimum = -scroll.adjustedContentInset.top;
        CGFloat maximum = MAX(minimum, scroll.contentSize.height - scroll.bounds.size.height + scroll.adjustedContentInset.bottom);
        if ((velocity.y > 0 && scroll.contentOffset.y > minimum + 0.5) ||
            (velocity.y < 0 && scroll.contentOffset.y < maximum - 0.5)) return NO;
    }
    // Consume an edge pull before WebKit can hand it to the native sheet.
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer != self.contentPan) return NO;
    return [otherGestureRecognizer.view isDescendantOfView:self.session.webView] &&
        ![self.contentScrollPans containsObject:(id)otherGestureRecognizer];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    UIView *otherView = otherGestureRecognizer.view;
    return gestureRecognizer == self.contentPan && [otherGestureRecognizer isKindOfClass:UIPanGestureRecognizer.class] && otherView != self.session.webView &&
        ![otherGestureRecognizer isKindOfClass:UIScreenEdgePanGestureRecognizer.class] &&
        [self.session.webView isDescendantOfView:otherView];
}
- (void)contentPanChanged:(UIPanGestureRecognizer *)gesture {
    [self nativePanChanged:gesture];
    if (gesture.state != UIGestureRecognizerStateBegan || ![self.session isActive] ||
        [self usesFloatingNativeSizing] || self.singleDetent || self.session.expanded || self.session.keyboardVisible ||
        [gesture velocityInView:self.session.webView].y >= 0) return;
    self.session.expanded = YES;
    self.hasRequestedNativeSelection = YES;
    self.requestedNativeExpanded = YES;
    UISheetPresentationController *sheet = self.sheetPresentationController;
    void (^expand)(void) = ^{ sheet.selectedDetentIdentifier = [self nativeDetentIdentifierForExpanded:YES]; };
    if (UIAccessibilityIsReduceMotionEnabled()) expand(); else [sheet animateChanges:expand];
}
- (void)nativePanChanged:(UIPanGestureRecognizer *)gesture {
    BOOL wasDragging = self.dragging;
    BOOL dragging = gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged;
    UIGestureRecognizerState webState = self.session.webView.scrollView.panGestureRecognizer.state;
    dragging |= webState == UIGestureRecognizerStateBegan || webState == UIGestureRecognizerStateChanged;
    UIGestureRecognizerState expansionState = self.contentPan.state;
    dragging |= expansionState == UIGestureRecognizerStateBegan || expansionState == UIGestureRecognizerStateChanged;
    for (UIPanGestureRecognizer *pan in self.observedPans)
        dragging |= pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged;
    for (UIPanGestureRecognizer *pan in self.contentScrollPans)
        dragging |= pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged;
    self.dragging = dragging;
    if (wasDragging && !dragging) {
        [self.session retryRootOffsetRepair];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self.session isActive] || self.dragging) return;
            BOOL deferred = self.deferredContentLayout;
            self.deferredContentLayout = NO;
            [self.session applyPendingContentHeight];
            if (deferred) [self updatePresentationAnimated:NO];
            [self.viewIfLoaded setNeedsLayout];
        });
    }
}
- (void)contentHeightDidChange {
    if (self.dragging) self.deferredContentLayout = YES;
    else [self updatePresentationAnimated:YES];
}
- (void)updateDismissalPolicy {
    self.modalInPresentation = !self.session.config.allowDismiss || self.session.processing ||
        self.session.codeLinkCompleted || self.touchBeganInWebContent;
    self.sheetPresentationController.prefersGrabberVisible = !self.session.processing;
}
- (void)keyboardChanged:(NSNotification *)note {
    if (![self.session isActive] || !self.view.window) return;
    BOOL ownsResponder = StashContainsFirstResponder(self.session.webView);
    if (!self.keyboardEpisodeOwned && !ownsResponder) return;
    if ([note.object isKindOfClass:UIScreen.class] && note.object != self.view.window.screen) return;
    StashRemoveFormInputAccessoryView(self.session.webView);
    self.keyboardFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    self.keyboardNotificationWindow = self.view.window;
    self.keyboardNotificationWindowBounds = self.view.window.bounds;
    self.keyboardNotificationOrientation = StashKeyboardWindowOrientation(self.view.window);
    CGRect keyboard = self.view.window ? [self.view.window convertRect:self.keyboardFrame fromCoordinateSpace:self.view.window.screen.coordinateSpace] : CGRectZero;
    BOOL hide = [note.name isEqualToString:UIKeyboardWillHideNotification];
    CGRect overlap = CGRectIntersection(self.view.window.bounds, keyboard);
    CGFloat safeBottom = CGRectGetMaxY(self.view.window.bounds) - self.view.window.safeAreaInsets.bottom;
    BOOL visible = !CGRectIsNull(overlap) && overlap.size.width > 0.5 && overlap.size.height > 0.5 &&
        CGRectGetMinY(overlap) < safeBottom - 0.5;
    // A real keyboard notification establishes ownership; WK can remain first responder for BODY or buttons.
    if (visible && ownsResponder) self.keyboardEpisodeOwned = YES;
    self.keyboardNotificationVisible = visible && (!hide || ownsResponder);
    self.keyboardNotificationHiding = hide;
    [self updateKeyboardGuideOcclusion];
    [self updatePresentationAnimated:YES];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}
- (void)keyboardSettled:(NSNotification *)note {
    if ([self.session isActive] && self.session.keyboardVisible)
        StashRemoveFormInputAccessoryView(self.session.webView);
    [self scheduleFocusReveal];
}
- (void)updateKeyboardGuideOcclusion {
    if (![self.session isActive] || !self.view.window) return;
    CGRect frame = self.view.keyboardLayoutGuide.layoutFrame;
    BOOL frameChanged = !self.hasKeyboardGuideFrame || !CGRectEqualToRect(frame, self.previousKeyboardGuideFrame);
    self.previousKeyboardGuideFrame = frame;
    self.hasKeyboardGuideFrame = YES;
    UIWindow *window = self.view.window;
    CGRect windowFrame = [window convertRect:frame fromView:self.view];
    CGRect windowOverlap = CGRectIntersection(window.bounds, windowFrame);
    CGFloat safeBottom = CGRectGetMaxY(window.bounds) - window.safeAreaInsets.bottom;
    // The hidden guide can retain the home-indicator inset even with usesBottomSafeArea disabled.
    BOOL inWindow = !CGRectIsNull(windowOverlap) && windowOverlap.size.width > 0.5 &&
        windowOverlap.size.height > 0.5 && CGRectGetMinY(windowOverlap) < safeBottom - 0.5;
    // A floating sheet's hidden guide can extend from its own bottom to the window bottom.
    BOOL belowContentBaseline = CGRectGetMinY(frame) >= CGRectGetMaxY(self.view.bounds) - 0.5 &&
        windowFrame.size.width >= window.bounds.size.width * 0.75 && CGRectGetMaxY(windowFrame) >= safeBottom - 0.5;
    if (!self.keyboardNotificationVisible && belowContentBaseline) inWindow = NO;
    if (self.keyboardEpisodeOwned && inWindow) self.keyboardGuideWasVisible = YES;
    if (self.keyboardNotificationHiding && self.keyboardGuideWasVisible && !inWindow)
        self.keyboardNotificationVisible = NO;
    if (!StashContainsFirstResponder(self.session.webView)) {
        self.keyboardEpisodeOwned = NO;
        self.keyboardNotificationVisible = NO;
    }
    BOOL visible = self.keyboardEpisodeOwned && (self.keyboardNotificationVisible || inWindow);
    if (!visible) {
        self.keyboardEpisodeOwned = NO;
        self.keyboardGuideWasVisible = NO;
        self.keyboardNotificationWindow = nil;
    }
    BOOL visibilityChanged = visible != self.session.keyboardVisible;
    self.session.keyboardVisible = visible;
    BOOL undocked = visible && inWindow && !StashKeyboardFrameIsDocked(windowFrame, window) &&
        !StashKeyboardGuideIsInsetDocked(windowFrame, window, self.view);
    BOOL geometryChanged = visibilityChanged || undocked != self.keyboardGuideUndocked;
    self.keyboardGuideUndocked = undocked;
    if (visibilityChanged) {
        if (visible) [self.session revealInitialContent];
        else [self.session.webView evaluateJavaScript:@"if(window.__stashSetKeyboardOcclusion)window.__stashSetKeyboardOcclusion(null)" completionHandler:nil];
    }
    if (!frameChanged && !geometryChanged) return;
    if ((geometryChanged || (frameChanged && visible)) && !self.keyboardGuideLayoutQueued) {
        self.keyboardGuideLayoutQueued = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.keyboardGuideLayoutQueued = NO;
            if (![self.session isActive] || !self.view.window) return;
            [self updatePresentationAnimated:NO];
            [self.view setNeedsLayout];
            [self.view layoutIfNeeded];
            [self scheduleFocusReveal];
        });
    }
    [self scheduleFocusReveal];
}
- (CGRect)resolvedKeyboardFrameInView:(UIView *)view dockedOnly:(BOOL)dockedOnly {
    UIView *content = self.viewIfLoaded;
    UIWindow *window = content.window;
    if (!self.session.keyboardVisible || !self.keyboardEpisodeOwned || !window ||
        self.session.webView.window != window || (view != window && view.window != window)) return CGRectNull;
    CGRect guide = CGRectNull;
    BOOL clampedBelowContent = NO;
    if (self.hasKeyboardGuideFrame) {
        CGRect local = content.keyboardLayoutGuide.layoutFrame;
        CGRect candidate = [window convertRect:local fromView:content];
        // A floating sheet can clamp the docked guide below its own content bounds.
        clampedBelowContent = StashKeyboardFrameIsDocked(candidate, window) &&
            CGRectGetMinY(local) >= CGRectGetMaxY(content.bounds) - 0.5;
        if (StashKeyboardFrameIsVisible(candidate, window) && !clampedBelowContent) guide = candidate;
    }
    CGRect notification = CGRectNull;
    BOOL sameContext = self.keyboardNotificationWindow == window &&
        CGRectEqualToRect(self.keyboardNotificationWindowBounds, window.bounds) &&
        self.keyboardNotificationOrientation == StashKeyboardWindowOrientation(window);
    if (sameContext && self.keyboardNotificationVisible && !self.keyboardNotificationHiding) {
        CGRect candidate = [window convertRect:self.keyboardFrame fromCoordinateSpace:window.screen.coordinateSpace];
        if (StashKeyboardFrameIsVisible(candidate, window)) notification = candidate;
    }
    CGRect keyboard = CGRectNull;
    BOOL guideDocked = !CGRectIsNull(guide) && (StashKeyboardFrameIsDocked(guide, window) ||
        StashKeyboardGuideIsInsetDocked(guide, window, content));
    if (!CGRectIsNull(guide)) {
        // Native sheets can anchor an otherwise matching guide above the window's bottom inset.
        BOOL insetGuide = StashKeyboardGuideIsInsetDocked(guide, window, content) &&
            StashKeyboardFrameIsDocked(notification, window) &&
            fabs(guide.size.width - notification.size.width) <= 0.5 &&
            fabs(guide.size.height - notification.size.height) <= 0.5 &&
            fabs(CGRectGetMinX(guide) - CGRectGetMinX(notification)) <= 0.5;
        if (insetGuide) {
            keyboard = notification;
        } else if (!guideDocked) {
            // A current undocked guide wins over a previous full-width notification.
            if (dockedOnly) return CGRectNull;
            keyboard = guide;
        } else {
            keyboard = guide;
            // Either source can lag; keep the earlier valid docked top.
            if (StashKeyboardFrameIsDocked(notification, window) &&
                CGRectGetMinY(notification) < CGRectGetMinY(guide)) keyboard = notification;
        }
    } else if (!self.hasKeyboardGuideFrame || !self.keyboardGuideWasVisible || clampedBelowContent) {
        // Notifications provide the initial geometry before a usable guide arrives.
        keyboard = notification;
    }
    if (CGRectIsNull(keyboard) || (dockedOnly && !StashKeyboardFrameIsDocked(keyboard, window) &&
        !(guideDocked && CGRectEqualToRect(keyboard, guide)))) return CGRectNull;
    return view == window ? keyboard : [view convertRect:keyboard fromView:window];
}
- (NSArray<NSNumber *> *)focusKeyboardOcclusion {
    WKWebView *web = self.session.webView;
    if (CGRectIsEmpty(web.bounds)) return nil;
    CGRect keyboard = [self resolvedKeyboardFrameInView:web dockedOnly:NO];
    if (CGRectIsNull(keyboard)) return nil;
    CGRect overlap = CGRectIntersection(web.bounds, keyboard);
    if (CGRectIsNull(overlap) || CGRectIsEmpty(overlap)) return nil;
    return @[@(overlap.origin.x - web.bounds.origin.x), @(overlap.origin.y - web.bounds.origin.y),
        @(overlap.size.width), @(overlap.size.height), @(web.bounds.size.width), @(web.bounds.size.height)];
}
- (void)scheduleFocusReveal {
    if (![self.session isActive] || !self.session.keyboardVisible || !self.view.window) return;
    if (self.focusRevealQueued) return;
    self.focusRevealQueued = YES;
    WKWebView *web = self.session.webView;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.focusRevealQueued = NO;
        if (![self.session isActive] || !self.session.keyboardVisible || !self.view.window || self.session.webView != web) return;
        [web layoutIfNeeded];
        [self normalizeIdleRootScrollOffset];
        NSArray *occlusion = [self focusKeyboardOcclusion];
        NSData *data = occlusion ? [NSJSONSerialization dataWithJSONObject:occlusion options:0 error:nil] : nil;
        NSString *value = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        NSString *script = [NSString stringWithFormat:@"if(window.__stashSetKeyboardOcclusion)window.__stashSetKeyboardOcclusion(%@);"
            @"if(window.__stashRevealFocusedElement)window.__stashRevealFocusedElement()", value ?: @"null"];
        [web evaluateJavaScript:script completionHandler:nil];
#if !__has_feature(objc_arc)
        [value release];
#endif
    });
}
- (BOOL)canNormalizeIdleRootScrollOffset {
    WKWebView *web = self.session.webView;
    UIScrollView *scroll = web.scrollView;
    return [self.session isActive] && web.window && !self.geometryTransitioning && !self.dragging && !self.updatingLayout &&
        !scroll.tracking && !scroll.dragging && !scroll.decelerating && !scroll.zooming && !scroll.zoomBouncing;
}
- (BOOL)normalizeIdleRootScrollOffset {
    WKWebView *web = self.session.webView;
    UIScrollView *scroll = web.scrollView;
    if (![self canNormalizeIdleRootScrollOffset]) return NO;
    UIEdgeInsets insets = scroll.adjustedContentInset;
    CGRect keyboard = [self resolvedKeyboardFrameInView:web dockedOnly:YES];
    if (!CGRectIsNull(keyboard) && fabs(CGRectGetMinY(keyboard) - CGRectGetMaxY(web.bounds)) <= 1 &&
        CGRectGetMinX(keyboard) <= CGRectGetMinX(web.bounds) + 0.5 &&
        CGRectGetMaxX(keyboard) >= CGRectGetMaxX(web.bounds) - 0.5 && isfinite(scroll.contentInset.bottom)) {
        // The viewport already ends above this keyboard; its automatic bottom inset is redundant.
        insets.bottom = scroll.contentInset.bottom;
    }
    CGPoint minimum = CGPointMake(-insets.left, -insets.top);
    CGPoint maximum = CGPointMake(MAX(minimum.x, scroll.contentSize.width - scroll.bounds.size.width + insets.right),
        MAX(minimum.y, scroll.contentSize.height - scroll.bounds.size.height + insets.bottom));
    CGPoint offset = scroll.contentOffset;
    if (!isfinite(offset.x) || !isfinite(offset.y) || !isfinite(maximum.x) || !isfinite(maximum.y)) return NO;
    CGPoint clamped = CGPointMake(MIN(maximum.x, MAX(minimum.x, offset.x)), MIN(maximum.y, MAX(minimum.y, offset.y)));
    if (fabs(clamped.x - offset.x) < 0.5 && fabs(clamped.y - offset.y) < 0.5) return NO;
    // WebKit can retain a pre-resize root offset after keyboard expansion, shifting DOM and accessibility coordinates.
    [scroll setContentOffset:clamped animated:NO];
    return YES;
}
- (void)updateTopChromeBackgroundColor {
    if (self.session.codeLink) {
        self.view.backgroundColor = UIColor.blackColor;
        return;
    }
    if (self.glassLoading) {
        self.view.backgroundColor = UIColor.clearColor;
        return;
    }
    UIColor *color = self.topChromeColor;
    color = color ?: self.session.webView.underPageBackgroundColor ?: stash_sheetBackgroundUIColor();
    self.view.backgroundColor = color;
}
- (void)dealloc {
    [self stopNativeEntrance];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    for (UIPanGestureRecognizer *gesture in self.observedPans) [gesture removeTarget:self action:@selector(nativePanChanged:)];
    self.touchOriginObserver.delegate = nil;
    [self.touchOriginObserver.view removeGestureRecognizer:self.touchOriginObserver];
    for (UIPanGestureRecognizer *pan in self.contentScrollPans) [pan removeTarget:self action:@selector(nativePanChanged:)];
    self.contentPan.delegate = nil;
    [self.contentPan.view removeGestureRecognizer:self.contentPan];
#if !__has_feature(objc_arc)
    [_spinner release]; [_loadingCover release]; [_topChromeColor release];
    [_observedPans release]; [_geometryUpdateLink release]; [_keyboardGuideTracker release];
    [_touchOriginObserver release];
    [_contentPan release];
    [_contentScrollPans release];
    [_entranceCorrection release]; [super dealloc];
#endif
}
@end
