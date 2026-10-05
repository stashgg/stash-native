//
//  StashNativeCardConfigs.mm
//  StashNativeDesktop
//
//  StashNativeCardConfig and its conversion to the shared config.
//

#import "StashNativeCardPrivate.h"

#include <cmath>

#include "StashDesktopUrl.h"

@implementation StashNativeCardConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _allowDismiss = YES;
        _presentation = StashNativeCardPresentationAttached;
        _width = 0;
        _height = 0;
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
    if (!config) {
        return c;
    }
    c.autoClose = config.autoClose;
    c.allowDismiss = config.allowDismiss;
    c.presentation = config.presentation == StashNativeCardPresentationWindow ? Presentation::Window : Presentation::Attached;
    c.width = (std::isfinite(config.width) && config.width > 0) ? config.width : 0;
    c.height = (std::isfinite(config.height) && config.height > 0) ? config.height : 0;
    c.backgroundColor = StashTrimmedUTF8(config.backgroundColor ?: @"");
    return c;
}
