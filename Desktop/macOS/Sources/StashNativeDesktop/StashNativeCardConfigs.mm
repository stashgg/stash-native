//
//  StashNativeCardConfigs.mm
//  StashNativeDesktop
//
//  StashNativeModalConfig / StashNativeCardConfig and their conversion to the shared config.
//

#import "StashNativeCardPrivate.h"

#include "StashDesktopUrl.h"

@implementation StashNativeModalConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _phoneWidthRatioPortrait = 0.80f;
        _phoneHeightRatioPortrait = 0.50f;
        _phoneWidthRatioLandscape = 0.50f;
        _phoneHeightRatioLandscape = 0.80f;
        _tabletWidthRatioPortrait = 0.40f;
        _tabletHeightRatioPortrait = 0.30f;
        _tabletWidthRatioLandscape = 0.30f;
        _tabletHeightRatioLandscape = 0.40f;
        _allowDismiss = YES;
        _autoClose = YES;
        _backgroundColor = nil;
    }
    return self;
}

- (instancetype)initWithPhoneWidthPortrait:(CGFloat)phoneWidthPortrait
                         phoneHeightPortrait:(CGFloat)phoneHeightPortrait
                         phoneWidthLandscape:(CGFloat)phoneWidthLandscape
                        phoneHeightLandscape:(CGFloat)phoneHeightLandscape
                        tabletWidthPortrait:(CGFloat)tabletWidthPortrait
                       tabletHeightPortrait:(CGFloat)tabletHeightPortrait
                       tabletWidthLandscape:(CGFloat)tabletWidthLandscape
                      tabletHeightLandscape:(CGFloat)tabletHeightLandscape
                              allowDismiss:(BOOL)allowDismiss {
    self = [super init];
    if (self) {
        _phoneWidthRatioPortrait = phoneWidthPortrait;
        _phoneHeightRatioPortrait = phoneHeightPortrait;
        _phoneWidthRatioLandscape = phoneWidthLandscape;
        _phoneHeightRatioLandscape = phoneHeightLandscape;
        _tabletWidthRatioPortrait = tabletWidthPortrait;
        _tabletHeightRatioPortrait = tabletHeightPortrait;
        _tabletWidthRatioLandscape = tabletWidthLandscape;
        _tabletHeightRatioLandscape = tabletHeightLandscape;
        _allowDismiss = allowDismiss;
        _autoClose = YES;
        _backgroundColor = nil;
    }
    return self;
}

@end

@implementation StashNativeCardConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _forcePortrait = NO;
        _cardHeightRatioPortrait = 0.68f;
        _cardWidthRatioLandscape = 0.7f;
        _cardHeightRatioLandscape = 0.9f;
        _tabletWidthRatioPortrait = 0.4f;
        _tabletHeightRatioPortrait = 0.5f;
        _tabletWidthRatioLandscape = 0.3f;
        _tabletHeightRatioLandscape = 0.6f;
        _autoClose = YES;
        _backgroundColor = nil;
    }
    return self;
}

@end

static std::string StashTrimmedUTF8(NSString *s) {
    return stash::desktop::url::trim(s.UTF8String ? s.UTF8String : "");
}

stash::desktop::SurfaceConfig StashSurfaceConfigFromCardConfig(StashNativeCardConfig *config) {
    using namespace stash::desktop;
    SurfaceConfig c;
    c.mode = SurfaceMode::Card;
    if (!config) {
        return c;
    }
    c.autoClose = config.autoClose;
    c.forcePortrait = config.forcePortrait;
    c.backgroundColor = StashTrimmedUTF8(config.backgroundColor ?: @"");
    c.cardHeightRatioPortrait = clampRatio(config.cardHeightRatioPortrait);
    c.cardWidthRatioLandscape = clampRatio(config.cardWidthRatioLandscape);
    c.cardHeightRatioLandscape = clampRatio(config.cardHeightRatioLandscape);
    c.tabletWidthRatioPortrait = clampRatio(config.tabletWidthRatioPortrait);
    c.tabletHeightRatioPortrait = clampRatio(config.tabletHeightRatioPortrait);
    c.tabletWidthRatioLandscape = clampRatio(config.tabletWidthRatioLandscape);
    c.tabletHeightRatioLandscape = clampRatio(config.tabletHeightRatioLandscape);
    return c;
}

stash::desktop::SurfaceConfig StashSurfaceConfigFromModalConfig(StashNativeModalConfig *config) {
    using namespace stash::desktop;
    SurfaceConfig c;
    c.mode = SurfaceMode::Modal;
    if (!config) {
        return c;
    }
    c.autoClose = config.autoClose;
    c.allowDismiss = config.allowDismiss;
    c.backgroundColor = StashTrimmedUTF8(config.backgroundColor ?: @"");
    c.phoneWidthRatioPortrait = clampRatio(config.phoneWidthRatioPortrait);
    c.phoneHeightRatioPortrait = clampRatio(config.phoneHeightRatioPortrait);
    c.phoneWidthRatioLandscape = clampRatio(config.phoneWidthRatioLandscape);
    c.phoneHeightRatioLandscape = clampRatio(config.phoneHeightRatioLandscape);
    c.modalTabletWidthRatioPortrait = clampRatio(config.tabletWidthRatioPortrait);
    c.modalTabletHeightRatioPortrait = clampRatio(config.tabletHeightRatioPortrait);
    c.modalTabletWidthRatioLandscape = clampRatio(config.tabletWidthRatioLandscape);
    c.modalTabletHeightRatioLandscape = clampRatio(config.tabletHeightRatioLandscape);
    return c;
}
