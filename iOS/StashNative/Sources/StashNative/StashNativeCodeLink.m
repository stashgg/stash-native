#import "StashNativeCardPrivate.h"
#import <AVFoundation/AVFoundation.h>

@interface StashCodeLinkPreview : UIView
@end
@implementation StashCodeLinkPreview
+ (Class)layerClass { return AVCaptureVideoPreviewLayer.class; }
@end

static UILabel *StashCodeLinkLabel(NSString *text, UIFontTextStyle style, CGFloat alpha) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = [UIColor.whiteColor colorWithAlphaComponent:alpha];
    label.numberOfLines = 0;
#if !__has_feature(objc_arc)
    return [label autorelease];
#else
    return label;
#endif
}

@interface StashCodeLinkViewController () <AVCaptureMetadataOutputObjectsDelegate> {
    dispatch_queue_t _cameraQueue;
}
@property (nonatomic, strong) AVCaptureSession *capture;
@property (nonatomic, strong) AVCaptureMetadataOutput *metadata;
@property (nonatomic, strong) StashCodeLinkPreview *preview;
@property (nonatomic, strong) UILabel *heading;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIVisualEffectView *callout;
@property (nonatomic, strong) CAShapeLayer *frameLayer;
@property (nonatomic, strong) CAShapeLayer *shadeLayer;
@property (nonatomic, strong) UIStackView *status;
@property (nonatomic, strong) UILabel *statusTitle;
@property (nonatomic, strong) UILabel *statusMessage;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIVisualEffectView *confirmation;
@property (nonatomic) CGRect scanFrame;
@property (nonatomic) BOOL visible;
@property (nonatomic) BOOL disposed;
@property (nonatomic) BOOL requestingAccess;
@property (nonatomic) BOOL configurationAttempted;
@property (nonatomic) BOOL captureReady;
@property (nonatomic) BOOL scanning;
@property (nonatomic) BOOL errorReported;
@end

@implementation StashCodeLinkViewController
- (instancetype)init {
    self = [super init];
    if (self) {
        _cameraQueue = dispatch_queue_create("gg.stash.native.CodeLink.camera", DISPATCH_QUEUE_SERIAL);
        _capture = [[AVCaptureSession alloc] init];
        _metadata = [[AVCaptureMetadataOutput alloc] init];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
            UISceneDidActivateNotification, UISceneWillDeactivateNotification])
            [center addObserver:self selector:@selector(activityChanged:) name:name object:nil];
        for (NSString *name in @[AVCaptureSessionDidStartRunningNotification, AVCaptureSessionWasInterruptedNotification,
            AVCaptureSessionInterruptionEndedNotification, AVCaptureSessionRuntimeErrorNotification])
            [center addObserver:self selector:@selector(captureChanged:) name:name object:_capture];
    }
    return self;
}
- (AVCaptureVideoPreviewLayer *)previewLayer { return (AVCaptureVideoPreviewLayer *)self.preview.layer; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.view.accessibilityIdentifier = @"stash-code-link";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    StashCodeLinkPreview *preview = [[StashCodeLinkPreview alloc] init];
    self.preview = preview;
    preview.userInteractionEnabled = NO;
    preview.alpha = 0;
    [self.view addSubview:preview];
    self.previewLayer.session = self.capture;
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.shadeLayer = [CAShapeLayer layer];
    self.shadeLayer.fillRule = kCAFillRuleEvenOdd;
    self.shadeLayer.fillColor = [UIColor colorWithWhite:0 alpha:0.22].CGColor;
    [self.view.layer addSublayer:self.shadeLayer];
    self.frameLayer = [CAShapeLayer layer];
    self.frameLayer.fillColor = UIColor.clearColor.CGColor;
    self.frameLayer.strokeColor = UIColor.whiteColor.CGColor;
    self.frameLayer.lineWidth = 2;
    [self.view.layer addSublayer:self.frameLayer];
    self.heading = StashCodeLinkLabel(@"Scan QR code", UIFontTextStyleTitle3, 1);
    [self.view addSubview:self.heading];
    self.closeButton = [UIButton buttonWithType:UIButtonTypeClose];
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        UIButtonConfiguration *button = [UIButtonConfiguration glassButtonConfiguration];
        button.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        button.baseForegroundColor = UIColor.whiteColor;
        button.image = [UIImage systemImageNamed:@"xmark" withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]];
        self.closeButton.configuration = button;
    }
#endif
    self.closeButton.accessibilityLabel = @"Close scanner";
    self.closeButton.accessibilityIdentifier = @"stash-code-link-close";
    [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.closeButton];
    [self installCallout];
    [self installStatus];
#if !__has_feature(objc_arc)
    [preview release];
#endif
}
- (void)installCallout {
    UIVisualEffectView *callout = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    self.callout = callout;
    callout.layer.cornerRadius = 20;
    callout.layer.cornerCurve = kCACornerCurveContinuous;
    callout.clipsToBounds = YES;
    callout.accessibilityIdentifier = @"stash-code-link-callout";
    [self.view addSubview:callout];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"viewfinder"]];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeCenter;
    icon.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.06];
    icon.layer.cornerRadius = 12;
    icon.isAccessibilityElement = NO;
    UILabel *title = StashCodeLinkLabel(@"Scan the webshop code", UIFontTextStyleHeadline, 1);
    UILabel *subtitle = StashCodeLinkLabel(@"Keep the QR code centered inside the frame.", UIFontTextStyleFootnote, 0.65);
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 4;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [callout.contentView addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:44], [icon.heightAnchor constraintEqualToConstant:44],
        [row.leadingAnchor constraintEqualToAnchor:callout.contentView.leadingAnchor constant:14],
        [row.trailingAnchor constraintEqualToAnchor:callout.contentView.trailingAnchor constant:-14],
        [row.topAnchor constraintEqualToAnchor:callout.contentView.topAnchor constant:14],
        [row.bottomAnchor constraintEqualToAnchor:callout.contentView.bottomAnchor constant:-14]
    ]];
#if !__has_feature(objc_arc)
    [callout release]; [icon release]; [text release]; [row release];
#endif
}
- (void)installStatus {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner = spinner;
    [spinner startAnimating];
    self.statusTitle = StashCodeLinkLabel(@"Starting camera", UIFontTextStyleHeadline, 1);
    self.statusMessage = StashCodeLinkLabel(@"", UIFontTextStyleFootnote, 0.7);
    self.statusTitle.textAlignment = NSTextAlignmentCenter;
    self.statusMessage.textAlignment = NSTextAlignmentCenter;
    self.settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.settingsButton setTitle:@"Open Settings" forState:UIControlStateNormal];
    self.settingsButton.tintColor = UIColor.whiteColor;
    self.settingsButton.hidden = YES;
    [self.settingsButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *status = [[UIStackView alloc] initWithArrangedSubviews:
        @[spinner, self.statusTitle, self.statusMessage, self.settingsButton]];
    self.status = status;
    status.axis = UILayoutConstraintAxisVertical;
    status.alignment = UIStackViewAlignmentCenter;
    status.spacing = 8;
    status.accessibilityIdentifier = @"stash-code-link-status";
    [self.view addSubview:status];
#if !__has_feature(objc_arc)
    [spinner release]; [status release];
#endif
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat left = MAX(16, safe.left + 16), right = MAX(16, safe.right + 16);
    CGFloat width = MAX(0, bounds.size.width - left - right);
    CGFloat top = MAX(24, safe.top + 12);
    self.preview.frame = bounds;
    self.confirmation.frame = bounds;
    self.closeButton.frame = CGRectMake(CGRectGetMaxX(bounds) - right - 44, top, 44, 44);
    CGSize heading = [self.heading sizeThatFits:CGSizeMake(MAX(0, width - 56), CGFLOAT_MAX)];
    self.heading.frame = CGRectMake(left + 4, top + MAX(0, (44 - heading.height) / 2), MAX(0, width - 56), heading.height);
    CGSize callout = [self.callout.contentView systemLayoutSizeFittingSize:CGSizeMake(width, 0)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    self.callout.frame = CGRectMake(left, MAX(0, bounds.size.height - safe.bottom - 16 - callout.height), width, callout.height);
    CGFloat start = MAX(CGRectGetMaxY(self.heading.frame), CGRectGetMaxY(self.closeButton.frame)) + 20;
    CGFloat end = CGRectGetMinY(self.callout.frame) - 20;
    CGFloat side = MAX(0, MIN(width * 0.84, end - start));
    self.scanFrame = CGRectMake((bounds.size.width - side) / 2, start + MAX(0, (end - start - side) / 2), side, side);
    UIBezierPath *frame = [UIBezierPath bezierPathWithRoundedRect:self.scanFrame cornerRadius:MIN(28, side / 8)];
    UIBezierPath *shade = [UIBezierPath bezierPathWithRect:bounds];
    [shade appendPath:frame];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.shadeLayer.frame = bounds;
    self.shadeLayer.path = shade.CGPath;
    self.frameLayer.frame = bounds;
    self.frameLayer.path = frame.CGPath;
    [CATransaction commit];
    CGFloat statusWidth = MAX(0, side - 24);
    CGSize status = [self.status systemLayoutSizeFittingSize:CGSizeMake(statusWidth, 0)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    self.status.frame = CGRectMake(CGRectGetMidX(self.scanFrame) - statusWidth / 2,
        CGRectGetMidY(self.scanFrame) - status.height / 2, statusWidth, status.height);
    [self updateCameraGeometry];
}
- (void)updateCameraGeometry {
    if (!self.captureReady || self.disposed) return;
    AVCaptureConnection *connection = self.previewLayer.connection;
    UIWindowScene *scene = self.view.window.windowScene;
    UIInterfaceOrientation orientation = scene.interfaceOrientation;
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) orientation = scene.effectiveGeometry.interfaceOrientation;
#endif
    if (!scene) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // Scene-less game hosts still expose their orientation through the root controller.
        orientation = self.view.window.rootViewController.interfaceOrientation;
#pragma clang diagnostic pop
    }
    if (orientation != UIInterfaceOrientationUnknown && connection.isVideoOrientationSupported &&
        connection.videoOrientation != (AVCaptureVideoOrientation)orientation)
        connection.videoOrientation = (AVCaptureVideoOrientation)orientation;
    CGRect region = [self.previewLayer metadataOutputRectOfInterestForRect:self.scanFrame];
    region = CGRectIntersection(region, CGRectMake(0, 0, 1, 1));
    if (CGRectIsNull(region) || CGRectIsEmpty(region)) return;
    dispatch_async(_cameraQueue, ^{ self.metadata.rectOfInterest = region; });
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.visible = YES;
    [self requestCamera];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopScanning];
}
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // A half-turn can change camera orientation without changing the view's bounds.
        [self updateCameraGeometry];
    }];
}
- (BOOL)canScan {
    UIWindow *window = self.viewIfLoaded.window;
    UIWindowScene *scene = window.windowScene;
    BOOL foreground = scene ? scene.activationState == UISceneActivationStateForegroundActive
        : UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    return !self.disposed && self.visible && !self.session.codeLinkCompleted && [self.session isActive] && self.viewIfLoaded.window &&
        foreground;
}
- (void)requestCamera {
    if (![self canScan]) return;
    id purpose = [NSBundle.mainBundle objectForInfoDictionaryKey:@"NSCameraUsageDescription"];
    if (![purpose isKindOfClass:NSString.class] || ![purpose length]) {
        [self cameraFailed:StashNativeCodeLinkErrorMissingCameraUsageDescription
            message:@"CodeLink requires NSCameraUsageDescription in the host app's Info.plist."];
        return;
    }
    if (!self.configurationAttempted && ![AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
        mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack]) {
        [self cameraFailed:StashNativeCodeLinkErrorCameraUnavailable message:@"No camera is available for QR scanning."];
        return;
    }
    AVAuthorizationStatus authorization = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (authorization == AVAuthorizationStatusNotDetermined) {
        if (self.requestingAccess) return;
        self.requestingAccess = YES;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.requestingAccess = NO;
                if ([self canScan]) [self requestCamera];
            });
        }];
    } else if (authorization != AVAuthorizationStatusAuthorized) {
        [self cameraFailed:StashNativeCodeLinkErrorCameraPermissionDenied message:@"Camera access is not allowed."];
    } else if (self.captureReady) {
        dispatch_async(_cameraQueue, ^{ if (!self.capture.isRunning) [self.capture startRunning]; });
    } else if (!self.configurationAttempted) {
        self.configurationAttempted = YES;
        [self configureCamera];
    }
}
- (void)configureCamera {
    dispatch_async(_cameraQueue, ^{
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
            mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
        NSError *error = nil;
        AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:&error] : nil;
        BOOL ready = NO;
        [self.capture beginConfiguration];
        if ([self.capture canSetSessionPreset:AVCaptureSessionPreset1280x720]) self.capture.sessionPreset = AVCaptureSessionPreset1280x720;
        if (input && [self.capture canAddInput:input] && [self.capture canAddOutput:self.metadata]) {
            [self.capture addInput:input];
            [self.capture addOutput:self.metadata];
            if ([self.metadata.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeQRCode]) {
                self.metadata.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];
                [self.metadata setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
                if (@available(iOS 16.0, *)) {
                    if (self.capture.isMultitaskingCameraAccessSupported) self.capture.multitaskingCameraAccessEnabled = YES;
                }
                ready = YES;
            }
        }
        [self.capture commitConfiguration];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.disposed || ![self.session isActive]) return;
            self.captureReady = ready;
            if (ready) {
                [self.view setNeedsLayout];
                [self.view layoutIfNeeded];
                [self requestCamera];
            } else [self cameraFailed:device ? StashNativeCodeLinkErrorCameraConfigurationFailed : StashNativeCodeLinkErrorCameraUnavailable
                message:error.localizedDescription ?: @"No camera is available for QR scanning."];
        });
    });
}
- (void)activityChanged:(NSNotification *)note {
    if ([note.object isKindOfClass:UIScene.class] && note.object != self.viewIfLoaded.window.windowScene) return;
    if ([note.name isEqualToString:UIApplicationWillResignActiveNotification] ||
        [note.name isEqualToString:UISceneWillDeactivateNotification]) {
        dispatch_async(_cameraQueue, ^{ [self.capture stopRunning]; });
    } else [self requestCamera];
}
- (void)captureChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self canScan]) return;
        if ([note.name isEqualToString:AVCaptureSessionDidStartRunningNotification]) {
            self.scanning = YES;
            [self.spinner stopAnimating];
            self.status.hidden = YES;
            [self updateCameraGeometry];
            [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.2 animations:^{ self.preview.alpha = 1; }];
        } else if ([note.name isEqualToString:AVCaptureSessionWasInterruptedNotification]) {
            self.scanning = NO;
            [self showStatus:@"Camera paused" message:@"Scanning will resume when the camera is available." settings:NO];
        } else if ([note.name isEqualToString:AVCaptureSessionInterruptionEndedNotification]) {
            self.scanning = self.capture.isRunning;
            self.status.hidden = YES;
            [self requestCamera];
        } else {
            NSError *error = note.userInfo[AVCaptureSessionErrorKey];
            if (error.code == AVErrorMediaServicesWereReset) [self requestCamera];
            else [self cameraFailed:StashNativeCodeLinkErrorCameraConfigurationFailed
                message:error.localizedDescription ?: @"The camera could not start."];
        }
    });
}
- (void)showStatus:(NSString *)title message:(NSString *)message settings:(BOOL)settings {
    [self.spinner stopAnimating];
    self.status.hidden = NO;
    self.statusTitle.text = title;
    self.statusMessage.text = message;
    self.settingsButton.hidden = !settings;
    [self.view setNeedsLayout];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.statusTitle);
}
- (void)cameraFailed:(StashNativeCodeLinkError)code message:(NSString *)message {
    if (self.disposed || self.session.codeLinkCompleted || ![self.session isActive]) return;
    self.scanning = NO;
    BOOL denied = code == StashNativeCodeLinkErrorCameraPermissionDenied;
    [self showStatus:denied ? @"Allow camera access" : @"Camera unavailable"
        message:denied ? @"Enable camera access in Settings to scan your webshop code."
        : @"Use a device with an available camera to scan your webshop code." settings:denied];
    if (self.errorReported) return;
    self.errorReported = YES;
    id<StashNativeCardDelegate> delegate = self.session.owner.delegate;
    if ([delegate respondsToSelector:@selector(stashNativeCardCodeLinkDidEncounterError:)])
        [delegate stashNativeCardCodeLinkDidEncounterError:[NSError errorWithDomain:StashNativeCodeLinkErrorDomain
            code:code userInfo:@{NSLocalizedDescriptionKey:message}]];
}
- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray<AVMetadataObject *> *)objects
    fromConnection:(AVCaptureConnection *)connection {
    if (![self canScan] || !self.scanning || output != self.metadata) return;
    for (AVMetadataObject *object in objects) {
        if (![object.type isEqualToString:AVMetadataObjectTypeQRCode] ||
            ![object isKindOfClass:AVMetadataMachineReadableCodeObject.class]) continue;
        AVMetadataMachineReadableCodeObject *code = (id)[self.previewLayer transformedMetadataObjectForMetadataObject:object];
        if (!code.stringValue.length || !CGRectContainsRect(self.scanFrame, code.bounds)) continue;
        [self.session completeCodeLink:code.stringValue];
        return;
    }
}
- (void)closeTapped {
    if ([self.session canUserDismiss]) [self.session finishWithUserDismiss:YES completion:nil];
}
- (void)showConnectedWithCompletion:(void (^)(void))completion {
    [self stopScanning];
    [self loadViewIfNeeded];
    [self.spinner stopAnimating];
    self.closeButton.enabled = NO;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    UIVisualEffectView *confirmation = [[UIVisualEffectView alloc] initWithEffect:nil];
    self.confirmation = confirmation;
    confirmation.frame = self.view.bounds;
    confirmation.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    confirmation.accessibilityIdentifier = @"stash-code-link-connected";
    confirmation.accessibilityViewIsModal = YES;
    [self.view addSubview:confirmation];
    UIImageView *checkmark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:76 weight:UIImageSymbolWeightRegular]]];
    checkmark.tintColor = UIColor.whiteColor;
    checkmark.contentMode = UIViewContentModeCenter;
    checkmark.isAccessibilityElement = NO;
    UILabel *title = StashCodeLinkLabel(@"Connected", UIFontTextStyleTitle2, 1);
    title.textAlignment = NSTextAlignmentCenter;
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[checkmark, title]];
    content.axis = UILayoutConstraintAxisVertical;
    content.alignment = UIStackViewAlignmentCenter;
    content.spacing = 16;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [confirmation.contentView addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:confirmation.contentView.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:confirmation.contentView.centerYAnchor],
        [content.widthAnchor constraintLessThanOrEqualToAnchor:confirmation.contentView.widthAnchor constant:-32]
    ]];
    [confirmation layoutIfNeeded];
    content.alpha = 0;
    content.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.82, 0.82);
    [UIView animateWithDuration:0.2 animations:^{
        if (UIAccessibilityIsReduceTransparencyEnabled()) confirmation.backgroundColor = UIColor.blackColor;
        else confirmation.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark];
        self.heading.alpha = self.closeButton.alpha = self.callout.alpha = self.status.alpha = 0;
        self.frameLayer.opacity = self.shadeLayer.opacity = 0;
    }];
    [UIView animateWithDuration:reduceMotion ? 0.2 : 0.4 delay:0
        usingSpringWithDamping:0.78 initialSpringVelocity:0
        options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            content.alpha = 1;
            content.transform = CGAffineTransformIdentity;
        } completion:nil];
    UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
    [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, title);
    NSTimeInterval hold = UIAccessibilityIsVoiceOverRunning() ? 1.4 : 0.85;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(hold * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.disposed && completion) completion();
    });
#if !__has_feature(objc_arc)
    [confirmation release]; [checkmark release]; [content release]; [feedback release];
#endif
}
- (void)openSettings {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
}
- (void)stopScanning {
    self.visible = NO;
    self.scanning = NO;
    dispatch_async(_cameraQueue, ^{ [self.capture stopRunning]; });
}
- (void)dispose {
    if (self.disposed) return;
    self.disposed = YES;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self stopScanning];
    self.previewLayer.session = nil;
    dispatch_async(_cameraQueue, ^{ [self.metadata setMetadataObjectsDelegate:nil queue:nil]; });
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
#if !__has_feature(objc_arc)
    [_capture release]; [_metadata release]; [_preview release]; [_heading release]; [_closeButton release];
    [_callout release]; [_frameLayer release]; [_shadeLayer release]; [_status release];
    [_statusTitle release]; [_statusMessage release]; [_settingsButton release]; [_spinner release];
    [_confirmation release];
    dispatch_release(_cameraQueue);
    [super dealloc];
#endif
}
@end
