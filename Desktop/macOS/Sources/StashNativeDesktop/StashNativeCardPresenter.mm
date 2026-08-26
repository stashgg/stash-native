//
//  StashNativeCardPresenter.mm
//  StashNativeDesktop
//
//  AppKit surface: dimmed backdrop over the host window's content, rounded card with a native
//  trust header (lock, host, close button) drawn by the app process so the page cannot forge it,
//  spinner until the page loads, click-outside / Esc / close to dismiss. Or a standalone window
//  for editor play mode.
//

#import "StashNativeCardPrivate.h"

#import <QuartzCore/QuartzCore.h>

#include "StashDesktopTheme.h"

static const CGFloat kCardCornerRadius = 14.0;
static const CGFloat kHeaderHeight = 36.0;
static const CGFloat kSpinnerSize = 32.0;
static const NSTimeInterval kEntranceDuration = 0.22;
static const NSTimeInterval kExitDuration = 0.16;
static const unsigned short kEscapeKeyCode = 53;

static NSColor *StashColorFromArgb(uint32_t argb) {
    return [NSColor colorWithSRGBRed:((argb >> 16) & 0xFF) / 255.0
                               green:((argb >> 8) & 0xFF) / 255.0
                                blue:(argb & 0xFF) / 255.0
                               alpha:((argb >> 24) & 0xFF) / 255.0];
}

@interface StashBackdropView : NSView
@property (nonatomic, weak) StashDesktopCore *core;
@end

@implementation StashBackdropView

- (void)mouseDown:(NSEvent *)event {
    (void)event;
    [self.core requestUserDismiss];
}

@end

// Swallows clicks so they never fall through to the backdrop.
@interface StashCardView : NSView
@end

@implementation StashCardView

- (void)mouseDown:(NSEvent *)event {
    (void)event;
}

@end

@implementation StashNativeCardPresenter {
    __weak StashDesktopCore *_core;
    NSWindow *_hostWindow;
    NSWindow *_standaloneWindow;
    StashBackdropView *_backdrop;
    StashCardView *_card;
    NSView *_header;
    NSImageView *_lockView;
    NSTextField *_hostLabel;
    NSButton *_closeButton;
    NSProgressIndicator *_spinner;
    WKWebView *_webView;
    id _escapeMonitor;
    id _resizeObserver;
    stash::desktop::SurfaceConfig _config;
    BOOL _dark;
}

- (instancetype)initWithCore:(StashDesktopCore *)core {
    self = [super init];
    if (self) {
        _core = core;
    }
    return self;
}

- (BOOL)isLive {
    return _backdrop.superview != nil || (_standaloneWindow != nil && _standaloneWindow.isVisible);
}

- (NSWindow *)sheetWindow {
    return _standaloneWindow ?: _hostWindow;
}

#pragma mark - Layout

- (NSRect)cardFrameForBounds:(NSRect)bounds {
    stash::desktop::SurfaceSize size = stash::desktop::resolveSurfaceSize(_config, bounds.size.width, bounds.size.height);
    return NSMakeRect(std::floor((bounds.size.width - size.width) / 2.0),
                      std::floor((bounds.size.height - size.height) / 2.0),
                      std::floor(size.width), std::floor(size.height));
}

- (void)layoutCard {
    if (!_backdrop || !_card) {
        return;
    }
    NSRect frame = [self cardFrameForBounds:_backdrop.bounds];
    _card.frame = frame;
    CGFloat w = frame.size.width;
    CGFloat h = frame.size.height;
    _header.frame = NSMakeRect(0, h - kHeaderHeight, w, kHeaderHeight);
    _webView.frame = NSMakeRect(0, 0, w, h - kHeaderHeight);
    _spinner.frame = NSMakeRect(std::floor((w - kSpinnerSize) / 2.0),
                                std::floor((h - kHeaderHeight - kSpinnerSize) / 2.0), kSpinnerSize, kSpinnerSize);
    CGFloat lockW = _lockView.hidden ? 0 : 18;
    _lockView.frame = NSMakeRect(14, std::floor((kHeaderHeight - 14) / 2.0), 14, 14);
    _hostLabel.frame = NSMakeRect(14 + lockW, std::floor((kHeaderHeight - 17) / 2.0), w - 14 - lockW - 48, 17);
    _closeButton.frame = NSMakeRect(w - 34, std::floor((kHeaderHeight - 24) / 2.0), 24, 24);
}

#pragma mark - Chrome

- (void)installEscapeMonitor {
    __weak StashNativeCardPresenter *weakSelf = self;
    _escapeMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        StashNativeCardPresenter *strongSelf = weakSelf;
        if (event.keyCode == kEscapeKeyCode && strongSelf && strongSelf.isLive) {
            [strongSelf->_core requestUserDismiss];
            return nil;
        }
        return event;
    }];
}

- (void)closeButtonPressed:(id)sender {
    (void)sender;
    [_core requestUserDismiss];
}

- (NSImage *)symbolNamed:(NSString *)name {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    [image setTemplate:YES];
    return image;
}

- (void)buildHeaderWithWidth:(CGFloat)width sheetArgb:(uint32_t)sheetArgb {
    _header = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, kHeaderHeight)];
    _header.wantsLayer = YES;
    _header.layer.backgroundColor = (_dark ? [NSColor colorWithWhite:1.0 alpha:0.07] : [NSColor colorWithWhite:0.0 alpha:0.05]).CGColor;
    (void)sheetArgb;

    _lockView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _lockView.image = [self symbolNamed:@"lock.fill"];
    _lockView.contentTintColor = [NSColor colorWithSRGBRed:0.29 green:0.87 blue:0.50 alpha:1.0];
    _lockView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [_header addSubview:_lockView];

    _hostLabel = [NSTextField labelWithString:@""];
    _hostLabel.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    _hostLabel.textColor = _dark ? [NSColor colorWithWhite:1.0 alpha:0.72] : [NSColor colorWithWhite:0.0 alpha:0.62];
    _hostLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_header addSubview:_hostLabel];

    _closeButton = [NSButton buttonWithImage:[self symbolNamed:@"xmark"] target:self action:@selector(closeButtonPressed:)];
    _closeButton.bordered = NO;
    _closeButton.contentTintColor = _hostLabel.textColor;
    _closeButton.toolTip = @"Close";
    [_header addSubview:_closeButton];
}

- (void)buildSpinner {
    _spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, kSpinnerSize, kSpinnerSize)];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.displayedWhenStopped = NO;
    _spinner.controlSize = NSControlSizeRegular;
    if (_dark) {
        _spinner.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    }
}

#pragma mark - Presentation

- (BOOL)presentWebView:(WKWebView *)webView
            hostWindow:(NSWindow *)hostWindow
                config:(const stash::desktop::SurfaceConfig &)config
        sheetColorArgb:(uint32_t)sheetArgb {
    [self teardown];
    NSView *content = hostWindow.contentView;
    if (!content) {
        return NO;
    }
    _config = config;
    _dark = stash::desktop::theme::isDarkColor(sheetArgb);
    _hostWindow = hostWindow;
    _webView = webView;

    _backdrop = [[StashBackdropView alloc] initWithFrame:content.bounds];
    _backdrop.core = _core;
    _backdrop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _backdrop.wantsLayer = YES;
    _backdrop.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:stash::desktop::theme::kOverlayDimAlpha].CGColor;
    _backdrop.alphaValue = 0.0;
    _backdrop.postsFrameChangedNotifications = YES;

    NSRect cardFrame = [self cardFrameForBounds:content.bounds];
    _card = [[StashCardView alloc] initWithFrame:cardFrame];
    _card.wantsLayer = YES;
    _card.layer.backgroundColor = StashColorFromArgb(sheetArgb).CGColor;
    _card.layer.cornerRadius = kCardCornerRadius;
    _card.layer.masksToBounds = YES;
    _card.layer.borderWidth = 1.0;
    _card.layer.borderColor = [NSColor colorWithWhite:_dark ? 1.0 : 0.0 alpha:0.14].CGColor;

    webView.frame = NSMakeRect(0, 0, cardFrame.size.width, cardFrame.size.height - kHeaderHeight);
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_card addSubview:webView];

    [self buildHeaderWithWidth:cardFrame.size.width sheetArgb:sheetArgb];
    [_card addSubview:_header];

    [self buildSpinner];
    [_card addSubview:_spinner];
    [_spinner startAnimation:nil];

    [_backdrop addSubview:_card];
    [content addSubview:_backdrop];
    [self layoutCard];

    __weak StashNativeCardPresenter *weakSelf = self;
    _resizeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSViewFrameDidChangeNotification
                                                                        object:_backdrop
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(NSNotification *note) {
        (void)note;
        [weakSelf layoutCard];
    }];

    // Entrance: fade the backdrop, slide the card up into place.
    NSRect target = _card.frame;
    NSRect start = target;
    start.origin.y -= 18.0;
    _card.frame = start;
    StashBackdropView *backdrop = _backdrop;
    StashCardView *card = _card;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = kEntranceDuration;
        ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        backdrop.animator.alphaValue = 1.0;
        card.animator.frame = target;
    }];

    [self installEscapeMonitor];
    [hostWindow makeFirstResponder:webView];
    return YES;
}

- (void)presentWebView:(WKWebView *)webView
   standaloneWithConfig:(const stash::desktop::SurfaceConfig &)config
        sheetColorArgb:(uint32_t)sheetArgb {
    [self teardown];
    _config = config;
    _dark = stash::desktop::theme::isDarkColor(sheetArgb);
    _webView = webView;

    stash::desktop::SurfaceSize size = stash::desktop::resolveSurfaceSize(config, 0, 0);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Stash Checkout";
    window.releasedWhenClosed = NO;
    window.delegate = self;
    window.backgroundColor = StashColorFromArgb(sheetArgb);
    _standaloneWindow = window;

    NSView *content = window.contentView;
    webView.frame = content.bounds;
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:webView];

    [self buildSpinner];
    _spinner.frame = NSMakeRect(std::floor((content.bounds.size.width - kSpinnerSize) / 2.0),
                                std::floor((content.bounds.size.height - kSpinnerSize) / 2.0), kSpinnerSize, kSpinnerSize);
    _spinner.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    [content addSubview:_spinner];
    [_spinner startAnimation:nil];

    [window center];
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:webView];
    [self installEscapeMonitor];
}

- (void)updateTrustHeaderForURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    NSString *text;
    BOOL secure = NO;
    if (!url) {
        text = @"";
    } else if ([scheme isEqualToString:@"file"]) {
        text = @"Local checkout (file)";
    } else if ([scheme isEqualToString:@"https"]) {
        text = url.host ?: @"";
        secure = YES;
    } else {
        text = url.host ?: url.absoluteString;
    }
    if (_hostLabel) {
        _hostLabel.stringValue = text;
        _lockView.hidden = !secure;
        [self layoutCard];
    }
    if (_standaloneWindow) {
        _standaloneWindow.title = text.length > 0 ? text : @"Stash Checkout";
    }
}

- (void)setLoading:(BOOL)loading {
    if (loading) {
        [_spinner startAnimation:nil];
    } else {
        [_spinner stopAnimation:nil];
    }
}

- (void)teardown {
    if (_escapeMonitor) {
        [NSEvent removeMonitor:_escapeMonitor];
        _escapeMonitor = nil;
    }
    if (_resizeObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_resizeObserver];
        _resizeObserver = nil;
    }
    [_spinner stopAnimation:nil];
    [_webView removeFromSuperview];
    _webView = nil;
    _header = nil;
    _lockView = nil;
    _hostLabel = nil;
    _closeButton = nil;
    _spinner = nil;

    if (_backdrop) {
        StashBackdropView *backdrop = _backdrop;
        _backdrop = nil;
        _card = nil;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = kExitDuration;
            backdrop.animator.alphaValue = 0.0;
        } completionHandler:^{
            [backdrop removeFromSuperview];
        }];
        // isLive must be false immediately, not after the fade.
        [backdrop removeFromSuperview];
    }
    if (_standaloneWindow) {
        NSWindow *window = _standaloneWindow;
        _standaloneWindow = nil;
        window.delegate = nil;
        [window close];
    }
    _hostWindow = nil;
}

#pragma mark - NSWindowDelegate (standalone)

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (sender == _standaloneWindow) {
        // The session decides; teardown closes the window when it agrees.
        [_core requestUserDismiss];
        return NO;
    }
    return YES;
}

@end
