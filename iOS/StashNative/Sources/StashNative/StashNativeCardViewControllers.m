#import "StashNativePrivate.h"
#import <math.h>

@implementation StashCardViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    UIColor *initialBackground = StashSheetBackgroundUIColor(self.session.presenter.traitCollection ?: self.traitCollection);
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
    UIViewController *content = self.session.scannerController;
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
        STASH_WEAK_REF StashCardViewController *weakSelf = self;
        UIUpdateLink *link = [UIUpdateLink updateLinkForView:self.view actionHandler:^(UIUpdateLink *updateLink, UIUpdateInfo *info) {
            StashCardViewController *controller = weakSelf;
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
    UIPanGestureRecognizer *contentPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(nativePanChanged:)];
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
    [self.session presentedSurfaceDidDisappear:self];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateKeyboardGuideOcclusion];
    [self reconcileHostSafeAreaInsets];
    if (self.session.scannerController) {
        self.session.scannerController.view.frame = self.view.bounds;
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
    [self cancelContentExpansion];
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
- (void)updateTopChromeBackgroundColor {
    if (self.session.scanner) {
        self.view.backgroundColor = UIColor.blackColor;
        return;
    }
    if (self.glassLoading) {
        self.view.backgroundColor = UIColor.clearColor;
        return;
    }
    UIColor *color = self.topChromeColor;
    color = color ?: self.session.webView.underPageBackgroundColor ?: StashSheetBackgroundUIColor(self.session.presenter.traitCollection ?: self.traitCollection);
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
    [_observedPans release]; [_geometryUpdateLink release];
    [_touchOriginObserver release];
    [_contentPan release];
    [_contentScrollPans release];
    [_entranceCorrection release]; [super dealloc];
#endif
}
@end
